import 'dart:async';
import 'dart:ui';

/// Debouncer mạnh mẽ: trì hoãn thực thi action cho đến khi ngừng gọi
/// Dùng cho: tìm kiếm, auto-save, resize, scroll handler...
class Debouncer {
  final Duration duration;
  Timer? _timer;

  Debouncer({
    required int milliseconds,
  }) : duration = Duration(milliseconds: milliseconds);

  Debouncer.fromDuration(this.duration);

  /// Hủy timer hiện tại và đặt lại
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// Chạy ngay lập tức, sau đó debounce các lần gọi tiếp theo
  void runImmediate(VoidCallback action) {
    if (_timer == null || !_timer!.isActive) {
      action();
    }
    _timer?.cancel();
    _timer = Timer(duration, () {});
  }

  /// Hủy timer đang chờ (không thực thi action)
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Flush: thực thi ngay action đang pending nếu có, hủy timer
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

/// Throttler: đảm bảo action chỉ chạy tối đa 1 lần trong khoảng thời gian
/// Khác với Debouncer: chạy action NGAY lập tức rồi chặn các lần tiếp theo
/// Dùng cho: nút bấm chống double-tap, scroll events, network polling...
class Throttler {
  final Duration duration;
  DateTime? _lastRun;
  Timer? _trailingTimer;

  Throttler({
    required int milliseconds,
    this.trailing = false,
  }) : duration = Duration(milliseconds: milliseconds);

  Throttler.fromDuration(this.duration, {this.trailing = false});

  /// Khi [trailing] = true, lần gọi cuối trong window sẽ được thực thi sau delay
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

/// RateLimiter: giới hạn số lần gọi trong một khoảng thời gian nhất định
/// Dùng cho: API calls, message sending rate limit...
class RateLimiter {
  final int maxCalls;
  final Duration window;
  final _timestamps = <DateTime>[];

  RateLimiter({
    required this.maxCalls,
    required this.window,
  });

  /// Trả về true nếu còn trong giới hạn rate, false nếu đã vượt
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

  /// Thời gian còn lại đến khi có thể gọi tiếp (null nếu đang available)
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
