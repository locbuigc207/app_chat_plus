import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Loại kết nối mạng
enum NetworkType {
  wifi,
  mobile,
  ethernet,
  none,
  unknown,
}

/// Trạng thái mạng
class NetworkStatus {
  final bool isConnected;
  final NetworkType type;
  final bool isMetered; // Kết nối tính phí (mobile data)

  const NetworkStatus({
    required this.isConnected,
    required this.type,
    this.isMetered = false,
  });

  static const offline = NetworkStatus(
    isConnected: false,
    type: NetworkType.none,
  );

  bool get isWifi => type == NetworkType.wifi;
  bool get isMobile => type == NetworkType.mobile;

  @override
  String toString() => 'NetworkStatus(connected: $isConnected, type: $type)';
}

/// Công cụ kiểm tra và quản lý kết nối mạng
class NetworkUtils {
  NetworkUtils._();

  static final Connectivity _connectivity = Connectivity();
  static final StreamController<NetworkStatus> _statusController =
      StreamController<NetworkStatus>.broadcast();

  static NetworkStatus _currentStatus = NetworkStatus.offline;
  static StreamSubscription? _subscription;

  // ─── Khởi tạo ──────────────────────────────────────────────────────────────

  /// Bắt đầu lắng nghe thay đổi kết nối
  static void startMonitoring() {
    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen(
      (results) async {
        final status = await _buildStatus(results);
        _currentStatus = status;
        _statusController.add(status);
      },
    );
  }

  static void stopMonitoring() {
    _subscription?.cancel();
    _subscription = null;
  }

  // ─── Kiểm tra kết nối ──────────────────────────────────────────────────────

  /// Kiểm tra có kết nối Internet thực sự không (DNS lookup)
  static Future<bool> hasConnection({
    String testHost = 'google.com',
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // Web platform không cần check (always connected in browser)
    if (kIsWeb) return true;

    try {
      final results = await _connectivity.checkConnectivity();
      if (results.contains(ConnectivityResult.none)) return false;

      // Verify thực sự có internet (không chỉ connected to wifi)
      final lookup = await InternetAddress.lookup(testHost).timeout(timeout);
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Lấy trạng thái hiện tại
  static Future<NetworkStatus> getStatus() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _currentStatus = await _buildStatus(results);
      return _currentStatus;
    } catch (_) {
      return NetworkStatus.offline;
    }
  }

  static NetworkStatus get currentStatus => _currentStatus;

  /// Stream theo dõi thay đổi trạng thái mạng
  static Stream<NetworkStatus> get statusStream => _statusController.stream;

  /// Stream bool đơn giản (true = online, false = offline)
  static Stream<bool> get connectivityStream =>
      statusStream.map((s) => s.isConnected).distinct();

  // ─── Retry Logic ────────────────────────────────────────────────────────────

  /// Retry với exponential backoff
  /// [operation]: Function trả về Future
  /// [maxRetries]: Số lần thử tối đa
  /// [initialDelay]: Độ trễ ban đầu
  /// [shouldRetry]: Kiểm tra có nên retry lỗi này không
  static Future<T> retryOperation<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
    Duration maxDelay = const Duration(seconds: 30),
    bool Function(dynamic error)? shouldRetry,
    void Function(int attempt, dynamic error)? onRetry,
  }) async {
    dynamic lastError;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await operation();
      } catch (e) {
        lastError = e;

        // Kiểm tra có nên retry không
        if (shouldRetry != null && !shouldRetry(e)) {
          rethrow;
        }

        if (attempt == maxRetries - 1) break;

        // Exponential backoff với jitter
        final baseDelay = initialDelay * (1 << attempt);
        final delay = baseDelay > maxDelay ? maxDelay : baseDelay;
        // Thêm jitter ngẫu nhiên ±10%
        final jitter = Duration(
          milliseconds: (delay.inMilliseconds *
                  0.1 *
                  (DateTime.now().millisecond % 10) /
                  10)
              .round(),
        );

        debugPrint(
          '🔄 Retry ${attempt + 1}/$maxRetries after ${delay.inMilliseconds}ms: $e',
        );

        onRetry?.call(attempt + 1, e);
        await Future.delayed(delay + jitter);
      }
    }

    throw lastError;
  }

  /// Thực hiện operation khi có kết nối, queue nếu offline
  static Future<T?> executeWhenOnline<T>(
    Future<T> Function() operation, {
    Duration checkInterval = const Duration(seconds: 3),
    Duration maxWait = const Duration(seconds: 30),
  }) async {
    final hasConn = await hasConnection();
    if (hasConn) return operation();

    // Chờ kết nối
    final completer = Completer<T?>();
    Timer? timeout;
    StreamSubscription? sub;

    timeout = Timer(maxWait, () {
      sub?.cancel();
      if (!completer.isCompleted) completer.complete(null);
    });

    sub = connectivityStream.where((c) => c).listen((_) async {
      timeout?.cancel();
      sub?.cancel();
      try {
        final result = await operation();
        if (!completer.isCompleted) completer.complete(result);
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    });

    return completer.future;
  }

  // ─── Tốc độ / Chất lượng ───────────────────────────────────────────────────

  /// Ước tính chất lượng kết nối bằng cách đo RTT
  static Future<Duration?> measureLatency({
    String host = 'google.com',
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (kIsWeb) return null;
    try {
      final start = DateTime.now();
      await InternetAddress.lookup(host).timeout(timeout);
      return DateTime.now().difference(start);
    } catch (_) {
      return null;
    }
  }

  // ─── Private helpers ────────────────────────────────────────────────────────

  static Future<NetworkStatus> _buildStatus(
      List<ConnectivityResult> results) async {
    if (results.contains(ConnectivityResult.none)) {
      return NetworkStatus.offline;
    }

    NetworkType type = NetworkType.unknown;
    bool isMetered = false;

    if (results.contains(ConnectivityResult.wifi)) {
      type = NetworkType.wifi;
    } else if (results.contains(ConnectivityResult.mobile)) {
      type = NetworkType.mobile;
      isMetered = true;
    } else if (results.contains(ConnectivityResult.ethernet)) {
      type = NetworkType.ethernet;
    }

    // Kiểm tra thực tế có internet không
    final isConnected = await hasConnection();

    return NetworkStatus(
      isConnected: isConnected,
      type: isConnected ? type : NetworkType.none,
      isMetered: isMetered,
    );
  }
}

/// Extension tiện ích cho Future với timeout an toàn
extension SafeTimeout<T> on Future<T> {
  Future<T?> withTimeout(
    Duration duration, {
    T? fallback,
  }) async {
    try {
      return await timeout(duration);
    } on TimeoutException {
      return fallback;
    } catch (_) {
      return fallback;
    }
  }
}
