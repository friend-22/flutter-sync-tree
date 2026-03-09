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

  SyncNode? _rootNode;
  DateTime? _nextEmitTime;
  bool _isWorking = false;
  bool _shouldError = false;
  bool _emittedError = false;

  SyncSimulator({required this.controller, this.intervalMs = 5000});

  bool get isWorking => _isWorking;
  bool get shouldError => _shouldError;
  bool get canNodeEmit => _rootNode != null;

  /// Override this to implement back-pressure (e.g., waiting for an active download).
  bool get canNextGen => true;

  VoidCallback? onDataInjected;

  /// Returns the remaining seconds until the next data injection.
  double get remainingSeconds {
    if (!_isWorking || _nextEmitTime == null || !canNodeProceed) return 0;
    final diff = _nextEmitTime!.difference(DateTime.now()).inMilliseconds;
    return max(0, diff / 1000.0);
  }

  bool get canNodeProceed =>
      _rootNode != null &&
      !_rootNode!.isPaused &&
      !_rootNode!.isStopped &&
      !(_rootNode!.status == SyncStatus.none);

  /// Generates the next data object.
  /// If [isError] is true, it should return a payload that triggers a [SyncStatus.error].
  T generateNext({bool isError = false});

  void emitData() {
    final data = generateNext(isError: _shouldError);
    controller.add(data);
  }

  void _emitData() {
    if (controller.isClosed) return;
    _emittedError = _shouldError;
    emitData();
    _shouldError = false;
  }

  Future<void> start(SyncNode rootNode) async {
    if (_isWorking) return;
    _isWorking = true;
    _rootNode = rootNode;

    try {
      while (_isWorking) {
        int currentInterval = _emittedError ? intervalMs * 2 : intervalMs;
        _nextEmitTime = DateTime.now().add(Duration(milliseconds: currentInterval));

        // Responsive wait loop
        while (_isWorking) {
          final now = DateTime.now();

          if (!canNodeProceed) {
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

        if (_isWorking && canNodeProceed) {
          _emitData();
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
    _shouldError = false;
    _emittedError = false;
    _nextEmitTime = null;
    _rootNode = null;
  }

  /// Signals the simulator to emit an error payload on the next cycle.
  void triggerError() => _shouldError = true;
}
