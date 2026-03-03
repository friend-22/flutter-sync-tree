import 'package:example/widgets/syc_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

class SyncGlobalController extends StatelessWidget {
  final SyncNode rootNode;

  const SyncGlobalController({super.key, required this.rootNode});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: rootNode.events,
      builder: (context, _) {
        final status = rootNode.status;
        final color = rootNode.statusColor;

        return RepaintBoundary(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                _buildStatusIndicator(color, rootNode.isSyncing),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "ROOT ENGINE",
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Colors.blueGrey.shade300,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        status.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: color,
                          letterSpacing: -0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _actionBtn(
                      Icons.play_arrow,
                      Colors.green,
                      rootNode.start,
                      rootNode.isStopped || status == SyncStatus.none,
                    ),
                    _actionBtn(Icons.pause, Colors.orange, rootNode.pause, rootNode.isSyncing),
                    _actionBtn(
                      Icons.play_circle_outline_rounded,
                      Colors.blue,
                      rootNode.resume,
                      rootNode.isPaused,
                    ),
                    _actionBtn(Icons.stop, Colors.red, rootNode.stop, !rootNode.isStopped),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusIndicator(Color color, bool isSyncing) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (isSyncing) _PulseCircle(color: color),

        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 4, spreadRadius: 1)],
          ),
        ),
      ],
    );
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onPressed, bool enabled) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: enabled ? color : Colors.grey.withValues(alpha: 0.2), size: 22),
        ),
      ),
    );
  }
}

class _PulseCircle extends StatefulWidget {
  final Color color;
  const _PulseCircle({required this.color});

  @override
  State<_PulseCircle> createState() => _PulseCircleState();
}

class _PulseCircleState extends State<_PulseCircle> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 0.8).animate(_controller),
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.2)),
      ),
    );
  }
}
