import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';

/// Interface for accessing counters related to sync operations.
mixin SummaryGetter {
  int getCount(String key);

  int get totalCount => getCount(SyncSummary.total);

  int get addCount => getCount(SyncSummary.add);
  int get updateCount => getCount(SyncSummary.update);
  int get removeCount => getCount(SyncSummary.remove);
  int get recoverCount => getCount(SyncSummary.recover);
  int get latestCount => getCount(SyncSummary.latest);

  bool get hasChanges => totalCount > 0;
  bool get allLatest => totalCount == latestCount;
}

/// Immutable value object representing the statistical summary of a sync task.
class SyncSummary extends Equatable with SummaryGetter {
  static const String total = 'total';
  static const String add = 'add';
  static const String update = 'update';
  static const String remove = 'remove';
  static const String recover = 'recover';
  static const String latest = 'latest';

  final Map<String, int> _map;
  const SyncSummary([this._map = const {}]);

  @override
  int getCount(String key) => _map[key] ?? 0;

  /// Returns a new [SyncSummary] with an incremented value for the given [key].
  SyncSummary operator +(String key) {
    final newMap = Map<String, int>.from(_map);
    newMap[key] = (newMap[key] ?? 0) + 1;
    return SyncSummary(newMap);
  }

  /// Combines two summaries by summing their key values.
  SyncSummary merge(SyncSummary other) {
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
