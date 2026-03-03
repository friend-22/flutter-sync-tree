import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_sync_tree/flutter_sync_tree.dart';

/// An abstract base class that simulates external data sources (e.g., Firebase, HTTP Server).
/// It periodically injects mock data into the [StreamController] based on [intervalMs].
abstract class SyncSimulator<T> {
  static final random = Random();
  final StreamController<T> controller;
  final int intervalMs;

  DateTime? _nextEmitTime;
  bool _isWorking = false;
  bool _shouldError = false;

  SyncSimulator({required this.controller, this.intervalMs = 5000});

  bool get isWorking => _isWorking;
  bool get shouldError => _shouldError;

  /// Override this to implement back-pressure (e.g., waiting for an active download).
  bool get canNextGen => true;

  VoidCallback? onDataInjected;

  /// Returns the remaining seconds until the next data injection.
  double get remainingSeconds {
    if (!_isWorking || _nextEmitTime == null) return 0;
    final diff = _nextEmitTime!.difference(DateTime.now()).inMilliseconds;
    return max(0, diff / 1000.0);
  }

  /// Generates the next data object.
  /// If [isError] is true, it should return a payload that triggers a [SyncStatus.error].
  T generateNext({bool isError = false});

  void emitData() {
    if (controller.isClosed) return;
    final data = generateNext(isError: _shouldError);
    controller.add(data);
    _shouldError = false;
  }

  Future<void> start(SyncNode rootNode) async {
    if (_isWorking) return;
    _isWorking = true;

    try {
      while (_isWorking) {
        int currentInterval = _shouldError ? intervalMs * 2 : intervalMs;
        _nextEmitTime = DateTime.now().add(Duration(milliseconds: currentInterval));

        // Responsive wait loop
        while (_isWorking) {
          final now = DateTime.now();

          if (rootNode.isPaused || rootNode.isStopped) {
            _nextEmitTime = _nextEmitTime!.add(const Duration(milliseconds: 100));
            await Future.delayed(const Duration(milliseconds: 100));
            continue;
          } else if (now.isAfter(_nextEmitTime!)) {
            break;
          }

          await Future.delayed(const Duration(milliseconds: 100));
        }

        if (!_isWorking) break;

        while (!canNextGen && _isWorking) {
          _nextEmitTime = DateTime.now().add(const Duration(seconds: 1));
          await Future.delayed(const Duration(seconds: 1));
        }

        if (_isWorking && !rootNode.isStopped && !rootNode.isPaused) {
          emitData();
          onDataInjected?.call();
        }
      }
    } finally {
      _isWorking = false;
      _nextEmitTime = null;
    }
  }

  /// Stops the simulation and resets the timer.
  void stop() {
    _isWorking = false;
    _nextEmitTime = null;
  }

  /// Signals the simulator to emit an error payload on the next cycle.
  void triggerError() => _shouldError = true;
}
