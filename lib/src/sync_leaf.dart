import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_sync_tree/flutter_sync_tree.dart';
import 'package:flutter_sync_tree/src/sync_types.dart';

/// A leaf node in the sync tree that performs actual work.
abstract class SyncLeaf<T> extends SyncNode {
  final RetryConfig retryConfig;
  final ThrottlerConfig throttlerConfig;
  final SyncTaskState _state = SyncTaskState();

  bool _isProcessing = false;
  bool _isStopped = false;

  SyncLeaf({
    super.key,
    this.retryConfig = const RetryConfig(),
    this.throttlerConfig = const ThrottlerConfig(),
  }) {
    _state.setup(throttlerConfig, (node) {
      notify(SyncType.progress, child: node ?? this);
    });
  }

  Completer<void>? _resumeCompleter;

  @override
  SyncSummary get summary => _state.summary;
  @override
  String? get message => _state.message;
  @override
  double get progress => _state.progress;

  /// Abstract method to extract work count from the incoming data.
  int getCount(T data);

  /// Abstract method defining the actual sync operation logic.
  Future<void> performSync(T data, OnSyncOper onSyncOper);

  /// Entry point to start a sync process with specific data.
  Future<void> triggerSync(T data) async {
    if (_isStopped || _isProcessing) return;
    _isProcessing = true;

    _state.reset();

    try {
      _state.setTotal(getCount(data));
      if (_state.total == 0) {
        notify(SyncType.complete);
        return;
      }

      notify(SyncType.start);
      SyncPrint.fromLeaf('$key', 'Sync Start: ${_state.total}');

      // Execute task with exponential backoff and timeout.
      await _runWithRetry(() {
        return performSync(data, (oper) async {
          await _waitIfPaused();
          if (_isStopped) throw Exception('Interrupted');
          _state.step(oper, this);
        });
      }).timeout(retryConfig.timeout);

      _state.flush(this);
      notify(SyncType.complete);
      SyncPrint.fromLeaf('$key', 'Sync Complete: ${_state.summary}');
    } catch (e) {
      _state.message = e.toString();
      notify(SyncType.error);
      SyncPrint.fromLeaf('$key', 'Sync Error: ${_state.message}');
    } finally {
      _isProcessing = false;
    }
  }

  /// Internal retry wrapper logic.
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

        final delayMS = (retryConfig.lazyDelayMs * math.pow(2, tries)).toInt();
        await Future.delayed(Duration(milliseconds: delayMS));
      }
    }
  }

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

  @override
  void pause() {
    if (isSyncing && !isPaused) {
      notify(SyncType.pause);
      SyncPrint.fromLeaf('$key', 'Sync Paused');
    }
  }

  @override
  void resume() {
    if (isPaused) {
      _resumeCompleter?.complete();
      _resumeCompleter = null;
      notify(SyncType.progress);
      SyncPrint.fromLeaf('$key', 'Sync Resumed');
    }
  }

  /// Suspends execution of the current loop if the throttler is paused.
  Future<void> _waitIfPaused() async {
    if (!isPaused) return;
    _resumeCompleter ??= Completer<void>();
    return _resumeCompleter!.future;
  }
}

/// A specialized Leaf for Firebase Cloud Firestore listeners.
// typedef QuerySnapshots = QuerySnapshot<Map<String, dynamic>>;
// abstract class FirebaseSyncLeaf extends SyncLeaf<QuerySnapshots> {
//   final Stream<QuerySnapshots> stream;
//   StreamSubscription<QuerySnapshots>? _sub;
//
//   FirebaseSyncLeaf({required this.stream, super.key});
//
//   @override
//   int getCount(QuerySnapshots data) => data.docChanges.length;
//
//   @override
//   Future<void> start() async {
//     _sub = stream.listen((snapshot) => triggerSync(snapshot));
//   }
//
//   @override
//   Future<void> stop() async {
//     _sub?.cancel();
//     _sub = null;
//     await super.stop();
//   }
// }
