import 'dart:async';

import 'package:example/widgets/syc_helper.dart';
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
    String compositionSummary = _getCompositionSummary();

    final message = widget.node.hasMessage ? widget.node.message! : '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.05),
        border: Border(bottom: BorderSide(color: statusColor.withValues(alpha: 0.1))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.icon ?? Icons.folder_rounded, color: statusColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (widget.node.key ?? 'Root').toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                    Text(
                      compositionSummary,
                      style: TextStyle(fontSize: 10, color: Colors.blueGrey.withAlpha(150)),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_activeLeafs.isNotEmpty || _errorLeafs.isNotEmpty) _buildActivitySummary(),

                  const SizedBox(width: 10),
                  SummaryBadge(summary: widget.node.summary),
                ],
              ),
            ],
          ),

          const SizedBox(height: 8),

          ProgressBar(progress: widget.node.progress, color: statusColor),
          const SizedBox(height: 8),

          SyncStatusTag(label: widget.node.status.name.toUpperCase(), color: statusColor),

          if (message.isNotEmpty) ...[const SizedBox(height: 8), _buildMessage(message)],
        ],
      ),
    );
  }

  String _getCompositionSummary() {
    if (widget.node is! SyncComposite) return 'Individual Leaf Node';

    final children = (widget.node as SyncComposite).allChildren;
    if (children.isEmpty) return 'No child nodes';

    final leafCount = children.whereType<SyncLeaf>().length;
    final compositeCount = children.whereType<SyncComposite>().length;

    List<String> parts = [];
    if (compositeCount > 0) parts.add('$compositeCount Group${compositeCount > 1 ? 's' : ''}');
    if (leafCount > 0) parts.add('$leafCount Leaf${leafCount > 1 ? 'ves' : ''}');

    return parts.join(' • ');
  }

  Widget _buildActivitySummary() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      spacing: 5,
      children: [
        ..._activeLeafs.map((n) => MiniTag(label: n.key ?? '', color: Colors.blue)),
        ..._errorLeafs.map((n) => MiniTag(label: n.key ?? '', color: Colors.red, isError: true)),
      ],
    );
  }

  Widget _buildMessage(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
