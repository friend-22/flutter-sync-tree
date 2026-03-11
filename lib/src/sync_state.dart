import 'package:equatable/equatable.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// A sealed class hierarchy representing the immutable state of the synchronization system.
///
/// Designed for UI consumption using `switch` expressions or pattern matching,
/// ensuring exhaustive handling of all possible synchronization states at compile time.
///
/// Each subclass captures only the data relevant to its specific state,
/// keeping the UI layer lean and predictable.
///
/// ### State Lifecycle
/// ```
/// SyncInitial
///     ↓  (sync started)
/// SyncInProgress  ←──────────────┐
///     ↓  (all nodes complete)    │ (re-triggered by child nodes)
/// SyncSuccess                    │
///     ↓  (any node errors)       │
/// SyncFailure   ─────────────────┘
///
/// SyncPaused  ↔  SyncInProgress  (pause / resume)
/// SyncStopped                    (explicit termination)
/// ```
///
/// ### Usage with switch expression
/// ```dart
/// Widget build(BuildContext context) {
///   return switch (state) {
///     SyncInitial()    => const StartButton(),
///     SyncInProgress() => LinearProgressIndicator(value: state.progress),
///     SyncSuccess()    => SuccessView(summary: state.summary),
///     SyncFailure()    => ErrorView(message: state.message),
///     SyncPaused()     => const PausedBanner(),
///     SyncStopped()    => const StoppedBanner(),
///   };
/// }
/// ```
sealed class SyncState extends Equatable {
  /// The root node of the synchronization tree.
  ///
  /// All state queries (progress, summary, node lookup) are delegated
  /// to this node, which aggregates the state of the entire tree.
  final SyncNode mainNode;

  const SyncState(this.mainNode);

  /// Aggregates the overall [SyncSummary] of the entire synchronization tree.
  ///
  /// Combines operation counts (add, update, remove, etc.) from all
  /// leaf nodes into a single unified report.
  SyncSummary get summary => mainNode.summary;

  /// Returns the normalized progress (0.0 to 1.0) of the entire synchronization tree.
  ///
  /// Calculated as `completedCount / totalCount` across all child nodes.
  /// Returns `0.0` before any work has started and `1.0` upon full completion.
  double get progress => mainNode.progress;

  @Deprecated('Use findNode instead. This will be removed in 1.1.0')
  SyncNode? getNode(String key) => findNode(key);

  /// Recursively searches for a [SyncNode] by [targetKey] within the tree.
  ///
  /// Checks [mainNode] first, then delegates to [SyncComposite.findNode]
  /// for deep traversal. Returns `null` if no matching node is found.
  SyncNode? findNode(String targetKey) {
    if (mainNode.key == targetKey) return mainNode;

    final current = mainNode;
    if (current is SyncComposite) {
      return current.findNode(targetKey);
    }
    return null;
  }

  /// Equality is based on the node key, rounded progress, and summary.
  ///
  /// Progress is rounded to 3 decimal places (`* 1000`) to prevent
  /// spurious inequality from floating-point precision differences,
  /// which would otherwise cause unnecessary UI rebuilds.
  @override
  List<Object?> get props => [mainNode.key, (progress * 1000).round(), summary];
}

/// The initial state before any synchronization tasks have been initiated.
///
/// This is the starting state when the notifier is first created.
/// Transition to [SyncInProgress] occurs when the first child node
/// emits [SyncStatus.start] or [SyncStatus.progress].
class SyncInitial extends SyncState {
  const SyncInitial(super.mainNode);
}

/// Represents an active synchronization process.
///
/// Emitted on every meaningful progress update from any node in the tree,
/// including both [SyncStatus.start] and [SyncStatus.progress] events.
/// The [origin] field identifies which specific node triggered the update,
/// enabling fine-grained UI responses (e.g., per-task progress indicators).
///
/// ### Example
/// ```dart
/// if (state is SyncInProgress) {
///   final inProgress = state as SyncInProgress;
///   print('${inProgress.origin.key}: ${inProgress.progress * 100}%');
/// }
/// ```
class SyncInProgress extends SyncState {
  /// The specific node (Leaf or Composite) that triggered this progress update.
  ///
  /// May differ from [mainNode] when a child node fires an event that
  /// propagates up to the root. Use this to display per-task progress.
  final SyncNode origin;

  const SyncInProgress(super.mainNode, this.origin);

  /// Returns the progress of the [origin] node rather than the root.
  ///
  /// This allows the UI to reflect the precise progress of the node
  /// that triggered the update, rather than the aggregated tree progress.
  /// To get the overall tree progress, use `mainNode.progress` instead.
  @override
  double get progress => origin.progress;

  /// Extends the base props with [origin]-specific fields.
  ///
  /// Including `origin.key`, `origin.progress` (rounded), and `origin.status`
  /// ensures that two [SyncInProgress] states with different origins or
  /// progress values are correctly treated as unequal, triggering UI rebuilds
  @override
  List<Object?> get props => [
        ...super.props,
        origin.key,
        (origin.progress * 1000).round(),
        origin.status,
      ];
}

/// The state indicating that the entire synchronization tree completed successfully.
///
/// Emitted by [SyncComposite] after all child nodes have reached a terminal
/// state and none reported an error. At this point, [summary] contains the
/// full aggregated results of the sync session.
class SyncSuccess extends SyncState {
  const SyncSuccess(super.mainNode);
}

/// The state representing a failure in the synchronization tree.
///
/// Emitted when one or more child nodes encounter an unrecoverable error.
/// The [origin] field identifies the specific node where the failure occurred,
/// and [message] provides a human-readable description of the error.
///
/// When [SyncComposite.stopOnError] is `false`, sibling nodes may still
/// complete successfully — use [summary] to inspect partial results.
class SyncFailure extends SyncState {
  /// The specific node where the synchronization error originated.
  ///
  /// Useful for targeted error recovery or displaying node-specific
  /// error messages in the UI.
  final SyncNode origin;

  const SyncFailure(super.mainNode, this.origin);

  /// Returns the error message from [origin], or a generic fallback if none is set.
  ///
  /// The message is sourced from [SyncNode.message], which is populated
  /// by [SyncLeaf] when an exception is caught during [performSync].
  String get message => origin.message ?? 'An unexpected error occurred during synchronization.';

  @override
  List<Object?> get props => [
        ...super.props,
        origin.key,
        origin.message,
      ];
}

/// The state indicating that the synchronization process is currently suspended.
///
/// Emitted when all child nodes have transitioned to [SyncStatus.pause].
/// The sync tree retains its current progress and can be resumed via
/// [SyncNode.resume] without restarting from the beginning.
class SyncPaused extends SyncState {
  const SyncPaused(super.mainNode);
}

/// The state indicating that the synchronization process was explicitly terminated.
///
/// Emitted when all child nodes have transitioned to [SyncStatus.stop],
/// typically in response to a user-initiated cancellation via [SyncNode.stop].
/// Unlike [SyncFailure], this is an intentional termination — not an error.
/// Partial results may still be available in [summary].
class SyncStopped extends SyncState {
  const SyncStopped(super.mainNode);
}

/// Convenience extensions for evaluating the type of a [SyncState].
///
/// Provides concise boolean accessors as an alternative to `is` type checks,
/// reducing boilerplate in conditional UI logic.
///
/// ### Example
/// ```dart
/// if (state.isFinished) showResultDialog(state.summary);
/// if (state.isInProgress) showLoadingIndicator();
/// ```
extension SyncStateX on SyncState {
  /// Returns `true` if no sync session has started yet.
  bool get isInitial => this is SyncInitial;

  /// Returns `true` if a sync session is currently active.
  bool get isInProgress => this is SyncInProgress;

  /// Returns `true` if the sync session has ended, either successfully or with an error.
  bool get isFinished => this is SyncSuccess || this is SyncFailure;

  /// Returns `true` if the sync session is temporarily suspended.
  bool get isPaused => this is SyncPaused;

  /// Returns `true` if the sync session was explicitly cancelled.
  bool get isStopped => this is SyncStopped;
}
