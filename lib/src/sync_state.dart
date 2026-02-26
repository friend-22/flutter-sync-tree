import 'package:equatable/equatable.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// A sealed class hierarchy representing the immutable state of the synchronization system.
///
/// Designed for UI consumption using 'switch' expressions or pattern matching,
/// ensuring exhaustive handling of all possible synchronization states.
sealed class SyncState extends Equatable {
  /// The root node of the synchronization tree.
  final SyncNode mainNode;

  const SyncState(this.mainNode);

  /// Aggregates the overall summary of the entire synchronization tree.
  SyncSummary get summary => mainNode.summary;

  /// Returns the normalized progress (0.0 to 1.0) of the entire synchronization tree.
  double get progress => mainNode.progress;

  @Deprecated('Use findNode instead. This will be removed in 1.1.0')
  SyncNode? getNode(String key) => findNode(key);

  /// Recursively searches for a [SyncNode] by its [targetKey] within the tree.
  SyncNode? findNode(String targetKey) {
    if (mainNode.key == targetKey) return mainNode;

    final current = mainNode;
    if (current is SyncComposite) {
      return current.findNode(targetKey);
    }
    return null;
  }

  @override
  List<Object?> get props => [mainNode.key, progress, summary];
}

/// The state before any synchronization tasks have been initiated.
class SyncInitial extends SyncState {
  const SyncInitial(super.mainNode);
}

/// Represents an active synchronization process, providing details about the [origin] node
/// that triggered the update.
class SyncInProgress extends SyncState {
  /// The specific node (Leaf or Composite) that initiated this progress update.
  final SyncNode origin;

  const SyncInProgress(super.mainNode, this.origin);

  /// Provides the specific progress value of the [origin] node.
  @override
  double get progress => origin.progress;

  @override
  List<Object?> get props => [
        ...super.props,
        origin.key,
        origin.progress,
        origin.status,
      ];
}

/// The state indicating that the entire synchronization tree has completed successfully.
class SyncSuccess extends SyncState {
  const SyncSuccess(super.mainNode);
}

/// The state representing a failure, capturing the [origin] node where the error occurred.
class SyncFailure extends SyncState {
  /// The specific node where the synchronization error originated.
  final SyncNode origin;

  const SyncFailure(super.mainNode, this.origin);

  /// Returns the localized error message from the origin node or a generic fallback message.
  String get message => origin.message ?? 'An unexpected error occurred during synchronization.';

  @override
  List<Object?> get props => [
        ...super.props,
        origin.key,
        origin.message,
      ];
}

/// The state indicating that the synchronization process is currently suspended.
class SyncPaused extends SyncState {
  const SyncPaused(super.mainNode);
}

/// The state indicating that the synchronization process was explicitly terminated.
class SyncStopped extends SyncState {
  const SyncStopped(super.mainNode);
}

/// Convenience extensions for evaluating [SyncState] types.
extension SyncStateX on SyncState {
  bool get isInitial => this is SyncInitial;
  bool get isInProgress => this is SyncInProgress;
  bool get isFinished => this is SyncSuccess || this is SyncFailure;
  bool get isPaused => this is SyncPaused;
  bool get isStopped => this is SyncStopped;
}
