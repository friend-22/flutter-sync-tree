import 'package:example/widgets/sync_child_row.dart';
import 'package:example/widgets/sync_header_section.dart';
import 'package:example/widgets/sync_log_sheet.dart';
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
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blueGrey.withAlpha(40)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => SyncLogSheet.show(context, parent),
            child: SyncHeaderSection(node: parent, icon: icon),
          ),

          if (children.isNotEmpty)
            Container(
              color: Colors.blueGrey.withValues(alpha: 0.02),
              child: Column(
                children: [
                  Divider(height: 1, color: Colors.blueGrey.withAlpha(30)),

                  ...children.asMap().entries.map((entry) {
                    final int index = entry.key;
                    final SyncNode child = entry.value;
                    final bool isLast = index == children.length - 1;

                    return Column(
                      children: [
                        InkWell(onTap: () => SyncLogSheet.show(context, child), child: _buildChildRow(child)),
                        if (!isLast)
                          Padding(
                            padding: const EdgeInsets.only(left: 42),
                            child: Divider(height: 1, color: Colors.blueGrey.withAlpha(15)),
                          ),
                      ],
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChildRow(SyncNode child) {
    if (child is FakeHttpDownloadLeaf) {
      return DownloadNodeRow(node: child);
    }
    return SyncChildRow(node: child);
  }
}
