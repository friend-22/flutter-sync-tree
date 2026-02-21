import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// A leaf node in the sync tree that performs actual synchronization work.
///
/// Generic type [T] represents the input data required for the sync operation.
/// It handles automatic retries, progress throttling, and pause/resume logic.
abstract class SyncLeaf<T> extends SyncNode {
  /// Configuration for exponential backoff retries.
  final RetryConfig retryConfig;

  /// Configuration for limiting the frequency of progress updates.
  final ThrottlerConfig throttlerConfig;

  /// Internal state manager for progress and summaries.
  final SyncTaskState _state = SyncTaskState();

  bool _isProcessing = false;
  bool _isStopped = false;

  SyncLeaf({
    super.key,
    this.retryConfig = const RetryConfig(),
    this.throttlerConfig = const ThrottlerConfig(),
  }) {
    _state.setup(throttlerConfig, (node) {
      notify(SyncStatus.progress, origin: node ?? this);
    });
  }

  /// Completer used to suspend execution during a pause.
  Completer<void>? _resumeCompleter;

  @override
  SyncSummary get summary => _state.summary;
  @override
  String? get message => _state.message;
  @override
  double get progress => _state.progress;

  /// Defines how many total items are in the provided [data].
  ///
  /// This count is used to calculate the weighted progress of the entire tree.
  int getCount(T data);

  /// The actual synchronization logic to be implemented by the user.
  ///
  /// Use [onSyncOper] to report each successful item processing
  /// (e.g., `await onSyncOper(SyncSummary.add)`).
  Future<void> performSync(T data, OnSyncOper onSyncOper);

  /// Starts the synchronization process with the given [data].
  ///
  /// This method manages the lifecycle (start -> progress -> complete/error).
  Future<void> triggerSync(T data) async {
    if (_isStopped || _isProcessing) return;
    _isProcessing = true;

    _state.reset();

    try {
      _state.setTotal(getCount(data));
      if (_state.total == 0) {
        notify(SyncStatus.complete);
        return;
      }

      notify(SyncStatus.start);
      SyncPrint.fromLeaf('$key', 'Sync Start: ${_state.total}');

      // Execute the task with exponential backoff and a global timeout.
      await _runWithRetry(() {
        return performSync(data, (oper) async {
          await _waitIfPaused();
          if (_isStopped) throw Exception('Interrupted');
          _state.step(oper, this);
        });
      }).timeout(retryConfig.timeout);

      _state.flush(this);
      notify(SyncStatus.complete);
      SyncPrint.fromLeaf('$key', 'Sync Complete: ${_state.summary}');
    } catch (e) {
      _state.message = e.toString();
      notify(SyncStatus.error);
      SyncPrint.fromLeaf('$key', 'Sync Error: ${_state.message}');
    } finally {
      _isProcessing = false;
    }
  }

  /// Internal wrapper that implements exponential backoff retry logic.
  Future<void> _runWithRetry(Future<void> Function() task) async {
    int tries = 0;
    while (tries < retryConfig.maxTryCount) {
      try {
        await task();
        return;
      } catch (e) {
        tries++;
        SyncPrint.fromLeaf(
            '$key', 'Sync ReTry: $tries/${retryConfig.maxTryCount}');

        if (tries >= retryConfig.maxTryCount || _isStopped) {
          rethrow;
        }

        // delay = baseDelay * 2^tries
        final delayMS = (retryConfig.lazyDelayMs * math.pow(2, tries)).toInt();
        await Future.delayed(Duration(milliseconds: delayMS));
      }
    }
  }

  /// Stops the sync process and releases resources.
  @override
  Future<void> stop() async {
    if (_resumeCompleter?.isCompleted == false) {
      _resumeCompleter?.complete();
    }
    _resumeCompleter = null;

    _isProcessing = false;
    _isStopped = true;

    _state.reset();

    await super.stop();
  }

  /// Suspends the synchronization process.
  @override
  void pause() {
    if (isSyncing && !isPaused) {
      notify(SyncStatus.pause);
      SyncPrint.fromLeaf('$key', 'Sync Paused');
    }
  }

  /// Resumes the synchronization process from where it was paused.
  @override
  void resume() {
    if (isPaused) {
      _resumeCompleter?.complete();
      _resumeCompleter = null;
      notify(SyncStatus.progress);
      SyncPrint.fromLeaf('$key', 'Sync Resumed');
    }
  }

  /// Internal helper to wait if the sync process is currently paused.
  Future<void> _waitIfPaused() async {
    if (!isPaused) return;
    _resumeCompleter ??= Completer<void>();
    return _resumeCompleter!.future;
  }
}

/// A specialized [SyncLeaf] for Firebase Cloud Firestore listeners.
///
/// It listens to a [QuerySnapshot] stream and automatically triggers
/// a synchronization process whenever data changes.
// typedef QuerySnapshots = QuerySnapshot<Map<String, dynamic>>;
//
// abstract class FirebaseSyncLeaf extends SyncLeaf<QuerySnapshots> {
//   /// The Firestore query stream to listen to.
//   final Stream<QuerySnapshots> stream;
//   StreamSubscription<QuerySnapshots>? _sub;
//
//   FirebaseSyncLeaf({
//     required this.stream,
//     super.key,
//     super.retryConfig,
//     super.throttlerConfig,
//   });
//
//   /// By default, it counts the number of document changes in the snapshot.
//   @override
//   int getCount(QuerySnapshots data) => data.docChanges.length;
//
//   /// Starts listening to the Firestore stream.
//   ///
//   /// Each snapshot emitted by the stream will invoke [triggerSync].
//   @override
//   Future<void> start() async {
//     // Prevent multiple subscriptions.
//     if (_sub != null) return;
//
//     _sub = stream.listen(
//       (snapshot) {
//         // triggerSync handles internal state and avoids overlapping runs.
//         triggerSync(snapshot);
//       },
//       onError: (e) {
//         // You can choose to notify error here or let the stream handle it.
//         SyncPrint.fromLeaf('$key', 'Firebase Stream Error: $e');
//       },
//       cancelOnError: false,
//     );
//   }
//
//   /// Cancels the Firestore subscription and stops the sync process.
//   @override
//   Future<void> stop() async {
//     await _sub?.cancel();
//     _sub = null;
//     await super.stop();
//   }
// }
