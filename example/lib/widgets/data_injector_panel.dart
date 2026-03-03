import 'dart:async';

import 'package:example/simulator/sync_simulator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

import 'adaptive_scroll_view.dart';

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
  final Map<SyncSimulator, ValueNotifier<bool>> _glowNotifiers = {};
  Timer? _refreshTimer;
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _setupSimulatorListeners();

    _refreshTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted && _isExpanded) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();

    for (var notifier in _glowNotifiers.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  void _setupSimulatorListeners() {
    final simulators = [widget.userSim, widget.photoSim, widget.httpSim, widget.twoWaySim];

    for (var sim in simulators) {
      _glowNotifiers[sim] = ValueNotifier<bool>(false);

      sim.onDataInjected = () async {
        if (!mounted) return;
        _glowNotifiers[sim]!.value = true;
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        _glowNotifiers[sim]!.value = false;
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        color: Colors.white,
        child: ExpansionTile(
          trailing: Icon(
            _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
            color: Colors.blueGrey,
          ),
          onExpansionChanged: (expanded) => setState(() => _isExpanded = expanded),

          dense: true,
          initiallyExpanded: true,
          shape: const Border(),
          collapsedShape: const Border(),

          title: _buildHeader(),

          children: [
            const Divider(height: 1, color: Colors.black12),
            AdaptiveScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _buildCompactTile("Users", widget.userSim, Colors.blue),
                  const SizedBox(width: 12),
                  _buildCompactTile("Photos", widget.photoSim, Colors.purple),
                  const SizedBox(width: 12),
                  _buildCompactTile("HTTP", widget.httpSim, Colors.orange),
                  const SizedBox(width: 12),
                  _buildCompactTile("Two-Way", widget.twoWaySim, Colors.green),
                ],
              ),
            ),

            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final activeCount = [
      widget.userSim,
      widget.photoSim,
      widget.httpSim,
      widget.twoWaySim,
    ].where((s) => s.isWorking).length;

    return Row(
      children: [
        const Icon(Icons.bolt_rounded, color: Colors.orangeAccent, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "TRAFFIC CONTROL",
                style: TextStyle(
                  color: Colors.blueGrey.shade900,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                "SIMULATING REAL-TIME BURSTS",
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 8, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        _buildActiveBadge(activeCount),
      ],
    );
  }

  Widget _buildCompactTile(String label, SyncSimulator sim, Color color) {
    return RepaintBoundary(
      child: ValueListenableBuilder<bool>(
        valueListenable: _glowNotifiers[sim]!,
        builder: (context, active, _) {
          return RepaintBoundary(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 140,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: sim.isWorking ? color.withValues(alpha: 0.03) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: active
                      ? Colors.amber.shade400
                      : (sim.isWorking ? color.withValues(alpha: 0.2) : Colors.transparent),
                  width: active ? 2.0 : 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildStatusDot(active, sim.isWorking, color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: sim.isWorking ? Colors.blueGrey.shade800 : Colors.blueGrey.shade300,
                          ),
                        ),
                      ),
                      if (sim.isWorking) _buildErrorTrigger(sim),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [_buildTimerText(sim, color), _buildCustomSwitch(sim, color)],
                  ),
                  const SizedBox(height: 8),
                  _buildProgressBar(active, sim, color),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimerText(SyncSimulator sim, Color color) {
    return Text(
      sim.isWorking ? "${sim.remainingSeconds.toStringAsFixed(1)}s" : "IDLE",
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        color: sim.isWorking ? color : Colors.blueGrey.shade200,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _buildCustomSwitch(SyncSimulator sim, Color color) {
    return GestureDetector(
      onTap: () {
        sim.isWorking ? sim.stop() : sim.start(widget.rootSync);
        setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 30,
        height: 16,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: sim.isWorking ? color : Colors.grey.shade300,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: sim.isWorking ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(bool active, SyncSimulator sim, Color color) {
    final double remaining = sim.remainingSeconds;
    final double progress = 1.0 - (remaining / (sim.intervalMs / 1000));

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: active ? 1.0 : (sim.isWorking ? progress : 0.0),
        minHeight: 3,
        backgroundColor: Colors.blueGrey.shade50,
        valueColor: AlwaysStoppedAnimation(active ? Colors.amber.shade400 : color),
      ),
    );
  }

  Widget _buildStatusDot(bool active, bool isWorking, Color color) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? Colors.yellow : (isWorking ? color : Colors.grey.shade300),
        boxShadow: active
            ? [BoxShadow(color: Colors.yellow.withValues(alpha: 0.8), blurRadius: 2, spreadRadius: 1)]
            : [],
      ),
    );
  }

  Widget _buildErrorTrigger(SyncSimulator sim) {
    return GestureDetector(
      onTap: () => setState(() => sim.triggerError()),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: sim.shouldError ? Colors.red.withValues(alpha: 0.1) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.flash_on,
          size: 14,
          color: sim.shouldError ? Colors.red : Colors.grey.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildActiveBadge(int activeCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: activeCount > 0 ? Colors.blue.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        "$activeCount ONLINE",
        style: TextStyle(
          color: activeCount > 0 ? Colors.blue.shade700 : Colors.grey,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
