import 'package:example/widgets/sync_child_row.dart';
import 'package:example/widgets/sync_header_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

import 'download_node_row.dart';
import '../mocks/fake_http_download.dart';

class SyncNodeTile extends StatelessWidget {
  final SyncNode parent;
  final List<SyncNode> children;
  final IconData? icon;

  const SyncNodeTile({super.key, required this.parent, this.children = const [], this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blueGrey.shade100.withAlpha(100)),
      ),
      child: Column(
        children: [
          SyncHeaderSection(node: parent, icon: icon),
          if (children.isNotEmpty) ...[
            const Divider(height: 1),
            Container(
              color: Colors.grey.shade50.withAlpha(100),
              child: Column(
                children: children.map((child) {
                  if (child is FakeHttpDownloadLeaf) {
                    return DownloadNodeRow(node: child);
                  } else {
                    return SyncChildRow(node: child);
                  }
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
