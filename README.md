<div align="center">

<h1>🌲 flutter_sync_tree</h1>

<p>A robust, high-performance synchronization framework for Flutter and Dart.<br/>
Manage complex multi-stage data pipelines with weighted progress, intelligent throttling, and resilient flow control.</p>

[![Pub Version](https://img.shields.io/pub/v/flutter_sync_tree?style=for-the-badge&logo=dart&logoColor=white&color=0175C2)](https://pub.dev/packages/flutter_sync_tree)
[![Pub Points](https://img.shields.io/pub/points/flutter_sync_tree?style=for-the-badge&logo=dart&logoColor=white&color=0175C2)](https://pub.dev/packages/flutter_sync_tree)
[![Pub Likes](https://img.shields.io/pub/likes/flutter_sync_tree?style=for-the-badge&logo=dart&logoColor=white&color=0175C2)](https://pub.dev/packages/flutter_sync_tree)
[![Live Demo](https://img.shields.io/badge/▶_Live_Demo-blueviolet?style=for-the-badge&logo=flutter&logoColor=white)](https://friend-22.github.io/flutter-sync-tree/)

<br/>

<table>
  <tr>
    <td align="center"><b>Dependency Pipeline</b><br/><sub>Primary + Late phase composition</sub></td>
    <td align="center"><b>Firebase Cluster</b><br/><sub>Parallel leaf nodes</sub></td>
  </tr>
  <tr>
    <td><img src="https://raw.githubusercontent.com/friend-22/flutter-sync-tree/main/assets/late_sync.gif" width="100%"/></td>
    <td><img src="https://raw.githubusercontent.com/friend-22/flutter-sync-tree/main/assets/parallel_sync.gif" width="100%"/></td>
  </tr>
</table>

</div>

<br/>

## Why flutter_sync_tree?

When syncing large datasets from Firebase or running multi-stage initialization, these problems arise:

**Progress is a lie** — A 1-item task and a 1,000-item task should not each represent 50% of the bar.

**UI jank** — Emitting thousands of state updates per second freezes the interface.

**One listener, two views** — You want a single root to watch for overall status, but you also need to know *which specific node* just failed or progressed. Without origin tracking, you'd need a separate listener per task.

**Rigid operation types** — Standard sync libraries give you `success` / `failure`. Real-world sync needs richer output: how many items were added vs. updated vs. already up-to-date vs. recovered after retry.

`flutter_sync_tree` solves all of these. Progress is **weighted by actual workload**, updates pass through a configurable **throttle gate**, every event carries its **origin node**, and `SyncSummary` accepts **any string key** you define.

---

## Features

| | |
|---|---|
| 🏗️ **Composite Tree** | Nest `SyncLeaf` and `SyncComposite` nodes into arbitrarily deep hierarchies |
| ⚖️ **Weighted Progress** | `completedCount / totalCount` across all children — not a naive average |
| ⚡ **Throttled Updates** | Gate UI rebuilds by delta threshold *and* time interval |
| 🔁 **Exponential Backoff** | Automatic retry with jitter: `baseDelay × multiplierⁿ` |
| ⏸️ **Pause / Resume** | Suspend mid-flight without losing state; resume from the same point |
| 📊 **Granular Stats** | Per-node `SyncSummary`: `add`, `update`, `remove`, `latest`, `recover` |
| 🎯 **Origin Tracking** | Every event carries the node that first triggered it |
| 🎨 **Flutter Native** | `ChangeNotifier` built-in — drop into any `ListenableBuilder` |
| 🌲 **Structured Logs** | Depth-aware console output that mirrors your tree |

---

## Architecture

Every unit in the tree is a `SyncNode`. The two concrete types share a unified interface:

```
SyncNode  (abstract — lifecycle contract + ChangeNotifier)
 ├── SyncLeaf<T>      executes actual work, owns Throttler + RetryConfig
 └── SyncComposite    orchestrates children, aggregates progress & summary
```

**Example tree**

```
root  (SyncComposite)
 ├── [Primary — parallel]
 │    ├── user_profile   SyncLeaf  100 items  ████████ high weight
 │    └── app_settings   SyncLeaf    1 item   ░ low weight
 └── [Late — parallel, starts after primary]
      └── photo_gallery  SyncComposite
           ├── album_meta    SyncLeaf
           └── hires_images  SyncLeaf
```

---

## Event Flow

`SyncComposite` listens to every child and re-broadcasts aggregated events to the UI:

| Child Event | Parent Emits | Origin | Notes |
|:---|:---|:---|:---|
| `start` | `progress` | child | Signals a specific task has begun |
| `progress` | `progress` | child | Throttled; updates overall progress bar |
| `complete` (partial) | `progress` | child | Snapshots child summary; waits for siblings |
| `complete` (all done) | `complete` | **parent** | Terminal — all children finished |
| `error` (all retries exhausted) | `error` | **parent** | Terminal — partial results in `summary` |
| `stop` / `pause` | `stop` / `pause` | **parent** | Emitted once every child reaches the state |

> Retries are handled silently inside `SyncLeaf`. No `error` event surfaces during retry attempts — only on final failure.

**Completion rule**: a `SyncComposite` is complete when every child has reached a terminal state (`complete`, `error`, or `idle` — never `syncing`). If any child is in error the parent emits `SyncStatus.error`; otherwise `SyncStatus.complete`.

---

## Getting Started

### 1 — Define your leaf

```dart
class UserProfileSync extends SyncLeaf<List<Map<String, dynamic>>> {
  final Stream<List<Map<String, dynamic>>> stream;
  StreamSubscription? _sub;

  UserProfileSync(this.stream) : super(key: 'user_profile');

  @override
  int getTotalCount(data) => data.length;

  @override
  Future<void> start() async {
    await super.start(); // ⚠️ always call super — initializes lifecycle state
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
    for (final item in data) {
      if (item['isUpToDate'] == true) {
        await onSyncOper(SyncSummary.latest);  // no-op at data layer
      } else {
        await onSyncOper(SyncSummary.update);  // write to local DB
      }
    }
  }
}
```

### 2 — Compose the tree

```dart
final root = SyncComposite(
  key: 'root',
  primarySyncs: [
    UserProfileSync(userStream),
    SettingsSync(settingsStream),
  ],
  lateSyncs: [
    LogHistorySync(logStream),
  ],
  stopOnError: false, // continue siblings on error; collect partial results
);

await root.start();
```

### 3 — React to state

`SyncState` is a sealed class — the compiler enforces exhaustive handling:

```dart
final label = switch (state) {
  SyncInitial()                 => 'Ready',
  SyncInProgress(:final origin) => '${origin.key}: ${(origin.progress * 100).toStringAsFixed(1)}%',
  SyncSuccess()                 => 'Done ✓',
  SyncFailure(:final message)   => 'Error: $message',
  SyncPaused()                  => 'Paused',
  SyncStopped()                 => 'Stopped',
};
```

---

## Configuration

### `ThrottlerConfig`

Controls how often progress updates reach the UI.

```dart
const ThrottlerConfig(
  threshold: 0.01,                         // min progress delta to emit (1%)
  interval: Duration(milliseconds: 100),   // min time between emissions
  precision: 1e-4,                         // float comparison tolerance
)
```

Use the built-in presets on `Throttler` for display-optimised rates:

```dart
Throttler.fps60(onUpdate: ...)  // 16ms interval, 0.5% threshold
Throttler.fps30(onUpdate: ...)  // 33ms interval, 1.0% threshold
```

### `RetryConfig`

Controls retry behaviour and exponential backoff.

```dart
const RetryConfig(
  maxTryCount: 3,                          // retries after initial failure
  baseDelayMs: 1000,                       // first retry delay: 1s
  multiplier: 2.0,                         // delay doubles each retry
  timeout: Duration(seconds: 30),          // per-attempt time limit
  maxJitterMs: 1000,                       // jitter ceiling (thundering herd)
)
```

Backoff formula: `delay = baseDelayMs × multiplier^(n−1) + jitter`

---

## Weighted Progress Formula

```
                  Σ completedCount  (across all leaf nodes)
Total Progress = ──────────────────────────────────────────
                    Σ totalCount    (across all leaf nodes)
```

A 1,000-item leaf alongside a 1-item leaf: the large leaf drives **99.9%** of the bar — exactly as users expect.

---

## License

MIT — see [LICENSE](LICENSE).

---

## Author

**Jack (friend-22)** · [jack.leecnet@gmail.com](mailto:jack.leecnet@gmail.com) · [github.com/friend-22/flutter-sync-tree](https://github.com/friend-22/flutter-sync-tree)

---

<sub>Architecture review and code refinement assisted by Claude (Anthropic).</sub>
