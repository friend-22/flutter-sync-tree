import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// Defines the lifecycle states of a synchronization process.
enum SyncStatus {
  /// The initial state before the node is initialized.
  none,

  /// The node is initialized and ready, but no operation is currently active.
  /// Often used when a node is reset for a new session.
  idle,

  /// Indicates that the synchronization process has been initiated.
  start,

  /// Indicates that data processing is active and progress updates are being emitted.
  progress,

  /// Indicates that the synchronization failed due to an unrecoverable error.
  error,

  /// Indicates that the node (or the entire tree) has successfully finished its task.
  complete,

  /// Indicates that the process has been temporarily paused by the user or system.
  pause,

  /// Indicates that the process was explicitly terminated before completion.
  stop
}

/// Configuration for retry logic using an exponential backoff strategy.
///
/// This determines how a [SyncLeaf] handles transient failures by re-attempting
/// operations with incrementally increasing delays to avoid server congestion.
class RetryConfig extends Equatable {
  /// The maximum number of retry attempts allowed before reporting a final [SyncStatus.error].
  ///
  /// Once this limit is reached, the error will be rethrown.
  final int maxTryCount;

  /// The initial delay in milliseconds for the first retry attempt.
  ///
  /// This serves as the foundation for subsequent backoff calculations.
  final int baseDelayMs;

  /// The factor by which the delay increases with each subsequent retry.
  ///
  /// The delay for the current attempt is calculated as:
  /// `baseDelayMs * (multiplier ^ (retryCount - 1))`
  final double multiplier;

  /// The maximum duration allowed for a single synchronization attempt.
  ///
  /// If an attempt exceeds this duration, a [TimeoutException] is thrown.
  final Duration timeout;

  /// An optional callback invoked on each retry attempt.
  ///
  /// Provides the current retry count (starting from 1) to the listener.
  final void Function(int retryCount)? onRetry;

  /// Creates a [RetryConfig] with predefined or custom settings.
  ///
  /// Default values are tuned for typical mobile network environments:
  /// - [maxTryCount]: 3 attempts
  /// - [baseDelayMs]: 1,000ms (1 second)
  /// - [multiplier]: 2.0 (doubles the delay each time)
  const RetryConfig({
    this.maxTryCount = 3,
    this.baseDelayMs = 1000,
    this.multiplier = 2.0,
    this.timeout = const Duration(seconds: 30),
    this.onRetry,
  });

  /// Calculates the delay for a specific retry attempt.
  ///
  /// Returns [Duration.zero] if [retryCount] is 0.
  /// For [retryCount] > 0, calculates exponential delay based on [multiplier].
  Duration getDelay(int retryCount) {
    if (retryCount <= 0) return Duration.zero;
    final int delay = baseDelayMs * pow(multiplier, retryCount - 1).toInt();
    return Duration(milliseconds: delay);
  }

  RetryConfig copyWith({
    int? maxTryCount,
    int? baseDelayMs,
    double? multiplier,
    Duration? timeout,
    void Function(int retryCount)? onRetry,
  }) {
    return RetryConfig(
      maxTryCount: maxTryCount ?? this.maxTryCount,
      baseDelayMs: baseDelayMs ?? this.baseDelayMs,
      multiplier: multiplier ?? this.multiplier,
      timeout: timeout ?? this.timeout,
      onRetry: onRetry ?? this.onRetry,
    );
  }

  @override
  List<Object?> get props => [maxTryCount, baseDelayMs, multiplier, timeout];
}

/// Configuration to throttle progress updates, optimizing UI rendering performance.
///
/// Throttling prevents the UI thread from being overwhelmed by high-frequency
/// state changes during rapid data processing.
class ThrottlerConfig extends Equatable {
  /// The minimum progress increment (0.0 to 1.0) required to trigger a UI update.
  final double threshold;

  /// The floating-point precision used for comparing progress values.
  final double precision;

  /// The minimum time interval required between consecutive progress updates.
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
/// [operation] describes the action performed, and [count] is the number of affected items.
typedef OnSyncOperation = Future<void> Function(String operation, {int count});

/// Callback for observing synchronization lifecycle events.
///
/// [status] represents the current state, and [origin] is the node that dispatched the event.
typedef OnSyncNotify = void Function(SyncStatus status, SyncNode origin);

/// Utility for logging synchronization events with distinct icons for tree levels.
///
/// Provides global toggles to filter logs based on the node type ([SyncComposite] or [SyncLeaf]).
class SyncLog {
  /// Whether to enable logs from [SyncComposite] (Tree) nodes.
  static bool enableComposite = true;

  /// Whether to enable logs from [SyncLeaf] (Leaf) nodes.
  static bool enableLeaf = true;

  /// Logs a message from a root or high-level tree structure.
  static void fromTree(String key, String message) {
    if (!enableComposite) return;
    debugPrint('🌲 [Tree:$key] $message');
  }

  /// Logs a message from a [SyncComposite] node.
  static void fromComposite(String key, String message) {
    if (!enableComposite) return;
    debugPrint('🌳 [Composite:$key] $message');
  }

  /// Logs a message from a [SyncLeaf] node.
  static void fromLeaf(String key, String message) {
    if (!enableLeaf) return;
    debugPrint('🍃 [Leaf:$key] $message');
  }
}
