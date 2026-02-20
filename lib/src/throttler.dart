/// A utility class to throttle updates based on value changes and time intervals.
///
/// It ensures that [onUpdate] is only called if a significant change has occurred
/// ([threshold]) and a minimum amount of time has passed ([duration]).
class Throttler<T> {
  /// The minimum change in value required to trigger an update.
  final double threshold;

  /// The minimum time interval required between updates.
  final Duration duration;

  /// The maximum possible value (e.g., 1.0 for progress or volume).
  final double maxValue;

  /// Used to handle floating-point rounding errors when checking for completion.
  final double precision;

  /// The callback triggered when the throttle conditions are met.
  final void Function(double value, T? extra) onUpdate;

  double _lastValue = -1.0;
  DateTime _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);

  Throttler({
    this.threshold = 0.01,
    this.maxValue = 1.0,
    this.duration = const Duration(milliseconds: 1000),
    this.precision = 1e-6,
    required this.onUpdate,
  });

  /// Preset for high-frequency updates (approx. 60 frames per second).
  Throttler.fps60({
    this.threshold = 0.01,
    this.maxValue = 1.0,
    this.duration = const Duration(milliseconds: 16),
    this.precision = 1e-6,
    required this.onUpdate,
  });

  /// Preset for medium-frequency updates (approx. 30 frames per second).
  Throttler.fps30({
    this.threshold = 0.01,
    this.maxValue = 1.0,
    this.duration = const Duration(milliseconds: 32),
    this.precision = 1e-6,
    required this.onUpdate,
  });

  /// Evaluates the new [value] and triggers [onUpdate] if logic allows.
  void update(double value, [T? extra]) {
    final now = DateTime.now();

    // 1. Forced Completion Check
    // If value reaches maxValue, we always update once and then stop.
    final bool isCompleted = value >= (maxValue - precision);
    if (isCompleted) {
      if (_lastValue >= maxValue) return; // Already reported completion

      _lastValue = maxValue;
      _lastUpdateTime = now;
      onUpdate(maxValue, extra);
      return;
    }

    // 2. Threshold & Time Gating
    final delta = (value - _lastValue).abs();
    final timeDelta = now.difference(_lastUpdateTime);

    // Only update if the value has changed enough AND enough time has passed.
    if (delta >= threshold && timeDelta >= duration) {
      _lastValue = value;
      _lastUpdateTime = now;
      onUpdate(value, extra);
    }
  }

  /// Resets the throttler state, allowing the next update to pass immediately.
  void reset() {
    _lastValue = -1.0;
    _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Manually forces an update to the [maxValue] regardless of conditions.
  void flush([T? extra]) {
    _lastValue = maxValue;
    _lastUpdateTime = DateTime.now();
    onUpdate(maxValue, extra);
  }
}
