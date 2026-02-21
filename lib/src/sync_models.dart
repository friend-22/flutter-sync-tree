import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';

/// Interface for accessing counters related to synchronization operations.
///
/// Provides convenient getters for standard operation types, while
/// allowing extensible access to custom operation keys.
mixin SummaryGetter {
  /// Returns the count of a specific operation by its [key].
  int getCount(String key);

  /// The total number of items planned for synchronization.
  int get totalCount => getCount(SyncSummary.total);

  /// The number of items successfully added.
  int get addCount => getCount(SyncSummary.add);

  /// The number of items successfully updated.
  int get updateCount => getCount(SyncSummary.update);

  /// The number of items successfully removed.
  int get removeCount => getCount(SyncSummary.remove);

  /// The number of items recovered after a failure or during a retry.
  int get recoverCount => getCount(SyncSummary.recover);

  /// The number of items that were already in the latest state (skipped).
  int get latestCount => getCount(SyncSummary.latest);

  /// Returns `true` if any operation (add, update, remove, etc.) has occurred.
  bool get hasChanges => totalCount > 0;

  /// Returns `true` if all items were already up-to-date.
  bool get allLatest => totalCount == latestCount;
}

/// An immutable value object representing the statistical summary of a sync task.
///
/// It acts as a cumulative counter map where you can track both standard
/// operations (add, update, remove) and custom business-specific metrics
/// by using [String] keys.
class SyncSummary extends Equatable with SummaryGetter {
  // Standard operation keys
  static const String total = 'total';
  static const String add = 'add';
  static const String update = 'update';
  static const String remove = 'remove';
  static const String recover = 'recover';
  static const String latest = 'latest';

  final Map<String, int> _map;

  /// Creates a new [SyncSummary] instance.
  ///
  /// The internal map is immutable to ensure state consistency.
  const SyncSummary([this._map = const {}]);

  @override
  int getCount(String key) => _map[key] ?? 0;

  /// Returns a new [SyncSummary] with the counter for [key] incremented by 1.
  ///
  /// This operator is used internally by the sync engine to update
  /// progress in a thread-safe, immutable manner.
  SyncSummary operator +(String key) {
    final newMap = Map<String, int>.from(_map);
    newMap[key] = (newMap[key] ?? 0) + 1;
    return SyncSummary(newMap);
  }

  /// Merges this summary with [other] by summing up all shared and unique keys.
  ///
  /// Useful for [SyncComposite] to aggregate results from all its child nodes.
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
  String toString() => 'Summary($_map)';

  @override
  List<Object?> get props => [const MapEquality<String, int>().hash(_map)];
}
