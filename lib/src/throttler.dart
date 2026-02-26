/// A utility class to throttle updates based on value changes and time intervals.
///
/// Prevents performance bottlenecks by ensuring that [onUpdate] is triggered
/// only when a significant change occurs ([threshold]) OR a specific [interval]
/// has passed, while guaranteeing that the final [maxValue] is always delivered.
class Throttler<T> {
  /// The minimum progress change (typically 0.0 to 1.0) required to trigger an update.
  final double threshold;

  /// The minimum time interval required between consecutive updates.
  final Duration interval;

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
    this.interval = const Duration(milliseconds: 1000),
    this.precision = 1e-6,
    required this.onUpdate,
  });

  /// Creates a throttler optimized for approximately 60 FPS updates.
  factory Throttler.fps60({required void Function(double value, T? extra) onUpdate}) => Throttler(
        threshold: 0.005,
        interval: const Duration(milliseconds: 16),
        onUpdate: onUpdate,
      );

  /// Creates a throttler optimized for approximately 30 FPS updates.
  factory Throttler.fps30({required void Function(double value, T? extra) onUpdate}) => Throttler(
        threshold: 0.01,
        interval: const Duration(milliseconds: 33),
        onUpdate: onUpdate,
      );

  /// Evaluates the new [value] and determines whether to dispatch [onUpdate].
  ///
  /// It prioritizes the completion state (reaching [maxValue]) and applies
  /// threshold and time-based gating for intermediate progress.
  void update(double value, [T? extra]) {
    final now = DateTime.now();

    // 1. Completion Logic: Ensure the final value is emitted exactly once upon reaching [maxValue].
    if (value >= (maxValue - precision)) {
      if (_lastValue < (maxValue - precision)) {
        flush(extra);
      }
      return;
    }

    // 2. Delta Check: Skip if the change is below the threshold to conserve resources.
    final delta = (value - _lastValue).abs();
    if (delta < threshold) return;

    // 3. Time Gating: Check if the required [interval] has elapsed since the last update.
    final timeSinceLastUpdate = now.difference(_lastUpdateTime);
    if (timeSinceLastUpdate >= interval) {
      _lastValue = value;
      _lastUpdateTime = now;
      onUpdate(value, extra);
    }
  }

  /// Resets the throttler's internal state to its initial conditions.
  void reset() {
    _lastValue = -1.0;
    _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Immediately forces an update with the [maxValue] and synchronizes the internal state.
  void flush([T? extra]) {
    _lastValue = maxValue;
    _lastUpdateTime = DateTime.now();
    onUpdate(maxValue, extra);
  }
}
