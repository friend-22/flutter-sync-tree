import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// A node that bundles multiple [SyncNode]s (Leafs or other Composites).
///
/// It coordinates execution order between [primarySyncs] and [lateSyncs],
/// and aggregates the progress and status of all its children into a single view.
///
/// [SyncComposite] uses a [Throttler] to prevent UI performance degradation
/// by limiting the frequency of progress updates emitted during heavy child activity.
class SyncComposite extends SyncNode {
  /// Core tasks that are executed first and in parallel.
  final List<SyncNode> primarySyncs;

  /// Secondary tasks that start only after primary tasks have progressed or completed.
  final List<SyncNode> lateSyncs;

  /// Combined list of all child nodes for unified management.
  final List<SyncNode> _children = [];

  /// Stores a snapshot of summaries from completed nodes to ensure data consistency.
  final Map<String, SyncSummary> _completedSnapshots = {};

  /// If true, the composite stops immediately if any child node encounters an error.
  final bool stopOnError;

  /// Configuration for the internal [Throttler] to manage update frequency.
  final ThrottlerConfig throttlerConfig;

  late Throttler _throttler;

  SyncComposite({
    super.key,
    this.throttlerConfig = const ThrottlerConfig(),
    required this.primarySyncs,
    List<SyncNode>? lateSyncs,
    this.stopOnError = false,
  }) : lateSyncs = lateSyncs ?? [] {
    // Initialize the throttler to notify listeners only when threshold
    // or duration constraints are met.
    _throttler = Throttler(
      threshold: throttlerConfig.threshold,
      duration: throttlerConfig.duration,
      precision: throttlerConfig.precision,
      onUpdate: (p, extra) {
        notify(SyncStatus.progress, origin: this);
        SyncPrint.fromComposite('$key', 'Progress: ${(progress * 100).toStringAsFixed(1)}%');
      },
    );

    _children.addAll([...primarySyncs, ...this.lateSyncs]);

    // Aggregate events from all children to represent the composite's overall state.
    for (final child in _children) {
      child.listen((type, origin) async {
        switch (type) {
          case SyncStatus.start:
            notify(SyncStatus.start);
            SyncPrint.fromComposite('$key', 'Started: ${origin.key}');
            if (origin.key != null) {
              _completedSnapshots.remove(origin.key!);
            }
            break;

          case SyncStatus.progress:
            _throttler.update(progress);
            break;

          case SyncStatus.complete:
            if (origin.key != null) {
              // Store summary snapshot upon completion.
              _completedSnapshots[origin.key!] = const SyncSummary().merge(origin.summary);
            }

            _throttler.update(progress);

            if (isCompleted) {
              notify(SyncStatus.complete, origin: this);
              SyncPrint.fromComposite('$key', 'Complete: $summary');
              _throttler.reset();
            }
            break;

          case SyncStatus.error:
            notify(SyncStatus.error, origin: origin);
            SyncPrint.fromComposite('$key', 'Error detected in ${origin.key}: $message');
            if (stopOnError) await stop();
            break;

          case SyncStatus.stop:
            if (_children.every((node) => node.isStopped)) {
              notify(SyncStatus.stop, origin: this);
              SyncPrint.fromComposite('$key', 'All children stopped.');
            }
            break;

          case SyncStatus.pause:
            if (_children.every((node) => node.isPaused)) {
              notify(SyncStatus.pause, origin: this);
              SyncPrint.fromComposite('$key', 'Paused');
            }
            break;

          default:
            notify(type, origin: origin);
            break;
        }
      });
    }
  }

  @override
  bool get isIdle => _children.every((h) => h.isIdle);

  @override
  bool get isSyncing => _children.any((h) => h.isSyncing);

  @override
  bool get isCompleted => _children.every((h) => h.isCompleted);

  @override
  bool get hasMessage => _children.any((h) => h.hasMessage);

  @override
  int get totalCount => _children.fold(0, (sum, node) => sum + node.totalCount);

  @override
  int get completedCount => _children.fold(0, (sum, node) => sum + node.completedCount);

  /// Calculates weighted progress based on the cumulative 'totalCount' of all children.
  @override
  double get progress {
    if (totalCount == 0) return 0.0;
    if (isCompleted) return 1.0;

    final result = completedCount / totalCount;
    // Cap at 1.0 to avoid floating point overflow display.
    return result > 0.999 ? 1.0 : result;
  }

  @override
  String? get message => _children.map((node) => node.message).whereType<String>().lastOrNull;

  /// Aggregates summaries from all child nodes, combining snapshots and active nodes.
  @override
  SyncSummary get summary {
    SyncSummary total = const SyncSummary();

    // 1. Add snapshots from completed nodes.
    for (var snapshot in _completedSnapshots.values) {
      total = total.merge(snapshot);
    }

    // 2. Add current summaries from active (syncing) nodes.
    for (var child in _children) {
      if (child.isSyncing && !_completedSnapshots.containsKey(child.key)) {
        total = total.merge(child.summary);
      }
    }
    return total;
  }

  /// Recursively searches for a node with the specified [targetKey].
  SyncNode? findNode(String targetKey) {
    for (final node in _children) {
      if (node.key == targetKey) return node;
      if (node is SyncComposite) {
        final found = node.findNode(targetKey);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Convenience helper to get the [SyncSummary] of a specific child node.
  SyncSummary getSummary(String targetKey) => findNode(targetKey)?.summary ?? const SyncSummary();

  @override
  Future<void> start() async {
    _throttler.reset();
    _completedSnapshots.clear();

    // Start primary tasks in parallel.
    await Future.wait(primarySyncs.map((h) => h.start()));

    // Start late tasks in parallel.
    // Note: Late tasks usually wait for primary data inside their own performSync.
    if (lateSyncs.isNotEmpty) {
      await Future.wait(lateSyncs.map((h) => h.start()));
    }

    await super.start();
  }

  @override
  Future<void> stop() async {
    await Future.wait(_children.map((node) => node.stop()));
    await super.stop();
  }

  @override
  void pause() {
    for (var node in _children) {
      node.pause();
    }
    notify(SyncStatus.pause);
  }

  @override
  void resume() {
    for (var node in _children) {
      node.resume();
    }
    if (isSyncing) notify(SyncStatus.progress);
  }
}
