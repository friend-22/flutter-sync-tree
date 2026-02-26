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

class SyncTreeDashboard extends StatefulWidget {
  const SyncTreeDashboard({super.key});

  @override
  State<SyncTreeDashboard> createState() => _SyncTreeDashboardState();
}

class _SyncTreeDashboardState extends State<SyncTreeDashboard> {
  // Sync Entities: Composites represent groups, Leaves represent individual tasks.
  late SyncComposite _rootSync, _firebaseGroup, _syncGroup;
  late SyncLeaf _userLeaf, _photoLeaf, _mediaLeaf;
  late FakeFirebaseLeaf _primaryLeaf;
  late LateFakeFirebaseLeaf _lateLeaf;

  // Simulators: Used to mimic real-world data stream bursts.
  late SyncSimulator _userSim, _photoSim, _httpSim;
  late SyncSimulator _twoWaySim;

  // StreamControllers: Act as the data source for each SyncLeaf.
  final usersController = StreamController<FakeQuerySnapshot>.broadcast();
  final photosController = StreamController<FakeQuerySnapshot>.broadcast();
  final httpsController = StreamController<FakeDownloadPackage>.broadcast();
  final primaryController = StreamController<FakeQuerySnapshot>.broadcast();
  final lateController = StreamController<FakeQuerySnapshot>.broadcast();

  StreamSubscription<FakeQuerySnapshot>? _subPrimary;

  @override
  void initState() {
    super.initState();
    _initSimulators();
    _setupSyncTree();
    _bindDependencyReset();
  }

  /// Initializes mock data generators for demonstration purposes.
  void _initSimulators() {
    _userSim = FakeQuerySnapshotSimulator(controller: usersController, maxCount: 40, minCount: 20);
    _photoSim = FakeQuerySnapshotSimulator(controller: photosController, maxCount: 50, minCount: 30);
    _httpSim = FakeHttpSimulator(controller: httpsController);
    _twoWaySim = TwoWaySyncSimulator(
      controller: primaryController,
      lateController: lateController,
      maxCount: 30,
      minCount: 20,
      intervalMs: 7000,
    );
  }

  /// The heart of the architecture: Defining the hierarchical synchronization tree.
  void _setupSyncTree() {
    // Group 1: Firebase Data Sync (Parallel execution by default within Composite)
    _userLeaf = FakeFirebaseLeaf(key: 'User Profile', stream: usersController.stream);
    _photoLeaf = FakeFirebaseLeaf(key: 'Gallery Photos', stream: photosController.stream);
    _firebaseGroup = SyncComposite(key: 'Firebase Data', primarySyncs: [_userLeaf, _photoLeaf]);

    // Group 2: Sequential Sync (LateSync waits for PrimarySync to complete)
    _primaryLeaf = FakeFirebaseLeaf(key: 'Primary Sync', stream: primaryController.stream);
    _lateLeaf = LateFakeFirebaseLeaf(
      key: 'Late Sync',
      stream: lateController.stream,
      primary: _primaryLeaf,
      retryConfig: RetryConfig(onRetry: (tries) => _lateLeaf.onRetry(tries)),
    );
    _syncGroup = SyncComposite(key: 'Sync Group', primarySyncs: [_primaryLeaf, _lateLeaf]);

    // Group 3: App Root - Aggregating all groups into a single source of truth.
    _mediaLeaf = FakeHttpDownloadLeaf(key: 'Resource Pack', stream: httpsController.stream);
    _rootSync = SyncComposite(key: 'App Root Sync', primarySyncs: [_firebaseGroup, _syncGroup, _mediaLeaf]);

    // Rebuild the UI whenever any node in the tree updates.
    _rootSync.events.listen((_) {
      if (mounted) setState(() {});
    });
  }

  /// Custom logic to reset state when primary data changes.
  void _bindDependencyReset() {
    _subPrimary = primaryController.stream.listen((_) {
      _primaryLeaf.resetDataStatus();
    });
  }

  @override
  Future<void> dispose() async {
    // Clean up all simulators and stream controllers to prevent memory leaks.
    _twoWaySim.stop();
    _userSim.stop();
    _photoSim.stop();
    _httpSim.stop();
    primaryController.close();
    lateController.close();
    usersController.close();
    photosController.close();
    httpsController.close();
    await _rootSync.dispose();

    // Disposing the root composite recursively disposes all child nodes.
    await _rootSync.dispose();

    await _subPrimary?.cancel();
    _subPrimary = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final verticalGap = const SizedBox(height: 16);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'EXPERT SYNC ENGINE',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1.2),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          _buildSectionTitle(Icons.tune_rounded, 'SIMULATION CONTROL'),
          DataInjectorPanel(
            rootSync: _rootSync,
            userSim: _userSim,
            photoSim: _photoSim,
            httpSim: _httpSim,
            twoWaySim: _twoWaySim,
          ),
          verticalGap,

          _buildSectionTitle(Icons.analytics_outlined, 'GLOBAL PERFORMANCE'),
          SyncGlobalController(rootNode: _rootSync),

          const SizedBox(height: 32),
          const Divider(thickness: 1, height: 1),

          verticalGap,
          _buildSectionTitle(Icons.account_tree_outlined, 'ROOT ORCHESTRATION'),
          SyncNodeTile(parent: _rootSync, children: [_mediaLeaf], icon: Icons.account_tree),

          verticalGap,
          _buildSectionTitle(Icons.cloud_sync_outlined, 'FIREBASE CLUSTER'),
          SyncNodeTile(parent: _firebaseGroup, children: [_userLeaf, _photoLeaf], icon: Icons.person),

          verticalGap,
          _buildSectionTitle(Icons.low_priority_rounded, 'DEPENDENCY PIPELINE'),
          SyncNodeTile(parent: _syncGroup, children: [_primaryLeaf, _lateLeaf], icon: Icons.sync),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.blueGrey.shade700),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Colors.blueGrey.shade800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
