import 'dart:async';

import 'package:example/widgets/sync_global_controller.dart';
import 'package:example/widgets/sync_node_tile.dart';
import 'package:example/simulator/sync_simulator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

import 'widgets/data_injector_panel.dart';
import 'mocks/fake_firebase.dart';
import 'mocks/fake_http_download.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const SyncTreeDashboard(),
    );
  }
}

/// Main dashboard that demonstrates the orchestration of multiple sync strategies.
class SyncTreeDashboard extends StatefulWidget {
  const SyncTreeDashboard({super.key});

  @override
  State<SyncTreeDashboard> createState() => _SyncTreeDashboardState();
}

class _SyncTreeDashboardState extends State<SyncTreeDashboard> {
  // Sync Nodes
  late SyncComposite _rootSync, _firebaseGroup, _syncGroup;
  late SyncLeaf _userLeaf, _photoLeaf, _mediaLeaf;
  late FakeFirebaseLeaf _primaryLeaf;
  late LateFakeFirebaseLeaf _lateLeaf;

  // Simulators
  late SyncSimulator _userSim, _photoSim, _httpSim;
  late SyncSimulator _twoWaySim;

  // Controllers
  final _usersCtrl = StreamController<FakeQuerySnapshot>.broadcast();
  final _photosCtrl = StreamController<FakeQuerySnapshot>.broadcast();
  final _httpsCtrl = StreamController<FakeDownloadPackage>.broadcast();
  final _primaryCtrl = StreamController<FakeQuerySnapshot>.broadcast();
  final _lateCtrl = StreamController<FakeQuerySnapshot>.broadcast();

  StreamSubscription<FakeQuerySnapshot>? _subPrimary;

  @override
  void initState() {
    super.initState();
    _initSimulators();
    _setupSyncTree();

    SyncLog.enableComposite = false;
    SyncLog.enableLeaf = false;

    // Reset primary status on every new data emission to simulate fresh sync cycles
    _subPrimary = _primaryCtrl.stream.listen((_) => _primaryLeaf.resetDataStatus());
  }

  void _initSimulators() {
    _userSim = FakeQuerySnapshotSimulator(controller: _usersCtrl, maxCount: 40, minCount: 20);
    _photoSim = FakeQuerySnapshotSimulator(controller: _photosCtrl, maxCount: 50, minCount: 30);
    _httpSim = FakeHttpSimulator(controller: _httpsCtrl);
    _twoWaySim = TwoWaySyncSimulator(
      controller: _primaryCtrl,
      lateController: _lateCtrl,
      maxCount: 20,
      minCount: 10,
      intervalMs: 10000,
    );
  }

  void _setupSyncTree() {
    // 1. Firebase Group: Simultaneous sync of users and photos
    _userLeaf = FakeFirebaseLeaf(key: 'User Profile', stream: _usersCtrl.stream);
    _photoLeaf = FakeFirebaseLeaf(key: 'Gallery Photos', stream: _photosCtrl.stream);
    _firebaseGroup = SyncComposite(key: 'Firebase Data', primarySyncs: [_userLeaf, _photoLeaf]);

    // 2. Dependency Group: 'Late Sync' waits for 'Primary Sync'
    _primaryLeaf = FakeFirebaseLeaf(key: 'Primary Sync', stream: _primaryCtrl.stream);
    _lateLeaf = LateFakeFirebaseLeaf(
      key: 'Late Sync',
      stream: _lateCtrl.stream,
      primary: _primaryLeaf,
      retryConfig: RetryConfig(maxTryCount: 5, onRetry: (tries) => _lateLeaf.onRetry(tries)),
    );
    _syncGroup = SyncComposite(key: 'Sequential Sync', primarySyncs: [_primaryLeaf, _lateLeaf]);

    // 3. HTTP Leaf: Continuous progress tracking
    _mediaLeaf = FakeHttpDownloadLeaf(key: 'Resource Pack', stream: _httpsCtrl.stream);

    // 4. Root Orchestrator
    _rootSync = SyncComposite(key: 'App Root Sync', primarySyncs: [_firebaseGroup, _syncGroup, _mediaLeaf]);

    // Listen to global events to trigger UI updates
    _rootSync.events.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Future<void> dispose() async {
    for (var sim in [_userSim, _photoSim, _httpSim, _twoWaySim]) {
      sim.stop();
    }
    for (var ctrl in [_usersCtrl, _photosCtrl, _httpsCtrl, _primaryCtrl, _lateCtrl]) {
      ctrl.close();
    }

    await _rootSync.dispose();
    await _subPrimary?.cancel();
    _subPrimary = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar(),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.grey.shade50],
          ),
        ),
        child: Scrollbar(
          thumbVisibility: true,
          thickness: 3,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: [
              SyncGlobalController(rootNode: _rootSync),

              const SizedBox(height: 24),
              _buildDividerWithLabel('NODE ARCHITECTURE'),
              const SizedBox(height: 16),

              _buildNodeList(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: DataInjectorPanel(
          rootSync: _rootSync,
          userSim: _userSim,
          photoSim: _photoSim,
          httpSim: _httpSim,
          twoWaySim: _twoWaySim,
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        children: [
          const Text(
            'SYNC ENGINE',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5),
          ),
          Text(
            'REAL-TIME ORCHESTRATION',
            style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade400),
          ),
        ],
      ),
      centerTitle: true,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.white.withValues(alpha: 0.9),
    );
  }

  Widget _buildDividerWithLabel(String label) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            label,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade300),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }

  Widget _buildNodeList() {
    return Column(
      children: [
        SyncNodeTile(parent: _rootSync, children: [_mediaLeaf], icon: Icons.hub_rounded),
        const SizedBox(height: 12),
        SyncNodeTile(parent: _firebaseGroup, children: [_userLeaf, _photoLeaf], icon: Icons.storage_rounded),
        const SizedBox(height: 12),
        SyncNodeTile(
          parent: _syncGroup,
          children: [_primaryLeaf, _lateLeaf],
          icon: Icons.account_tree_rounded,
        ),
      ],
    );
  }
}
