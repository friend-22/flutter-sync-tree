import 'dart:async';

import 'package:example/simulator/sync_simulator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

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
  final Map<SyncSimulator, bool> _isGlowActive = {};

  Timer? _uiRefreshTimer;

  @override
  void initState() {
    super.initState();
    _setupSimulatorListeners();

    _uiRefreshTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    super.dispose();
  }

  void _setupSimulatorListeners() {
    final simulators = [widget.userSim, widget.photoSim, widget.httpSim, widget.twoWaySim];

    for (var sim in simulators) {
      _isGlowActive[sim] = false;

      // Handle data injection events with visual feedback
      sim.onDataInjected = () async {
        if (!mounted) return;

        // 1. Synchronously trigger the "Glow" effect
        setState(() => _isGlowActive[sim] = true);

        // 2. Perform asynchronous wait outside of setState
        await Future.delayed(const Duration(milliseconds: 250));

        // 3. Synchronously reset the state
        if (mounted) {
          setState(() => _isGlowActive[sim] = false);
        }
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const Divider(height: 16, thickness: 0.5),
          Row(
            spacing: 20,
            mainAxisAlignment: .spaceAround,
            children: [
              _buildSlimControl("Users", widget.userSim, Colors.blue),
              _buildSlimControl("Photos", widget.photoSim, Colors.purple),
              _buildSlimControl("HTTP", widget.httpSim, Colors.orange),
              _buildSlimControl("Two-Way", widget.twoWaySim, Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.bolt, color: Colors.orangeAccent, size: 16),
        const SizedBox(width: 6),
        Text(
          "DATA INJECTOR",
          style: TextStyle(
            color: Colors.blueGrey.shade800,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        Text(
          "SIMULATE REAL-TIME BURSTS",
          style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 9, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildSlimControl(String label, SyncSimulator sim, Color color) {
    final bool active = _isGlowActive[sim] ?? false;

    final double remaining = sim.remainingSeconds;
    final double progress = 1.0 - (remaining / (sim.intervalMs / 1000));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildGlowDot(active, sim.isWorking, color),
            const SizedBox(width: 8),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: sim.isWorking ? Colors.blueGrey.shade900 : Colors.blueGrey.shade300,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (sim.isWorking)
                  Text(
                    "${remaining.toStringAsFixed(1)}s",
                    style: TextStyle(
                      fontSize: 9,
                      color: color.withValues(alpha: 0.8),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),

            Transform.scale(
              scale: 0.7,
              child: Switch(
                value: sim.isWorking,
                activeThumbColor: color,
                onChanged: (val) {
                  val ? sim.start(widget.rootSync) : sim.stop();
                  setState(() {});
                },
              ),
            ),

            _buildErrorBolt(sim),
          ],
        ),

        if (sim.isWorking)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: SizedBox(
              width: 80,
              height: 2,
              child: LinearProgressIndicator(
                value: active ? 1.0 : progress,
                backgroundColor: color.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(active ? Colors.yellow : color),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGlowDot(bool active, bool isWorking, Color color) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? color : (isWorking ? color.withValues(alpha: 0.2) : Colors.grey.shade300),
        boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)] : [],
      ),
    );
  }

  Widget _buildErrorBolt(SyncSimulator sim) {
    if (!sim.isWorking) return const SizedBox(width: 20);
    return GestureDetector(
      onTap: () => setState(() => sim.triggerError()),
      child: Icon(
        Icons.flash_on,
        size: 20,
        color: sim.shouldError ? Colors.red : Colors.orange.withValues(alpha: 0.4),
      ),
    );
  }
}
