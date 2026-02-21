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