import 'dart:async';

import 'package:example/sync_simulator.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

enum FakeDocumentChangeType { added, modified, removed }

class FakeQuerySnapshot {
  final List<FakeDocumentChangeType> docChanges;

  FakeQuerySnapshot(this.docChanges);
}

class FakeFirebaseLeaf extends SyncLeaf<FakeQuerySnapshot> {
  final Stream<FakeQuerySnapshot> stream;
  StreamSubscription<FakeQuerySnapshot>? _sub;

  bool _receivedData = false;

  FakeFirebaseLeaf({required this.stream, required super.key, super.retryConfig, super.throttlerConfig});

  bool get isReceivedData => _receivedData;

  @override
  int getTotalCount(FakeQuerySnapshot data) => data.docChanges.length;

  @override
  Future<void> start() async {
    await super.start();
    _sub = stream.listen((snapshot) => triggerSync(snapshot));
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await super.stop();
  }

  @override
  Future<void> performSync(FakeQuerySnapshot data, OnSyncOper onSyncOper) async {
    _receivedData = false;
    for (var change in data.docChanges) {
      switch (change) {
        case FakeDocumentChangeType.added:
          await onSyncOper(SyncSummary.add);
          // await onSyncOper(SyncSummary.latest);
          // await onSyncOper(SyncSummary.recover);
          break;
        case FakeDocumentChangeType.modified:
          await onSyncOper(SyncSummary.update);
          break;
        case FakeDocumentChangeType.removed:
          await onSyncOper(SyncSummary.remove);
          break;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _receivedData = true;
  }

  void resetDataStatus() {
    _receivedData = false;
  }
}

class FakeQuerySnapshotSimulator extends SyncSimulator<FakeQuerySnapshot> {
  final int maxCount;
  final int minCount;

  FakeQuerySnapshotSimulator({required super.controller, required this.maxCount, required this.minCount});

  @override
  FakeQuerySnapshot generateData() {
    final randCount = minCount + random.nextInt(maxCount - minCount + 1);
    final changes = List.generate(randCount, (index) {
      return FakeDocumentChangeType.values[random.nextInt(FakeDocumentChangeType.values.length)];
    });
    return FakeQuerySnapshot(changes);
  }
}

class LateFakeFirebaseLeaf extends FakeFirebaseLeaf {
  final FakeFirebaseLeaf primary;

  int retryCount = 0;

  LateFakeFirebaseLeaf({
    required this.primary,
    required super.stream,
    required super.key,
    super.retryConfig,
    super.throttlerConfig,
  });

  @override
  Future<void> performSync(FakeQuerySnapshot data, OnSyncOper onSyncOper) async {
    if (!primary.isReceivedData) {
      SyncPrint.fromLeaf('$key', 'Waiting for ${primary.key}...');
      throw Exception('Dependency not met: ${primary.key}');
    }
    retryCount = 0;

    await super.performSync(data, onSyncOper);
  }

  void onRetry(int tries) {
    retryCount = tries;
    notify(status);
  }
}

class TwoWaySyncSimulator extends FakeQuerySnapshotSimulator {
  final StreamController<FakeQuerySnapshot> lateController;

  TwoWaySyncSimulator({
    required super.controller,
    required super.maxCount,
    required super.minCount,
    required this.lateController,
  });

  @override
  Future<void> start(SyncNode rootNode) async {
    if (isWorking) return;
    isWorking = true;

    while (isWorking) {
      if (!rootNode.isStopped && !rootNode.isPaused) {
        final data = generateData();
        lateController.add(data);
        controller.add(data);
        onDataInjected?.call();
      }
      await Future.delayed(const Duration(milliseconds: 3000));
    }
    isWorking = false;
  }
}
