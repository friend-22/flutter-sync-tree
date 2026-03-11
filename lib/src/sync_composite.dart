import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// A container node that orchestrates multiple [SyncNode]s (Leaves or other Composites).
///
/// Implements the **Composite** design pattern, allowing a tree of sync tasks
/// to be managed as a single unified unit. The composite aggregates the progress,
/// status, and summary of all its children, emitting events that reflect the
/// collective state of the entire subtree.
///
/// ### Features
/// - **Depth Propagation**: Automatically assigns hierarchy levels to children
///   for consistent, indented log output.
/// - **Parallel Execution**: Starts [primarySyncs] and [lateSyncs] concurrently
///   within each group.
/// - **Status Aggregation**: Emits [SyncStatus.complete] only after every child
///   has reached a terminal state (complete, error, or idle).
/// - **Throttled Updates**: Aggregates high-frequency progress signals from
///   children through a shared [Throttler] to prevent UI overload.
/// - **Snapshot Tracking**: Captures completed child summaries to ensure the
///   aggregate [summary] remains stable even after children reset.
///
/// ### Tree Structure Example
/// ```
/// SyncComposite (root)
/// ├── SyncComposite (bundle)
/// │   ├── SyncLeaf (userSync)
/// │   └── SyncLeaf (productSync)
/// └── SyncLeaf (downloadSync)
/// ```
///
/// ### Usage
/// ```dart
/// final root = SyncComposite(
///   key: 'root',
///   primarySyncs: [userLeaf, productLeaf],
///   lateSyncs: [downloadLeaf],
///   stopOnError: false,
/// );
///
/// await root.start();
/// await userLeaf.triggerSync(userData);
/// ```
class SyncComposite extends SyncNode {
  /// Core tasks executed first, in parallel.
  ///
  /// All primary syncs are started simultaneously via [Future.wait].
  /// [lateSyncs] are initiated only after all primary starts have returned.
  final List<SyncNode> primarySyncs;

  /// Secondary tasks initiated after [primarySyncs] have started.
  ///
  /// Late syncs typically depend on or react to primary sync progress.
  /// They are started in parallel with each other, but after [primarySyncs].
  final List<SyncNode> lateSyncs;

  /// Flattened list of all child nodes ([primarySyncs] + [lateSyncs]).
  ///
  /// Used for unified iteration across all children regardless of group.
  final List<SyncNode> _children = [];

  /// Snapshots of [SyncSummary] captured when each child node completes.
  ///
  /// Keyed by [SyncNode.key]. Ensures that the aggregate [summary] remains
  /// stable and correct even after a child node resets its own state
  /// (e.g., when re-triggered in a subsequent session).
  final Map<String, SyncSummary> _completedSnapshots = {};

  /// If `true`, calls [stop] on all children when any child emits [SyncStatus.error].
  ///
  /// If `false` (default), sibling nodes continue running and partial results
  /// are preserved in [summary].
  final bool stopOnError;

  /// Controls how frequently aggregated progress updates are dispatched to listeners.
  ///
  /// Shared across all child progress events to ensure the composite's
  /// [SyncStatus.progress] notifications stay within UI-friendly bounds.
  final ThrottlerConfig throttlerConfig;

  /// A short delay applied before finalizing composite completion.
  ///
  /// When multiple children complete near-simultaneously (common in parallel sync),
  /// this delay allows any in-flight async events to settle before [isCompleted]
  /// is evaluated. Prevents premature or missed completion notifications.
  final Duration syncDelay;

  /// The throttler instance that gates outgoing [SyncStatus.progress] notifications.
  late Throttler _throttler;

  /// Guards against processing child events before the composite is fully initialized.
  ///
  /// Set to `true` at construction and after each completed session.
  /// Set to `false` when the first child emits [SyncStatus.start], signaling
  /// that a new session has begun and snapshots should be managed.
  bool _needsInitialization = true;

  /// Prevents [isCompleted] from returning `true` while [start] is still
  /// dispatching initial [Future.wait] calls to children.
  ///
  /// Without this guard, a fast-completing child could trigger [_notifyComplete]
  /// before all children have been started.
  bool _isDispatching = false;

  /// Prevents concurrent execution of [_notifyComplete].
  ///
  /// Since [_notifyComplete] is `async` and contains an `await`, it is possible
  /// for multiple children to complete and each invoke [_notifyComplete] before
  /// the first invocation finishes. This flag ensures only one runs at a time.
  bool _isNotifying = false;

  SyncComposite({
    super.key,
    this.throttlerConfig = const ThrottlerConfig(),
    required this.primarySyncs,
    List<SyncNode>? lateSyncs,
    this.stopOnError = false,
    this.syncDelay = const Duration(milliseconds: 50),
  }) : lateSyncs = lateSyncs ?? [] {
    // Initialize the throttler to gate outgoing progress notifications.
    // The onUpdate callback translates throttler emissions into SyncStatus.progress events.
    _throttler = Throttler(
      threshold: throttlerConfig.threshold,
      interval: throttlerConfig.interval,
      precision: throttlerConfig.precision,
      onUpdate: (p, origin) {
        notify(SyncStatus.progress, origin: this, onNotify: () {
          _log('🔄 Syncing:', progress: p);
        });
      },
    );

    _children.addAll([...primarySyncs, ...this.lateSyncs]);

    // Assign depth values recursively so log output is properly indented.
    _propagateDepth(depth);

    // Subscribe to all child lifecycle events.
    // Each child's events are routed to the appropriate handler method.
    for (final child in _children) {
      child.listen((status, origin) async {
        switch (status) {
          case SyncStatus.none:
            break;
          case SyncStatus.idle:
            _handleChildIdle(origin);
            break;
          case SyncStatus.start:
            _handleChildStart(origin);
            break;
          case SyncStatus.progress:
            // Forward child progress to the shared throttler for aggregation.
            _throttler.update(progress, origin);
            break;
          case SyncStatus.complete:
            _handleChildComplete(origin);
            break;
          case SyncStatus.error:
            _handleChildError(origin);
            break;
          case SyncStatus.stop:
            _handleChildStop(origin);
            break;
          case SyncStatus.pause:
            _handleChildPause(origin);
            break;
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Child Event Handlers
  // ---------------------------------------------------------------------------

  /// Propagates [SyncStatus.idle] upward when all children are ready.
  ///
  /// Called when any child transitions to idle. Only emits if every
  /// child is idle, indicating the composite itself is fully ready.
  void _handleChildIdle(SyncNode origin) {
    if (isIdle) {
      notify(SyncStatus.idle, origin: this, onNotify: () => _log('⚙️ All nodes ready'));
    }
  }

  /// Handles a child transitioning to [SyncStatus.start].
  ///
  /// On the first start event of a new session ([_needsInitialization] is `true`),
  /// clears snapshots and resets all non-syncing nodes to prepare for a clean run.
  /// On subsequent start events (re-triggers), removes the origin's stale snapshot
  /// so the active summary is used instead.
  void _handleChildStart(SyncNode origin) {
    if (_needsInitialization) {
      _completedSnapshots.clear();
      _resetAllNodes();
      _needsInitialization = false;
    } else {
      // Remove the stale snapshot so live summary is used during re-sync.
      if (origin.key != null) {
        _completedSnapshots.remove(origin.key!);
      }
    }

    notify(SyncStatus.start, origin: origin, onNotify: () {
      _log('🚀 Child started: [${origin.key}]');
    });
  }

  /// Handles a child transitioning to [SyncStatus.complete].
  ///
  /// Captures a snapshot of the completed child's summary, then checks
  /// if all children are done. If so, triggers [_notifyComplete].
  /// Otherwise, emits a throttled progress update while waiting.
  void _handleChildComplete(SyncNode origin) {
    if (origin.key != null) {
      // Snapshot the summary immediately to preserve it before the child resets.
      _completedSnapshots[origin.key!] = origin.summary;
    }

    if (isCompleted) {
      _notifyComplete();
    } else {
      _log('✅ Child done: [${origin.key}] (Still waiting for others)');
      _throttler.update(progress, origin);
    }
  }

  /// Handles a child transitioning to [SyncStatus.error].
  ///
  /// Snapshots the errored child's summary for partial result reporting.
  /// If [stopOnError] is `true`, halts the entire tree immediately.
  /// Otherwise, checks if the remaining children have also finished.
  void _handleChildError(SyncNode origin) {
    if (origin.key != null) {
      // Snapshot the summary immediately to preserve it before the child resets.
      _completedSnapshots[origin.key!] = origin.summary;
    }

    if (stopOnError) {
      stop();
    } else if (isCompleted) {
      _notifyComplete();
    }
  }

  /// Handles a child transitioning to [SyncStatus.stop].
  ///
  /// Only emits [SyncStatus.stop] on this composite once all children
  /// have stopped, ensuring the parent receives a single, clean stop signal.
  void _handleChildStop(SyncNode origin) {
    if (isStopped) {
      _needsInitialization = true;
      _completedSnapshots.clear();
      _throttler.reset();

      notify(SyncStatus.stop, origin: this, onNotify: () => _log('🛑 All stopped'));
    }
  }

  /// Handles a child transitioning to [SyncStatus.pause].
  ///
  /// Only emits [SyncStatus.pause] on this composite once all children
  /// have paused, ensuring the parent receives a single, clean pause signal.
  void _handleChildPause(SyncNode origin) {
    if (isPaused) {
      notify(SyncStatus.pause, origin: this, onNotify: () => _log('⏳ All suspended'));
    }
  }

  // ---------------------------------------------------------------------------
  // Completion Logic
  // ---------------------------------------------------------------------------

  /// Finalizes the composite state once all children have reached a terminal state.
  ///
  /// Guarded by [_isNotifying] to prevent concurrent re-entrant calls.
  /// Applies [syncDelay] before evaluating [isCompleted] to allow any
  /// near-simultaneous async child completions to settle.
  ///
  /// After the delay, evaluates [isCompleted] exactly once:
  /// - If completed: flushes the throttler, determines final status
  ///   (error or complete), and emits the terminal notification.
  /// - If not completed: logs a "still waiting" message (another child
  ///   will eventually trigger [_notifyComplete] again).
  ///
  /// Always resets [_throttler] and [_needsInitialization] regardless of outcome.
  void _notifyComplete() async {
    if (_needsInitialization || _isNotifying) return;
    _isNotifying = true;

    try {
      if (_children.length > 1) {
        if (syncDelay > Duration.zero) {
          _log('⏳ Waiting for sync delay: ${syncDelay.inMilliseconds}ms');
        }

        // Use microtask for zero-delay to yield to other pending events
        // without incurring a real timer overhead.
        syncDelay == Duration.zero ? await Future.microtask(() {}) : await Future.delayed(syncDelay);
      }

      // Evaluate isCompleted exactly once after the delay to get a consistent snapshot,
      // avoiding double-evaluation issues from the async gap above.
      if (isCompleted) {
        // Force the final 1.0 progress to be emitted before the terminal status.
        _throttler.flush(this);

        final hasError = _children.any((h) => h.isError);
        final finalStatus = hasError ? SyncStatus.error : SyncStatus.complete;
        final logMsg = hasError ? '🚨 Error: "$message"' : '✨ Done: $summary';

        notify(finalStatus, origin: this, onNotify: () {
          _log(logMsg);
          if (hasError) _log('📊 Partial Success: $summary');
          if (_isRoot) SyncLog.clearLine();
        });
      } else {
        // Another child is still running. It will call _notifyComplete when it finishes.
        _log('🔄 Synchronization still in progress... (Waiting for children)');
      }
    } finally {
      // Always reset, regardless of whether we completed or not,
      // to ensure clean state for the next session.
      _throttler.reset();
      _needsInitialization = true;
      _isNotifying = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Recursive Utilities
  // ---------------------------------------------------------------------------

  /// Recursively resets all non-syncing leaf nodes to prepare for a new session.
  ///
  /// Only resets [SyncLeaf] nodes that are not currently syncing to avoid
  /// interrupting active tasks. [SyncComposite] children are recursed into.
  void _resetAllNodes() {
    for (var child in _children) {
      if (child is SyncComposite) {
        child._resetAllNodes();
      } else if (child is SyncLeaf && !child.isSyncing) {
        child.reset();
      }
    }
  }

  /// Recursively assigns [depth] values to all nodes in the subtree.
  ///
  /// Called once during construction to ensure every node has the correct
  /// depth for [SyncLog] indentation. Root nodes start at `depth = 0`;
  /// each level of nesting increments by 1.
  void _propagateDepth(int currentDepth) {
    depth = currentDepth;

    for (var child in _children) {
      if (child is SyncComposite) {
        child._propagateDepth(currentDepth + 1);
      } else {
        child.depth = currentDepth + 1;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // SyncGetter Overrides
  // ---------------------------------------------------------------------------

  /// Returns `true` if every child is idle.
  @override
  bool get isIdle => _children.every((h) => h.isIdle);

  /// Returns `true` if any child is actively syncing.
  @override
  bool get isSyncing => _children.any((h) => h.isSyncing);

  /// Returns `true` if all children have reached a terminal state.
  ///
  /// Guarded by [_isDispatching] (prevents premature completion during [start])
  /// and [_children.isEmpty] (an empty composite is never considered complete).
  /// A child is considered terminal if it is idle, completed, or in error —
  /// but not if it is actively syncing.
  @override
  bool get isCompleted {
    if (_isDispatching || _children.isEmpty) return false;

    return _children.every((h) {
      if (h.isSyncing) return false;
      return h.isIdle || h.isCompleted || h.isError;
    });
  }

  /// Returns `true` if any child is in an error state.
  @override
  bool get isError => _children.any((h) => h.isError);

  /// Returns `true` if every child is paused.
  @override
  bool get isPaused => _children.every((h) => h.isPaused);

  /// Returns `true` if every child has been stopped.
  @override
  bool get isStopped => _children.every((h) => h.isStopped);

  /// Returns `true` if any child has a non-null message (typically an error).
  @override
  bool get hasMessage => _children.any((h) => h.hasMessage);

  /// Returns the sum of [totalCount] across all children.
  @override
  int get totalCount => _children.fold(0, (sum, node) => sum + node.totalCount);

  /// Returns the sum of [completedCount] across all children.
  @override
  int get completedCount => _children.fold(0, (sum, node) => sum + node.completedCount);

  /// Returns the aggregate progress as a normalized ratio (0.0 to 1.0).
  ///
  /// Calculated as `completedCount / totalCount` across all children.
  /// Returns `1.0` if the composite is completed, and `0.0` if no work
  /// has been assigned yet. Values above `0.999` are capped to `1.0`
  /// to prevent floating-point overflow in progress bar widgets.
  @override
  double get progress {
    if (totalCount == 0) return 0.0;
    if (isCompleted) return 1.0;

    final result = completedCount / totalCount;
    // Cap at 1.0 to prevent floating-point imprecision from causing values like 1.0000001.
    return result > 0.999 ? 1.0 : result;
  }

  /// Returns the combined error/status messages from all children.
  ///
  /// Collects non-null, non-empty messages from all children, deduplicates
  /// them (via [Set]), and joins them with newlines. Returns `null` if no
  /// child has a message.
  @override
  String? get message {
    if (!hasMessage) return null;

    final messages =
        _children.map((node) => node.message).whereType<String>().where((msg) => msg.isNotEmpty).toSet();

    return messages.isEmpty ? null : messages.join('\n');
  }

  /// Aggregates [SyncSummary] from all child nodes.
  ///
  /// For each child, prefers the completed snapshot (if available) over the
  /// live summary. This ensures that the aggregate result remains stable and
  /// correct even after a child resets its own internal state between sessions.
  @override
  SyncSummary get summary {
    return _children.fold(const SyncSummary(), (total, child) {
      final key = child.key;
      final childSummary = (key != null) ? (_completedSnapshots[key] ?? child.summary) : child.summary;
      return total.merge(childSummary);
    });
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns all child nodes (primary + late) as a flat list.
  List<SyncNode> get allChildren => List.unmodifiable(_children);

  /// Returns `true` if this composite is the root of the tree (depth == 0).
  bool get _isRoot => depth == 0;

  @Deprecated('Use findNode instead. This will be removed in 1.1.0')
  SyncNode? getNode(String key) => findNode(key);

  /// Recursively searches for a [SyncNode] with the given [targetKey].
  ///
  /// Performs a depth-first search through the tree. Returns `null` if no
  /// node with the given key exists.
  SyncNode? findNode(String targetKey) {
    for (final node in _children) {
      if (node.key == targetKey) return node;
      if (node is SyncComposite) {
        final found = node.findNode(targetKey);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Returns the [SyncSummary] for the node identified by [targetKey].
  ///
  /// Returns an empty [SyncSummary] if no matching node is found.
  SyncSummary getSummary(String targetKey) => findNode(targetKey)?.summary ?? const SyncSummary();

  // ---------------------------------------------------------------------------
  // Lifecycle Overrides
  // ---------------------------------------------------------------------------

  /// Disposes all child nodes before releasing this node's own resources.
  ///
  /// Ensures that child stream subscriptions are cancelled and child event
  /// streams are closed before the parent's [super.dispose] cleans up
  /// the remaining subscriptions registered via [listen].
  @override
  Future<void> dispose() async {
    for (var child in _children) {
      await child.dispose();
    }
    await super.dispose();
  }

  /// Starts all child nodes, initiating the sync session.
  ///
  /// Primary syncs are started first, in parallel. Late syncs are started
  /// immediately after (also in parallel). [_isDispatching] is held `true`
  /// during the entire dispatch phase to prevent [isCompleted] from returning
  /// prematurely if a child completes before all starts have returned.
  ///
  /// [_notifyComplete] is called in `finally` to handle the edge case where
  /// all children complete synchronously before [_isDispatching] is cleared.
  @override
  Future<void> start() async {
    if (_isRoot) _log('🚀 Global Sync Started');

    _completedSnapshots.clear();
    _throttler.reset();
    _needsInitialization = true;
    _isDispatching = true;

    try {
      // Start primary tasks concurrently.
      await Future.wait(primarySyncs.map((h) => h.start()));

      // Start late tasks concurrently after primary starts have returned.
      if (lateSyncs.isNotEmpty) {
        await Future.wait(lateSyncs.map((h) => h.start()));
      }

      if (_isRoot) SyncLog.clearLine();
    } finally {
      _isDispatching = false;
      _notifyComplete();
    }
  }

  /// Stops all child nodes concurrently.
  ///
  /// Each child transitions to [SyncStatus.stop], which propagates upward
  /// through [_handleChildStop] once all children have stopped.
  @override
  Future<void> stop() async {
    if (_isRoot) _log('🛑 Global Sync Stop Requested');

    await Future.wait(_children.map((node) => node.stop()));

    if (_isRoot) SyncLog.clearLine();
  }

  /// Pauses all child nodes.
  ///
  /// Each child suspends at its next [SyncLeaf._handleOperation] checkpoint.
  /// The composite emits [SyncStatus.pause] once all children have paused,
  /// via [_handleChildPause].
  @override
  void pause() {
    if (_isRoot) {
      SyncLog.clearLine();
      _log('⏳ Synchronization process paused');
    }

    for (var node in _children) {
      node.pause();
    }
  }

  /// Resumes all previously paused child nodes.
  ///
  /// Unblocks each child's [SyncLeaf._waitIfPaused] future, allowing
  /// processing to continue from where it left off.
  @override
  void resume() {
    if (_isRoot) {
      SyncLog.clearLine();
      _log('⏳ Synchronization process resumed');
    }

    for (var node in _children) {
      node.resume();
    }
  }

  /// Internal logging helper that delegates to [SyncLog.fromComposite].
  void _log(String message, {double? progress}) {
    SyncLog.fromComposite(depth, '$key', message, progress: progress);
  }
}
