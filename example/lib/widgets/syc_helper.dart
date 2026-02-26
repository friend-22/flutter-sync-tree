import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

class SummaryBadge extends StatelessWidget {
  final SyncSummary summary;

  const SummaryBadge({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    if (summary.totalCount == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withAlpha(15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blueGrey.withAlpha(40), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildItem(Icons.layers_outlined, '${summary.totalCount}', Colors.blueGrey),

          if (summary.addCount > 0) ...[
            _buildDivider(),
            _buildItem(Icons.add_circle_outline_rounded, '${summary.addCount}', Colors.green),
          ],

          if (summary.updateCount > 0) ...[
            _buildDivider(),
            _buildItem(Icons.published_with_changes_rounded, '${summary.updateCount}', Colors.blue),
          ],

          if (summary.removeCount > 0) ...[
            _buildDivider(),
            _buildItem(Icons.delete_outline_rounded, '${summary.removeCount}', Colors.redAccent),
          ],
        ],
      ),
    );
  }

  Widget _buildItem(IconData icon, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color),
        ),
      ],
    );
  }

  Widget _buildDivider() => Container(
    height: 10,
    width: 1,
    color: Colors.blueGrey.withAlpha(50),
    margin: const EdgeInsets.symmetric(horizontal: 6),
  );
}

class ProgressBar extends StatelessWidget {
  final double progress;
  final Color color;

  const ProgressBar({super.key, required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Overall Progress', style: TextStyle(fontSize: 11, color: Colors.grey)),
            Text(
              '${(progress * 100).toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ],
    );
  }
}

class MiniTag extends StatelessWidget {
  final String label;
  final Color color;
  final bool isError;

  const MiniTag({super.key, required this.label, required this.color, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isError ? 25 : 15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(60), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isError)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.warning_amber_rounded, size: 10, color: Colors.red),
            )
          else
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          Text(
            label.toUpperCase(),
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.2),
          ),
        ],
      ),
    );
  }
}

class CircularIndicator extends StatelessWidget {
  final double progress;
  final bool isRetrying;
  final Color color;

  const CircularIndicator({super.key, required this.progress, required this.isRetrying, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(
        value: isRetrying ? null : progress,
        strokeWidth: 2.5,
        backgroundColor: Colors.grey.shade100,
        valueColor: AlwaysStoppedAnimation(isRetrying ? Colors.orange : color),
      ),
    );
  }
}

class StatusIcon extends StatelessWidget {
  final SyncNode node;
  final double size;
  final bool isRetrying;

  const StatusIcon({super.key, required this.node, this.size = 20, this.isRetrying = false});

  @override
  Widget build(BuildContext context) {
    if (isRetrying) return Icon(Icons.rotate_right_rounded, color: Colors.orange, size: size);
    if (node.isCompleted) return Icon(Icons.check_circle_rounded, color: Colors.green, size: size);
    if (node.isError) return Icon(Icons.error_outline_rounded, color: Colors.red, size: size);
    if (node.isPaused) return Icon(Icons.pause_circle_filled_rounded, color: Colors.orange, size: size);
    return Icon(Icons.radio_button_unchecked_rounded, color: Colors.grey.shade300, size: size);
  }
}

class SyncStatusTag extends StatelessWidget {
  final String label;
  final Color color;

  const SyncStatusTag({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(100), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

extension SyncNodeUI on SyncNode {
  Color get statusColor {
    if (isError) return Colors.red;
    if (isCompleted) return Colors.green;
    if (isPaused) return Colors.orange;
    if (isSyncing) return Colors.blue;
    return Colors.blueGrey;
  }

  Color get statusColorLight => statusColor.withAlpha(20);
}
