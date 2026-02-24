import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

abstract class SyncSimulator<T> {
  final random = Random();
  final StreamController<T> controller;

  bool isWorking = false;

  VoidCallback? onDataInjected;

  SyncSimulator({required this.controller});

  T generateData();

  Future<void> start(SyncNode rootNode) async {
    if (isWorking) return;
    isWorking = true;

    while (isWorking) {
      if (!rootNode.isStopped && !rootNode.isPaused) {
        controller.add(generateData());
        onDataInjected?.call();
      }
      await Future.delayed(const Duration(milliseconds: 3000));
    }
    isWorking = false;
  }

  void stop() {
    isWorking = false;
  }
}

class DataInjectorPanel extends StatefulWidget {
  final SyncNode rootSync;
  final SyncSimulator userSim;
  final SyncSimulator photoSim;
  final SyncSimulator httpSim;
  final SyncSimulator twoWaySim;

  const DataInjectorPanel({
    super.key,
    required this.rootSync,
    required this.userSim,
    required this.photoSim,
    required this.httpSim,
    required this.twoWaySim,
  });

  @override
  State<DataInjectorPanel> createState() => _DataInjectorPanelState();
}

class _DataInjectorPanelState extends State<DataInjectorPanel> {
  final Map<SyncSimulator, DateTime> _lastInjection = {};

  @override
  void initState() {
    super.initState();
    for (var sim in [widget.userSim, widget.photoSim, widget.httpSim, widget.twoWaySim]) {
      sim.onDataInjected = () {
        if (mounted) {
          setState(() {
            _lastInjection[sim] = DateTime.now();
          });
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) setState(() {});
          });
        }
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.blueGrey.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          children: [
            const Text("📡 Server Data Injector", style: TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSwitch("Users", widget.userSim),
                _buildSwitch("Photos", widget.photoSim),
                _buildSwitch("HTTP", widget.httpSim),
                _buildSwitch("Two-Way", widget.twoWaySim),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitch(String label, SyncSimulator simulator) {
    final isGlowing =
        _lastInjection[simulator] != null &&
        DateTime.now().difference(_lastInjection[simulator]!).inMilliseconds < 300;

    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(width: 4),

            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isGlowing ? Colors.greenAccent : Colors.grey.withValues(alpha: 0.3),
                boxShadow: isGlowing
                    ? [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.8), blurRadius: 8)]
                    : [],
              ),
            ),
          ],
        ),
        Switch(
          value: simulator.isWorking,
          activeTrackColor: Colors.purple.withValues(alpha: 0.3),
          activeThumbColor: Colors.purple,
          onChanged: (v) {
            setState(() {
              v ? simulator.start(widget.rootSync) : simulator.stop();
            });
          },
        ),
      ],
    );
  }
}
