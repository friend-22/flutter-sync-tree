## 1.0.3
### 🔄 Breaking Changes
- **Naming Consistency Updates:**
  - **SyncLeaf**: Renamed `getCount(T data)` to `getTotalCount(T data)`.
  - **SyncComposite**: Renamed `isComplete` to `isCompleted` and `getNode()` to `findNode()`.
  - **Throttler/ThrottlerConfig**: Renamed `duration` to `interval` to better represent the time gap between updates.
  - **RetryConfig**: Renamed `lazyDelayMs` to `baseDelayMs` to clarify it as the starting point for backoff calculations.
  - **Logging**: Renamed `SyncPrint` to `SyncLog` for a more standard naming convention.
- **SyncState**: Renamed `getNode(String key)` to `findNode(String key)` to maintain API uniformity.

### 🚀 Performance & UI Optimization
- **Integrated Throttler in SyncComposite**: Aggregates high-frequency progress events from multiple child nodes to optimize main thread performance.
- **Jank Prevention**: Ensures the root progress only dispatches updates at meaningful intervals, highly configurable via `ThrottlerConfig`.

### 📊 Documentation & Reliability
- **Improved README Rendering**: Replaced LaTeX formulas with high-compatibility ASCII/Markdown diagrams for consistent rendering across `pub.dev` and GitHub.
- **Enhanced Discoverability**: Refined package metadata and descriptions to improve SEO and user guidance.
- **Added "In-Depth Examples"**: New section in documentation providing a step-by-step guide for hierarchical synchronization logic.

* **🐞 Bug Fixes & Refactoring**
  - **Notification Throttling**: Eliminated redundant state notifications to prevent log flooding and unnecessary UI rebuilds.
  - **Flow Control**: Introduced `canNextGen` logic in `SyncSimulator` to prevent data collisions by ensuring active streams finish before the next generation.
  - **Lifecycle Safety**: Enhanced stream subscription handling in `SyncLeaf` for more robust resource management during `dispose`.
  - **API Fixes**: Corrected method naming in example snippets to match the updated 1.0.3 API.

## 1.0.2

### 🔄 Breaking Changes
* **Naming Alignment**: Renamed `SyncType` to `SyncStatus` for better semantic clarity and state representation.
* **Stream Renaming**: Renamed `syncStream` to `events` in `SyncNode` to follow standard event-driven naming conventions.
* **Callback Signature**: Updated `OnSyncNotify` parameters to `(SyncStatus status, SyncNode origin)` to support source tracking.

### ✨ New Features
* **SyncState System**: Introduced a `Sealed Class` hierarchy (`SyncInitial`, `SyncInProgress`, `SyncSuccess`, `SyncFailure`, `SyncPaused`, `SyncStopped`) for easier UI integration with pattern matching.
* **Origin Tracking**: Added the `origin` field to events, allowing developers to identify exactly which child node triggered an update within complex trees.

### 📈 Improvements
* **UX-Focused Progress**: Updated `SyncTaskState` to include `latest` (up-to-date) operations in progress calculations, ensuring the progress bar reaches 100% when data is already synchronized.
* **Throttler Refinement**: Enhanced floating-point `precision` handling and added `fps30`/`fps60` factory constructors for optimized UI performance.
* **Documentation**: Revamped README with architectural diagrams, weighted progress formulas, and Riverpod integration examples.


## 1.0.1
* Minor documentation fixes.

## 1.0.0
* Initial release of flutter_sync_tree.
* Support for Hierarchical Sync Tree, Weighted Progress, and Throttling.