import 'package:example/mocks/fake_firebase.dart';
import 'package:example/widgets/sync_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

class SyncChildRow extends StatelessWidget {
  final SyncNode node;
  const SyncChildRow({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: node.events,
      builder: (context, _) {
        final (isWaiting, retryCount, primaryKey) = switch (node) {
          LateFakeFirebaseLeaf n when n.isSyncing => (n.isWaiting, n.retryCount, n.primary.key),
          _ => (false, 0, null),
        };

        final isError = node.isError;
        final statusColor = node.statusColor;

        String statusLabel = isError
            ? 'FAILED'
            : isWaiting
            ? (retryCount > 0 ? 'RETRY $retryCount' : 'WAITING')
            : '${(node.progress * 100).toInt()}%';

        String subtitle = isError
            ? (node.message ?? 'Sync failed')
            : isWaiting
            ? 'Waiting for $primaryKey...'
            : '';

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isError ? Colors.red.withValues(alpha: 0.05) : Colors.transparent,
            border: Border(
              left: (isError || isWaiting) ? BorderSide(color: statusColor, width: 4) : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              _buildLeading(isError, isWaiting, retryCount > 0, node.progress, statusColor),
              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleRow(isError, isWaiting),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: isError ? Colors.red : Colors.orange.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 8),

              _buildStatusTrailing(statusLabel, statusColor, retryCount > 0),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTitleRow(bool isError, bool isWaiting) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            node.key ?? 'UNKNOWN',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isError ? Colors.red.shade900 : Colors.blueGrey.shade900,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (!isError && !isWaiting && node.summary.totalCount > 0) ...[
          _buildSeparator(),
          Flexible(child: SummaryBadge(summary: node.summary, isCompact: true)),
        ],
      ],
    );
  }

  Widget _buildSeparator() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      width: 1,
      height: 8,
      color: Colors.blueGrey.withAlpha(30),
    );
  }

  Widget _buildStatusTrailing(String label, Color color, bool isRetrying) {
    return SizedBox(
      width: 55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.3),
          ),
          const SizedBox(height: 2),
          StatusIcon(node: node, size: 13, isRetrying: isRetrying),
        ],
      ),
    );
  }

  Widget _buildLeading(bool isError, bool isWaiting, bool isRetrying, double progress, Color color) {
    if (isError) {
      return Icon(Icons.error_outline_rounded, color: color, size: 20, key: const ValueKey('error'));
    }
    if (isWaiting) {
      return Center(
        key: const ValueKey('waiting'),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        ),
      );
    }
    return CircularIndicator(
      key: const ValueKey('normal'),
      progress: progress,
      color: color,
      isRetrying: isRetrying,
    );
  }
}
