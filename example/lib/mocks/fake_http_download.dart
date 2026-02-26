import 'dart:async';
import 'dart:math';

import 'package:example/simulator/sync_simulator.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// Represents a chunk of downloaded data, mimicking a typical HTTP progress event.
class FakeDownloadSnapshot {
  final int received; // Bytes received so far.

  FakeDownloadSnapshot(this.received);
}

/// Represents a downloadable resource with a known total size and a data stream.
class FakeDownloadPackage {
  final int totalSize;
  final Stream<FakeDownloadSnapshot> stream;

  FakeDownloadPackage(this.totalSize, this.stream);
}

/// A [SyncLeaf] designed to handle continuous streaming data, such as file downloads.
class FakeHttpDownloadLeaf extends SyncLeaf<FakeDownloadPackage> {
  final Stream<FakeDownloadPackage> stream;
  StreamSubscription<FakeDownloadPackage>? _sub;

  FakeHttpDownloadLeaf({required this.stream, super.key, super.retryConfig, super.throttlerConfig});

  @override
  int getTotalCount(FakeDownloadPackage data) => data.totalSize;

  @override
  Future<void> start() async {
    await super.start();

    // Listen for incoming download requests/packages.
    _sub = stream.listen((snapshot) => triggerSync(snapshot));
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await super.stop();
  }

  @override
  Future<void> performSync(FakeDownloadPackage data, OnSyncOperation onSyncOper) async {
    // 💡 HTTP Specific Validation: Triggers an error if storage is insufficient for the file size.
    if (data.totalSize > 10000) {
      throw Exception('🚨 Storage Full: Cannot save ${data.totalSize} bytes to local storage.');
    }

    int lastBytes = 0;

    //💡 Handling Nested Streams: Processing progress updates from the download stream.
    await for (final snapshot in data.stream) {
      // Respect the sync engine's control flow (e.g., if the user stops the tree).
      if (isStopped) break;

      // Calculate the delta (incremental change) to update the progress bar smoothly.
      final delta = snapshot.received - lastBytes;
      if (delta > 0) {
        lastBytes = snapshot.received;

        // Update the progress by reporting the number of new bytes 'synced'.
        await onSyncOper('data', count: delta);
      }
    }
  }
}

/// Simulates an HTTP server that "streams" a resource in chunks.
class FakeHttpSimulator extends SyncSimulator<FakeDownloadPackage> {
  bool _isDownloading = false;

  FakeHttpSimulator({required super.controller, super.intervalMs});

  @override
  bool get canNextGen => !_isDownloading;

  @override
  FakeDownloadPackage generateNext({bool isError = false}) {
    // Randomize file size between 3,000 and 10,000 bytes.
    final total = isError ? 10001 : 3000 + SyncSimulator.random.nextInt(7001);
    return FakeDownloadPackage(total, _createStream(total));
  }

  /// Creates a mock stream that yields progress updates at 300ms intervals.
  Stream<FakeDownloadSnapshot> _createStream(int total) async* {
    _isDownloading = true;
    int current = 0;

    // Randomize the chunk size (download speed).
    final step = 100 + SyncSimulator.random.nextInt(901);

    while (current < total) {
      await Future.delayed(Duration(milliseconds: 30 + Random().nextInt(90)));
      current += step;

      if (current > total) current = total;
      yield FakeDownloadSnapshot(current);
    }

    _isDownloading = false;
  }
}
