import 'package:equatable/equatable.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// A sealed class hierarchy representing the immutable state of the synchronization system.
///
/// This structure is designed for UI consumption using 'switch' expressions
/// or Pattern Matching, ensuring all possible states are handled.
sealed class SyncState extends Equatable {
  /// The root node of the synchronization tree.
  final SyncNode mainNode;

  const SyncState(this.mainNode);

  /// Returns the overall summary of the entire synchronization tree.
  SyncSummary get summary => mainNode.summary;

  /// Returns the overall progress (0.0 to 1.0) of the entire synchronization tree.
  double get progress => mainNode.progress;

  /// Recursively searches for a [SyncNode] with the given [targetKey] within the tree.
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

/// The initial state before any synchronization tasks have started.
class SyncInitial extends SyncState {
  const SyncInitial(super.mainNode);
}

/// Represents an active synchronization state, highlighting the specific [origin] node
/// that triggered the update.
class SyncInProgress extends SyncState {
  /// The specific node (Leaf or Composite) that initiated this progress update.
  final SyncNode origin;

  const SyncInProgress(super.mainNode, this.origin);

  /// Returns the progress of the [origin] node specifically.
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

/// State indicating that the entire synchronization tree has completed successfully.
class SyncSuccess extends SyncState {
  const SyncSuccess(super.mainNode);
}

/// State indicating a failure, capturing the [origin] node where the error occurred.
class SyncFailure extends SyncState {
  /// The specific node where the synchronization failed.
  final SyncNode origin;

  const SyncFailure(super.mainNode, this.origin);

  /// Returns the error message from the origin node or a default message.
  String get message => origin.message ?? 'An unknown error occurred during sync.';

  @override
  List<Object?> get props => [
        ...super.props,
        origin.key,
        origin.message,
      ];
}

/// State indicating that the synchronization process has been manually paused.
class SyncPaused extends SyncState {
  const SyncPaused(super.mainNode);
}

/// State indicating that the synchronization process has been explicitly stopped.
class SyncStopped extends SyncState {
  const SyncStopped(super.mainNode);
}

/// Useful extensions for checking the current [SyncState] type easily.
extension SyncStateX on SyncState {
  bool get isInitial => this is SyncInitial;
  bool get isInProgress => this is SyncInProgress;
  bool get isFinished => this is SyncSuccess || this is SyncFailure;
  bool get isPaused => this is SyncPaused;
  bool get isStopped => this is SyncStopped;
}
