import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// A container node that orchestrates multiple [SyncNode]s (Leafs or other Composites).
///
/// It manages the execution lifecycle of its children, aggregating their progress
/// and status into a single, unified view. It supports:
/// - **Depth Propagation**: Automatically sets the hierarchy level for consistent logging.
/// - **Parallel Execution**: Starts primary and late tasks in batches.
/// - **Status Aggregation**: Emits [SyncStatus.complete] only when all children are finished.
/// - **Throttled Updates**: Regulates high-frequency progress signals from children.
class SyncComposite extends SyncNode {
  /// Core tasks that are executed first and in parallel.
  final List<SyncNode> primarySyncs;

  /// Secondary tasks that are initiated after primary tasks have started or completed.
  final List<SyncNode> lateSyncs;

  /// Flattened list of all child nodes for simplified internal management.
  final List<SyncNode> _children = [];

  /// Stores snapshots of summaries from nodes that have finished.
  final Map<String, SyncSummary> _completedSnapshots = {};

  /// If true, the composite terminates all operations if any child encounters an error.
  final bool stopOnError;

  /// Throttler configuration for aggregating child progress updates.
  final ThrottlerConfig throttlerConfig;

  /// A small delay used when finalizing status to ensure all async events have settled.
  final Duration syncDelay;

  late Throttler _throttler;

  bool _needsInitialization = true;

  bool _isDispatching = false;

  bool _isNotifying = false;

  SyncComposite({
    super.key,
    this.throttlerConfig = const ThrottlerConfig(),
    required this.primarySyncs,
    List<SyncNode>? lateSyncs,
    this.stopOnError = false,
    this.syncDelay = const Duration(milliseconds: 50),
  }) : lateSyncs = lateSyncs ?? [] {
    // Initialize the throttler to ensure progress updates adhere to
    // threshold and interval constraints.
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

    // Set depth hierarchy recursively for all children
    _propagateDepth(depth);

    // Listen to child lifecycle events
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

  // --- Child Event Handlers ---

  void _handleChildIdle(SyncNode origin) {
    if (isIdle) {
      notify(SyncStatus.idle, origin: this, onNotify: () => _log('⚙️ All nodes ready'));
    }
  }

  void _handleChildStart(SyncNode origin) {
    if (_needsInitialization) {
      _completedSnapshots.clear();
      _resetAllNodes();
      _needsInitialization = false;
    } else {
      _completedSnapshots.remove(origin.key!);
    }

    notify(SyncStatus.start, origin: origin, onNotify: () {
      _log('🚀 Child started: [${origin.key}]');
    });
  }

  void _handleChildComplete(SyncNode origin) {
    if (origin.key != null) {
      _completedSnapshots[origin.key!] = const SyncSummary().merge(origin.summary);
    }

    if (isCompleted) {
      _notifyComplete();
    } else {
      _log('✅ Child done: [${origin.key}] (Still waiting for others)');
      _throttler.update(progress, origin);
    }
  }

  void _handleChildError(SyncNode origin) {
    if (origin.key != null) {
      _completedSnapshots[origin.key!] = const SyncSummary().merge(origin.summary);
    }

    if (stopOnError) {
      stop();
    } else if (isCompleted) {
      _notifyComplete();
    }
  }

  void _handleChildStop(SyncNode origin) {
    if (isStopped) {
      _needsInitialization = true;
      _completedSnapshots.clear();

      notify(SyncStatus.stop, origin: this, onNotify: () => _log('🛑 All stopped'));
    }
  }

  void _handleChildPause(SyncNode origin) {
    if (isPaused) {
      notify(SyncStatus.pause, origin: this, onNotify: () => _log('⏳ All suspended'));
    }
  }

  /// Finalizes the composite state once all children have reached a terminal state.
  void _notifyComplete() async {
    if (_needsInitialization || _isNotifying) return;
    _isNotifying = true;

    try {
      if (primarySyncs.length > 1) {
        if (syncDelay > Duration.zero) {
          _log('⏳ Waiting for sync delay: ${syncDelay.inMilliseconds}ms');
        }
        syncDelay == Duration.zero ? await Future.microtask(() {}) : await Future.delayed(syncDelay);
      }

      if (!isCompleted) {
        _log('🔄 Synchronization still in progress... (Waiting for children)');
        return;
      }

      _throttler.flush(this);

      final hasError = _children.any((h) => h.isError);
      final finalStatus = hasError ? SyncStatus.error : SyncStatus.complete;
      final logMsg = hasError ? '🚨 Error: "$message"' : '✨ Done: $summary';

      notify(finalStatus, origin: this, onNotify: () {
        _log(logMsg);
        if (hasError) _log('📊 Partial Success: $summary');
        if (_isRoot) SyncLog.clearLine();
      });

      _throttler.reset();
      _needsInitialization = true;
    } finally {
      _isNotifying = false;
    }
  }

  // --- Recursive Utilities ---

  void _resetAllNodes() {
    for (var child in _children) {
      if (child is SyncComposite) {
        child._resetAllNodes();
      } else if (child is SyncLeaf && !child.isSyncing) {
        child.reset();
      }
    }
  }

  void _propagateDepth(int currentDepth) {
    depth = currentDepth;

    for (var child in _children) {
      child.depth = currentDepth + 1;

      if (child is SyncComposite) {
        child._propagateDepth(currentDepth + 1);
      }
    }
  }

  // --- Overrides ---

  @override
  bool get isIdle => _children.every((h) => h.isIdle);

  @override
  bool get isSyncing => _children.any((h) => h.isSyncing);

  @override
  bool get isCompleted {
    if (_isDispatching || _children.isEmpty) return false;

    return _children.every((h) {
      if (h.isSyncing) return false;
      return h.isIdle || h.isCompleted || h.isError;
    });
  }

  @override
  bool get isError => _children.any((h) => h.isError);

  @override
  bool get isPaused => _children.every((h) => h.isPaused);

  @override
  bool get isStopped => _children.every((h) => h.isStopped);

  @override
  bool get hasMessage => _children.any((h) => h.hasMessage);

  @override
  int get totalCount => _children.fold(0, (sum, node) => sum + node.totalCount);

  @override
  int get completedCount => _children.fold(0, (sum, node) => sum + node.completedCount);

  /// Calculates the aggregate progress based on the total workload of all active children.
  @override
  double get progress {
    if (totalCount == 0) return 0.0;
    if (isCompleted) return 1.0;

    final result = completedCount / totalCount;
    // Normalize and cap the value to prevent UI overflow from floating point precision issues.
    return result > 0.999 ? 1.0 : result;
  }

  @override
  String? get message {
    final messages =
        _children.map((node) => node.message).whereType<String>().where((msg) => msg.isNotEmpty).toSet();

    if (messages.isEmpty) return null;

    return messages.join('\n');
  }

  /// Aggregates summaries from all child nodes, combining snapshots and active metrics.
  @override
  SyncSummary get summary {
    return _children.fold(const SyncSummary(), (total, child) {
      final key = child.key;
      final childSummary = (key != null) ? (_completedSnapshots[key] ?? child.summary) : child.summary;
      return total.merge(childSummary);
    });
  }

  List<SyncNode> get allChildren => _children;

  bool get _isRoot => depth == 0;

  @Deprecated('Use findNode instead. This will be removed in 1.1.0')
  SyncNode? getNode(String key) => findNode(key);

  /// Recursively searches for a specific [SyncNode] by its key.
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

  /// Convenience method to retrieve the [SyncSummary] for a specific child node.
  SyncSummary getSummary(String targetKey) => findNode(targetKey)?.summary ?? const SyncSummary();

  @override
  Future<void> start() async {
    if (_isRoot) _log('🚀 Global Sync Started');

    _completedSnapshots.clear();
    _throttler.reset();
    _needsInitialization = true;
    _isDispatching = true;

    try {
      // Initiate primary tasks in parallel.
      await Future.wait(primarySyncs.map((h) => h.start()));

      // Initiate late tasks in parallel.
      // Secondary tasks typically synchronize internally with primary task progress.
      if (lateSyncs.isNotEmpty) {
        await Future.wait(lateSyncs.map((h) => h.start()));
      }

      if (_isRoot) SyncLog.clearLine();
    } finally {
      _isDispatching = false;
      _notifyComplete();
    }
  }

  @override
  Future<void> stop() async {
    if (_isRoot) _log('🛑 Global Sync Stop Requested');

    await Future.wait(_children.map((node) => node.stop()));

    if (_isRoot) SyncLog.clearLine();
  }

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

  @override
  void resume() {
    if (_isRoot) {
      SyncLog.clearLine();
      _log('⏳ Synchronization process resume');
    }

    for (var node in _children) {
      node.resume();
    }
  }

  void _log(String message, {double? progress}) {
    SyncLog.fromComposite(depth, '$key', message, progress: progress);
  }
}
