import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const SyncExampleScreen(),
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
    );
  }
}

class SyncExampleScreen extends StatefulWidget {
  const SyncExampleScreen({super.key});

  @override
  State<SyncExampleScreen> createState() => _SyncExampleScreenState();
}

class _SyncExampleScreenState extends State<SyncExampleScreen> {
  late SyncComposite _rootSync;
  // ignore: unused_field
  late SyncState? _currentState;

  @override
  void initState() {
    super.initState();
    _setupSync();
  }

  void _setupSync() {
    // 1. Create Leaf Nodes
    final userSync = MockSyncLeaf('User Profile', items: 100);
    final photoSync = MockSyncLeaf('Photos', items: 500);
    final logSync = MockSyncLeaf('System Logs', items: 1000);

    // 2. Compose Tree
    _rootSync = SyncComposite(key: 'RootSync', primarySyncs: [userSync, photoSync], lateSyncs: [logSync]);

    // 3. Update UI via Events
    _rootSync.events.listen((event) {
      setState(() {
        // Here you could use the SyncState sealed classes we built
        final status = event.$1;
        final origin = event.$2;

        // Example mapping to states
        if (status == SyncStatus.progress) {
          _currentState = SyncInProgress(_rootSync, origin);
        } else if (status == SyncStatus.complete) {
          _currentState = SyncSuccess(_rootSync);
        }
        // ... add other states
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Throttled Sync Tree Example')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Overall Progress: ${(_rootSync.progress * 100).toStringAsFixed(1)}%'),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: _rootSync.progress),
            const SizedBox(height: 30),
            _buildStatusCard(),
            const SizedBox(height: 40),
            ElevatedButton(onPressed: () => _rootSync.start(), child: const Text('Start Full Sync')),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final summary = _rootSync.summary;
    return Card(
      child: ListTile(
        title: Text('Statistics (Weighted)'),
        subtitle: Text(
          'Updated: ${summary.updateCount} | Latest: ${summary.latestCount} | Recover: ${summary.recoverCount}',
        ),
      ),
    );
  }
}

// Simple Mock for Example
class MockSyncLeaf extends SyncLeaf<int> {
  final int items;
  MockSyncLeaf(String key, {required this.items}) : super(key: key);

  @override
  int getCount(int data) => data;

  @override
  Future<void> performSync(int data, OnSyncOper onSyncOper) async {
    for (int i = 0; i < items; i++) {
      await Future.delayed(const Duration(milliseconds: 10));
      await onSyncOper(SyncSummary.update);
    }
  }

  @override
  Future<void> start() {
    // TODO: implement start
    throw UnimplementedError();
  }
}
