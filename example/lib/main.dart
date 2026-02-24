import 'dart:async';

import 'package:example/sync_node_tile.dart';
import 'package:example/sync_simulator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

import 'fake_firebase.dart';
import 'fake_http_download.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: const SyncExampleScreen());
  }
}

class SyncExampleScreen extends StatefulWidget {
  const SyncExampleScreen({super.key});

  @override
  State<SyncExampleScreen> createState() => _SyncExampleScreenState();
}

class _SyncExampleScreenState extends State<SyncExampleScreen> {
  late SyncComposite _rootSync, _firebaseGroup, _syncGroup;
  late SyncLeaf _userSync, _photoSync, _httpSync;
  late SyncSimulator _userSim, _photoSim, _httpSim;
  late SyncSimulator _twoWaySim;
  late FakeFirebaseLeaf _primarySync;
  late LateFakeFirebaseLeaf _lateSync;

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

  void _initSimulators() {
    _userSim = FakeQuerySnapshotSimulator(controller: usersController, maxCount: 10, minCount: 5);
    _photoSim = FakeQuerySnapshotSimulator(controller: photosController, maxCount: 20, minCount: 10);
    _httpSim = FakeHttpSimulator(controller: httpsController);
    _twoWaySim = TwoWaySyncSimulator(
      controller: primaryController,
      lateController: lateController,
      maxCount: 10,
      minCount: 5,
    );
  }

  void _setupSyncTree() {
    // 1. Firebase Group
    _userSync = FakeFirebaseLeaf(key: 'User Profile', stream: usersController.stream);
    _photoSync = FakeFirebaseLeaf(key: 'Gallery Photos', stream: photosController.stream);
    _firebaseGroup = SyncComposite(key: 'Firebase Data', primarySyncs: [_userSync, _photoSync]);

    // 2. Sync Group (Primary & Late)
    _primarySync = FakeFirebaseLeaf(key: 'Primary Sync', stream: primaryController.stream);
    _lateSync = LateFakeFirebaseLeaf(
      key: 'Late Sync',
      stream: lateController.stream,
      primary: _primarySync,
      retryConfig: RetryConfig(lazyDelayMs: 100, onRetry: (tries) => _lateSync.onRetry(tries)),
    );
    _syncGroup = SyncComposite(key: 'Sync Group', primarySyncs: [_primarySync, _lateSync]);

    // 3. Root
    _httpSync = FakeHttpDownloadLeaf(key: 'Resource Pack', stream: httpsController.stream);
    _rootSync = SyncComposite(
      key: 'App Root Sync',
      primarySyncs: [_firebaseGroup, _httpSync, _syncGroup],
      throttlerConfig: const ThrottlerConfig(duration: Duration(milliseconds: 100)),
    );

    _rootSync.events.listen((_) {
      if (mounted) setState(() {});
    });
  }

  void _bindDependencyReset() {
    _subPrimary = primaryController.stream.listen((_) {
      _primarySync.resetDataStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(title: const Text('Expert Sync Tree'), elevation: 0),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DataInjectorPanel(
            rootSync: _rootSync,
            userSim: _userSim,
            photoSim: _photoSim,
            httpSim: _httpSim,
            twoWaySim: _twoWaySim,
          ),
          const SizedBox(height: 20),

          _buildMainActions(),
          const SizedBox(height: 30),

          const Text('Sync Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SyncNodeTile(parent: _rootSync, children: [_httpSync], icon: Icons.account_tree),
          const Divider(height: 32),
          SyncNodeTile(parent: _firebaseGroup, children: [_userSync, _photoSync], icon: Icons.person),
          const Divider(height: 32),
          SyncNodeTile(parent: _syncGroup, children: [_primarySync, _lateSync], icon: Icons.sync),
        ],
      ),
    );
  }

  Widget _buildMainActions() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _actionIcon(Icons.play_arrow, Colors.green, _rootSync.start),
          _actionIcon(Icons.pause, Colors.orange, _rootSync.pause),
          _actionIcon(Icons.play_circle_filled, Colors.blue, _rootSync.resume),
          _actionIcon(Icons.stop, Colors.red, _rootSync.stop),
        ],
      ),
    );
  }

  Widget _actionIcon(IconData icon, Color color, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, color: color),
      onPressed: onPressed,
    );
  }

  @override
  Future<void> dispose() async {
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

    await _subPrimary?.cancel();
    _subPrimary = null;

    super.dispose();
  }
}
