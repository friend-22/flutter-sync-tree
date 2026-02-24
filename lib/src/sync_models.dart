import 'package:equatable/equatable.dart';

/// Interface for accessing counters related to synchronization operations.
///
/// This mixin provides convenient getters for standard operation types defined in
/// [SyncSummary], while allowing extensible access to custom operation keys.
mixin SummaryGetter {
  /// Returns the count of a specific operation identified by its [key].
  int getCount(String key);

  /// The total number of items processed or planned for synchronization.
  int get totalCount => getCount(SyncSummary.total);

  /// The number of items successfully added to the destination.
  int get addCount => getCount(SyncSummary.add);

  /// The number of items successfully updated in the destination.
  int get updateCount => getCount(SyncSummary.update);

  /// The number of items successfully removed from the destination.
  int get removeCount => getCount(SyncSummary.remove);

  /// The number of items recovered during retries or after a failure.
  int get recoverCount => getCount(SyncSummary.recover);

  /// The number of items that were already up-to-date and skipped.
  int get latestCount => getCount(SyncSummary.latest);

  /// Returns `true` if any synchronization operation has performed a change.
  bool get hasChanges => totalCount > 0;

  /// Returns `true` if all processed items were already in their latest state.
  bool get allLatest => totalCount > 0 && totalCount == latestCount;
}

/// An immutable value object representing the statistical result of a sync task.
///
/// It functions as a cumulative counter map that tracks both standard
/// operations (add, update, remove) and custom domain-specific metrics.
class SyncSummary extends Equatable with SummaryGetter {
  /// Key for the total number of synchronization targets.
  static const String total = 'total';

  /// Key for successful 'add' operations.
  static const String add = 'add';

  /// Key for successful 'update' operations.
  static const String update = 'update';

  /// Key for successful 'remove' operations.
  static const String remove = 'remove';

  /// Key for items recovered during the process.
  static const String recover = 'recover';

  /// Key for items that were already latest and skipped.
  static const String latest = 'latest';

  final Map<String, int> _map;

  /// Creates a new [SyncSummary] instance.
  ///
  /// The internal map is kept immutable to ensure consistent state tracking
  /// across the synchronization tree.
  const SyncSummary([this._map = const {}]);

  @override
  int getCount(String key) => _map[key] ?? 0;

  /// Returns a new [SyncSummary] with the counter for [key] incremented by 1.
  ///
  /// This operator allows the sync engine to update progress in a
  /// thread-safe and immutable manner.
  SyncSummary operator +(String key) {
    final newMap = Map<String, int>.from(_map);
    newMap[key] = (newMap[key] ?? 0) + 1;
    return SyncSummary(newMap);
  }

  /// Merges this summary with [other] by summing up values for all keys.
  ///
  /// This is primarily used by [SyncComposite] nodes to aggregate
  /// results from multiple child nodes into a single summary.
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
  String toString() => 'SyncSummary($_map)';

  @override
  List<Object?> get props => [_map]; // Equatable handles Map equality by default
}
