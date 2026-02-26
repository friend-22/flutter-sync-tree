import 'dart:async';

import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// An internal exception used to break the synchronization loop when a stop signal is received.
class _SyncInterruptedException implements Exception {
  const _SyncInterruptedException();
}

/// A leaf node in the synchronization tree that executes the actual workload.
///
/// The generic type [T] represents the input data required for the operation.
/// This class orchestrates the lifecycle of a single task, featuring:
/// - Automatic retries with exponential backoff.
/// - Progress throttling to optimize UI performance.
/// - Interruptible execution (pause, resume, and stop).
abstract class SyncLeaf<T> extends SyncNode {
  /// Configuration for retry strategy and backoff timing.
  final RetryConfig retryConfig;

  /// Configuration for throttling the frequency of progress updates.
  final ThrottlerConfig throttlerConfig;

  /// Internal state manager for tracking progress metrics and summaries.
  final SyncTaskState _state = SyncTaskState();

  bool _isProcessing = false;
  Completer<void>? _resumeCompleter;

  SyncLeaf({
    super.key,
    this.retryConfig = const RetryConfig(),
    this.throttlerConfig = const ThrottlerConfig(),
  }) {
    // Initializes the state manager with the provided throttler configuration.
    _state.setup(throttlerConfig, (originNode) {
      notify(SyncStatus.progress, origin: originNode ?? this);
    });
  }

  @override
  SyncSummary get summary => _state.summary;

  @override
  String? get message => _state.message;

  @override
  double get progress => _state.progress;

  @override
  int get totalCount => _state.total;

  @override
  int get completedCount => _state.completed;

  /// Calculates the total number of items to be processed from the [data].
  ///
  /// This value is critical for calculating accurate weighted progress.
  int getTotalCount(T data);

  /// The core synchronization logic to be implemented by the subclass.
  ///
  /// Implementation should invoke [onSyncOper] to report each processed item:
  /// ```dart
  /// await onSyncOper(SyncSummary.add);
  /// ```
  Future<void> performSync(T data, OnSyncOperation onSyncOper);

  /// Triggers the synchronization process using the provided [data].
  ///
  /// Manages the full execution lifecycle: Start -> Progress -> Completion or Error.
  Future<void> triggerSync(T data) async {
    if (isStopped || _isProcessing) return;
    _isProcessing = true;

    await _waitIfPaused();

    try {
      _state.reset();
      _state.setTotal(getTotalCount(data));

      // Immediate completion if there is no workload to process.
      if (_state.total == 0) {
        notify(SyncStatus.complete);
        return;
      }

      notify(SyncStatus.start);
      SyncLog.fromLeaf('$key', 'Workload started: ${_state.total} items');

      // Executes the task wrapped in retry and timeout logic.
      await _runWithRetry(() {
        return performSync(data, (operation, {int count = 1}) async {
          await _waitIfPaused();
          if (isStopped) throw const _SyncInterruptedException();
          _state.step(operation, this, count: count);
        });
      });

      if (!isStopped) {
        _state.flush(this);
        notify(SyncStatus.complete);
        SyncLog.fromLeaf('$key', 'Workload completed: ${_state.summary}');
      }
    } catch (e) {
      if (e is _SyncInterruptedException || isStopped) {
        SyncLog.fromLeaf('$key', 'Terminated by user');
      } else {
        _state.message = e.toString();
        notify(SyncStatus.error);
        SyncLog.fromLeaf('$key', 'Failed: ${_state.message}');
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Internal wrapper that handles retry logic with an exponential backoff strategy.
  Future<void> _runWithRetry(Future<void> Function() task) async {
    int retryCount = 0;

    while (true) {
      await _waitIfPaused();
      if (isStopped) return;

      try {
        await task().timeout(retryConfig.timeout);
        return;
      } catch (e) {
        await _waitIfPaused();

        if (isStopped) rethrow;

        retryCount++;
        SyncLog.fromLeaf('$key', 'Retry attempt: $retryCount/${retryConfig.maxTryCount}');

        if (retryCount > retryConfig.maxTryCount || isStopped) {
          rethrow;
        }

        // Notify subscribers of the retry attempt.
        retryConfig.onRetry?.call(retryCount);

        // Wait for the calculated backoff period before the next attempt.
        await Future.delayed(retryConfig.getDelay(retryCount));
      }
    }
  }

  @override
  Future<void> dispose() async {
    _resumeCompleter?.complete();
    _resumeCompleter = null;
    await super.dispose();
  }

  @override
  Future<void> start() async {
    _isProcessing = false;
    await super.start();
  }

  @override
  Future<void> stop() async {
    _state.reset();
    _isProcessing = false;
    await super.stop();
  }

  @override
  void pause() {
    if (!isPaused) {
      notify(SyncStatus.pause);
    }
  }

  @override
  void resume() {
    if (isPaused) {
      _resumeCompleter?.complete();
      _resumeCompleter = null;
      notify(SyncStatus.progress);
    }
  }

  /// Suspends execution if the node is in the [SyncStatus.pause] state.
  Future<void> _waitIfPaused() async {
    if (!isPaused) return;

    SyncLog.fromLeaf('$key', 'Execution suspended (Paused)');
    _resumeCompleter ??= Completer<void>();
    await _resumeCompleter!.future;
  }

  /// Resets the internal state and transitions the node to the [SyncStatus.idle] state.
  void reset() {
    _state.reset();
    notify(SyncStatus.idle);
  }
}
