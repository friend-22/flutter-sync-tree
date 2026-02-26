import 'dart:async';

import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// The base abstract class for all synchronization units, including Leaves and Composites.
///
/// It establishes the standard lifecycle (start, stop, pause, resume)
/// and provides a broadcast stream for real-time monitoring of the synchronization tree.
abstract class SyncNode with SyncGetter {
  /// A unique identifier for the node, used for telemetry, logging, and searching.
  final String? key;

  final _syncController = StreamController<(SyncStatus, SyncNode)>.broadcast();
  final List<StreamSubscription> _internalSubs = [];
  SyncStatus _status = SyncStatus.none;

  SyncNode({this.key});

  @override
  SyncStatus get status => _status;

  /// A broadcast stream that emits synchronization lifecycle events.
  ///
  /// Each event is a record (tuple) containing:
  /// - [SyncStatus]: The new state of the node.
  /// - [SyncNode]: The origin node where the event was initially triggered.
  Stream<(SyncStatus, SyncNode)> get events => _syncController.stream;

  /// Releases active resources, cancels internal subscriptions, and closes the event stream.
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
  ///
  /// Transitions the state to [SyncStatus.idle] to indicate it is ready for processing.
  Future<void> start() async {
    notify(SyncStatus.idle);
    SyncLog.fromLeaf('$key', 'Transitioned to Idle');
  }

  /// Terminates the synchronization process and transitions the state to [SyncStatus.stop].
  Future<void> stop() async {
    notify(SyncStatus.stop);
  }

  /// Suspends the current synchronization task without releasing resources.
  void pause();

  /// Resumes a previously suspended synchronization task.
  void resume();

  /// Broadcasts a status change to all active subscribers.
  ///
  /// The [origin] parameter allows parent nodes to propagate child events
  /// while preserving the identity of the node that generated the event.
  void notify(SyncStatus status, {SyncNode? origin}) {
    final bool isStatusChanged = _status != status;
    final bool isSyncing = status == SyncStatus.start || status == SyncStatus.progress;

    // Prevents redundant notifications unless it's a critical state change
    // or an active progress update.
    if (!isStatusChanged && !hasMessage && !isSyncing) {
      return;
    }

    _status = status;
    if (!_syncController.isClosed) {
      _syncController.add((status, origin ?? this));
    }
  }

  /// Attaches a listener to the [events] stream for lifecycle monitoring.
  ///
  /// Subscriptions are tracked internally and automatically cancelled on [dispose].
  StreamSubscription listen(OnSyncNotify onNotify) {
    final sub = _syncController.stream.listen((event) {
      onNotify(event.$1, event.$2);
    });
    _internalSubs.add(sub);
    return sub;
  }
}

/// A mixin providing derived state logic and status flags for [SyncNode].
mixin SyncGetter {
  /// Returns the current cumulative statistical summary.
  SyncSummary get summary;

  /// Returns the total number of items identified for synchronization.
  int get totalCount;

  /// Returns the number of items successfully processed in the current session.
  int get completedCount;

  /// Returns the overall progress as a normalized ratio between 0.0 and 1.0.
  double get progress;

  /// Returns an optional error or status message associated with the node's current state.
  String? get message;

  /// Returns the current lifecycle status.
  SyncStatus get status;

  bool get isIdle => status == SyncStatus.idle;
  bool get isSyncing => status == SyncStatus.start || status == SyncStatus.progress;
  bool get isCompleted => status == SyncStatus.complete;
  bool get isError => status == SyncStatus.error;
  bool get isPaused => status == SyncStatus.pause;
  bool get isStopped => status == SyncStatus.stop;

  /// Returns true if a message is present, typically representing an error or diagnostic info.
  bool get hasMessage => (message != null);
}

/// A mutable state container that tracks progress and statistics for a discrete task.
///
/// It utilizes a [Throttler] to regulate frequency of progress updates,
/// preventing UI performance degradation during rapid data processing.
class SyncTaskState {
  int total = 0;
  int completed = 0;
  double progress = 0.0;
  SyncSummary summary = const SyncSummary();
  String? message;
  late Throttler<SyncNode?> throttler;

  /// Initializes the internal [Throttler] with the specified configuration.
  ///
  /// [onUpdate] is invoked when throttle conditions (threshold or interval) are met.
  void setup(ThrottlerConfig config, void Function(SyncNode? node) onUpdate) {
    throttler = Throttler(
      threshold: config.threshold,
      precision: config.precision,
      interval: config.interval,
      onUpdate: (p, node) {
        progress = p;
        onUpdate(node);
        SyncLog.fromLeaf('${node?.key}', 'Progress updated: ${(progress * 100).toStringAsFixed(1)}%');
      },
    );
  }

  /// Resets the internal state to its default values for a fresh session.
  void reset() {
    total = 0;
    completed = 0;
    progress = 0.0;
    summary = const SyncSummary();
    message = null;
    throttler.reset();
  }

  /// Sets the total workload count and initializes the [summary] with the total.
  void setTotal(int count) {
    total = count;
    summary = SyncSummary({SyncSummary.total: count});
  }

  /// Records an operation and increments progress statistics.
  ///
  /// Operations marked as [SyncSummary.recover] are logged in the summary
  /// but do not advance the [completed] count, as they represent data
  /// reconciliation rather than progress on active workload.
  void step(String operation, SyncNode node, {int count = 1}) {
    for (int i = 0; i < count; i++) {
      summary = summary + operation;
    }

    if (operation != SyncSummary.recover) {
      completed += count;
      progress = total > 0 ? completed / total : 0.0;
      throttler.update(progress, node);
    }
  }

  /// Forces the throttler to emit the current state immediately.
  ///
  /// Essential for ensuring the final 1.0 (100%) progress is dispatched upon completion.
  void flush(SyncNode node) {
    throttler.flush(node);
  }
}
