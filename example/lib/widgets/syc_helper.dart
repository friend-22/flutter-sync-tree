import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

class SummaryBadge extends StatelessWidget {
  final SyncSummary summary;
  final bool isCompact;

  const SummaryBadge({super.key, required this.summary, this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    if (summary.totalCount == 0) return const SizedBox.shrink();

    final dataCount = summary.getCount('data');

    final items = [
      _buildItem(Icons.layers_outlined, '${summary.totalCount}', Colors.blueGrey),

      if (dataCount > 0)
        _buildItem(Icons.storage_rounded, SyncFormatter.formatSize(dataCount), Colors.indigoAccent),

      if (summary.addCount > 0)
        _buildItem(Icons.add_circle_outline_rounded, '${summary.addCount}', Colors.green),
      if (summary.updateCount > 0)
        _buildItem(Icons.published_with_changes_rounded, '${summary.updateCount}', Colors.blue),
      if (summary.removeCount > 0)
        _buildItem(Icons.delete_outline_rounded, '${summary.removeCount}', Colors.redAccent),
    ];

    return Container(
      padding: isCompact
          ? const EdgeInsets.symmetric(horizontal: 0, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: isCompact
          ? null
          : BoxDecoration(
              color: Colors.blueGrey.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blueGrey.withAlpha(40), width: 0.5),
            ),
      child: Wrap(
        spacing: isCompact ? 6 : 8,
        runSpacing: isCompact ? 2 : 4,
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: items,
      ),
    );
  }

  Widget _buildItem(IconData icon, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: isCompact ? 9 : 10, color: color),
        const SizedBox(width: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: isCompact ? 9 : 10,
            fontWeight: isCompact ? FontWeight.w700 : FontWeight.w900,
            color: color,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class ProgressBar extends StatelessWidget {
  final double progress;
  final Color color;

  const ProgressBar({super.key, required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Overall Progress',
                  style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500),
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.1), // 배경색을 테마색에 맞춤
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isError ? 25 : 15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(60), width: 0.8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 90),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isError)
              const Padding(
                padding: EdgeInsets.only(right: 3),
                child: Icon(Icons.warning_amber_rounded, size: 10, color: Colors.red),
              ),

            Flexible(
              child: Text(
                label.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ],
        ),
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
    return Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          value: isRetrying ? null : progress,
          strokeWidth: 2.0,
          backgroundColor: Colors.blueGrey.withAlpha(20),
          valueColor: AlwaysStoppedAnimation(isRetrying ? Colors.orange : color),
        ),
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
      child: _buildIcon(),
    );
  }

  Widget _buildIcon() {
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

class SyncFormatter {
  static String formatSize(int bytes) {
    if (bytes <= 0) return "0.0 B";
    const units = ["B", "KB", "MB", "GB"];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return "${size.toStringAsFixed(1)} ${units[i]}";
  }

  static String formatCount(int count) {
    if (count < 1000) return count.toString();
    if (count < 1000000) return "${(count / 1000).toStringAsFixed(1)}k";
    return "${(count / 1000000).toStringAsFixed(1)}m";
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

  String get displayStatus {
    if (isError) return "FAILED";
    if (isSyncing) return "${(progress * 100).toInt()}%";
    if (isCompleted) return "DONE";
    return "IDLE";
  }

  String get logMessage {
    if (isError) return message ?? "Unknown error occurred";
    if (isSyncing) {
      return "Progressing: ${(progress * 100).toStringAsFixed(1)}% | $summary";
    }
    if (isCompleted) return "Task finished successfully: $summary";
    return "Node transitioned to ${status.name} state.";
  }

  // IconData get icon => message.contains('🚨') ? Icons.error_rounded : Icons.info_rounded;
  // Color get color => message.contains('🚨') ? Colors.red : Colors.blueGrey;
  //
  // String get timeString {
  //   final t = timestamp;
  //   return "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${t.millisecond}";
  // }
}
