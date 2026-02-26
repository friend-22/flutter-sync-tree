-----

# 🚀 Expert Sync Tree: Technical Deep Dive

This example isn't just a "Hello World". It demonstrates how `flutter_sync_tree` handles high-pressure, complex synchronization logic.

## 🏗 Advanced Scenarios in this Example

### 1\. Inter-Node Dependency (`LateSync`) 🔗

In production, you often can't sync 'Items' until 'Category' data is ready.

  * **The Solution:** `LateFakeFirebaseLeaf` checks if its `primary` node has successfully received data.
  * **The Magic:** If the primary isn't ready, it throws a `Dependency not met` exception. The core engine's **Exponential Backoff (RetryConfig)** automatically handles the waiting period without a single line of `Timer` or `manual retry` logic in your UI.

### 2\. Bridging Nested Streams (`HTTP Download`) 🌊

How do you sync a continuous stream (like a large file download) into a tree?

  * **The Solution:** `FakeHttpDownloadLeaf` uses `await for` to listen to an inner download stream.
  * **The Logic:** It calculates the `delta` (incremental bytes) and reports it via `onSyncOper('data', count: delta)`. This allows a single task to update its progress bar hundreds of times smoothly.

### 3\. Smart Validation & Error Injection ⚡

The `DataInjectorPanel` allows you to "poison" the next data packet.

  * **Payload Validation:** `FakeFirebaseLeaf` throws an error if the data count exceeds 50, simulating "Payload Too Large" (413) errors.
  * **Storage Check:** `FakeHttpDownloadLeaf` simulates a "Storage Full" scenario if the simulated file size is too large.

-----

## 🧠 Key Implementation Patterns

### Mapping Domain Events to SyncSummary

Instead of managing counters manually, use the `onSyncOper` callback to categorize your work:

```dart
switch (change) {
  case FakeDocumentChangeType.added:
    await onSyncOper(SyncSummary.add); // Increments 'add' count & progress
    break;
  case FakeDocumentChangeType.removed:
    await onSyncOper(SyncSummary.remove); // Increments 'remove' count & progress
    break;
}
```

### Bridging External Streams to Lifecycle

The simulators show how to wrap any data source into the `SyncNode` lifecycle:

```dart
@override
Future<void> start() async {
  await super.start();
  // Simply bridge your stream to triggerSync
  _sub = stream.listen((data) => triggerSync(data));
}
```

-----

## 📊 Summary of Simulated Nodes

| Node Name | Type | Key Behavior |
| :--- | :--- | :--- |
| **User Profile** | `FirebaseLeaf` | Parallel sync, random document changes. |
| **Resource Pack** | `HttpLeaf` | Chunk-based progress updates (Bytes). |
| **Late Sync** | `LateLeaf` | **Wait & Retry** logic based on `Primary Sync`. |
| **Two-Way** | `Simulator` | Simultaneous data injection to multiple leaves. |

-----