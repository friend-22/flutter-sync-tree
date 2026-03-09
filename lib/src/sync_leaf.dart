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
/// - **Automatic retries** with exponential backoff and jitter.
/// - **Progress throttling** to prevent UI thread jank.
/// - **Interruptible execution** (pause, resume, and stop support).
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

      final total = getTotalCount(data);
      _state.setTotal(total);

      // Immediate completion if there is no workload to process.
      if (total == 0) {
        notify(SyncStatus.complete, onNotify: () {
          _log('📭 No items to synchronize. Skipping...');
        });
        return;
      }

      notify(SyncStatus.start, onNotify: () {
        _log('🚀 Started: ${_state.total} items');
      });

      // Executes the task wrapped in retry and timeout logic.
      await _runWithRetry(() => performSync(data, _handleOperation));

      if (!isStopped) {
        _state.flush(this);
        notify(SyncStatus.complete, onNotify: () {
          _log('✅ Done: ${_state.summary}');
        });
      }
    } catch (e) {
      _handleError(e);
    } finally {
      _isProcessing = false;
    }
  }

  /// Internal handler for each step of the synchronization.
  ///
  /// Ensures that pause and stop signals are respected during processing.
  Future<void> _handleOperation(String operation, {int count = 1}) async {
    await _waitIfPaused();

    if (isStopped) {
      throw const _SyncInterruptedException();
    }

    _state.step(operation, this, count: count);
  }

  /// Categorizes and logs errors, updating the node status to [SyncStatus.error].
  void _handleError(Object e) {
    if (e is _SyncInterruptedException || isStopped) {
      _log('Terminated by user');
    } else {
      _state.message = e.toString();
      notify(SyncStatus.error, onNotify: () {
        _log('🚨 Error: "${_state.message}"');
      });
    }
  }

  /// Orchestrates retry logic using the configured [RetryConfig].
  Future<void> _runWithRetry(Future<void> Function() task) async {
    int retryCount = 0;

    while (true) {
      await _waitIfPaused();
      if (isStopped) return;

      try {
        await task().timeout(retryConfig.timeout);
        return;
      } catch (e) {
        // If the task was manually stopped, don't retry.
        if (e is _SyncInterruptedException) rethrow;

        await _waitIfPaused();
        if (isStopped) return;

        retryCount++;
        if (retryCount > retryConfig.maxTryCount) rethrow;

        _log('♻️ Retry: $retryCount/${retryConfig.maxTryCount}');

        // Notify subscribers of the retry attempt.
        retryConfig.onRetry?.call(retryCount);

        // Wait for the calculated backoff period before the next attempt.
        await Future.delayed(retryConfig.getDelay(retryCount));
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_resumeCompleter != null && !_resumeCompleter!.isCompleted) {
      _resumeCompleter!.complete();
    }
    _resumeCompleter = null;
    await super.dispose();
  }

  @override
  Future<void> start() async {
    _isProcessing = false;
    notify(SyncStatus.idle, onNotify: () => _log('⚙️ Ready'));
  }

  @override
  Future<void> stop() async {
    _state.reset();
    _isProcessing = false;
    notify(SyncStatus.stop, onNotify: () => _log('🛑 Stopped'));
  }

  @override
  void pause() {
    if (!isPaused) {
      notify(SyncStatus.pause, onNotify: () => _log('⏳ Paused'));
    }
  }

  @override
  void resume() {
    if (isPaused) {
      _resumeCompleter?.complete();
      _resumeCompleter = null;

      // Maintain progress state or return to idle if not started
      if (totalCount > 0 || completedCount > 0) {
        notify(SyncStatus.progress);
      } else {
        notify(SyncStatus.idle);
      }

      _log('⏳ Resume');
    }
  }

  /// Suspends execution if the node is in the [SyncStatus.pause] state.
  Future<void> _waitIfPaused() async {
    if (!isPaused) return;

    _log('⏳ Execution suspended (Paused)');
    _resumeCompleter ??= Completer<void>();
    await _resumeCompleter!.future;
  }

  /// Completely resets the task state to its initial configuration.
  void reset() {
    _state.reset();
    notify(SyncStatus.idle, onNotify: () => _log('⚙️ Reset: Ready for next sync'));
  }

  /// Internal logging helper that respects the tree depth.
  void _log(String message) {
    SyncLog.fromLeaf(depth, '$key', message);
  }
}
