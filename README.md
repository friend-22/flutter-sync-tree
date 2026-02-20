# Throttled Sync Tree

A robust, high-performance synchronization framework for Flutter/Dart. It manages complex, multi-layered data synchronization with built-in **weighted progress calculation**, **intelligent throttling**, and **resilient flow control**.

Perfect for applications handling large-scale real-time data (like Firebase Cloud Firestore) or complex initialization sequences.

## ✨ Key Features

* **Hierarchical Sync Structure**: Group multiple sync tasks into a single tree using the **Composite Pattern**. Manage single tasks (`SyncLeaf`) and groups (`SyncComposite`) uniformly.
* **Smart Weighted Progress**: Progress is calculated based on the actual volume of data (`totalCount`) in each node, ensuring the progress bar reflects reality, not just the number of tasks.
* **Performance Optimized Throttling**: Prevents UI jank during high-frequency data updates (e.g., initial 10k+ record syncs) by limiting update frequency through configurable thresholds and durations.
* **Resilient Flow Control**:
    * **Pause & Resume**: Suspend and restart sync tasks seamlessly using `Completer` logic.
    * **Exponential Backoff Retry**: Automatically retry failed tasks with increasing delays.
    * **Stop on Error**: Optional fail-fast mechanism for the entire sync tree.
* **State-Driven Design**: Clean `SyncState` hierarchy (Initial, InProgress, Success, Failure) that works perfectly with Bloc, Provider, or Riverpod.

-----

## 🏗 Architecture

Designed with a focus on **Scalability** and **Maintainability**.



* **SyncNode**: The base abstraction for all synchronization units.
* **SyncLeaf**: The "Leaf" node that handles actual data processing (e.g., Firestore → Local DB).
* **SyncComposite**: The "Branch" node that aggregates multiple nodes and calculates overall progress.

-----

## 🚀 Getting Started

### 1. Define your SyncLeaf

Extend `SyncLeaf` or `FirebaseSyncLeaf` to implement your actual synchronization logic.

```dart
class UserProfileSync extends SyncLeaf<Map<String, dynamic>> {
  UserProfileSync() : super(key: 'user_profile');

  @override
  int getCount(Map<String, dynamic> data) => data.length;

  @override
  Future<void> performSync(data, onSyncOper) async {
    for (var entry in data.entries) {
      // Simulate work
      await Future.delayed(Duration(milliseconds: 100));
      
      // Notify operation (add, update, remove, etc.)
      await onSyncOper(SyncSummary.update);
    }
  }
}
```


### 2\. Compose a Sync Tree

Combine multiple leaves into a composite node.

```dart
final syncTree = SyncComposite(
  key: 'root_sync',
  primarySyncs: [
    UserProfileSync(),
    SettingsSync(),
  ],
  lateSyncs: [
    LogHistorySync(),
  ],
  stopOnError: true,
);
```

### 3\. Listen to Progress

Listen to the stream to update your UI.

```dart
syncTree.syncStream.listen((event) {
  final type = event.$1;   // SyncType
  final node = event.$2;   // The node that triggered the update

  print('Total Progress: ${syncTree.progress * 100}%');
  print('Summary: ${syncTree.summary}');
});

await syncTree.start();
```

-----

## 🛠 Configurations

### ThrottlerConfig

Fine-tune how often your UI updates.

* `threshold`: Minimum % change to trigger an update (e.g., `0.01` for 1%).
* `duration`: Minimum time between updates (e.g., `100ms`).

### RetryConfig

Control the resilience of your sync tasks.

* `maxTryCount`: Number of attempts.
* `lazyDelayMs`: Base delay for exponential backoff.
* **Retry Delay Formula:** `delay = lazyDelayMs * (2 ^ tries)`
-----

## 📊 Why "Weighted" Progress?

In a typical average-based system, a task with 1 item and a task with 1,000 items both 
represent 50% of the progress. In **Throttled Sync Tree**, the 1,000-item task correctly
takes up 99.9% of the progress bar weight.

* **Progress Calculation:** `Total Progress = Σ(Node Progress * Total Count) / Σ(Total Count)`

-----

## 📜 License
  This project is licensed under the **MIT License** - see the LICENSE file for details.

-----
## 🙏 Acknowledgments
* **Riverpod**: Inspiration for reactive state management.

* **Firebase**: Foundation for real-time stream handling.

* **Gemini**: Supported code refactoring and architecture optimization.

-----
## 👨‍💻 Author
**LeeCNet**

Email: jack.leecnet@gmail.com

Github: https://github.com/friend-22/flutter-sync-tree

-----
