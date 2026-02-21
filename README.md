-----

# 🚀 Throttled Sync Tree

[](https://www.google.com/search?q=https://pub.dev/packages/throttled_sync_tree)
[](https://opensource.org/licenses/MIT)

**A robust, high-performance synchronization framework for Flutter/Dart.** It manages complex, multi-layered data synchronization with **weighted progress calculation**, **intelligent throttling**, and **resilient flow control**.

Perfect for applications handling large-scale real-time data (like Firebase Cloud Firestore) or complex multi-stage initialization sequences.

-----

## ✨ Key Features

* **🏗️ Hierarchical Structure**: Group sync tasks into a tree using the **Composite Pattern**. Manage individual `SyncLeaf` and grouped `SyncComposite` nodes uniformly.
* **⚖️ Smart Weighted Progress**: Progress is calculated based on the actual volume of data (`totalCount`), ensuring the progress bar reflects reality, not just the number of tasks.
* **⚡ Performance Optimized Throttling**: Prevents UI jank during high-frequency updates (e.g., initial 10k+ record syncs) by gating updates through configurable thresholds and durations.
* **🛡️ Resilient Flow Control**:
  * **Pause & Resume**: Seamlessly suspend and restart tasks.
  * **Exponential Backoff**: Automatic retries with increasing delays (`base * 2^tries`).
  * **Phase Management**: Execute tasks in `primary` (immediate) or `late` (sequential) phases.
* **📊 Rich Statistics**: Track not just progress, but also specific operation types like `add`, `update`, `remove`, `latest`, and `recover`.
* **🎯 Origin Tracking**: Identify exactly which node triggered an event within a complex tree.

-----

## 🏗 Architecture

* **SyncNode**: The base abstraction for all units.
* **SyncLeaf**: The worker node for actual data processing (e.g., Firestore → Local DB).
* **SyncComposite**: The coordinator node that aggregates children and calculates overall progress.

-----

## 🚀 Getting Started

### 1\. Define your SyncLeaf

Extend `SyncLeaf` or `FirebaseSyncLeaf` to implement your logic. Use `onSyncOper` to report different types of successes.

```dart
class UserProfileSync extends SyncLeaf<List<Map<String, dynamic>>> {
  UserProfileSync() : super(key: 'user_profile');

  @override
  int getCount(data) => data.length;

  @override
  Future<void> performSync(data, onSyncOper) async {
    for (var item in data) {
      // Logic: If already exists and same, it's 'latest'. If fixed, it's 'recover'.
      if (isLatest(item)) {
        await onSyncOper(SyncSummary.latest); 
      } else {
        await updateData(item);
        await onSyncOper(SyncSummary.update);
      }
    }
  }
}
```

### 2\. Compose a Sync Tree

```dart
final syncTree = SyncComposite(
  key: 'root_sync',
  primarySyncs: [UserProfileSync(), SettingsSync()], // Parallel
  lateSyncs: [LogHistorySync()], // Sequential
  stopOnError: true,
);
```

### 3\. Listen to Events

The `events` stream provides the **Status** and the **Origin** node.

```dart
syncTree.events.listen((event) {
  final status = event.$1;   // SyncStatus (start, progress, complete, etc.)
  final origin = event.$2;   // The specific node that triggered this update

  print('Status: $status from ${origin.key}');
  print('Progress: ${(syncTree.progress * 100).toStringAsFixed(1)}%');
  print('Details: ${syncTree.summary.addCount} added, ${syncTree.summary.latestCount} skipped');
});

await syncTree.start();
```

-----

## 🛠 Configurations

### ThrottlerConfig

Fine-tune UI update frequency.

* `threshold`: Minimum % change to trigger update (default: `0.01`).
* `duration`: Minimum time between updates (default: `100ms`).

### RetryConfig

Control resilience.

* `maxTryCount`: Number of attempts.
* `lazyDelayMs`: Base delay for exponential backoff.
* `timeout`: Maximum time allowed for a single sync attempt.

-----

## 📊 Why "Weighted" Progress?

In a typical average-based system, a task with 1 item and a task with 1,000 items both represent 50% of the progress. In **Throttled Sync Tree**, the 1,000-item task correctly takes up **99.9%** of the progress bar weight.

> **Formula:** \> $$Total Progress = \frac{\sum (Node Progress \times Total Count)}{\sum Total Count}$$

-----

## 📜 License

This project is licensed under the **MIT License**.

-----

## 👨‍💻 Author

**Jack (friend-22)** Email: [jack.leecnet@gmail.com](mailto:jack.leecnet@gmail.com)  
Github: [friend-22/flutter-sync-tree](https://github.com/friend-22/flutter-sync-tree)

-----

### 🙏 Acknowledgments

* **Riverpod/Bloc**: Inspiration for reactive state handling.
* **Firebase**: Foundation for real-time stream handling.
* **Gemini (Google AI)**: Supported architecture optimization and code refactoring.

-----