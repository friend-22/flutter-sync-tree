import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// Defines the various states of a synchronization process.
enum SyncStatus {
  /// Initial state before any operation has been initialized.
  none,

  /// The node is initialized and ready but currently inactive.
  idle,

  /// Triggered when the synchronization process begins.
  start,

  /// Triggered during active data processing to provide progress updates.
  progress,

  /// Triggered when an unrecoverable error occurs during synchronization.
  error,

  /// Triggered when the task or the entire tree completes successfully.
  complete,

  /// Triggered when the synchronization is manually paused by the user.
  pause,

  /// Triggered when the synchronization is explicitly stopped.
  stop
}

/// Configuration for retry logic with exponential backoff.
///
/// This determines how a [SyncLeaf] handles transient failures by retrying
/// the operation with increasing delays.
class RetryConfig extends Equatable {
  /// Maximum number of retry attempts before the process fails with an error.
  final int maxTryCount;

  /// Base delay in milliseconds for exponential backoff.
  ///
  /// The actual delay typically follows: (lazyDelayMs * 2^tries).
  final int lazyDelayMs;

  /// Maximum time allowed for a single synchronization attempt before it times out.
  final Duration timeout;

  /// Optional callback triggered on every retry attempt with the current retry count.
  final void Function(int tries)? onRetry;

  const RetryConfig({
    this.maxTryCount = 5,
    this.lazyDelayMs = 50,
    this.timeout = const Duration(seconds: 30),
    this.onRetry,
  });

  /// Returns a copy of this configuration with the given fields replaced.
  RetryConfig copyWith({
    int? maxTryCount,
    int? lazyDelayMs,
    Duration? timeout,
    void Function(int tries)? onRetry,
  }) {
    return RetryConfig(
      maxTryCount: maxTryCount ?? this.maxTryCount,
      lazyDelayMs: lazyDelayMs ?? this.lazyDelayMs,
      timeout: timeout ?? this.timeout,
      onRetry: onRetry ?? this.onRetry,
    );
  }

  @override
  List<Object?> get props => [maxTryCount, lazyDelayMs, timeout];
}

/// Configuration for throttling progress updates to optimize UI rendering performance.
///
/// Throttling prevents the UI from being overwhelmed by too many state changes
/// in a short period, especially during high-frequency data processing.
class ThrottlerConfig extends Equatable {
  /// Minimum progress change (0.0 to 1.0) required to emit a new update.
  final double threshold;

  /// Precision for floating-point comparisons to handle progress calculations.
  final double precision;

  /// Minimum time interval that must pass between consecutive updates.
  final Duration duration;

  const ThrottlerConfig({
    this.threshold = 0.01,
    this.precision = 1e-4,
    this.duration = const Duration(milliseconds: 100),
  });

  /// Returns a copy of this configuration with the given fields replaced.
  ThrottlerConfig copyWith({
    double? threshold,
    double? precision,
    Duration? duration,
  }) {
    return ThrottlerConfig(
      threshold: threshold ?? this.threshold,
      precision: precision ?? this.precision,
      duration: duration ?? this.duration,
    );
  }

  @override
  List<Object?> get props => [threshold, precision, duration];
}

/// Callback signature for reporting individual sync operations (e.g., 'add', 'update').
///
/// [oper] is the type of operation performed, and [count] is the number of items affected.
typedef OnSyncOper = Future<void> Function(String oper, {int count});

/// Callback signature for listening to synchronization lifecycle events.
///
/// [type] is the category of the event, and [child] is the node that triggered it.
typedef OnSyncNotify = void Function(SyncStatus type, SyncNode child);

/// Utility for logging synchronization events with tree and leaf differentiation.
///
/// Provides global toggles to enable or disable logs for different node levels.
class SyncPrint {
  /// Globally enables or disables logs from [SyncComposite] nodes.
  static bool enableComposite = true;

  /// Globally enables or disables logs from [SyncLeaf] nodes.
  static bool enableLeaf = true;

  /// Logs a message formatted for a [SyncComposite] node.
  static void fromComposite(String key, String message) {
    if (!SyncPrint.enableComposite) return;
    debugPrint('?? [Composite:$key] $message');
  }

  /// Logs a message formatted for a [SyncLeaf] node.
  static void fromLeaf(String key, String message) {
    if (!SyncPrint.enableLeaf) return;
    debugPrint('?? [Leaf:$key] $message');
  }
}
