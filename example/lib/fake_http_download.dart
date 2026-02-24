import 'dart:async';

import 'package:example/sync_simulator.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

class FakeDownloadSnapshot {
  final int received;
  FakeDownloadSnapshot(this.received);
}

class FakeDownloadPackage {
  final int totalSize;
  final Stream<FakeDownloadSnapshot> stream;
  FakeDownloadPackage(this.totalSize, this.stream);
}

class FakeHttpDownloadLeaf extends SyncLeaf<FakeDownloadPackage> {
  final Stream<FakeDownloadPackage> stream;
  StreamSubscription<FakeDownloadPackage>? _sub;

  FakeHttpDownloadLeaf({required this.stream, super.key, super.retryConfig, super.throttlerConfig});

  @override
  int getTotalCount(FakeDownloadPackage data) => data.totalSize;

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
  Future<void> performSync(FakeDownloadPackage data, OnSyncOper onSyncOper) async {
    int lastBytes = 0;

    await for (final snapshot in data.stream) {
      if (isStopped) break;

      final delta = snapshot.received - lastBytes;
      if (delta > 0) {
        lastBytes = snapshot.received;
        await onSyncOper('data', count: delta);
      }
    }
  }
}

class FakeHttpSimulator extends SyncSimulator<FakeDownloadPackage> {
  FakeHttpSimulator({required super.controller});

  @override
  FakeDownloadPackage generateData() {
    final total = 3000 + random.nextInt(7001);
    return FakeDownloadPackage(total, _createStream(total));
  }

  Stream<FakeDownloadSnapshot> _createStream(int total) async* {
    int current = 0;

    final step = 100 + random.nextInt(901);

    while (current < total) {
      await Future.delayed(const Duration(milliseconds: 300));
      current += step;

      if (current > total) current = total;
      yield FakeDownloadSnapshot(current);
    }
  }
}
