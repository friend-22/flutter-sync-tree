/// A utility class to throttle updates based on value changes and time intervals.
///
/// Prevents performance bottlenecks by ensuring that [onUpdate] is triggered
/// only when meaningful progress occurs, while guaranteeing that the final
/// [maxValue] (e.g., 100% completion) is always delivered exactly once.
///
/// An update is dispatched only when **all** of the following conditions are met:
/// 1. The delta between the new value and the last emitted value exceeds [threshold].
/// 2. At least [interval] has elapsed since the last update.
///
/// Reaching [maxValue] bypasses these conditions and always triggers [flush].
///
/// ### How it works
/// ```
/// update(0.05) → delta=1.05 ✅, interval elapsed ✅ → emit 0.05
/// update(0.06) → delta=0.01 ❌ (below threshold)   → skip
/// update(0.20) → delta=0.15 ✅, interval elapsed ✅ → emit 0.20
/// update(1.00) → maxValue reached                  → flush (always emits)
/// ```
///
/// ### Example
/// ```dart
/// final throttler = Throttler<String>(
///   threshold: 0.01,
///   interval: Duration(milliseconds: 100),
///   onUpdate: (value, label) {
///     print('[$label] Progress: ${(value * 100).toStringAsFixed(1)}%');
///   },
/// );
///
/// throttler.update(0.25, 'taskA'); // emits if conditions met
/// throttler.update(0.26, 'taskA'); // likely skipped (delta too small)
/// throttler.flush('taskA');        // forces emit at 1.0 (completion)
/// throttler.reset();               // clears state for next session
/// ```
///
/// The generic type [T] represents optional metadata passed alongside the
/// progress value (e.g., the originating node or a task label).
class Throttler<T> {
  /// The minimum progress change required to trigger an update.
  ///
  /// Expressed as an absolute delta on the same scale as the tracked value
  /// (typically 0.0 to 1.0 for normalized progress).
  ///
  /// For example, a value of `0.01` means at least 1% progress must occur
  /// since the last emission before a new update is dispatched.
  /// Smaller values produce smoother updates at the cost of higher frequency.
  final double threshold;

  /// The minimum time interval required between consecutive updates.
  ///
  /// Acts as a hard rate limiter — even if [threshold] is exceeded,
  /// no update is emitted until this duration has elapsed since the last one.
  ///
  /// Defaults to 1,000ms. Use [Throttler.fps60] or [Throttler.fps30]
  /// for display-optimized presets.
  final Duration interval;

  /// The value representing full completion (e.g., `1.0` for 100%).
  ///
  /// When [update] receives a value at or above `maxValue - precision`,
  /// [flush] is called immediately to guarantee the final state is emitted,
  /// bypassing the normal [threshold] and [interval] checks.
  final double maxValue;

  /// Tolerance used for floating-point comparisons.
  ///
  /// Values within this range of [maxValue] are treated as "complete",
  /// and values within this range of [_lastValue] are considered unchanged.
  /// Prevents spurious emissions caused by floating-point rounding errors.
  /// Defaults to `1e-6`.
  final double precision;

  /// Callback invoked when throttle conditions are satisfied.
  ///
  /// Receives the current [value] and an optional [extra] metadata object
  /// of type [T]. This is where UI updates, logging, or state notifications
  /// should be performed.
  final void Function(double value, T? extra) onUpdate;

  /// The most recently emitted progress value.
  ///
  /// Initialized to `-1.0` so that the very first [update] call always
  /// passes the delta check regardless of the starting value.
  double _lastValue = -1.0;

  /// The timestamp of the most recent emission.
  ///
  /// Initialized to the Unix epoch so that the very first [update] call
  /// always passes the time gate check.
  DateTime _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);

  Throttler({
    this.threshold = 0.01,
    this.maxValue = 1.0,
    this.interval = const Duration(milliseconds: 1000),
    this.precision = 1e-6,
    required this.onUpdate,
  });

  /// Creates a throttler optimized for approximately 60 FPS updates.
  ///
  /// Uses a 16ms interval (~1000ms / 60) and a 0.5% threshold,
  /// suitable for smooth progress animations in high-performance UIs.
  factory Throttler.fps60({required void Function(double value, T? extra) onUpdate}) => Throttler(
        threshold: 0.005,
        interval: const Duration(milliseconds: 16),
        onUpdate: onUpdate,
      );

  /// Creates a throttler optimized for approximately 30 FPS updates.
  ///
  /// Uses a 33ms interval (~1000ms / 30) and a 1% threshold,
  /// suitable for standard animations or less performance-critical UIs.
  factory Throttler.fps30({required void Function(double value, T? extra) onUpdate}) => Throttler(
        threshold: 0.01,
        interval: const Duration(milliseconds: 33),
        onUpdate: onUpdate,
      );

  /// Evaluates [value] and dispatches [onUpdate] if throttle conditions are met.
  ///
  /// Evaluation is performed in three stages:
  ///
  /// 1. **Completion check**: If [value] is within [precision] of [maxValue],
  ///    [flush] is called to guarantee the final emission, then returns immediately.
  ///    This prevents [maxValue] from being silently skipped by the delta/interval gates.
  ///
  /// 2. **Delta check**: If the absolute difference between [value] and [_lastValue]
  ///    is less than [threshold], the update is suppressed to avoid noise.
  ///
  /// 3. **Time gate**: If less than [interval] has elapsed since the last emission,
  ///    the update is deferred even if the delta is sufficient.
  ///
  /// [extra] is forwarded as-is to [onUpdate] when an emission occurs.
  void update(double value, [T? extra]) {
    final now = DateTime.now();

    // Stage 1 — Completion: bypass all gates and flush exactly once at maxValue.
    // This guarantees the 100% completion signal is never dropped.
    if (value >= (maxValue - precision)) {
      if (_lastValue < (maxValue - precision)) {
        flush(extra);
      }
      return;
    }

    // Stage 2 — Delta: suppress updates where progress change is negligible.
    final delta = (value - _lastValue).abs();
    if (delta < threshold || (delta - threshold).abs() < precision) {
      return;
    }

    // Stage 3 — Time gate: enforce the minimum interval between emissions.
    final timeSinceLastUpdate = now.difference(_lastUpdateTime);
    if (timeSinceLastUpdate >= interval) {
      _lastValue = value;
      _lastUpdateTime = now;
      onUpdate(value, extra);
    }
  }

  /// Resets the throttler's internal state to its initial conditions.
  ///
  /// Should be called at the start of each new sync session to ensure
  /// stale state from a previous run does not affect the new cycle.
  /// Restores [_lastValue] to `-1.0` and [_lastUpdateTime] to the Unix epoch,
  /// which guarantees the next [update] call passes all gate checks.
  void reset() {
    _lastValue = -1.0;
    _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Forces an immediate emission with [maxValue], bypassing all throttle conditions.
  ///
  /// Includes an idempotency check — if [_lastValue] is already within [precision]
  /// of [maxValue], the call is a no-op to prevent duplicate emissions.
  /// This is safe to call multiple times at the end of a sync cycle.
  ///
  /// Typically called in two scenarios:
  /// - At task completion to guarantee the final 1.0 (100%) is always emitted.
  /// - When a parent [SyncComposite] needs to force-flush before notifying its own listeners.
  void flush([T? extra]) {
    // Idempotency guard: skip if already at maxValue to avoid redundant UI rebuilds.
    if ((maxValue - _lastValue).abs() < precision) return;

    _lastValue = maxValue;
    _lastUpdateTime = DateTime.now();
    onUpdate(maxValue, extra);
  }
}
