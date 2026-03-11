import 'dart:async';

import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// An internal exception used to interrupt the sync loop when a stop signal is received.
///
/// Thrown inside [SyncLeaf._handleOperation] when [_isProcessing] is `false`,
/// which is set by [SyncLeaf.stop]. This causes [_runWithRetry] to rethrow
/// the exception without retrying, and [triggerSync] catches it in [_handleError]
/// to suppress the error notification (it's an intentional termination, not a fault).
class _SyncInterruptedException implements Exception {
  const _SyncInterruptedException();
}

/// A leaf node in the synchronization tree that executes the actual workload.
///
/// The generic type [T] represents the input data passed to [performSync].
/// Subclasses implement [getTotalCount] and [performSync] to define what work
/// is done and how progress is reported.
///
/// ### Features
/// - **Automatic retries** with exponential backoff and jitter via [RetryConfig].
/// - **Progress throttling** to prevent UI thread jank via [ThrottlerConfig].
/// - **Interruptible execution** — respects pause, resume, and stop signals
///   at every [_handleOperation] checkpoint.
///
/// ### Implementing a Leaf
/// ```dart
/// class UserSyncLeaf extends SyncLeaf<List<User>> {
///   final UserRepository _repo;
///
///   UserSyncLeaf(this._repo) : super(key: 'userSync');
///
///   @override
///   int getTotalCount(List<User> data) => data.length;
///
///   @override
///   Future<void> performSync(List<User> data, OnSyncOperation onSyncOper) async {
///     for (final user in data) {
///       if (await _repo.exists(user.id)) {
///         await _repo.update(user);
///         await onSyncOper(SyncSummary.update);
///       } else {
///         await _repo.insert(user);
///         await onSyncOper(SyncSummary.add);
///       }
///     }
///   }
/// }
/// ```
abstract class SyncLeaf<T> extends SyncNode {
  /// Configuration for retry strategy and exponential backoff timing.
  ///
  /// Controls how many times [performSync] is retried on failure,
  /// how long to wait between attempts, and when to give up.
  final RetryConfig retryConfig;

  /// Configuration for throttling the frequency of progress notifications.
  ///
  /// Prevents [SyncStatus.progress] from being emitted on every single item,
  /// which would cause excessive UI rebuilds during high-throughput operations.
  final ThrottlerConfig throttlerConfig;

  /// Internal state manager for progress tracking and summary accumulation.
  ///
  /// Owns the [Throttler] instance and all mutable counters for this task.
  /// Encapsulated here to keep [SyncLeaf] focused on orchestration.
  late final SyncTaskState _state;

  /// Tracks whether [triggerSync] is currently executing.
  ///
  /// Used as both a guard against concurrent invocations and as a stop signal:
  /// setting this to `false` (via [stop]) causes the next [_handleOperation]
  /// call to throw [_SyncInterruptedException], cleanly interrupting the loop.
  bool _isProcessing = false;

  /// Completer used to suspend execution when the node is paused.
  ///
  /// Created lazily in [_waitIfPaused] and completed by [resume].
  /// Reset to `null` after each resume to allow re-pausing.
  Completer<void>? _resumeCompleter;

  SyncLeaf({
    super.key,
    this.retryConfig = const RetryConfig(),
    this.throttlerConfig = const ThrottlerConfig(),
  }) {
    // Wire up the state manager's throttler to emit SyncStatus.progress
    // via this node's notify() whenever throttle conditions are met.
    _state = SyncTaskState(throttlerConfig, (originNode) {
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

  // ---------------------------------------------------------------------------
  // Abstract Interface
  // ---------------------------------------------------------------------------

  /// Returns the total number of items to be processed from [data].
  ///
  /// This value is used as the denominator for progress calculations.
  /// Must reflect the actual number of [onSyncOper] calls that [performSync]
  /// will make, or progress reporting will be inaccurate.
  ///
  /// Returning `0` causes [triggerSync] to skip processing and emit
  /// [SyncStatus.complete] immediately.
  int getTotalCount(T data);

  /// The core synchronization logic implemented by the subclass.
  ///
  /// Must call [onSyncOper] once for each processed item to report progress
  /// and advance the [completedCount]. The operation key should be one of
  /// the predefined [SyncSummary] constants or a custom domain-specific key.
  ///
  /// **Important**: Do not swallow exceptions inside this method. Let them
  /// propagate so [_runWithRetry] can handle retries and [_handleError]
  /// can emit the correct error status.
  ///
  /// ```dart
  /// @override
  /// Future<void> performSync(T data, OnSyncOperation onSyncOper) async {
  ///   for (final item in data) {
  ///     await processItem(item);
  ///     await onSyncOper(SyncSummary.add);
  /// ```
  Future<void> performSync(T data, OnSyncOperation onSyncOper);

  // ---------------------------------------------------------------------------
  // Execution Lifecycle
  // ---------------------------------------------------------------------------

  /// Triggers the full synchronization cycle for the given [data].
  ///
  /// This is the primary entry point for executing work on a [SyncLeaf].
  /// Should be called after [start] has transitioned the node to idle.
  ///
  /// Execution flow:
  /// 1. Guard against concurrent invocations via [_isProcessing].
  /// 2. Wait if currently paused.
  /// 3. Reset state and calculate [getTotalCount].
  /// 4. Emit [SyncStatus.start] and invoke [performSync] via [_runWithRetry].
  /// 5. On success: flush throttler and emit [SyncStatus.complete].
  /// 6. On failure: delegate to [_handleError].
  Future<void> triggerSync(T data) async {
    if (_isProcessing || isStopped) return;

    _isProcessing = true;

    try {
      await _waitIfPaused();

      _state.reset();

      final total = getTotalCount(data);
      _state.setTotal(total);

      // No items to process — complete immediately without starting.
      if (total == 0) {
        notify(SyncStatus.complete, onNotify: () {
          _log('📭 No items to synchronize. Skipping...');
        });
        return;
      }

      notify(SyncStatus.start, onNotify: () {
        _log('🚀 Started: ${_state.total} items');
      });

      // Run the task with retry/timeout wrapping.
      await _runWithRetry(() => performSync(data, _handleOperation));

      // Only emit complete if we haven't been stopped mid-flight.
      if (_isProcessing) {
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

  /// Called by [performSync] for each processed item via [OnSyncOperation].
  ///
  /// Serves as the primary checkpoint for pause and stop signal detection:
  /// - Suspends if paused (via [_waitIfPaused]).
  /// - Throws [_SyncInterruptedException] if [_isProcessing] is `false` (stopped).
  /// - Records the operation in [_state] and advances the progress throttler.
  Future<void> _handleOperation(String operation, {int count = 1}) async {
    await _waitIfPaused();

    if (!_isProcessing) {
      throw const _SyncInterruptedException();
    }

    _state.step(operation, this, count: count);
  }

  /// Classifies errors and updates node status accordingly.
  ///
  /// Intentional interruptions ([_SyncInterruptedException] or `!_isProcessing`)
  /// are logged silently without emitting [SyncStatus.error], as they result
  /// from user-initiated stops rather than actual failures.
  ///
  /// All other exceptions are stored in [_state.message] and broadcast
  /// as [SyncStatus.error] for the parent composite to handle.
  void _handleError(Object e) {
    if (e is _SyncInterruptedException || !_isProcessing) {
      _log('Terminated by user');
    } else {
      _state.message = e.toString();
      notify(SyncStatus.error, onNotify: () {
        _log('🚨 Error: "${_state.message}"');
      });
    }
  }

  /// Executes [task] with retry and timeout logic based on [retryConfig].
  ///
  /// On each attempt:
  /// 1. Waits if paused.
  /// 2. Executes [task] with a [retryConfig.timeout] deadline.
  /// 3. On success, returns immediately.
  /// 4. On [_SyncInterruptedException], re-throws without retrying (intentional stop).
  /// 5. On other exceptions, increments [retryCount] and waits for the
  ///    backoff delay from [RetryConfig.getDelay] before the next attempt.
  /// 6. If [retryCount] exceeds [RetryConfig.maxTryCount], re-throws the final error.
  Future<void> _runWithRetry(Future<void> Function() task) async {
    int retryCount = 0;

    while (true) {
      await _waitIfPaused();

      if (!_isProcessing) {
        throw const _SyncInterruptedException();
      }

      try {
        await task().timeout(retryConfig.timeout);
        return;
      } catch (e) {
        // Don't retry intentional interruptions — propagate immediately.
        if (e is _SyncInterruptedException) rethrow;

        await _waitIfPaused();

        if (!_isProcessing) {
          throw const _SyncInterruptedException();
        }

        retryCount++;
        if (retryCount > retryConfig.maxTryCount) rethrow;

        _log('♻️ Retry: $retryCount/${retryConfig.maxTryCount}');

        // Notify external listeners of the retry (e.g., for UI indicators).
        retryConfig.onRetry?.call(retryCount);

        // Wait for the calculated exponential backoff + jitter delay.
        await Future.delayed(retryConfig.getDelay(retryCount));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle Overrides
  // ---------------------------------------------------------------------------

  /// Completes the pause completer (if pending) before releasing resources.
  ///
  /// Prevents the [_waitIfPaused] future from leaking if [dispose] is called
  /// while the node is suspended mid-execution.
  @override
  Future<void> dispose() async {
    if (_resumeCompleter != null && !_resumeCompleter!.isCompleted) {
      _resumeCompleter!.complete();
    }
    _resumeCompleter = null;
    await super.dispose();
  }

  /// Transitions the node to [SyncStatus.idle], signaling it is ready for [triggerSync].
  ///
  /// Resets [_isProcessing] to allow a fresh invocation of [triggerSync].
  /// Called by the parent [SyncComposite] during the [start] dispatch phase.
  @override
  Future<void> start() async {
    _isProcessing = false;
    notify(SyncStatus.idle, onNotify: () => _log('⚙️ Ready'));
  }

  /// Immediately halts processing and transitions to [SyncStatus.stop].
  ///
  /// Sets [_isProcessing] to `false`, which causes the next [_handleOperation]
  /// call to throw [_SyncInterruptedException] and cleanly exit [triggerSync].
  /// Resets [_state] to clear any partial progress data.
  @override
  Future<void> stop() async {
    _state.reset();
    _isProcessing = false;
    notify(SyncStatus.stop, onNotify: () => _log('🛑 Stopped'));
  }

  /// Suspends the node without releasing resources.
  ///
  /// Transitions to [SyncStatus.pause]. Execution continues until the next
  /// [_handleOperation] checkpoint, where [_waitIfPaused] will block.
  /// No-ops if already paused.
  @override
  void pause() {
    if (!isPaused) {
      notify(SyncStatus.pause, onNotify: () => _log('⏳ Paused'));
    }
  }

  /// Resumes a previously paused node.
  ///
  /// Completes [_resumeCompleter] to unblock [_waitIfPaused], then transitions
  /// back to [SyncStatus.progress] (if work has started) or [SyncStatus.idle].
  /// No-ops if not currently paused.
  @override
  void resume() {
    if (isPaused) {
      _resumeCompleter?.complete();
      _resumeCompleter = null;

      // Return to progress if work has started, otherwise return to idle.
      if (completedCount == 0) {
        notify(SyncStatus.idle);
      } else if (completedCount < totalCount) {
        notify(SyncStatus.progress);
      }

      _log('⏳ Resumed');
    }
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  /// Suspends execution until [resume] is called, if the node is paused.
  ///
  /// Creates [_resumeCompleter] lazily on first call. Subsequent calls
  /// while still paused reuse the same completer. After [resume] completes
  /// the completer, this method returns and execution continues normally.
  Future<void> _waitIfPaused() async {
    if (!isPaused) return;

    _log('⏳ Execution suspended (Paused)');
    _resumeCompleter ??= Completer<void>();
    await _resumeCompleter!.future;
  }

  /// Resets internal state and transitions to [SyncStatus.idle].
  ///
  /// Called by [SyncComposite._resetAllNodes] at the start of a new session
  /// to prepare non-syncing leaf nodes for re-use.
  void reset() {
    _state.reset();
    notify(SyncStatus.idle, onNotify: () => _log('⚙️ Reset: Ready for next sync'));
  }

  /// Delegates log output to [SyncLog.fromLeaf] with this node's depth and key.
  void _log(String message) {
    SyncLog.fromLeaf(depth, '$key', message);
  }
}
