import 'dart:async';

import 'app_log.dart';

/// Notices when the UI thread stops running for longer than it should.
///
/// A frozen window looks identical to a crashed one from the outside. This
/// timer ticks on the same isolate as the UI, so a tick that arrives late is
/// proof that something blocked the thread, and for how long.
class UiStallWatchdog {
  final Duration interval;
  final Duration threshold;

  /// Injected so tests do not have to wait in real time.
  final DateTime Function() now;

  /// Called with the measured stall, defaults to writing a log entry.
  final void Function(Duration stall) onStall;

  Timer? _timer;
  DateTime? _lastTick;

  UiStallWatchdog({
    this.interval = const Duration(milliseconds: 500),
    this.threshold = const Duration(seconds: 2),
    DateTime Function()? now,
    void Function(Duration stall)? onStall,
  }) : now = now ?? DateTime.now,
       onStall = onStall ?? _logStall;

  static void _logStall(Duration stall) => AppLog.warn(
    'UI thread stalled for ${stall.inMilliseconds} ms',
    details: 'Anything that blocks the UI isolate shows up here: a large '
        'synchronous file read, unpacking an archive, or scanning a mod '
        'library on the main thread.',
  );

  void start() {
    stop();
    _lastTick = now();
    _timer = Timer.periodic(interval, (_) => tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _lastTick = null;
  }

  /// Exposed for tests: compares this tick against the previous one.
  void tick() {
    final previous = _lastTick;
    final current = now();
    _lastTick = current;

    if (previous == null) return;

    final late = current.difference(previous) - interval;
    if (late >= threshold) onStall(late);
  }
}
