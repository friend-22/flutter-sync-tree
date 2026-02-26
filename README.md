-----

# 🚀 Throttled Sync Tree

[](https://www.google.com/search?q=https://pub.dev/packages/throttled_sync_tree)
[](https://opensource.org/licenses/MIT)

**A robust, high-performance synchronization framework for Flutter and Dart.**
It manages complex, multi-layered data synchronization with **weighted progress calculation, 
intelligent throttling**, and **resilient flow control**.

Designed for applications handling large-scale real-time data (like Firebase Cloud Firestore) 
or complex multi-stage initialization sequences where UI responsiveness is critical.

-----

## ✨ Key Features

* **🏗️ Hierarchical Structure**: Organize sync tasks into a tree using the **Composite Pattern**. 
 Manage individual `SyncLeaf` and grouped `SyncComposite` nodes through a unified interface.
* **⚖️ Intelligent Weighted Progress**: Progress is calculated based on the actual workload volume (`totalCount`), 
 ensuring the progress bar reflects data reality rather than just the number of tasks.
* **⚡ Performance-Optimized Throttling**: Prevents UI jank during high-frequency updates (e.g., initial 10k+ record syncs) 
 by gating updates through configurable thresholds and time intervals.
* **🛡️ Resilient Flow Control**:
  * **Pause & Resume**: Seamlessly suspend and restart synchronization tasks.
  * **Smart Exponential Backoff**: Automatic retries with incrementally increasing delays.
    * `Formula: baseDelay * (multiplier ^ (retryCount - 1))`
  * **Phase Management**: Execute tasks in `Primary` (parallel) or `Late` (sequential) phases.
* **📊 Granular Statistics**: Track specific operation metrics including `total`, `add`, `update`, `remove`, `latest`, and `recover`.
* **🎯 Origin Tracking**: Precisely identify which node triggered an event, even within deeply nested trees.

---

## 🏗 Architecture

Throttled Sync Tree follows the `Composite Design Pattern`. Every task is a `SyncNode`, allowing you to build deeply nested 
synchronization logic that remains highly maintainable.

* **SyncNode**: The base abstraction for all units.
* **SyncLeaf**: The worker node for concrete data processing (e.g., Cloud → Local DB).
* **SyncComposite**: The coordinator node that aggregates children and calculates global progress.

**Visual Tree Example**

```text
Root (SyncComposite)
 ├── Primary Phase (Parallel)
 │    ├── UserProfile (SyncLeaf) ── 100 items (High Weight ⚖️)
 │    └── AppSettings (SyncLeaf) ── 1 item    (Low Weight  ⚖️)
 └── Late Phase (Sequential/Parallel)
      └── PhotoGallery (SyncComposite)
           ├── AlbumMetadata (SyncLeaf)
           └── HighResImages (SyncLeaf)
```
-----

## 📡 Event Propagation & Lifecycle

`SyncComposite` acts as a central hub monitoring its children. It aggregates individual child events and re-broadcasts 
them to the UI based on the configured throttling policy.


| Phase | Child Event | Parent Status | Origin in Event | UI / Logic Impact                                                       |
| :--- | :--- | :--- | :--- |:------------------------------------------------------------------------|
| **Start** | `start` | **progress** | `Child` | **Live Tracking**: Displays a "Syncing" indicator for specific child.   |
| **Progress** | `progress` | **progress** | `Child` | **Throttled Update**: Updates the parent's overall progress bar.        |
| **Error (Transient)** | `error` | **progress** | `Child` | **Relay**: Parent remains active while the child handles retries.       |
| **Complete (Single)** | `complete` | **progress** | `Child` | **Snapshot**: Saves child summary and recalculates total weight.        |
| **Error (Final)** | `error` | **error** | `Parent` | **Failure**: Triggered if all retries fail or stopOnError is enabled.   |
| **Complete (Final)** | `complete` | **complete** | `Parent` | **Success**: Triggered only when ALL children finish successfully.      |
| **Control** | `stop / pause` | **stop / pause** | `Parent` | **Global State**: Transitions occur when all children reach this state. |

---

## 💡 Key Architectural Concepts

### 1\. Origin-Aware Events
The origin parameter preserves the identity of the node where the event first occurred. 
This allows the UI to display **granular updates** (e.g., "Updating User Profiles...") even when 
listening to the top-level root node.

### 2\. Cumulative Error Messaging
The parent node's error message is reactively derived from its children, ensuring the most relevant 
diagnostic info bubbles up to the top-level listener.
```dart
@override
String? get message => _children
    .map((node) => node.message)
    .whereType<String>()
    .lastOrNull; // Returns the most recent error message from any failing child.
```

### 3\. Strict Success Policy
A `SyncComposite` is considered successfully complete only if **every single child** reaches the `complete` state.
 If one child fails, the parent transitions to `error` to maintain data integrity across the system.

---
## 🚀 Getting Started

### 1\. Define your SyncLeaf

Extend `SyncLeaf` to implement your logic. Use `onSyncOper` to report different operation types.

```dart
class UserProfileSync extends SyncLeaf<List<Map<String, dynamic>>> {
  final Stream<List<Map<String, dynamic>>> stream;
  StreamSubscription? _sub;

  UserProfileSync(this.stream) : super(key: 'user_profile');

  @override
  int getTotalCount(data) => data.length;

  @override
  Future<void> start() async {
    // ⚠️ Crucial: Always call super.start() to initialize lifecycle state.
    await super.start();
    _sub = stream.listen((snapshot) => triggerSync(snapshot));
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await super.stop();
  }

  @override
  Future<void> performSync(data, onSyncOper) async {
    for (var item in data) {
      // Check for 'Pause' or 'Stop' signals to keep the engine responsive.
      if (item['isUpToDate'] == true) {
        await onSyncOper(SyncSummary.latest); // Skip if no action required.
      } else {
        await onSyncOper(SyncSummary.update); // Perform actual data update.
      }
    }
  }
}
```

### 2\. Compose the Sync Tree

```dart
final syncTree = SyncComposite(
  key: 'root_sync',
  primarySyncs: [UserProfileSync(userStream), SettingsSync(settingsStream)],
  lateSyncs: [LogHistorySync(logStream)],
  stopOnError: true,
);
```

### 3\. Listen to Reactive States

Throttled Sync Tree provides a **Sealed Class** hierarchy for states, making it a perfect match for Flutter's pattern matching.
```dart
// Convert events to SyncState using a BLoC, Riverpod, or ViewModel
final message = switch (state) {
  SyncInitial() => 'Ready to begin',
  SyncInProgress(origin: var o) => 'Syncing ${o.key}... ${(o.progress * 100).toStringAsFixed(1)}%',
  SyncFailure(message: var m) => 'Error: $m',
  SyncSuccess() => 'Synchronization complete! 🚀',
  SyncPaused() => 'Process paused',
  _ => 'Processing...'
};
```

-----

## 🛠 Configurations

### ThrottlerConfig

Fine-tune UI update frequency to save CPU cycles.

* `threshold`: Minimum % change (0.0 to 1.0) required to trigger an update.
* `interval`: Minimum time duration between consecutive updates.

### RetryConfig

Control resilience and network behavior.

* `maxTryCount`: The maximum number of additional attempts after the initial failure.
* `baseDelayMs`: The starting delay (in ms) for the first retry.
* `multiplier` : The factor by which the delay increases for each subsequent retry.
* `timeout`: Time limit for a single synchronization attempt.

-----

## 📊 Why "Weighted" Progress?

In a typical average-based system, a task with 1 item and a task with 1,000 items each represent 50% of the progress.
In **Throttled Sync Tree**, the 1,000-item task correctly takes up **99.9%** of the progress bar weight.

**Progress Formula:**
```text
                  Σ (Child Progress × Child Total Count)
Total Progress = ────────────────────────────────────────
                        Σ (All Child Total Counts)
```

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