import 'package:flutter/foundation.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// Defines the various states of a synchronization process.
enum SyncType { none, start, progress, error, complete, pause, stop }

/// Configuration for retry logic when a sync task fails.
class RetryConfig {
  /// Maximum number of retry attempts.
  final int maxTryCount;

  /// Base delay in milliseconds for exponential backoff.
  final int lazyDelayMs;

  /// Total time allowed for a single sync attempt.
  final Duration timeout;

  const RetryConfig({
    this.maxTryCount = 3,
    this.lazyDelayMs = 50,
    this.timeout = const Duration(seconds: 30),
  });
}

/// Configuration for throttling UI/stream updates to prevent performance bottlenecks.
class ThrottlerConfig {
  final double threshold;
  final double precision;
  final Duration duration;

  const ThrottlerConfig({
    this.threshold = 0.01,
    this.precision = 1e-4,
    this.duration = const Duration(milliseconds: 100),
  });
}

typedef OnSyncOper = Future<void> Function(String oper);
typedef OnSyncNotify = void Function(SyncType type, SyncNode child);

/// Utility for logging sync events with tree/leaf differentiation.
class SyncPrint {
  static bool enableTree = true;
  static bool enableLeaf = true;

  static void fromTree(String key, String message) {
    if (!SyncPrint.enableTree) return;
    debugPrint('Tree: key:$key, $message');
  }

  static void fromLeaf(String key, String message) {
    if (!SyncPrint.enableLeaf) return;
    debugPrint('Leaf: key:$key, $message');
  }
}
