import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// An abstract base class that mimics external data sources (e.g., Firebase, HTTP Server).
/// It periodically "injects" mock data into the [StreamController].
abstract class SyncSimulator<T> {
  static final random = Random();

  final StreamController<T> controller;
  final int intervalMs;
  DateTime? _nextEmitTime;

  DateTime? get nextEmitTime => _nextEmitTime;

  // Lifecycle flag to control the simulation loop.
  bool isWorking = false;

  // 💡 State flag to trigger an intentional error in the next emission cycle.
  bool _shouldError = false;
  bool get shouldError => _shouldError;

  bool get canNextGen => true;

  // Callback triggered whenever new data is emitted.
  VoidCallback? onDataInjected;

  SyncSimulator({required this.controller, this.intervalMs = 5000});

  double get remainingSeconds {
    if (_nextEmitTime == null || !isWorking) return 0;
    final diff = _nextEmitTime!.difference(DateTime.now()).inMilliseconds;
    return (diff > 0 ? diff : 0) / 1000;
  }

  /// Generates data or an empty/invalid payload to trigger a [SyncStatus.error].
  T generateNext({bool isError = false});

  void emitData() {
    controller.add(generateNext(isError: _shouldError));
  }

  Future<void> start(SyncNode rootNode) async {
    if (isWorking) return;
    isWorking = true;

    while (isWorking) {
      int resolveIntervalMs = !_shouldError ? intervalMs : intervalMs * 2;

      if (!rootNode.isStopped && !rootNode.isPaused) {
        emitData();
        onDataInjected?.call();

        _shouldError = false;
      }

      _nextEmitTime = DateTime.now().add(Duration(milliseconds: resolveIntervalMs));

      int elapsed = 0;
      while (elapsed < resolveIntervalMs && isWorking) {
        await Future.delayed(const Duration(milliseconds: 100));
        elapsed += 100;

        if (rootNode.isPaused || rootNode.isStopped) {
          _nextEmitTime = _nextEmitTime!.add(const Duration(milliseconds: 100));
        }
      }

      while (!canNextGen && isWorking) {
        await Future.delayed(const Duration(milliseconds: 1000));
      }
    }

    _nextEmitTime = null;
    isWorking = false;
  }

  void stop() => isWorking = false;

  /// External trigger to force an error state for testing purposes.
  void triggerError() => _shouldError = true;
}
