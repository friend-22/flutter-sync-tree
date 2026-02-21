import 'package:flutter/foundation.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// Defines the various states of a synchronization process.
enum SyncStatus {
  /// Initial state before any operation.
  none,

  /// Triggered when the sync process starts.
  start,

  /// Triggered during active data processing with progress updates.
  progress,

  /// Triggered when an unrecoverable error occurs.
  error,

  /// Triggered when the task or entire tree completes successfully.
  complete,

  /// Triggered when the sync is manually paused.
  pause,

  /// Triggered when the sync is stopped and resources are cleaned up.
  stop
}

/// Configuration for retry logic with exponential backoff.
class RetryConfig {
  /// Maximum number of retry attempts before throwing an error.
  final int maxTryCount;

  /// Base delay in milliseconds for exponential backoff.
  ///
  /// The actual delay increases with each attempt: (lazyDelayMs * 2^tries).
  final int lazyDelayMs;

  /// Total time allowed for a single synchronization attempt.
  final Duration timeout;

  const RetryConfig({
    this.maxTryCount = 3,
    this.lazyDelayMs = 50,
    this.timeout = const Duration(seconds: 30),
  });
}

/// Configuration for throttling progress updates to optimize UI performance.
class ThrottlerConfig {
  /// Minimum progress change (0.0 to 1.0) required to trigger an update.
  final double threshold;

  /// Floating point precision for progress comparisons.
  final double precision;

  /// Minimum time interval between consecutive updates.
  final Duration duration;

  const ThrottlerConfig({
    this.threshold = 0.01,
    this.precision = 1e-4,
    this.duration = const Duration(milliseconds: 100),
  });
}

/// Callback for reporting an individual synchronization operation (e.g., 'add', 'update').
typedef OnSyncOper = Future<void> Function(String oper);

/// Callback for listening to synchronization lifecycle events.
///
/// [type] is the event category, and [origin] is the node where the event started.
typedef OnSyncNotify = void Function(SyncStatus type, SyncNode child);

/// Utility for logging synchronization events with tree and leaf differentiation.
class SyncPrint {
  /// Global toggle for tree-level (Composite) logs.
  static bool enableTree = true;

  /// Global toggle for leaf-level (Individual task) logs.
  static bool enableLeaf = true;

  /// Logs a message from a [SyncComposite].
  static void fromTree(String key, String message) {
    if (!SyncPrint.enableTree) return;
    debugPrint('🌲 [Tree:$key] $message');
  }

  /// Logs a message from a [SyncLeaf].
  static void fromLeaf(String key, String message) {
    if (!SyncPrint.enableLeaf) return;
    debugPrint('🍃 [Leaf:$key] $message');
  }
}
