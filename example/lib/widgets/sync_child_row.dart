import 'package:example/widgets/syc_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

import '../mocks/fake_firebase.dart';

class SyncChildRow extends StatelessWidget {
  final SyncNode node;
  const SyncChildRow({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: node.events,
      builder: (context, _) {
        final bool isError = node.isError;
        final bool isLate = node is LateFakeFirebaseLeaf;
        final lateNode = isLate ? node as LateFakeFirebaseLeaf : null;

        final bool isWaiting = isLate && !lateNode!.primary.isReceivedData && node.isSyncing;
        final int retryCount = (isLate && isWaiting) ? lateNode.retryCount : 0;
        final bool isRetrying = retryCount > 0;

        final statusColor = node.statusColor;
        final Color rowBgColor = isError
            ? Colors.red.withAlpha(15)
            : (isWaiting ? Colors.orange.withAlpha(10) : Colors.transparent);

        String statusLabel = '${(node.progress * 100).toInt()}%';
        String subtitle = node.summary.toString();

        if (isError) {
          statusLabel = 'FAILED';
          subtitle = (node.message != null && node.message!.isNotEmpty)
              ? node.message!
              : 'Synchronization failed';
        } else if (isWaiting) {
          statusLabel = isRetrying ? 'RETRY $retryCount' : 'WAITING';
          subtitle = 'Waiting for ${lateNode.primary.key}...';
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: rowBgColor,
            border: (isError || isWaiting) ? Border(left: BorderSide(color: statusColor, width: 3)) : null,
          ),
          child: Row(
            children: [
              _buildLeading(isError, isWaiting, isRetrying, node.progress, statusColor),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.key ?? 'UNKNOWN',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isError ? Colors.red.shade900 : Colors.black87,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        color: isError
                            ? Colors.red.shade400
                            : (isWaiting ? Colors.orange : Colors.grey.shade600),
                        fontWeight: isError ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    statusLabel,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: statusColor),
                  ),
                  const SizedBox(height: 2),
                  StatusIcon(node: node, size: 14, isRetrying: isRetrying),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeading(bool isError, bool isWaiting, bool isRetrying, double progress, Color color) {
    if (isError) {
      return Icon(Icons.error_outline_rounded, color: color, size: 22);
    }
    if (isWaiting) {
      return SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color));
    }
    return CircularIndicator(progress: progress, color: color, isRetrying: isRetrying);
  }
}
