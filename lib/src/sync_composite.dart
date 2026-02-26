import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// A container node that orchestrates multiple [SyncNode]s (Leafs or other Composites).
///
/// It coordinates execution order between [primarySyncs] and [lateSyncs],
/// aggregating the progress and status of all child nodes into a unified view.
///
/// [SyncComposite] utilizes an internal [Throttler] to regulate the frequency
/// of progress updates emitted during intense child node activity.
class SyncComposite extends SyncNode {
  /// Core tasks that are executed first and in parallel.
  final List<SyncNode> primarySyncs;

  /// Secondary tasks that are initiated after primary tasks have started or completed.
  final List<SyncNode> lateSyncs;

  /// Flattened list of all child nodes for simplified internal management.
  final List<SyncNode> _children = [];

  /// A registry of summary snapshots from completed nodes to maintain data consistency.
  final Map<String, SyncSummary> _completedSnapshots = {};

  /// If true, the composite terminates all operations if any child encounters an error.
  final bool stopOnError;

  /// Configuration for the internal throttler to manage UI update frequency.
  final ThrottlerConfig throttlerConfig;

  late Throttler _throttler;

  bool _isFirstStartSignal = true;

  SyncComposite({
    super.key,
    this.throttlerConfig = const ThrottlerConfig(),
    required this.primarySyncs,
    List<SyncNode>? lateSyncs,
    this.stopOnError = false,
  }) : lateSyncs = lateSyncs ?? [] {
    // Initialize the throttler to ensure progress updates adhere to
    // threshold and interval constraints.
    _throttler = Throttler(
      threshold: throttlerConfig.threshold,
      interval: throttlerConfig.interval,
      precision: throttlerConfig.precision,
      onUpdate: (progressValue, _) {
        notify(SyncStatus.progress, origin: this);
        SyncLog.fromComposite('$key', 'Total Progress: ${(progress * 100).toStringAsFixed(1)}%');
      },
    );

    _children.addAll([...primarySyncs, ...this.lateSyncs]);

    // Subscribes to events from all children to derive the composite's overall state.
    for (final child in _children) {
      child.listen((status, origin) async {
        switch (status) {
          case SyncStatus.start:
            if (_isFirstStartSignal) {
              _completedSnapshots.clear();
              _resetAllNodes();
              _isFirstStartSignal = false;
            } else {
              _completedSnapshots.remove(origin.key!);
            }

            notify(SyncStatus.start, origin: origin);
            SyncLog.fromComposite('$key', 'Node started: ${origin.key}');
            break;

          case SyncStatus.progress:
            _throttler.update(progress);
            break;

          case SyncStatus.complete:
            if (origin.key != null) {
              _completedSnapshots[origin.key!] = const SyncSummary().merge(origin.summary);
            }

            _throttler.update(progress);

            // Check if all active children have reached a terminal state.
            if (isCompleted) {
              if (_children.any((h) => h.isError)) {
                notify(SyncStatus.error, origin: this);
                SyncLog.fromComposite('$key', 'Session concluded with errors.');
              } else {
                notify(SyncStatus.complete, origin: this);
                SyncLog.fromComposite('$key', 'Session completed successfully: $summary');
              }
              _throttler.reset();
              _isFirstStartSignal = true;
            }
            break;

          case SyncStatus.error:
            if (origin.key != null) {
              _completedSnapshots[origin.key!] = const SyncSummary().merge(origin.summary);
            }

            notify(SyncStatus.error, origin: origin);

            SyncLog.fromComposite('$key', 'Error reported by ${origin.key}: $message');
            if (stopOnError) await stop();
            break;

          case SyncStatus.stop:
            if (_children.every((node) => node.isStopped)) {
              _isFirstStartSignal = true;
              _completedSnapshots.clear();

              notify(SyncStatus.stop, origin: this);
              SyncLog.fromComposite('$key', 'Synchronization process stopped.');
            }
            break;

          case SyncStatus.pause:
            if (_children.every((node) => node.isPaused)) {
              notify(SyncStatus.pause, origin: this);
              SyncLog.fromComposite('$key', 'Synchronization process paused.');
            }
            break;

          default:
            notify(status, origin: origin);
            break;
        }
      });
    }
  }

  /// Recursively resets child nodes to clear previous session data or error states.
  void _resetAllNodes() {
    for (var child in _children) {
      if (child is SyncComposite) {
        child._resetAllNodes();
      } else if (child is SyncLeaf && child.isError) {
        child.reset();
      }
    }
  }

  @override
  bool get isIdle => _children.every((h) => h.isIdle);

  @override
  bool get isSyncing => _children.any((h) => h.isSyncing);

  @override
  bool get isCompleted {
    if (_children.isEmpty) return false;

    return _children.every((h) {
      if (h.isSyncing && !h.isIdle) return false;

      // Consider a node finished if it had work and is now in a terminal state (Complete/Error).
      if (h.totalCount > 0 || h.completedCount > 0) {
        return h.isCompleted || h.isError;
      }

      return true;
    });
  }

  @override
  bool get isError => _children.any((h) => h.isError);

  @override
  bool get isPaused => _children.every((h) => h.isPaused);

  @override
  bool get isStopped => _children.every((h) => h.isStopped);

  @override
  bool get hasMessage => _children.any((h) => h.hasMessage);

  @override
  int get totalCount => _children.fold(0, (sum, node) => sum + node.totalCount);

  @override
  int get completedCount => _children.fold(0, (sum, node) => sum + node.completedCount);

  /// Calculates the aggregate progress based on the total workload of all active children.
  @override
  double get progress {
    if (totalCount == 0) return 0.0;
    if (isCompleted) return 1.0;

    final result = completedCount / totalCount;
    // Normalize and cap the value to prevent UI overflow from floating point precision issues.
    return result > 0.999 ? 1.0 : result;
  }

  @override
  String? get message {
    final messages =
        _children.map((node) => node.message).whereType<String>().where((msg) => msg.isNotEmpty).toSet();

    if (messages.isEmpty) return null;

    return messages.join('\n');
  }

  /// Aggregates summaries from all child nodes, combining snapshots and active metrics.
  @override
  SyncSummary get summary {
    SyncSummary total = const SyncSummary();

    for (var child in _children) {
      final key = child.key;

      if (key != null && _completedSnapshots.containsKey(key)) {
        total = total.merge(_completedSnapshots[key]!);
      } else if (child.isSyncing) {
        total = total.merge(child.summary);
      }
    }

    return total;
  }

  List<SyncNode> get allChildren => _children;

  @Deprecated('Use findNode instead. This will be removed in 1.1.0')
  SyncNode? getNode(String key) => findNode(key);

  /// Recursively searches for a specific [SyncNode] by its key.
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

  /// Convenience method to retrieve the [SyncSummary] for a specific child node.
  SyncSummary getSummary(String targetKey) => findNode(targetKey)?.summary ?? const SyncSummary();

  @override
  Future<void> start() async {
    _throttler.reset();
    _isFirstStartSignal = true;
    _completedSnapshots.clear();

    // Initiate primary tasks in parallel.
    await Future.wait(primarySyncs.map((h) => h.start()));

    // Initiate late tasks in parallel.
    // Secondary tasks typically synchronize internally with primary task progress.
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
