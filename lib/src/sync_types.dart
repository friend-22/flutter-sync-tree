import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// Defines the lifecycle states of a synchronization process.
///
/// Each state represents a distinct phase in the node's execution lifecycle.
/// States transition in a predictable order:
///
/// ```
/// none → idle → start → progress → complete
///                              ↘ error
///              ↕ pause / resume
///              → stop
/// ```
enum SyncStatus {
  /// The initial state before the node is initialized.
  ///
  /// This is the default state when a node is first created and has not yet
  /// been started or configured.
  none,

  /// The node is initialized and ready, but no operation is currently active.
  ///
  /// Emitted after [start] is called on a [SyncLeaf] (before [triggerSync]),
  /// or after a node is reset for a new session.
  idle,

  /// Indicates that the synchronization process has been initiated.
  ///
  /// Emitted once when the first item begins processing. At this point,
  /// [SyncNode.totalCount] is set and progress tracking begins.
  start,

  /// Indicates that data processing is active and progress updates are being emitted.
  ///
  /// This state is throttled via [ThrottlerConfig] to prevent excessive UI rebuilds
  /// during high-frequency operations.
  progress,

  /// Indicates that the synchronization failed due to an unrecoverable error.
  ///
  /// When [SyncComposite.stopOnError] is `false`, other sibling nodes continue
  /// running and partial results are preserved in [SyncNode.summary].
  error,

  /// Indicates that the node (or the entire tree) has successfully finished its task.
  ///
  /// For a [SyncComposite], this is emitted only after all child nodes have
  /// reached a terminal state (complete, error, or idle).
  complete,

  /// Indicates that the process has been temporarily paused by the user or system.
  ///
  /// Execution is suspended at the next [SyncLeaf._handleOperation] checkpoint.
  /// Call [SyncNode.resume] to continue from where it left off.
  pause,

  /// Indicates that the process was explicitly terminated before completion.
  ///
  /// Unlike [error], this is a deliberate termination. Partial results may still
  /// be available via [SyncNode.summary] depending on how far the task progressed.
  stop
}

/// Configuration for retry logic using an exponential backoff strategy.
///
/// This determines how a [SyncLeaf] handles transient failures by re-attempting
/// operations with incrementally increasing delays to avoid server congestion.
///
/// ### Backoff Formula
/// ```
/// delay = baseDelayMs * (multiplier ^ (retryCount - 1)) + jitter
/// ```
///
/// ### Example
/// ```dart
/// final config = RetryConfig(
///   maxTryCount: 5,
///   baseDelayMs: 500,
///   multiplier: 2.0,
///   timeout: Duration(seconds: 60),
///   maxJitterMs: 500,
///   onRetry: (count) => print('Retry attempt: $count'),
/// );
/// ```
class RetryConfig extends Equatable {
  /// Shared [Random] instance for jitter calculations.
  ///
  /// Using a static instance avoids the overhead of creating a new [Random]
  /// on every [getDelay] call.
  final Random? random;

  /// The maximum number of retry attempts allowed before reporting a final [SyncStatus.error].
  ///
  /// Once this limit is reached, the error will be rethrown and propagated
  /// to the parent [SyncComposite].
  final int maxTryCount;

  /// The initial delay in milliseconds for the first retry attempt.
  ///
  /// This serves as the foundation for subsequent backoff calculations.
  /// For example, with [baseDelayMs] = 1000 and [multiplier] = 2.0:
  /// - Retry 1: ~1,000ms
  /// - Retry 2: ~2,000ms
  /// - Retry 3: ~4,000ms
  final int baseDelayMs;

  /// The factor by which the delay increases with each subsequent retry.
  ///
  /// The delay for the current attempt is calculated as:
  /// `baseDelayMs * (multiplier ^ (retryCount - 1))`
  ///
  /// A value of `1.0` results in a constant delay (no backoff).
  /// A value of `2.0` doubles the delay on each retry.
  final double multiplier;

  /// The maximum duration allowed for a single synchronization attempt.
  ///
  /// If an attempt exceeds this duration, a [TimeoutException] is thrown
  /// and the retry logic is triggered (if retries remain).
  final Duration timeout;

  /// An optional callback invoked on each retry attempt.
  ///
  /// Provides the current retry count (starting from 1) to the listener.
  /// Useful for logging, analytics, or showing user-facing retry indicators.
  final void Function(int retryCount)? onRetry;

  /// The upper bound in milliseconds for the random jitter added to each delay.
  ///
  /// Jitter is calculated as a random value in the range `[0, maxJitter)`,
  /// where `maxJitter = (delay ~/ 10).clamp(1, maxJitterMs)`.
  ///
  /// Increasing this value adds more randomness, which is useful when many
  /// clients are retrying simultaneously (Thundering Herd prevention).
  /// Defaults to 1,000ms.
  final int maxJitterMs;

  /// Creates a [RetryConfig] with predefined or custom settings.
  ///
  /// Default values are tuned for typical mobile network environments:
  /// - [maxTryCount]: 3 attempts
  /// - [baseDelayMs]: 1,000ms (1 second)
  /// - [multiplier]: 2.0 (doubles the delay each time)
  /// - [timeout]: 30 seconds per attempt
  /// - [maxJitterMs]: 1,000ms jitter ceiling
  const RetryConfig({
    this.random,
    this.maxTryCount = 3,
    this.baseDelayMs = 1000,
    this.multiplier = 2.0,
    this.timeout = const Duration(seconds: 30),
    this.maxJitterMs = 1000,
    this.onRetry,
  });

  Random get _random => random ?? Random();

  /// Calculates the delay for a specific retry attempt including a randomized jitter.
  ///
  /// Returns [Duration.zero] if [retryCount] is 0 or negative.
  ///
  /// The jitter is capped between 1ms and [maxJitterMs] to prevent both
  /// zero-jitter (synchronized retries) and excessively long waits.
  ///
  /// Jitter helps prevent "Thundering Herd" problems where many clients
  /// retry at the exact same millisecond after a shared failure (e.g., server restart).
  Duration getDelay(int retryCount) {
    if (retryCount <= 0) return Duration.zero;

    double delayMs = baseDelayMs.toDouble();
    for (int i = 1; i < retryCount; i++) {
      delayMs *= multiplier;
      if (delayMs > timeout.inMilliseconds) {
        return timeout;
      }
    }

    // Exponential backoff: delay grows by multiplier on each attempt.
    final int delay = delayMs.toInt().clamp(0, timeout.inMilliseconds);

    // Jitter: randomize +0~10% of the delay, capped between 1ms and maxJitterMs.
    // This spreads out retry storms when many clients fail simultaneously.
    final int maxJitter = (delay ~/ 10).clamp(1, maxJitterMs);
    final int jitter = _random.nextInt(maxJitter);

    // Cap the final delay so it never exceeds the configured timeout.
    final int finalDelay = (delay + jitter).clamp(0, timeout.inMilliseconds);

    return Duration(milliseconds: finalDelay);
  }

  RetryConfig copyWith({
    Random? random,
    int? maxTryCount,
    int? baseDelayMs,
    double? multiplier,
    Duration? timeout,
    void Function(int retryCount)? onRetry,
    int? maxJitterMs,
  }) {
    return RetryConfig(
      random: random ?? this.random,
      maxTryCount: maxTryCount ?? this.maxTryCount,
      baseDelayMs: baseDelayMs ?? this.baseDelayMs,
      multiplier: multiplier ?? this.multiplier,
      timeout: timeout ?? this.timeout,
      onRetry: onRetry ?? this.onRetry,
      maxJitterMs: maxJitterMs ?? this.maxJitterMs,
    );
  }

  @override
  List<Object?> get props => [random, maxTryCount, baseDelayMs, multiplier, timeout, maxJitterMs];
}

/// Configuration to throttle progress updates, optimizing UI rendering performance.
///
/// Throttling prevents the UI thread from being overwhelmed by high-frequency
/// state changes during rapid data processing. A progress update is dispatched
/// only when **both** conditions are met:
/// 1. The progress delta since the last update exceeds [threshold].
/// 2. At least [interval] has elapsed since the last update.
///
/// ### Example
/// ```dart
/// // Suitable for 60 FPS rendering with fine-grained progress
/// const config = ThrottlerConfig(
///   threshold: 0.005,
///   interval: Duration(milliseconds: 16),
/// );
/// ```
class ThrottlerConfig extends Equatable {
  /// The minimum progress increment (0.0 to 1.0) required to trigger a UI update.
  ///
  /// For example, a value of `0.01` means updates are emitted at most every 1%
  /// of total progress. Smaller values produce smoother animations at the cost
  /// of more frequent rebuilds.
  final double threshold;

  /// The floating-point precision used when comparing progress values.
  ///
  /// Values within this tolerance are treated as equal to avoid redundant updates
  /// caused by floating-point rounding errors. Defaults to `1e-4`.
  final double precision;

  /// The minimum time interval required between consecutive progress updates.
  ///
  /// Acts as a rate limiter regardless of how quickly the underlying data changes.
  /// Combined with [threshold], this prevents both too-frequent and too-infrequent updates.
  final Duration interval;

  const ThrottlerConfig({
    this.threshold = 0.01,
    this.precision = 1e-4,
    this.interval = const Duration(milliseconds: 100),
  });

  /// Creates a copy of this configuration with updated fields.
  ThrottlerConfig copyWith({
    double? threshold,
    double? precision,
    Duration? interval,
  }) {
    return ThrottlerConfig(
      threshold: threshold ?? this.threshold,
      precision: precision ?? this.precision,
      interval: interval ?? this.interval,
    );
  }

  @override
  List<Object?> get props => [threshold, precision, interval];
}

/// Callback for reporting discrete synchronization operations (e.g., 'add', 'update').
///
/// Invoked inside [SyncLeaf.performSync] for each processed item.
/// [operation] should be one of the predefined keys in [SyncSummary]
/// (e.g., [SyncSummary.add], [SyncSummary.update]) or a custom domain-specific key.
/// [count] defaults to 1 but can be used to batch-report multiple items at once.
///
/// ### Example
/// ```dart
/// await onSyncOper(SyncSummary.add);         // single item added
/// await onSyncOper(SyncSummary.latest, count: 5); // 5 items already up-to-date
/// ```
typedef OnSyncOperation = Future<void> Function(String operation, {int count});

/// Callback for observing synchronization lifecycle events.
///
/// Attached via [SyncNode.listen] to receive all status transitions from
/// a node and its descendants. [status] is the new lifecycle state,
/// and [origin] is the specific node that triggered the event (which may
/// differ from the node being listened to in a [SyncComposite] tree).
typedef OnSyncNotify = void Function(SyncStatus status, SyncNode origin);

/// Utility for logging synchronization events with distinct icons for tree levels.
///
/// Provides global toggles to filter logs based on the node type ([SyncComposite] or [SyncLeaf]).
class SyncLog {
  /// Whether to enable logs from [SyncComposite] (Tree) nodes.
  static bool enableComposite = true;

  /// Whether to enable logs from [SyncLeaf] (Leaf) nodes.
  static bool enableLeaf = true;

  static String _prefix(int depth, String icon) {
    if (depth <= 0) return '$icon ';
    final indent = '  ' * depth;
    return '$indent$icon ';
  }

  /// Clears the line or adds a break for readability.
  static void clearLine() {
    if (!enableComposite && !enableLeaf) return;
    _log('');
  }

  /// Logs a message from a root or high-level tree structure.
  static void fromTree(String key, String message) {
    if (!enableComposite && !enableLeaf) return;
    _log('${_prefix(0, '🌲')}[$key] $message');
  }

  /// Logs a message from a [SyncComposite] node.
  static void fromComposite(int depth, String key, String message, {double? progress}) {
    if (!enableComposite) return;

    final String bar = progress != null ? ' ${_drawProgressBar(progress)}' : '';
    _log('${_prefix(depth, '🌳')}[$key] $message$bar');
  }

  /// Logs a message from a [SyncLeaf] node.
  static void fromLeaf(int depth, String key, String message, {double? progress}) {
    if (!enableLeaf) return;

    final String bar = progress != null ? ' ${_drawProgressBar(progress)}' : '';
    _log('${_prefix(depth, '🍃')}[$key] $message$bar');
  }

  /// Generates a visual progress bar: [████░░░░░░] 40.0%
  static String _drawProgressBar(double progress) {
    const int width = 10;
    final double clamped = progress.clamp(0.0, 1.0);
    final int filled = (clamped * width).toInt();

    final String bar = '█' * filled + '░' * (width - filled);
    final String percent = '${(clamped * 100).toStringAsFixed(1).padLeft(5)}%';

    return '[$bar] $percent';
  }

  static void _log(String message) {
    if (logger != null) {
      logger!(message);
    } else {
      debugPrint(message);
    }
  }

  static void Function(String message)? logger;
}
