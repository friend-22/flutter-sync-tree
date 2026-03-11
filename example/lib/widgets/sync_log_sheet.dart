import 'dart:async';

import 'package:example/mocks/fake_firebase.dart';
import 'package:example/widgets/sync_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

typedef LogEntry = ({
  DateTime time,
  SyncStatus status,
  String key,
  double progress,
  String summary,
  String? message,
  bool isWaiting,
  int? retryCount,
  Color color,
});

class SyncLogSheet extends StatefulWidget {
  final SyncNode node;

  const SyncLogSheet({super.key, required this.node});

  static void show(BuildContext context, SyncNode node) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SyncLogSheet(node: node),
    );
  }

  @override
  State<SyncLogSheet> createState() => _SyncLogSheetState();
}

class _SyncLogSheetState extends State<SyncLogSheet> {
  final List<LogEntry> _eventHistory = [];
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();

    _subscription = widget.node.events.listen((event) {
      if (!mounted) return;

      final status = event.$1;
      final origin = event.$2;

      final entry = (
        time: DateTime.now(),
        status: status,
        key: origin.key ?? 'Unknown',
        progress: origin.progress,
        summary: origin.summary.toString(),
        message: origin.message,
        color: origin.statusColor,
        isWaiting: (origin is LateFakeFirebaseLeaf) ? origin.isWaiting : false,
        retryCount: (origin is LateFakeFirebaseLeaf) ? origin.retryCount : null,
      );

      setState(() {
        _eventHistory.insert(0, entry);
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            _buildHandle(),
            _buildHeader(),
            const Divider(color: Colors.white10, height: 1),
            Expanded(child: _buildLogList(controller)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Row(
        children: [
          const Icon(Icons.terminal_rounded, size: 20, color: Colors.greenAccent),
          const SizedBox(width: 10),
          Text(
            "${widget.node.key} REAL-TIME EVENTS",
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),

          IconButton(
            onPressed: () => setState(() => _eventHistory.clear()),
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white38, size: 20),
            tooltip: 'Clear Logs',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: widget.node.statusColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.node.status.name.toUpperCase(),
              style: TextStyle(color: widget.node.statusColor, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(ScrollController controller) {
    if (_eventHistory.isEmpty) {
      return const Center(
        child: Text(
          "Waiting for events...",
          style: TextStyle(color: Colors.white24, fontFamily: 'monospace'),
        ),
      );
    }

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: _eventHistory.length,
      itemBuilder: (context, index) {
        final log = _eventHistory[index];

        final timeStr =
            "${log.time.hour.toString().padLeft(2, '0')}:"
            "${log.time.minute.toString().padLeft(2, '0')}:"
            "${log.time.second.toString().padLeft(2, '0')}."
            "${log.time.millisecond.toString().padLeft(3, '0')}";

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    timeStr,
                    style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 9,
                      fontFamily: 'monospace',
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildStatusBadge(log),

                  if (log.retryCount != null && log.retryCount! > 0) _buildRetryBadge(log.retryCount!),

                  if (log.isWaiting)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Text(
                        "⌛ WAITING...",
                        style: TextStyle(color: Colors.cyanAccent, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),

                  const Spacer(),
                  Text(
                    "${(log.progress * 100).toStringAsFixed(2)}%",
                    style: const TextStyle(color: Colors.white30, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                log.summary,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
              if (log.message != null && log.message!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    "└ ${log.message}",
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHandle() => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    width: 40,
    height: 4,
    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)),
  );

  Widget _buildStatusBadge(LogEntry log) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: log.color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        log.status.name.toUpperCase(),
        style: TextStyle(color: log.color, fontSize: 8, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildRetryBadge(int count) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.4)),
      ),
      child: Text(
        "RETRY $count",
        style: const TextStyle(color: Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }
}
