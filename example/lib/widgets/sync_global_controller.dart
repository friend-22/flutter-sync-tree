import 'package:example/widgets/syc_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

class SyncGlobalController extends StatelessWidget {
  final SyncNode rootNode;

  const SyncGlobalController({super.key, required this.rootNode});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<(SyncStatus, SyncNode)>(
      stream: rootNode.events,
      builder: (context, snapshot) {
        final status = rootNode.status;
        final color = rootNode.statusColor;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.blueGrey.shade100),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _buildStatusIndicator(color),
                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "ROOT ENGINE",
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blueGrey),
                      ),
                      Text(
                        status.name.toUpperCase(),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
                      ),
                    ],
                  ),
                ),

                _actionBtn(
                  Icons.play_arrow,
                  Colors.green,
                  rootNode.start,
                  rootNode.isStopped || status == SyncStatus.none,
                ),
                _actionBtn(Icons.pause, Colors.orange, rootNode.pause, rootNode.isSyncing),
                _actionBtn(Icons.play_circle_filled, Colors.blue, rootNode.resume, rootNode.isPaused),
                _actionBtn(Icons.stop, Colors.red, rootNode.stop, !rootNode.isStopped),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusIndicator(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 6, spreadRadius: 1)],
      ),
    );
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onPressed, bool enabled) {
    return IconButton(
      icon: Icon(icon, color: enabled ? color : Colors.grey.shade300, size: 22),
      onPressed: enabled ? onPressed : null,
      visualDensity: VisualDensity.compact,
    );
  }
}
