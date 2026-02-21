import 'dart:async';

import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// The base abstract class for all synchronization units (Leaf or Composite).
///
/// It defines the standard lifecycle: start, stop, pause, and resume,
/// and provides a broadcast stream for real-time event monitoring.
abstract class SyncNode with SyncGetter {
  final String? key;
  final _syncController = StreamController<(SyncStatus, SyncNode)>.broadcast();
  final List<StreamSubscription> _internalSubs = [];
  SyncStatus _status = SyncStatus.none;

  SyncNode({this.key});

  @override
  SyncStatus get status => _status;

  /// A broadcast stream that emits synchronization events.
  ///
  /// Each event is a record containing:
  /// - [SyncStatus]: The state of the sync (e.g., start, progress, error).
  /// - [SyncNode]: The node where the event originated (useful for tree tracking).
  Stream<(SyncStatus, SyncNode)> get events => _syncController.stream;

  /// Starts the synchronization process for this node.
  Future<void> start();

  /// Stops the synchronization and releases all active resources and subscriptions.
  Future<void> stop() async {
    notify(SyncStatus.stop);
    await _cleanup();
    if (!_syncController.isClosed) _syncController.close();
  }

  /// Suspends the current synchronization task.
  void pause();

  /// Resumes a paused synchronization task.
  void resume();

  /// Broadcasts a status change to all listeners.
  ///
  /// The [origin] parameter allows re-broadcasting events from child nodes
  /// while preserving the information of where the event started.
  void notify(SyncStatus status, {SyncNode? origin}) {
    _status = status;
    if (!_syncController.isClosed) {
      _syncController.add((status, origin ?? this));
    }
  }

  /// Attaches a listener to the [events] stream.
  ///
  /// Subscriptions are managed internally and cancelled automatically on [stop].
  void listen(OnSyncNotify onNotify) {
    final sub = _syncController.stream.listen((event) {
      onNotify(event.$1, event.$2);
    });
    _internalSubs.add(sub);
  }

  /// Cancels all internal stream subscriptions.
  Future<void> _cleanup() async {
    for (var sub in _internalSubs) {
      await sub.cancel();
    }
    _internalSubs.clear();
  }
}

/// A mixin providing derived state logic based on the core sync properties.
mixin SyncGetter {
  /// The current statistical summary of the synchronization.
  SyncSummary get summary;

  /// The progress ratio from 0.0 to 1.0.
  double get progress;

  /// An optional error or status message.
  String? get message;

  /// The current state in the [SyncStatus] lifecycle.
  SyncStatus get status;

  bool get isSyncing =>
      status == SyncStatus.start || status == SyncStatus.progress;
  bool get isComplete => status == SyncStatus.complete;
  bool get isPaused => status == SyncStatus.pause;
  bool get hasError => (message != null);
}

/// Manages the mutable state of an individual sync task during its execution.
///
/// It tracks total counts, completed items, and uses a [Throttler] to
/// prevent UI jank from excessive progress updates.
class SyncTaskState {
  int total = 0;
  int completed = 0;
  double progress = 0.0;
  SyncSummary summary = const SyncSummary();
  String? message;
  late Throttler<SyncNode?> throttler;

  /// Initializes the throttler to limit progress update frequency.
  ///
  /// [config] determines how often [onUpdate] is triggered.
  void setup(ThrottlerConfig config, void Function(SyncNode?) onUpdate) {
    throttler = Throttler(
      threshold: config.threshold,
      precision: config.precision,
      duration: config.duration,
      onUpdate: (p, node) {
        progress = p;
        onUpdate(node);
        SyncPrint.fromLeaf('${node?.key}',
            'Progress updated: ${(progress * 100).toStringAsFixed(1)}%');
      },
    );
  }

  /// Resets the state to its initial empty values.
  void reset() {
    total = 0;
    completed = 0;
    progress = 0.0;
    summary = const SyncSummary();
    message = null;
    throttler.reset();
  }

  /// Sets the total number of items to sync and initializes the [summary].
  void setTotal(int count) {
    total = count;
    summary = SyncSummary({SyncSummary.total: count});
  }

  /// Increments progress and updates the summary for a specific operation [oper].
  ///
  /// Note: [SyncSummary.recover] operations are tracked in the summary but
  /// do not increment the [completed] progress, as they represent
  /// data reconciliation rather than standard task completion.
  void step(String oper, SyncNode node) {
    summary = summary + oper;

    // 'Recover' represents healing existing data, so it doesn't
    // contribute to the progress of 'new' work being done.
    if (oper != SyncSummary.recover) {
      completed++;
      progress = total > 0 ? completed / total : 0.0;
      throttler.update(progress, node);
    }
  }

  /// Forces the throttler to emit the current state immediately.
  /// Usually called when a task completes to ensure the final 1.0 is sent.
  void flush(SyncNode node) {
    throttler.flush(node);
  }
}
