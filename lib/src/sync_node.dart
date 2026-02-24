import 'dart:async';

import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// The base abstract class for all synchronization units, including Leaves and Composites.
///
/// It establishes the standard lifecycle (start, stop, pause, resume)
/// and provides a broadcast stream for real-time monitoring of the sync tree.
abstract class SyncNode with SyncGetter {
  /// A unique identifier for the node, used for logging and searching.
  final String? key;

  final _syncController = StreamController<(SyncStatus, SyncNode)>.broadcast();
  final List<StreamSubscription> _internalSubs = [];
  SyncStatus _status = SyncStatus.none;

  SyncNode({this.key});

  @override
  SyncStatus get status => _status;

  /// A broadcast stream that emits synchronization events.
  ///
  /// Each event is a record (tuple) containing:
  /// - [SyncStatus]: The new state of the node.
  /// - [SyncNode]: The origin node where the event was triggered.
  Stream<(SyncStatus, SyncNode)> get events => _syncController.stream;

  /// Releases all active resources, cancels subscriptions, and closes the event stream.
  Future<void> dispose() async {
    await stop();

    for (var sub in _internalSubs) {
      await sub.cancel();
    }
    _internalSubs.clear();

    if (!_syncController.isClosed) {
      await _syncController.close();
    }
  }

  /// Initiates the synchronization process for this node.
  Future<void> start() async {
    notify(SyncStatus.idle);
    SyncPrint.fromLeaf('$key', 'Idle');
  }

  /// Terminates the synchronization and transitions the state to [SyncStatus.stop].
  Future<void> stop() async {
    notify(SyncStatus.stop);
  }

  /// Suspends the current synchronization task without releasing resources.
  void pause();

  /// Resumes a previously paused synchronization task.
  void resume();

  /// Broadcasts a status change to all subscribers.
  ///
  /// The [origin] parameter allows parent nodes to re-broadcast child events
  /// while preserving the identity of the node where the event first occurred.
  void notify(SyncStatus status, {SyncNode? origin}) {
    _status = status;
    if (!_syncController.isClosed) {
      _syncController.add((status, origin ?? this));
    }
  }

  /// Attaches a listener to the [events] stream for lifecycle monitoring.
  ///
  /// Subscriptions are managed internally and are automatically cleaned up on [dispose].
  void listen(OnSyncNotify onNotify) {
    final sub = _syncController.stream.listen((event) {
      onNotify(event.$1, event.$2);
    });
    _internalSubs.add(sub);
  }
}

/// A mixin providing derived state logic and boolean flags for [SyncNode].
mixin SyncGetter {
  /// Returns the current cumulative statistical summary.
  SyncSummary get summary;

  /// Returns the total number of items to be synchronized.
  int get totalCount;

  /// Returns the number of items successfully processed.
  int get completedCount;

  /// Returns the overall progress as a ratio between 0.0 and 1.0.
  double get progress;

  /// Returns an optional error or status message associated with the node.
  String? get message;

  /// Returns the current lifecycle state.
  SyncStatus get status;

  bool get isIdle => status == SyncStatus.idle;
  bool get isSyncing => status == SyncStatus.start || status == SyncStatus.progress;
  bool get isCompleted => status == SyncStatus.complete;
  bool get isPaused => status == SyncStatus.pause;
  bool get isStopped => status == SyncStatus.stop;

  /// Returns true if a message is present, typically indicating an error or warning.
  bool get hasMessage => (message != null);
}

/// A mutable state container that tracks progress and statistics for a single task.
///
/// It utilizes a [Throttler] to regulate progress updates, preventing
/// UI performance degradation from high-frequency events.
class SyncTaskState {
  int total = 0;
  int completed = 0;
  double progress = 0.0;
  SyncSummary summary = const SyncSummary();
  String? message;
  late Throttler<SyncNode?> throttler;

  /// Initializes the [Throttler] with the provided [config].
  ///
  /// [onUpdate] is called when the throttler's conditions (time/threshold) are met.
  void setup(ThrottlerConfig config, void Function(SyncNode?) onUpdate) {
    throttler = Throttler(
      threshold: config.threshold,
      precision: config.precision,
      duration: config.duration,
      onUpdate: (p, node) {
        progress = p;
        onUpdate(node);
        SyncPrint.fromLeaf('${node?.key}', 'Progress: ${(progress * 100).toStringAsFixed(1)}%');
      },
    );
  }

  /// Resets the internal state to initial values.
  void reset() {
    total = 0;
    completed = 0;
    progress = 0.0;
    summary = const SyncSummary();
    message = null;
    throttler.reset();
  }

  /// Configures the total item count and prepares the initial [summary].
  void setTotal(int count) {
    total = count;
    summary = SyncSummary({SyncSummary.total: count});
  }

  /// Increments progress and updates the statistics for a specific operation.
  ///
  /// Operations with [SyncSummary.recover] are recorded in the summary but
  /// do not advance the [completed] count, as they represent data
  /// reconciliation rather than progress on new work.
  void step(String oper, SyncNode node, {int count = 1}) {
    for (int i = 0; i < count; i++) {
      summary = summary + oper;
    }

    if (oper != SyncSummary.recover) {
      completed += count;
      progress = total > 0 ? completed / total : 0.0;
      throttler.update(progress, node);
    }
  }

  /// Forces the throttler to push the current state immediately.
  ///
  /// Typically called upon task completion to ensure the final 1.0 (100%) progress is emitted.
  void flush(SyncNode node) {
    throttler.flush(node);
  }
}
