import 'dart:async';

import 'package:example/simulator/sync_simulator.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// Represents the type of document changes, mimicking Firebase Firestore's [DocumentChangeType].
enum FakeDocumentChangeType { added, modified, removed }

/// A mock snapshot that holds a list of document changes.
class FakeQuerySnapshot {
  final List<FakeDocumentChangeType> docChanges;

  FakeQuerySnapshot(this.docChanges);
}

/// A specialized [SyncLeaf] that handles Firebase-like stream data.
class FakeFirebaseLeaf extends SyncLeaf<FakeQuerySnapshot> {
  final Stream<FakeQuerySnapshot> stream;
  StreamSubscription<FakeQuerySnapshot>? _sub;

  // Internal flag to track if this leaf has successfully synchronized at least once.
  bool _receivedData = false;

  FakeFirebaseLeaf({required this.stream, required super.key, super.retryConfig, super.throttlerConfig});

  bool get isReceivedData => _receivedData;

  @override
  int getTotalCount(FakeQuerySnapshot data) => data.docChanges.length;

  @override
  Future<void> start() async {
    await super.start();

    // Listening to the live stream and triggering sync whenever a new snapshot arrives.
    _sub = stream.listen((snapshot) => triggerSync(snapshot));
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await super.stop();
  }

  @override
  Future<void> performSync(FakeQuerySnapshot data, OnSyncOperation onSyncOper) async {
    // 💡 Validation Logic: Too Large data is treated as a sync failure.
    if (data.docChanges.length > 50) {
      throw Exception('🚨 Payload Too Large: ${data.docChanges.length} changes detected (Max: 50)');
    }

    _receivedData = false;
    for (var change in data.docChanges) {
      // Map domain-specific changes to SyncSummary operations.
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
      // Artificial delay to simulate network/DB latency.
      await Future.delayed(Duration(milliseconds: 30 + SyncSimulator.random.nextInt(90)));
    }
    _receivedData = true; // Mark as successfully synced.
  }

  void resetDataStatus() => _receivedData = false;
}

/// A [SyncLeaf] that waits for another "primary" leaf to finish before it starts its own sync.
/// Perfect for handling data dependencies (e.g., Syncing 'Posts' only after 'Users' are ready).
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
  Future<void> performSync(FakeQuerySnapshot data, OnSyncOperation onSyncOper) async {
    //💡 Check Dependency: If the primary leaf isn't ready, fail intentionally.
    // The SyncTree's Retry mechanism will catch this and try again based on RetryConfig.
    if (!primary.isReceivedData) {
      SyncLog.fromLeaf('$key', 'Waiting for ${primary.key}...');
      throw Exception('Dependency not met: ${primary.key}');
    }

    // Reset retry count once the dependency is met and sync starts.
    retryCount = 0;
    await super.performSync(data, onSyncOper);
  }

  /// Hook to update the UI with the current retry attempt.
  void onRetry(int tries) {
    retryCount = tries;
    notify(status); // Manually notify listeners to show "Retry X" in UI.
  }
}

/// Generates mock Firebase snapshots with random document changes.
class FakeQuerySnapshotSimulator extends SyncSimulator<FakeQuerySnapshot> {
  final int maxCount;
  final int minCount;

  FakeQuerySnapshotSimulator({
    required super.controller,
    required this.maxCount,
    required this.minCount,
    super.intervalMs,
  });

  @override
  FakeQuerySnapshot generateNext({bool isError = false}) {
    final randCount = isError ? 51 : minCount + SyncSimulator.random.nextInt(maxCount - minCount + 1);
    final changes = List.generate(randCount, (index) {
      return FakeDocumentChangeType.values[SyncSimulator.random.nextInt(
        FakeDocumentChangeType.values.length,
      )];
    });
    return FakeQuerySnapshot(changes);
  }
}

/// Simulates a scenario where two different streams receive data simultaneously.
class TwoWaySyncSimulator extends FakeQuerySnapshotSimulator {
  final StreamController<FakeQuerySnapshot> lateController;

  TwoWaySyncSimulator({
    required super.controller,
    required super.maxCount,
    required super.minCount,
    required this.lateController,
    super.intervalMs,
  });

  @override
  void emitData() {
    final data = generateNext();

    // Decide which controller gets the 'poisoned' data.
    final errData = shouldError ? generateNext(isError: true) : data;
    final randBool = SyncSimulator.random.nextBool();

    // Mimics real-world inconsistency where one stream might fail while others succeed.
    lateController.add(randBool ? data : errData);
    controller.add(randBool ? errData : data);
  }
}
