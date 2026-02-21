import 'package:equatable/equatable.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// Sealed class hierarchy representing the immutable state of the Sync system.
///
/// Perfect for UI consumption with 'switch' expressions or Pattern Matching.
sealed class SyncState extends Equatable {
  final SyncNode mainNode;

  const SyncState(this.mainNode);

  /// Overall summary of the entire sync tree.
  SyncSummary get summary => mainNode.summary;

  /// Overall progress of the entire sync tree (0.0 to 1.0).
  double get progress => mainNode.progress;

  /// Recursively searches for a node with the given [targetKey].
  SyncNode? getNode(String targetKey) {
    if (mainNode.key == targetKey) return mainNode;
    final node = mainNode;
    if (node is SyncComposite) {
      return node.getNode(targetKey);
    }
    return null;
  }

  @override
  List<Object?> get props =>
      [mainNode.key, mainNode.progress, mainNode.summary];
}

class SyncInitial extends SyncState {
  const SyncInitial(super.mainNode);
}

/// Represents an active sync state, providing the specific [origin] node currently being processed.
class SyncInProgress extends SyncState {
  /// The specific child node that triggered this progress update.
  final SyncNode origin;
  const SyncInProgress(super.mainNode, this.origin);

  @override
  double get progress => origin.progress;

  @override
  List<Object?> get props => [...super.props, origin.key, origin.progress];
}

class SyncSuccess extends SyncState {
  const SyncSuccess(super.mainNode);
}

class SyncFailure extends SyncState {
  final SyncNode origin;
  const SyncFailure(super.mainNode, this.origin);

  String get message => origin.message ?? 'Unknown Error';

  @override
  List<Object?> get props => [...super.props, origin.key, origin.message];
}

class SyncPaused extends SyncState {
  const SyncPaused(super.mainNode);
}

class SyncStopped extends SyncState {
  const SyncStopped(super.mainNode);
}

extension SyncStateX on SyncState {
  bool get isInitial => this is SyncInitial;
  bool get isInProgress => this is SyncInProgress;
  bool get isFinished => this is SyncSuccess || this is SyncFailure;
  bool get isPaused => this is SyncPaused;
}
