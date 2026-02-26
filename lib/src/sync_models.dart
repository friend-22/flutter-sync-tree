import 'package:equatable/equatable.dart';

/// An interface for accessing statistical counters related to synchronization operations.
///
/// This mixin provides convenient accessors for standard metrics defined in [SyncSummary],
/// while allowing flexible retrieval of custom, domain-specific operation keys.
mixin SummaryGetter {
  /// Returns the current count of a specific operation identified by [key].
  int getCount(String key);

  /// The total number of items targeted or identified for synchronization.
  int get totalCount => getCount(SyncSummary.total);

  /// The number of items successfully created at the destination.
  int get addCount => getCount(SyncSummary.add);

  /// The number of items successfully modified at the destination.
  int get updateCount => getCount(SyncSummary.update);

  /// The number of items successfully deleted from the destination.
  int get removeCount => getCount(SyncSummary.remove);

  /// The number of items successfully recovered during retries or reconciliation.
  int get recoverCount => getCount(SyncSummary.recover);

  /// The number of items that were already in the latest state and thus skipped.
  int get latestCount => getCount(SyncSummary.latest);

  /// Returns `true` if any synchronization operations have been recorded.
  bool get hasChanges => totalCount > 0;

  /// Returns `true` if every processed item was already up-to-date.
  bool get allLatest => totalCount > 0 && totalCount == latestCount;
}

/// An immutable value object representing the statistical breakdown of a synchronization task.
///
/// Acts as a cumulative counter that tracks both standard lifecycle operations
/// (add, update, remove) and custom metrics across the synchronization tree.
class SyncSummary extends Equatable with SummaryGetter {
  /// Key representing the total workload.
  static const String total = 'total';

  /// Key representing creation operations.
  static const String add = 'add';

  /// Key representing modification operations.
  static const String update = 'update';

  /// Key representing deletion operations.
  static const String remove = 'remove';

  /// Key representing items recovered after initial failure.
  static const String recover = 'recover';

  /// Key representing items that required no action.
  static const String latest = 'latest';

  final Map<String, int> _map;

  /// Creates a [SyncSummary] instance.
  ///
  /// The internal map is immutable, ensuring consistent state as results
  /// propagate from leaf nodes up to the composite root.
  const SyncSummary([this._map = const {}]);

  @override
  int getCount(String key) => _map[key] ?? 0;

  /// Returns a new [SyncSummary] with the counter for [key] incremented by 1.
  ///
  /// This operator facilitates a functional, thread-safe approach to
  /// updating synchronization progress within the engine.
  SyncSummary operator +(String key) {
    final newMap = Map<String, int>.from(_map);
    newMap[key] = (newMap[key] ?? 0) + 1;
    return SyncSummary(newMap);
  }

  /// Merges this summary with [other] by aggregating values for all keys.
  ///
  /// Primarily utilized by composite nodes to consolidate results from
  /// multiple child nodes into a unified statistical report.
  SyncSummary merge(SyncSummary other) {
    if (other._map.isEmpty) return this;
    if (_map.isEmpty) return other;

    final newMap = Map<String, int>.from(_map);
    other._map.forEach((key, value) {
      newMap[key] = (newMap[key] ?? 0) + value;
    });
    return SyncSummary(newMap);
  }

  @override
  String toString() {
    if (_map.isEmpty) return 'SyncSummary(empty)';

    const priorityKeys = [
      SyncSummary.total,
      SyncSummary.add,
      SyncSummary.update,
      SyncSummary.remove,
      SyncSummary.recover,
      SyncSummary.latest,
    ];

    final sortedKeys = _map.keys.toList()
      ..sort((a, b) {
        final indexA = priorityKeys.indexOf(a);
        final indexB = priorityKeys.indexOf(b);

        if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
        if (indexA != -1) return -1;
        if (indexB != -1) return 1;
        return a.compareTo(b);
      });

    final buffer =
        sortedKeys.where((key) => (_map[key] ?? 0) > 0).map((key) => '$key: ${_map[key]}').join(', ');

    return 'SyncSummary($buffer)';
  }

  @override
  List<Object?> get props => [_map];
}
