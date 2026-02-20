import 'dart:async';

import 'package:flutter_sync_tree/flutter_sync_tree.dart';
import 'package:flutter_sync_tree/src/sync_types.dart';

/// The base abstract class for all synchronization units (Leaf or Composite).
abstract class SyncNode with SyncGetter {
  final String? key;
  final _syncController = StreamController<(SyncType, SyncNode)>.broadcast();
  final List<StreamSubscription> _internalSubs = [];
  SyncType _syncType = SyncType.none;

  SyncNode({this.key});

  @override
  SyncType get syncType => _syncType;

  /// Stream emitting status updates for this node.
  Stream<(SyncType, SyncNode)> get syncStream => _syncController.stream;

  Future<void> start();

  /// Stops the synchronization and cleans up resources.
  Future<void> stop() async {
    notify(SyncType.stop);

    await _cleanup();

    if (!_syncController.isClosed) _syncController.close();
  }

  void pause();
  void resume();

  /// Broadcasts a status change to listeners.
  void notify(SyncType type, {SyncNode? child}) {
    _syncType = type;
    if (!_syncController.isClosed) {
      _syncController.add((type, child ?? this));
    }
  }

  void listen(OnSyncNotify onNotify) {
    final sub = _syncController.stream.listen((event) {
      onNotify(event.$1, event.$2);
    });
    _internalSubs.add(sub);
  }

  Future<void> _cleanup() async {
    for (var sub in _internalSubs) {
      await sub.cancel();
    }
    _internalSubs.clear();
  }
}

/// Mixin providing common getter logic for any object involved in the sync lifecycle.
mixin SyncGetter {
  SyncSummary get summary;
  double get progress;
  String? get message;
  SyncType get syncType;

  bool get isSyncing =>
      syncType == SyncType.start || syncType == SyncType.progress;
  bool get isComplete => syncType == SyncType.complete;
  bool get isPaused => syncType == SyncType.pause;
  bool get hasError => (message != null);
}

/// Holds the mutable state for an individual sync task execution.
class SyncTaskState {
  int total = 0;
  int completed = 0;
  double progress = 0.0;
  SyncSummary summary = const SyncSummary();
  String? message;
  late Throttler<SyncNode?> throttler;

  /// Initializes the throttler to limit the frequency of progress updates.
  void setup(ThrottlerConfig config, void Function(SyncNode?) onUpdate) {
    throttler = Throttler(
      threshold: config.threshold,
      precision: config.precision,
      duration: config.duration,
      onUpdate: (p, node) {
        progress = p;
        onUpdate(node);
        SyncPrint.fromLeaf('${node?.key}', 'progress: $progress');
      },
    );
  }

  void reset() {
    total = 0;
    completed = 0;
    progress = 0.0;
    summary = const SyncSummary();
    message = null;
    throttler.reset();
  }

  void setTotal(int count) {
    total = count;
    summary = SyncSummary({SyncSummary.total: count});
  }

  /// Increments progress and updates the summary for a specific operation.
  void step(String oper, SyncNode node) {
    summary = summary + oper;

    // Recovery doesn't count towards completion progress as it's a "no-op" or "fix-up".
    if (oper != SyncSummary.recover) {
      completed++;
      progress = total > 0 ? completed / total : 0.0;
      throttler.update(progress, node);
    }
  }

  /// Ensures the final 1.0 progress state is emitted.
  void flush(SyncNode node) {
    throttler.flush(node);
  }
}
