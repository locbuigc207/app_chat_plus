
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkUtils {
  static final Connectivity _connectivity = Connectivity();

  
  static Future<bool> hasConnection() async {
    try {
      
      final connectivityResult = await _connectivity.checkConnectivity();

      if (connectivityResult.contains(ConnectivityResult.none)) {
        return false;
      }

      
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));

      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  
  static Future<T?> retryOperation<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        return await operation();
      } catch (e) {
        print('❌ Attempt ${i + 1} failed: $e');

        if (i == maxRetries - 1) {
          rethrow;
        }

        
        final delay = initialDelay * (1 << i);
        print('⏳ Retrying in ${delay.inSeconds}s...');
        await Future.delayed(delay);
      }
    }
    return null;
  }

  
  static Stream<bool> get connectivityStream {
    return _connectivity.onConnectivityChanged.asyncMap((_) async {
      return await hasConnection();
    });
  }
}
