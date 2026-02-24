import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// An internal exception used to break the synchronization loop when stopped.
class _SyncInterruptedException implements Exception {
  const _SyncInterruptedException();
}

/// A leaf node in the sync tree that performs actual synchronization work.
///
/// Generic type [T] represents the input data required for the sync operation.
/// This class manages the complex lifecycle of a single task, including:
/// - Automatic retries with exponential backoff.
/// - Progress throttling for UI optimization.
/// - Pause and resume capabilities during execution.
abstract class SyncLeaf<T> extends SyncNode {
  /// Configuration for retry attempts and backoff timing.
  final RetryConfig retryConfig;

  /// Configuration for throttling frequency of progress updates.
  final ThrottlerConfig throttlerConfig;

  /// Internal state manager for tracking progress and summaries.
  final SyncTaskState _state = SyncTaskState();

  bool _isProcessing = false;
  Completer<void>? _resumeCompleter;

  SyncLeaf({
    super.key,
    this.retryConfig = const RetryConfig(),
    this.throttlerConfig = const ThrottlerConfig(),
  }) {
    // Setup the state manager with the provided throttler configuration.
    _state.setup(throttlerConfig, (node) {
      notify(SyncStatus.progress, origin: node ?? this);
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

  /// Determines the total number of items to be processed within the given [data].
  ///
  /// This value is essential for accurate weighted progress calculation.
  int getTotalCount(T data);

  /// The core synchronization logic to be implemented by the user.
  ///
  /// Users should call [onSyncOper] to report each processed item:
  /// ```dart
  /// await onSyncOper(SyncSummary.add);
  /// ```
  Future<void> performSync(T data, OnSyncOper onSyncOper);

  /// Triggers the synchronization process with the provided [data].
  ///
  /// This method orchestrates the lifecycle: Start -> Progress -> Completion/Error.
  Future<void> triggerSync(T data) async {
    if (isStopped || _isProcessing) return;
    _isProcessing = true;

    await _waitIfPaused();

    try {
      _state.reset();
      _state.setTotal(getTotalCount(data));

      // Immediate completion if there is no data to process.
      if (_state.total == 0) {
        notify(SyncStatus.complete);
        return;
      }

      notify(SyncStatus.start);
      SyncPrint.fromLeaf('$key', 'Start: ${_state.total}');

      // Execute the task wrapped with retry and timeout logic.
      await _runWithRetry(() {
        return performSync(data, (oper, {int count = 1}) async {
          await _waitIfPaused();

          if (isStopped) {
            throw const _SyncInterruptedException();
          }

          _state.step(oper, this, count: count);
        });
      });

      if (!isStopped) {
        _state.flush(this);
        notify(SyncStatus.complete);
        SyncPrint.fromLeaf('$key', 'Complete: ${_state.summary}');
      }
    } catch (e) {
      if (e is _SyncInterruptedException) {
        SyncPrint.fromLeaf('$key', 'Terminated (Stopped)');
      } else {
        _state.message = e.toString();
        notify(SyncStatus.error);
        SyncPrint.fromLeaf('$key', 'Error: ${_state.message}');
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Internal execution wrapper that handles retry logic with exponential backoff.
  Future<void> _runWithRetry(Future<void> Function() task) async {
    int tries = 0;
    while (tries < retryConfig.maxTryCount) {
      try {
        await task().timeout(retryConfig.timeout);
        return;
      } catch (e) {
        // If timed out while paused, just wait and keep retrying without incrementing count.
        if (e is TimeoutException && isPaused) {
          await _waitIfPaused();
          continue;
        }

        tries++;
        SyncPrint.fromLeaf('$key', 'Retry: $tries/${retryConfig.maxTryCount}');

        if (tries >= retryConfig.maxTryCount || isStopped) {
          rethrow;
        }

        // Notify the user of the retry attempt.
        retryConfig.onRetry?.call(tries);

        // Exponential delay calculation: baseDelay * 2^tries
        final delayMS = (retryConfig.lazyDelayMs * math.pow(2, tries)).toInt();
        await Future.delayed(Duration(milliseconds: delayMS));
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
    if (!isPaused && !isCompleted && !isStopped) {
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

  /// Helper to suspend execution while the node is in [SyncStatus.pause].
  Future<void> _waitIfPaused() async {
    if (!isPaused) return;

    SyncPrint.fromLeaf('$key', 'Waiting (Paused)...');
    _resumeCompleter ??= Completer<void>();
    await _resumeCompleter!.future;
  }
}
