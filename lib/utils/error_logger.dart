// lib/utils/error_logger.dart
import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart'; // Để dùng kIsWeb

class ErrorLogger {
  static final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Khởi tạo error logging
  static Future<void> initialize() async {
    // CHỈ CHẠY CRASHLYTICS NẾU LÀ MOBILE (Không chạy trên Web để tránh lỗi)
    if (!kIsWeb) {
      try {
        // Enable Crashlytics collection
        await _crashlytics.setCrashlyticsCollectionEnabled(true);

        // Pass Flutter errors to Crashlytics
        FlutterError.onError = (FlutterErrorDetails errorDetails) {
          _crashlytics.recordFlutterFatalError(errorDetails);
        };

        // Catch async errors
        PlatformDispatcher.instance.onError = (error, stack) {
          _crashlytics.recordError(error, stack, fatal: true);
          return true;
        };
      } catch (e) {
        print(
            '⚠️ Failed to initialize Crashlytics (Expected on some platforms): $e');
      }
    }

    print('✅ Error logging initialized');
  }

  /// Log error với context
  static Future<void> logError(
    dynamic error,
    StackTrace? stackTrace, {
    String? context,
    Map<String, dynamic>? additionalInfo,
  }) async {
    // Log to console (Chạy trên mọi nền tảng)
    print('❌ Error in $context: $error');
    if (stackTrace != null) {
      print('Stack trace: $stackTrace');
    }

    // CHỈ LƯU LÊN FIREBASE CRASHLYTICS NẾU LÀ MOBILE
    if (!kIsWeb) {
      try {
        // Set custom keys
        if (context != null) {
          await _crashlytics.setCustomKey('error_context', context);
        }

        if (additionalInfo != null) {
          for (var entry in additionalInfo.entries) {
            await _crashlytics.setCustomKey(entry.key, entry.value.toString());
          }
        }

        // Log to Firebase Crashlytics
        await _crashlytics.recordError(
          error,
          stackTrace,
          reason: context,
          fatal: false,
        );
      } catch (e) {
        print('⚠️ Failed to log error to Crashlytics: $e');
      }
    }
  }

  /// Log event cho analytics (Analytics hỗ trợ cả Web)
  static Future<void> logEvent(
    String name,
    Map<String, dynamic>? params,
  ) async {
    try {
      // Convert to Map<String, Object>?
      final Map<String, Object>? convertedParams = params?.map(
        (key, value) => MapEntry(key, value as Object),
      );

      await _analytics.logEvent(
        name: name,
        parameters: convertedParams,
      );
      print('📊 Event logged: $name');
    } catch (e) {
      print('❌ Failed to log event: $e');
    }
  }

  /// Log screen view
  static Future<void> logScreenView(String screenName) async {
    print('📱 Screen View: $screenName'); // In ra console cho dễ debug
    await logEvent('screen_view', {
      'screen_name': screenName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Set user properties
  static Future<void> setUserId(String userId) async {
    try {
      if (!kIsWeb) {
        await _crashlytics.setUserIdentifier(userId);
      }
      await _analytics.setUserId(id: userId);
    } catch (e) {
      print('⚠️ Failed to set user ID: $e');
    }
  }

  /// Log message operations
  static Future<void> logMessageSent({
    required String conversationId,
    required int messageType,
  }) async {
    await logEvent('message_sent', {
      'conversation_id': conversationId,
      'message_type': messageType,
    });
  }

  static Future<void> logMessageRead({
    required String conversationId,
  }) async {
    await logEvent('message_read', {
      'conversation_id': conversationId,
    });
  }
}
