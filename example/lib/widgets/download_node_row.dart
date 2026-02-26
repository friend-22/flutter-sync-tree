import 'package:flutter/material.dart';

import '../mocks/fake_http_download.dart';

class DownloadNodeRow extends StatelessWidget {
  final FakeHttpDownloadLeaf node;

  const DownloadNodeRow({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: node.events,
      builder: (context, _) {
        final totalKb = (node.totalCount / 1024).toStringAsFixed(1);
        final currentKb = (node.completedCount / 1024).toStringAsFixed(1);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_download_outlined, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(node.key ?? 'HTTP', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const Spacer(),
                  Text('$currentKb / $totalKb KB', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: node.progress,
                  minHeight: 4,
                  backgroundColor: Colors.blue.withAlpha(20),
                  valueColor: AlwaysStoppedAnimation(node.isError ? Colors.red : Colors.blue),
                ),
              ),
              if (node.isError)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    node.message ?? 'Download Failed',
                    style: const TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
