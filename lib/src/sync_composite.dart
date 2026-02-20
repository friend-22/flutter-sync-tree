import 'package:flutter_sync_tree/flutter_sync_tree.dart';
import 'package:flutter_sync_tree/src/sync_types.dart';

/// A node that bundles multiple [SyncNode]s (Leafs or other Composites).
class SyncComposite extends SyncNode {
  /// Primary tasks that start immediately.
  final List<SyncNode> primarySyncs;

  /// Tasks that are executed after primary tasks.
  final List<SyncNode> lateSyncs;
  final List<SyncNode> _allNodes = [];

  /// If true, stops the entire tree if one node fails.
  final bool stopOnError;

  SyncComposite({super.key, required this.primarySyncs, List<SyncNode>? lateSyncs, this.stopOnError = false})
      : lateSyncs = lateSyncs ?? [] {
    _allNodes.addAll([...primarySyncs, ...this.lateSyncs]);

    // Aggregate events from all children.
    for (final leaf in _allNodes) {
      leaf.listen((type, child) async {
        if (type == SyncType.error) {
          notify(SyncType.error, child: child);
          if (stopOnError) await stop();
        } else if (type == SyncType.complete) {
          if (isComplete) {
            notify(SyncType.complete, child: this);
          } else {
            notify(SyncType.progress, child: child);
          }
        } else {
          notify(type, child: child);
        }
      });
    }
  }

  @override
  bool get isSyncing => _allNodes.any((h) => h.isSyncing);

  @override
  bool get isComplete => _allNodes.every((h) => h.isComplete);

  @override
  bool get hasError => _allNodes.any((h) => h.hasError);

  /// Calculates weighted progress based on the total task count of all children.
  @override
  double get progress {
    if (isComplete) return 1.0;

    int totalTasks = 0;
    double completedWeight = 0.0;

    for (final h in _allNodes) {
      final count = h.summary.totalCount;

      if (count > 0) {
        totalTasks += count;
        completedWeight += (count * h.progress);
      }
    }

    final result = totalTasks == 0 ? 0.0 : completedWeight / totalTasks;
    return result > 0.999 ? 1.0 : result;
  }

  @override
  String? get message => _allNodes.map((h) => h.message).whereType<String>().lastOrNull;

  SyncNode? getNode(String targetKey) {
    for (final s in _allNodes) {
      if (s.key == targetKey) return s;

      if (s is SyncComposite) {
        final found = s.getNode(targetKey);
        if (found != null) return found;
      }
    }
    return null;
  }

  SyncSummary getSummary(String targetKey) {
    return getNode(targetKey)?.summary ?? const SyncSummary();
  }

  @override
  SyncSummary get summary {
    SyncSummary total = const SyncSummary();
    for (final h in [...primarySyncs, ...lateSyncs]) {
      total = total.merge(h.summary);
    }
    return total;
  }

  @override
  Future<void> start() async {
    await Future.wait(primarySyncs.map((h) => h.start()));
    if (lateSyncs.isNotEmpty) {
      await Future.wait(lateSyncs.map((h) => h.start()));
    }
  }

  @override
  Future<void> stop() async {
    await Future.wait([...primarySyncs, ...lateSyncs].map((s) => s.stop()));
    await super.stop();
  }

  @override
  void pause() {
    for (var node in [...primarySyncs, ...lateSyncs]) {
      node.pause();
    }
    notify(SyncType.pause);
  }

  @override
  void resume() {
    for (var node in [...primarySyncs, ...lateSyncs]) {
      node.resume();
    }
    if (isSyncing) {
      notify(SyncType.progress);
    }
  }
}
