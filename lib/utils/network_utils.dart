import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkType {
  wifi,
  mobile,
  ethernet,
  none,
  unknown,
}

class NetworkStatus {
  final bool isConnected;
  final NetworkType type;
  final bool isMetered;

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

class NetworkUtils {
  NetworkUtils._();

  static final Connectivity _connectivity = Connectivity();
  static final StreamController<NetworkStatus> _statusController =
      StreamController<NetworkStatus>.broadcast();

  static NetworkStatus _currentStatus = NetworkStatus.offline;
  static StreamSubscription? _subscription;

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

  static Future<bool> hasConnection({
    String testHost = 'google.com',
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (kIsWeb) return true;

    try {
      final results = await _connectivity.checkConnectivity();
      if (results.contains(ConnectivityResult.none)) return false;

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

  static Stream<NetworkStatus> get statusStream => _statusController.stream;

  static Stream<bool> get connectivityStream => statusStream.map((s) => s.isConnected).distinct();

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

        if (shouldRetry != null && !shouldRetry(e)) {
          rethrow;
        }

        if (attempt == maxRetries - 1) break;

        final baseDelay = initialDelay * (1 << attempt);
        final delay = baseDelay > maxDelay ? maxDelay : baseDelay;

        final jitter = Duration(
          milliseconds:
              (delay.inMilliseconds * 0.1 * (DateTime.now().millisecond % 10) / 10).round(),
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

  static Future<T?> executeWhenOnline<T>(
    Future<T> Function() operation, {
    Duration checkInterval = const Duration(seconds: 3),
    Duration maxWait = const Duration(seconds: 30),
  }) async {
    final hasConn = await hasConnection();
    if (hasConn) return operation();

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

  static Future<NetworkStatus> _buildStatus(List<ConnectivityResult> results) async {
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

    final isConnected = await hasConnection();

    return NetworkStatus(
      isConnected: isConnected,
      type: isConnected ? type : NetworkType.none,
      isMetered: isMetered,
    );
  }
}

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
