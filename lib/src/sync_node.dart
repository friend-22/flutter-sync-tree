import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// The base abstract class for all synchronization units, including Leaves and Composites.
///
/// Establishes the standard lifecycle contract (start, stop, pause, resume)
/// and implements [ChangeNotifier] to allow Flutter widgets to reactively
/// rebuild in response to state changes.
///
/// The tree is built by composing [SyncNode] subclasses:
/// - [SyncLeaf]: Executes the actual workload for a single task.
/// - [SyncComposite]: Orchestrates multiple [SyncNode]s in parallel.
///
/// ### Lifecycle
/// ```
/// start() → idle → [triggerSync()] → start → progress → complete / error
///                                          ↕ pause / resume
///                                  → stop()
/// dispose() → cancels all subscriptions and closes the event stream
/// ```
///
/// ### Example
/// ```dart
/// class MyLeaf extends SyncLeaf<List<Item>> {
///   MyLeaf() : super(key: 'myLeaf');
///
///   @override
///   int getTotalCount(List<Item> data) => data.length;
///
///   @override
///   Future<void> performSync(List<Item> data, OnSyncOperation onSyncOper) async {
///     for (final item in data) {
///       await repository.upsert(item);
///       await onSyncOper(SyncSummary.add);
///     }
///   }
/// }
/// ```
abstract class SyncNode with SyncGetter, ChangeNotifier {
  /// A unique identifier for the node, used for logging, telemetry, and tree traversal.
  ///
  /// Should be unique within its parent [SyncComposite] to ensure correct
  /// snapshot tracking and [SyncComposite.findNode] lookups.
  /// If `null`, the node is excluded from snapshot management.
  final String? key;

  /// The depth level of this node within the synchronization tree.
  ///
  /// Set automatically by [SyncComposite._propagateDepth] during construction.
  /// Root nodes have `depth = 0`; each level of nesting increments by 1.
  /// Used by [SyncLog] to produce indented, hierarchical log output.
  int depth = 0;

  /// Internal broadcast stream controller for lifecycle event distribution.
  ///
  /// Uses a broadcast stream to support multiple simultaneous listeners
  /// (e.g., parent composite + UI layer).
  final _syncController = StreamController<(SyncStatus, SyncNode)>.broadcast();

  /// Tracks all active [StreamSubscription]s created via [listen].
  ///
  /// Subscriptions are cancelled automatically in [dispose] to prevent
  /// memory leaks from dangling stream listeners.
  final List<StreamSubscription> _internalSubs = [];

  /// The current lifecycle status of this node.
  ///
  /// Updated atomically in [notify] before broadcasting to subscribers.
  SyncStatus _status = SyncStatus.none;

  SyncNode({this.key});

  @override
  SyncStatus get status => _status;

  /// A broadcast stream that emits synchronization lifecycle events.
  ///
  /// Each event is a record (tuple) containing:
  /// - [SyncStatus]: The new lifecycle state of the node.
  /// - [SyncNode]: The origin node where the event was initially triggered.
  ///   For leaf nodes, this is always `this`. For composites, it may be
  ///   a child node whose event is being propagated upward.
  ///
  /// Prefer [listen] over subscribing directly to this stream, as [listen]
  /// automatically tracks and cancels the subscription on [dispose].
  Stream<(SyncStatus, SyncNode)> get events => _syncController.stream;

  /// Releases all active resources and closes the event stream.
  ///
  /// Calls [stop] first to ensure any in-progress work is halted cleanly,
  /// then cancels all tracked [StreamSubscription]s and closes [_syncController].
  ///
  /// Subclasses that override [dispose] must call `super.dispose()` via
  /// the `@mustCallSuper` annotation to ensure proper cleanup.
  @override
  @mustCallSuper
  Future<void> dispose() async {
    await stop();

    for (var sub in _internalSubs) {
      await sub.cancel();
    }
    _internalSubs.clear();

    if (!_syncController.isClosed) {
      await _syncController.close();
    }

    super.dispose();
  }

  /// Initiates the synchronization process for this node.
  ///
  /// For [SyncLeaf], transitions the node to [SyncStatus.idle] (ready state).
  /// For [SyncComposite], starts all child nodes in parallel batches.
  ///
  /// Call [SyncLeaf.triggerSync] separately to begin the actual workload.
  Future<void> start();

  /// Terminates the synchronization process immediately.
  ///
  /// Resets internal state and transitions to [SyncStatus.stop].
  /// Any in-progress work is interrupted at the next [SyncLeaf._handleOperation] checkpoint.
  Future<void> stop();

  /// Suspends the current synchronization task without releasing resources.
  ///
  /// Execution is paused at the next [SyncLeaf._handleOperation] checkpoint.
  /// Progress and state are preserved. Call [resume] to continue.
  void pause();

  /// Resumes a previously suspended synchronization task.
  ///
  /// Unblocks the [SyncLeaf._waitIfPaused] future and continues processing
  /// from where it left off. No-ops if the node is not currently paused.
  void resume();

  /// Broadcasts a status change to all active subscribers.
  ///
  /// Updates [_status], emits to [_syncController], invokes [onNotify],
  /// and calls [notifyListeners] to trigger Flutter widget rebuilds.
  ///
  /// Updates are suppressed if the status has not changed AND no message
  /// is present AND the node is not actively syncing — this prevents
  /// redundant rebuilds from no-op state transitions.
  ///
  /// The [origin] parameter preserves the identity of the node that originally
  /// triggered the event, allowing parent composites to propagate child events
  /// upstream without losing traceability.
  ///
  /// [onNotify] is an optional side-effect callback (e.g., logging) invoked
  /// after the stream event is emitted but before [notifyListeners].
  void notify(SyncStatus status, {SyncNode? origin, void Function()? onNotify}) {
    final bool isStatusChanged = _status != status;
    final bool isSyncing = status == SyncStatus.start || status == SyncStatus.progress;

    // Suppress no-op updates to avoid unnecessary widget rebuilds.
    // Progress updates (isSyncing) always pass through to keep the UI in sync.
    final shouldNotify = isStatusChanged || hasMessage || isSyncing;
    if (!shouldNotify) return;

    _status = status;

    if (!_syncController.isClosed) {
      _syncController.add((status, origin ?? this));

      // Execute side-effect callback (e.g., logging) after emitting the event.
      onNotify?.call();

      // Notify all registered Flutter [ChangeNotifier] listeners (e.g., widgets).
      notifyListeners();
    }
  }

  /// Attaches a listener to the [events] stream for lifecycle monitoring.
  ///
  /// The returned [StreamSubscription] is tracked in [_internalSubs] and
  /// automatically cancelled when [dispose] is called, preventing leaks.
  ///
  /// Used internally by [SyncComposite] to observe child node events,
  /// and can be used externally to monitor any node in the tree.
  StreamSubscription listen(OnSyncNotify onNotify) {
    final sub = _syncController.stream.listen((event) {
      onNotify(event.$1, event.$2);
    });
    _internalSubs.add(sub);
    return sub;
  }
}

/// A mixin providing derived state flags and metric accessors for [SyncNode].
///
/// Separates the read-only query interface from the mutable lifecycle logic
/// in [SyncNode], making it easy to expose only the state-inspection API
/// to consumers (e.g., UI layers or parent composites).
mixin SyncGetter {
  /// Returns the current cumulative statistical summary of this node's work.
  ///
  /// For [SyncLeaf], reflects the operations recorded via [OnSyncOperation].
  /// For [SyncComposite], aggregates summaries from all child nodes.
  SyncSummary get summary;

  /// Returns the total number of items identified for synchronization.
  ///
  /// Set once at the start of a sync session via [SyncTaskState.setTotal].
  /// Used as the denominator for progress calculations.
  int get totalCount;

  /// Returns the number of items successfully processed in the current session.
  ///
  /// Incremented by [SyncTaskState.step] for each non-[SyncSummary.recover] operation.
  int get completedCount;

  /// Returns the overall progress as a normalized ratio between 0.0 and 1.0.
  ///
  /// Calculated as `completedCount / totalCount`. Returns `0.0` before work
  /// starts and `1.0` upon completion. Capped to prevent floating-point overflow.
  double get progress;

  /// Returns an optional error or status message for the node's current state.
  ///
  /// Populated by [SyncLeaf] when an exception is caught during [performSync].
  /// `null` when no error has occurred.
  String? get message;

  /// Returns the current lifecycle status of this node.
  SyncStatus get status;

  /// Returns `true` if the node is ready but not yet processing.
  bool get isIdle => status == SyncStatus.idle;

  /// Returns `true` if the node is actively processing items.
  ///
  /// Covers both [SyncStatus.start] (first item) and [SyncStatus.progress]
  /// (subsequent items) to represent the full active processing window.
  bool get isSyncing => status == SyncStatus.start || status == SyncStatus.progress;

  /// Returns `true` if the node has successfully finished all work.
  bool get isCompleted => status == SyncStatus.complete;

  /// Returns `true` if the node encountered an unrecoverable error.
  bool get isError => status == SyncStatus.error;

  /// Returns `true` if the node is temporarily suspended.
  bool get isPaused => status == SyncStatus.pause;

  /// Returns `true` if the node was explicitly terminated.
  bool get isStopped => status == SyncStatus.stop;

  /// Returns `true` if a message is present.
  ///
  /// Typically indicates an error condition. Used by [SyncNode.notify]
  /// to force an update even when the status has not changed.
  bool get hasMessage => (message != null);
}

/// A mutable state container that tracks progress and statistics for a single [SyncLeaf] task.
///
/// Owned exclusively by its parent [SyncLeaf] and never shared across nodes.
/// Encapsulates all mutable state to keep [SyncLeaf] itself clean and focused
/// on orchestration logic.
///
/// Uses a [Throttler] to regulate the frequency of progress notifications,
/// preventing UI thread saturation during high-throughput data processing.
class SyncTaskState {
  /// The total number of items to be processed in this session.
  int total = 0;

  /// The number of items processed so far (excludes [SyncSummary.recover] operations).
  int completed = 0;

  /// The last emitted progress value (0.0 to 1.0), synchronized with the throttler.
  double progress = 0.0;

  /// The cumulative operation summary for this session.
  SyncSummary summary = const SyncSummary();

  /// An optional error message set when [performSync] throws an exception.
  String? message;

  /// The throttler that gates progress notifications to prevent UI overload.
  late final Throttler<SyncNode?> throttler;

  /// Initializes the internal [Throttler] with the specified [ThrottlerConfig].
  ///
  /// Must be called once before any other methods. [onUpdate] is invoked
  /// whenever the throttler determines a progress notification should be dispatched,
  /// allowing the parent [SyncLeaf] to call [SyncNode.notify].
  SyncTaskState(ThrottlerConfig config, void Function(SyncNode? node) onUpdate) {
    throttler = Throttler(
      threshold: config.threshold,
      precision: config.precision,
      interval: config.interval,
      onUpdate: (p, node) {
        progress = p;
        onUpdate(node);
        SyncLog.fromLeaf(node?.depth ?? 0, '${node?.key}', '🔄 Progress:', progress: p);
      },
    );
  }

  /// Resets all fields to their default values for a fresh sync session.
  ///
  /// Must be called at the start of each [SyncLeaf.triggerSync] invocation
  /// to ensure stale data from a previous session does not persist.
  void reset() {
    total = 0;
    completed = 0;
    progress = 0.0;
    summary = const SyncSummary();
    message = null;
    throttler.reset();
  }

  /// Sets the total workload and initializes the summary with the [total] count.
  ///
  /// Should be called once after [reset], before processing begins.
  /// The [SyncSummary.total] key is pre-populated so that progress can be
  /// calculated correctly from the very first item.
  void setTotal(int count) {
    total = count;
    summary = SyncSummary({SyncSummary.total: count});
  }

  /// Records a single operation and updates progress statistics.
  ///
  /// Appends [operation] to [summary] (repeated [count] times) and advances
  /// the [completed] counter and [progress] ratio — unless the operation is
  /// [SyncSummary.recover], which represents data reconciliation work that
  /// does not count toward the forward progress of the active workload.
  ///
  /// Delegates to [Throttler.update] to gate whether a progress notification
  /// should be dispatched based on the current threshold and interval.
  void step(String operation, SyncNode node, {int count = 1}) {
    summary = summary.plus(operation, count);

    if (operation != SyncSummary.recover) {
      completed += count;
      progress = total > 0 ? completed / total : 0.0;
      throttler.update(progress, node);
    }
  }

  /// Forces the throttler to emit the current progress immediately.
  ///
  /// Called at the end of a sync session to guarantee the final 1.0 (100%)
  /// progress value is dispatched, even if the last [step] did not trigger
  /// a throttled update due to timing or threshold constraints.
  void flush(SyncNode node) {
    throttler.flush(node);
  }
}
