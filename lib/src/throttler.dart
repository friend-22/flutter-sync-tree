/// A utility class to throttle updates based on value changes and time intervals.
///
/// Prevents performance bottlenecks by ensuring that [onUpdate] is triggered
/// only when a significant change occurs ([threshold]) OR a specific [duration]
/// has passed, while always ensuring the final [maxValue] is delivered.
class Throttler<T> {
  /// The minimum progress change (typically 0.0 to 1.0) required to trigger an update.
  final double threshold;

  /// The minimum time interval required between updates.
  final Duration duration;

  /// The target value (e.g., 1.0) representing task completion.
  final double maxValue;

  /// Tolerance for floating-point comparisons to handle precision issues.
  final double precision;

  /// Callback function triggered when the throttle conditions are met.
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

  /// Creates a throttler optimized for ~60 FPS updates.
  factory Throttler.fps60({required void Function(double, T?) onUpdate}) => Throttler(
        threshold: 0.005,
        duration: const Duration(milliseconds: 16),
        onUpdate: onUpdate,
      );

  /// Creates a throttler optimized for ~30 FPS updates.
  factory Throttler.fps30({required void Function(double, T?) onUpdate}) => Throttler(
        threshold: 0.01,
        duration: const Duration(milliseconds: 32),
        onUpdate: onUpdate,
      );

  /// Evaluates the new [value] and determines whether to trigger [onUpdate].
  ///
  /// It prioritizes the completion state (reaching [maxValue]) and then applies
  /// threshold and time-based gating for intermediate values.
  void update(double value, [T? extra]) {
    final now = DateTime.now();

    // 1. Completion Logic: Always ensure the final value is emitted exactly once.
    if (value >= (maxValue - precision)) {
      if (_lastValue < (maxValue - precision)) {
        flush(extra);
      }
      return;
    }

    // 2. Early Exit: Skip if the change is below the threshold to save resources.
    final delta = (value - _lastValue).abs();
    if (delta < threshold) return;

    // 3. Time Gating: Check if enough time has passed since the last update.
    final timeSinceLastUpdate = now.difference(_lastUpdateTime);
    if (timeSinceLastUpdate >= duration) {
      _lastValue = value;
      _lastUpdateTime = now;
      onUpdate(value, extra);
    }
  }

  /// Resets the internal state of the throttler.
  void reset() {
    _lastValue = -1.0;
    _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Immediately forces an update with the [maxValue] and updates the internal state.
  void flush([T? extra]) {
    _lastValue = maxValue;
    _lastUpdateTime = DateTime.now();
    onUpdate(maxValue, extra);
  }
}
