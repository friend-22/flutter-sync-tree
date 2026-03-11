import 'dart:async';

import 'package:example/widgets/sync_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

class SyncHeaderSection extends StatefulWidget {
  final SyncNode node;
  final IconData? icon;
  const SyncHeaderSection({super.key, required this.node, this.icon});

  @override
  State<SyncHeaderSection> createState() => _SyncHeaderSectionState();
}

class _SyncHeaderSectionState extends State<SyncHeaderSection> {
  final Set<SyncLeaf> _activeLeafs = {};
  final Set<SyncLeaf> _errorLeafs = {};
  StreamSubscription? _uiSub;

  @override
  void initState() {
    super.initState();

    _listenEvents();
  }

  void _listenEvents() {
    _uiSub = widget.node.events.listen((event) {
      if (!mounted) return;

      final status = event.$1;
      final origin = event.$2;

      setState(() {
        if (origin is SyncLeaf) {
          switch (status) {
            case SyncStatus.start:
            case SyncStatus.progress:
              _activeLeafs.add(origin);
              _errorLeafs.remove(origin);
              break;

            case SyncStatus.complete:
            case SyncStatus.idle:
              _activeLeafs.remove(origin);
              _errorLeafs.remove(origin);
              break;

            case SyncStatus.error:
              _activeLeafs.remove(origin);
              _errorLeafs.add(origin);
              break;
            default:
              break;
          }
        }

        if (status == SyncStatus.stop || (status == SyncStatus.complete && origin == widget.node)) {
          _activeLeafs.clear();
          _errorLeafs.clear();
        }
      });
    });
  }

  @override
  void dispose() {
    _uiSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = widget.node.statusColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.04),
        border: Border(bottom: BorderSide(color: statusColor.withValues(alpha: 0.1), width: 1.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFolderIcon(statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (widget.node.key ?? 'Root').toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.5,
                        color: Colors.blueGrey.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _buildCompositionRow(),
                  ],
                ),
              ),
              SummaryBadge(summary: widget.node.summary),
            ],
          ),

          const SizedBox(height: 16),
          ProgressBar(progress: widget.node.progress, color: statusColor),

          const SizedBox(height: 12),
          _buildStatusAndActivity(statusColor),

          if (widget.node.hasMessage) ...[
            const SizedBox(height: 12),
            _buildMessage(widget.node.message!, statusColor),
          ],
        ],
      ),
    );
  }

  Widget _buildFolderIcon(Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Icon(widget.icon ?? Icons.account_tree_rounded, color: color, size: 20),
    );
  }

  Widget _buildCompositionRow() {
    if (widget.node is! SyncComposite) {
      return const Text('LEAF NODE', style: TextStyle(fontSize: 9, color: Colors.grey));
    }

    final children = (widget.node as SyncComposite).allChildren;
    final leafCount = children.whereType<SyncLeaf>().length;
    final compositeCount = children.whereType<SyncComposite>().length;

    return Row(
      children: [
        if (compositeCount > 0) ...[
          const Icon(Icons.folder_open_rounded, size: 10, color: Colors.grey),
          const SizedBox(width: 2),
          Text(
            '$compositeCount GROUPS',
            style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 6),
        ],
        const Icon(Icons.insert_drive_file_outlined, size: 10, color: Colors.grey),
        const SizedBox(width: 2),
        Text(
          '$leafCount LEAVES',
          style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildStatusAndActivity(Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SyncStatusTag(label: widget.node.status.name.toUpperCase(), color: color),
            if (_activeLeafs.isNotEmpty || _errorLeafs.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '• ${_activeLeafs.length} ACTIVE / ${_errorLeafs.length} ERR',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade400),
              ),
            ],
          ],
        ),
        if (_activeLeafs.isNotEmpty || _errorLeafs.isNotEmpty) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ..._activeLeafs.map(
                  (n) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: MiniTag(label: n.key ?? '', color: Colors.blue),
                  ),
                ),
                ..._errorLeafs.map(
                  (n) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: MiniTag(label: n.key ?? '', color: Colors.red, isError: true),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMessage(String message, Color statusColor) {
    final bool isError = widget.node.isError;
    final Color color = isError ? Colors.red : statusColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Icons.warning_amber_rounded : Icons.info_outline_rounded, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color.withValues(alpha: 0.9),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }
}
