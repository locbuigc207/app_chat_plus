import 'dart:async';
import 'dart:ui';

class Debouncer {
  final Duration duration;
  Timer? _timer;

  Debouncer({
    required int milliseconds,
  }) : duration = Duration(milliseconds: milliseconds);

  Debouncer.fromDuration(this.duration);

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void runImmediate(VoidCallback action) {
    if (_timer == null || !_timer!.isActive) {
      action();
    }
    _timer?.cancel();
    _timer = Timer(duration, () {});
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void flush(VoidCallback action) {
    if (_timer != null && _timer!.isActive) {
      _timer!.cancel();
      _timer = null;
      action();
    }
  }

  bool get isPending => _timer?.isActive ?? false;

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

class Throttler {
  final Duration duration;
  DateTime? _lastRun;
  Timer? _trailingTimer;

  Throttler({
    required int milliseconds,
    this.trailing = false,
  }) : duration = Duration(milliseconds: milliseconds);

  Throttler.fromDuration(this.duration, {this.trailing = false});

  final bool trailing;

  VoidCallback? _pendingAction;

  void run(VoidCallback action) {
    final now = DateTime.now();
    if (_lastRun == null || now.difference(_lastRun!) >= duration) {
      _lastRun = now;
      _trailingTimer?.cancel();
      action();
    } else if (trailing) {
      _pendingAction = action;
      _trailingTimer?.cancel();
      final remaining = duration - now.difference(_lastRun!);
      _trailingTimer = Timer(remaining, () {
        _lastRun = DateTime.now();
        _pendingAction?.call();
        _pendingAction = null;
      });
    }
  }

  void cancel() {
    _trailingTimer?.cancel();
    _trailingTimer = null;
    _pendingAction = null;
  }

  void reset() {
    _lastRun = null;
    cancel();
  }

  void dispose() {
    cancel();
  }
}

class RateLimiter {
  final int maxCalls;
  final Duration window;
  final _timestamps = <DateTime>[];

  RateLimiter({
    required this.maxCalls,
    required this.window,
  });

  bool tryAcquire() {
    final now = DateTime.now();
    _timestamps.removeWhere(
      (ts) => now.difference(ts) > window,
    );

    if (_timestamps.length < maxCalls) {
      _timestamps.add(now);
      return true;
    }
    return false;
  }

  Duration? get timeUntilAvailable {
    if (_timestamps.length < maxCalls) return null;
    final now = DateTime.now();
    _timestamps.sort();
    final oldest = _timestamps.first;
    final waitTime = window - now.difference(oldest);
    return waitTime.isNegative ? null : waitTime;
  }

  void reset() => _timestamps.clear();

  int get remainingCalls {
    final now = DateTime.now();
    _timestamps.removeWhere(
      (ts) => now.difference(ts) > window,
    );
    return maxCalls - _timestamps.length;
  }
}
