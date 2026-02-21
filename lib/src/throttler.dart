/// A utility class to throttle updates based on value changes and time intervals.
///
/// It prevents performance bottlenecks by ensuring that [onUpdate] is only
/// triggered when a significant change occurs ([threshold]) or
/// a specific [duration] has passed.
class Throttler<T> {
  /// The minimum progress change (0.0 to 1.0) required to trigger an update.
  final double threshold;

  /// The minimum time interval required between updates.
  final Duration duration;

  /// The maximum value (typically 1.0) representing task completion.
  final double maxValue;

  /// Tolerance for floating-point comparisons.
  final double precision;

  /// Callback triggered when throttle conditions are met.
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

  /// Factory for high-frequency updates (~60 FPS), ideal for smooth animations.
  factory Throttler.fps60({required void Function(double, T?) onUpdate}) =>
      Throttler(
        threshold: 0.005,
        duration: const Duration(milliseconds: 16),
        onUpdate: onUpdate,
      );

  /// Factory for standard updates (~30 FPS), good balance between performance and smoothness.
  factory Throttler.fps30({required void Function(double, T?) onUpdate}) =>
      Throttler(
        threshold: 0.01,
        duration: const Duration(milliseconds: 32),
        onUpdate: onUpdate,
      );

  /// Evaluates the new [value] and triggers [onUpdate] if conditions are met.
  void update(double value, [T? extra]) {
    final now = DateTime.now();

    // 1. Completion Logic
    // Ensures that reaching the [maxValue] always triggers an update once.
    final bool isCompleted = value >= (maxValue - precision);
    if (isCompleted) {
      if (_lastValue >= (maxValue - precision)) return;

      _lastValue = maxValue;
      _lastUpdateTime = now;
      onUpdate(maxValue, extra);
      return;
    }

    // 2. Threshold & Time-based Gating
    final delta = (value - _lastValue).abs();
    final timeSinceLastUpdate = now.difference(_lastUpdateTime);

    // Update only if BOTH threshold is crossed AND duration has passed.
    if (delta >= threshold && timeSinceLastUpdate >= duration) {
      _lastValue = value;
      _lastUpdateTime = now;
      onUpdate(value, extra);
    }
  }

  /// Resets the throttler state to its initial values.
  void reset() {
    _lastValue = -1.0;
    _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Immediately forces an update with the [maxValue].
  void flush([T? extra]) {
    final now = DateTime.now();
    _lastValue = maxValue;
    _lastUpdateTime = now;
    onUpdate(maxValue, extra);
  }
}
