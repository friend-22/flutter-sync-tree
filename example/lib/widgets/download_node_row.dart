import 'package:example/mocks/fake_http_download.dart';
import 'package:example/widgets/syc_helper.dart';
import 'package:flutter/material.dart';

class DownloadNodeRow extends StatelessWidget {
  final FakeHttpDownloadLeaf node;

  const DownloadNodeRow({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: node.events,
      builder: (context, _) {
        final bool isError = node.isError;
        final bool isSyncing = node.isSyncing;
        final color = isError ? Colors.red : Colors.blue;

        final totalSize = SyncFormatter.formatSize(node.totalCount);
        final currentSize = SyncFormatter.formatSize(node.completedCount);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isError ? Colors.red.withAlpha(10) : Colors.transparent,
            border: Border(bottom: BorderSide(color: Colors.blueGrey.withAlpha(15), width: 0.5)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Icon(
                      isError ? Icons.report_problem_rounded : Icons.cloud_download_rounded,
                      size: 18,
                      color: color.withAlpha(200),
                    ),
                  ),
                  const SizedBox(width: 8),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (node.key ?? 'HTTP RESOURCE').toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isError ? Colors.red.shade900 : Colors.blueGrey.shade800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isError ? (node.message ?? 'Connection failed') : '$currentSize / $totalSize',
                          style: TextStyle(
                            fontSize: 9,
                            color: isError ? Colors.red.shade400 : Colors.grey.shade500,
                            fontWeight: isError ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(
                    width: 45,
                    child: Text(
                      '${(node.progress * 100).toInt()}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              _buildProgressBar(isSyncing, isError, node.progress, color),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgressBar(bool isSyncing, bool isError, double progress, Color color) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: color.withAlpha(20),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
