import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// A node that bundles multiple [SyncNode]s (Leafs or other Composites).
///
/// It coordinates the execution order between [primarySyncs] and [lateSyncs],
/// and aggregates the progress and status of all its children.
class SyncComposite extends SyncNode {
  /// Core tasks that are executed first and in parallel.
  final List<SyncNode> primarySyncs;

  /// Secondary tasks that start only after all [primarySyncs] have completed successfully.
  final List<SyncNode> lateSyncs;

  /// Combined list of all child nodes for internal management.
  final List<SyncNode> _children = [];

  /// If true, the entire composite stops immediately if any child node fails.
  final bool stopOnError;

  SyncComposite(
      {super.key,
      required this.primarySyncs,
      List<SyncNode>? lateSyncs,
      this.stopOnError = false})
      : lateSyncs = lateSyncs ?? [] {
    _children.addAll([...primarySyncs, ...this.lateSyncs]);

    // Aggregate events from all children to represent the composite's state.
    for (final child in _children) {
      child.listen((type, origin) async {
        if (type == SyncStatus.error) {
          notify(SyncStatus.error, origin: origin);
          if (stopOnError) await stop();
        } else if (type == SyncStatus.complete) {
          // Notify completion only when all children are done.
          if (isComplete) {
            notify(SyncStatus.complete, origin: this);
          } else {
            notify(SyncStatus.progress, origin: origin);
          }
        } else {
          notify(type, origin: origin);
        }
      });
    }
  }

  @override
  bool get isSyncing => _children.any((h) => h.isSyncing);

  @override
  bool get isComplete => _children.every((h) => h.isComplete);

  @override
  bool get hasError => _children.any((h) => h.hasError);

  /// Calculates a weighted progress percentage (0.0 to 1.0).
  ///
  /// The weight is determined by the `totalCount` of each child node.
  @override
  double get progress {
    if (isComplete) return 1.0;

    int totalWeight = 0;
    double completedWeight = 0.0;

    for (final node in _children) {
      final weight = node.summary.totalCount;

      if (weight > 0) {
        totalWeight += weight;
        completedWeight += (weight * node.progress);
      }
    }

    if (totalWeight == 0) return 0.0;
    final result = completedWeight / totalWeight;

    // Clamp to 1.0 to avoid floating point precision issues.
    return result > 0.999 ? 1.0 : result;
  }

  @override
  String? get message =>
      _children.map((node) => node.message).whereType<String>().lastOrNull;

  /// Recursively searches for a node with the specified [targetKey].
  SyncNode? getNode(String targetKey) {
    for (final node in _children) {
      if (node.key == targetKey) return node;

      if (node is SyncComposite) {
        final found = node.getNode(targetKey);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Helper to get the [SyncSummary] of a specific child node by its key.
  SyncSummary getSummary(String targetKey) {
    return getNode(targetKey)?.summary ?? const SyncSummary();
  }

  @override
  SyncSummary get summary {
    return _children.fold(
      const SyncSummary(),
      (total, node) => total.merge(node.summary),
    );
  }

  /// Starts the synchronization process.
  ///
  /// 1. Executes all [primarySyncs] in parallel.
  /// 2. Waits for completion.
  /// 3. Executes all [lateSyncs] in parallel.
  @override
  Future<void> start() async {
    await Future.wait(primarySyncs.map((h) => h.start()));
    if (lateSyncs.isNotEmpty) {
      await Future.wait(lateSyncs.map((h) => h.start()));
    }
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
    if (isSyncing) {
      notify(SyncStatus.progress);
    }
  }
}
