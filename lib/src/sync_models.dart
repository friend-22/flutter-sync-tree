import 'package:equatable/equatable.dart';

/// A mixin providing convenient read-only accessors for [SyncSummary] counters.
///
/// Applied to [SyncSummary] itself, this interface standardizes how operation
/// counts are retrieved — both for the predefined keys (add, update, remove, etc.)
/// and for custom, domain-specific operation keys via [getCount].
///
/// ### Example
/// ```dart
/// final summary = SyncSummary({
///   SyncSummary.total: 100,
///   SyncSummary.add: 30,
///   SyncSummary.latest: 70,
/// });
///
/// print(summary.addCount);    // 30
/// print(summary.latestCount); // 70
/// print(summary.allLatest);   // false (not all items were skipped)
/// ```
mixin SummaryGetter {
  /// Returns the current count for a specific operation identified by [key].
  ///
  /// Returns `0` if [key] has not been recorded. Use this method to access
  /// custom domain-specific operation keys beyond the predefined constants.
  int getCount(String key);

  /// The total number of items targeted or identified for synchronization.
  ///
  /// Set once at the start of a session via [SyncTaskState.setTotal].
  /// Serves as the denominator for all progress calculations.
  int get totalCount => getCount(SyncSummary.total);

  /// The number of items successfully created at the destination.
  int get addCount => getCount(SyncSummary.add);

  /// The number of items successfully modified at the destination.
  int get updateCount => getCount(SyncSummary.update);

  /// The number of items successfully deleted from the destination.
  int get removeCount => getCount(SyncSummary.remove);

  /// The number of items recovered during retries or conflict reconciliation.
  ///
  /// Unlike other operations, [SyncSummary.recover] does not advance the
  /// [completedCount] in [SyncTaskState], as it represents a correction
  /// rather than forward progress on the primary workload.
  int get recoverCount => getCount(SyncSummary.recover);

  /// The number of items that were already up-to-date and required no action.
  ///
  /// These items still count toward [completedCount] and progress,
  /// but represent a no-op at the data layer.
  int get latestCount => getCount(SyncSummary.latest);

  /// Returns `true` if any synchronization operations have been recorded.
  ///
  /// Equivalent to `totalCount > 0`. Use this to distinguish between
  /// "no work done" and "all items were already up-to-date".
  bool get hasChanges => totalCount > 0;

  /// Returns `true` if every processed item was already up-to-date.
  ///
  /// Both conditions must hold: work was attempted (`totalCount > 0`)
  /// and every item was skipped (`totalCount == latestCount`).
  bool get allLatest => totalCount > 0 && totalCount == latestCount;
}

/// An immutable value object representing the statistical breakdown of a synchronization task.
///
/// Tracks both standard lifecycle operations (add, update, remove, recover, latest)
/// and custom domain-specific metrics, identified by arbitrary string keys.
///
/// Designed to be accumulated functionally: each operation produces a new instance
/// via [operator +] or [merge], preserving immutability as results propagate
/// from leaf nodes up to the composite root.
///
/// ### Predefined Keys
/// | Key                    | Meaning                                     |
/// |------------------------|---------------------------------------------|
/// | [SyncSummary.total]    | Total items targeted for sync               |
/// | [SyncSummary.add]      | Items created at destination                |
/// | [SyncSummary.update]   | Items modified at destination               |
/// | [SyncSummary.remove]   | Items deleted from destination              |
/// | [SyncSummary.recover]  | Items reconciled after failure              |
/// | [SyncSummary.latest]   | Items already up-to-date (skipped)          |
///
/// ### Example
/// ```dart
/// // Building a summary inside performSync
/// await onSyncOper(SyncSummary.add);           // +1 add
/// await onSyncOper(SyncSummary.latest, count: 5); // +5 latest
///
/// // Merging two summaries (done automatically by SyncComposite)
/// final merged = summaryA.merge(summaryB);
/// print(merged.addCount); // combined add count
/// ```
class SyncSummary extends Equatable with SummaryGetter {
  /// Key for the total number of items targeted for synchronization.
  static const String total = 'total';

  /// Key for items successfully created at the destination.
  static const String add = 'add';

  /// Key for items successfully modified at the destination.
  static const String update = 'update';

  /// Key for items successfully deleted from the destination.
  static const String remove = 'remove';

  /// Key for items recovered during retries or conflict reconciliation.
  ///
  /// Recover operations are recorded in the summary but do not advance
  /// the [completedCount] in [SyncTaskState.step], as they represent
  /// corrective work rather than primary progress.
  static const String recover = 'recover';

  /// Key for items that were already in the desired state and skipped.
  static const String latest = 'latest';

  /// The internal counter map.
  ///
  /// Declared as `const {}` by default, making empty instances allocation-free.
  /// Always replaced (never mutated) to preserve immutability.
  final Map<String, int> _map;

  /// Creates a [SyncSummary] from an optional counter map.
  ///
  /// The default empty map (`const {}`) is allocation-free and safe to share.
  /// Composite nodes use this to initialize a clean accumulator before folding
  /// child summaries together via [merge].
  const SyncSummary([this._map = const {}]);

  /// Returns the count for [key], or `0` if the key has not been recorded.
  @override
  int getCount(String key) => _map[key] ?? 0;

  /// Returns a new [SyncSummary] with the counter for [key] incremented by 1.
  ///
  /// This operator enables a clean, functional accumulation pattern inside
  /// [SyncTaskState.step]:
  /// ```dart
  /// summary = summary + SyncSummary.add;
  /// ```
  /// Each call creates a new instance, preserving immutability.
  SyncSummary operator +(String key) {
    final newMap = Map<String, int>.from(_map);
    newMap[key] = (newMap[key] ?? 0) + 1;
    return SyncSummary(newMap);
  }

  SyncSummary plus(String key, int count) {
    if (count <= 0) return this;
    final newMap = Map<String, int>.from(_map);
    newMap[key] = (newMap[key] ?? 0) + count;
    return SyncSummary(newMap);
  }

  /// Returns a new [SyncSummary] that combines this instance with [other].
  ///
  /// All keys from both summaries are aggregated by summing their values.
  /// Used by [SyncComposite.summary] to consolidate results from multiple
  /// child nodes into a single unified report.
  ///
  /// Short-circuits with early returns when either map is empty to avoid
  /// unnecessary allocations in the common case of merging with a blank summary.
  SyncSummary merge(SyncSummary other) {
    if (other._map.isEmpty) return this;
    if (_map.isEmpty) return other;

    final newMap = Map<String, int>.from(_map);
    other._map.forEach((key, value) {
      newMap[key] = (newMap[key] ?? 0) + value;
    });
    return SyncSummary(newMap);
  }

  /// Returns a human-readable string representation of this summary.
  ///
  /// Keys are sorted by a predefined priority order (total → add → update →
  /// remove → recover → latest → custom keys alphabetically), and keys with
  /// a count of `0` are omitted for clarity.
  ///
  /// Example output: `SyncSummary(total: 100, add: 30, latest: 70)`
  @override
  String toString() {
    if (_map.isEmpty) return 'SyncSummary(empty)';

    // Predefined display order for standard keys.
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

        // Priority keys come first, in their defined order.
        if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
        if (indexA != -1) return -1;
        if (indexB != -1) return 1;
        // Custom keys are sorted alphabetically after priority keys.
        return a.compareTo(b);
      });

    final buffer =
        sortedKeys.where((key) => (_map[key] ?? 0) > 0).map((key) => '$key: ${_map[key]}').join(', ');

    return 'SyncSummary($buffer)';
  }

  /// Equality is based solely on the contents of the internal counter map.
  @override
  List<Object?> get props => [_map];
}
