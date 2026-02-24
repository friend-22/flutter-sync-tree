import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

import 'fake_firebase.dart';

class SyncNodeTile extends StatefulWidget {
  final SyncNode parent;
  final List<SyncNode> children;
  final IconData? icon;

  const SyncNodeTile({super.key, required this.parent, this.children = const [], this.icon});

  @override
  State<SyncNodeTile> createState() => _SyncNodeTileState();
}

class _SyncNodeTileState extends State<SyncNodeTile> {
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    for (var node in [widget.parent, ...widget.children]) {
      _subs.add(node.events.listen((_) => setState(() {})));
    }
  }

  @override
  void dispose() {
    for (var sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          // 1. 부모 헤더 (전체 진행률)
          _buildParentHeader(widget.parent),
          const Divider(height: 1),
          // 2. 자식들 리스트 (콤팩트한 한 줄씩)
          ...widget.children.map((child) => _buildChildRow(child)),
        ],
      ),
    );
  }

  Widget _buildParentHeader(SyncNode n) {
    return Container(
      color: Colors.blueGrey.withValues(alpha: .05),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Icon(widget.icon ?? Icons.folder, color: _getStatusColor(n)),
              const SizedBox(width: 12),
              Expanded(
                child: Text('${n.key}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              _buildStatusTrailing(n),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: n.progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(_getStatusColor(n)),
          ),
        ],
      ),
    );
  }

  Widget _buildChildRow(SyncNode n) {
    final bool isRetrying = (n is LateFakeFirebaseLeaf) && n.retryCount > 0;
    final String statusText = isRetrying ? 'Retry ${n.retryCount}' : '${(n.progress * 100).toInt()}%';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _buildCircularProgress(n, isRetrying),
          const SizedBox(width: 12),
          _buildNodeInfo(n, isRetrying, statusText),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isRetrying ? Colors.orange : Colors.black,
            ),
          ),
          _buildStatusTrailing(n, size: 16, isRetrying: isRetrying),
        ],
      ),
    );
  }

  Widget _buildCircularProgress(SyncNode n, bool isRetrying) {
    return SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(
        value: isRetrying ? null : n.progress,
        strokeWidth: 3,
        backgroundColor: Colors.grey.shade100,
        valueColor: AlwaysStoppedAnimation(isRetrying ? Colors.orange : _getStatusColor(n)),
      ),
    );
  }

  Widget _buildNodeInfo(SyncNode n, bool isRetrying, String statusText) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(n.key ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              // 💡 재시도 횟수 뱃지 추가
              if (isRetrying)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(fontSize: 9, color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          Text(n.summary.toString(), style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  // 상태별 컬러와 아이콘 로직 (기존과 동일하지만 사이즈 조절 가능하게)
  Widget _buildStatusTrailing(SyncNode n, {double size = 20, bool isRetrying = false}) {
    if (isRetrying) return Icon(Icons.hourglass_empty_rounded, color: Colors.orange, size: size);
    if (n.isCompleted) return Icon(Icons.check_circle, color: Colors.green, size: size);
    if (n.status == SyncStatus.error) return Icon(Icons.error, color: Colors.red, size: size);
    if (n.isPaused) return Icon(Icons.pause_circle, color: Colors.orange, size: size);
    return Icon(Icons.pending_outlined, color: Colors.grey.shade400, size: size);
  }

  Color _getStatusColor(SyncNode n) {
    if (n.isCompleted) return Colors.green;
    if (n.isSyncing) return Colors.blue;
    if (n.isPaused) return Colors.orange;
    if (n.status == SyncStatus.error) return Colors.red;
    return Colors.grey;
  }
}
