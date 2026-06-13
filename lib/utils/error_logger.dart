import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class ErrorLogger {
  ErrorLogger._();

  static FirebaseCrashlytics get _crashlytics => FirebaseCrashlytics.instance;
  static FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    if (!kIsWeb) {
      try {
        await _crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

        FlutterError.onError = (FlutterErrorDetails details) {
          if (kDebugMode) {
            FlutterError.presentError(details);
          }
          _crashlytics.recordFlutterFatalError(details);
        };

        PlatformDispatcher.instance.onError = (error, stack) {
          _crashlytics.recordError(error, stack, fatal: true);
          return true;
        };

        debugPrint('✅ Crashlytics initialized (collection: ${!kDebugMode})');
      } catch (e) {
        debugPrint('⚠️ Crashlytics init failed: $e');
      }
    }

    _initialized = true;
    debugPrint('✅ ErrorLogger initialized');
  }

  static Future<void> logError(
    dynamic error,
    StackTrace? stackTrace, {
    String? context,
    Map<String, dynamic>? additionalInfo,
    bool fatal = false,
  }) async {
    if (kDebugMode) {
      debugPrint('❌ [${context ?? "Unknown"}] $error');
      if (stackTrace != null) debugPrint('$stackTrace');
    }

    if (kIsWeb) return;

    try {
      if (context != null) {
        await _crashlytics.setCustomKey('error_context', context);
      }
      await _crashlytics.setCustomKey(
          'timestamp', DateTime.now().toIso8601String());

      if (additionalInfo != null) {
        for (final entry in additionalInfo.entries) {
          final value = entry.value;

          if (value is String ||
              value is int ||
              value is double ||
              value is bool) {
            await _crashlytics.setCustomKey(entry.key, value);
          } else {
            await _crashlytics.setCustomKey(entry.key, value.toString());
          }
        }
      }

      await _crashlytics.recordError(
        error,
        stackTrace,
        reason: context,
        fatal: fatal,
        printDetails: kDebugMode,
      );
    } catch (e) {
      debugPrint('⚠️ Failed to log to Crashlytics: $e');
    }
  }

  static Future<void> logFatalError(
    dynamic error,
    StackTrace? stackTrace, {
    String? context,
  }) =>
      logError(error, stackTrace, context: context, fatal: true);

  static Future<T?> guardAsync<T>(
    Future<T> Function() action, {
    String? context,
    T? fallback,
  }) async {
    try {
      return await action();
    } catch (e, stack) {
      await logError(e, stack, context: context);
      return fallback;
    }
  }

  static Future<void> logEvent(
    String name,
    Map<String, dynamic>? params,
  ) async {
    try {
      final sanitizedName = _sanitizeEventName(name);

      final Map<String, Object>? converted = params?.map(
        (key, value) {
          final sanitizedKey = _sanitizeParamKey(key);
          return MapEntry(sanitizedKey, value as Object);
        },
      );

      await _analytics.logEvent(
        name: sanitizedName,
        parameters: converted,
      );

      if (kDebugMode) debugPrint('📊 Event: $sanitizedName | $params');
    } catch (e) {
      debugPrint('⚠️ Failed to log event "$name": $e');
    }
  }

  static Future<void> logScreenView(String screenName) async {
    if (kDebugMode) debugPrint('📱 Screen: $screenName');
    try {
      await _analytics.logScreenView(screenName: screenName);
    } catch (e) {
      debugPrint('⚠️ Failed to log screen view: $e');
    }
  }

  static Future<void> setUserId(String userId) async {
    try {
      if (!kIsWeb) await _crashlytics.setUserIdentifier(userId);
      await _analytics.setUserId(id: userId);
    } catch (e) {
      debugPrint('⚠️ Failed to set userId: $e');
    }
  }

  static Future<void> setUserProperty(String name, String value) async {
    try {
      await _analytics.setUserProperty(name: name, value: value);
    } catch (e) {
      debugPrint('⚠️ Failed to set user property: $e');
    }
  }

  static Future<void> clearUserId() async {
    try {
      if (!kIsWeb) await _crashlytics.setUserIdentifier('');
      await _analytics.setUserId(id: null);
    } catch (e) {
      debugPrint('⚠️ Failed to clear userId: $e');
    }
  }

  static Future<void> logMessageSent({
    required String conversationId,
    required int messageType,
    int? characterCount,
    bool hasReply = false,
    bool hasMention = false,
  }) async {
    await logEvent('message_sent', {
      'conversation_id': conversationId,
      'message_type': messageType,
      if (characterCount != null) 'char_count': characterCount,
      'has_reply': hasReply ? 1 : 0,
      'has_mention': hasMention ? 1 : 0,
    });
  }

  static Future<void> logMessageRead({
    required String conversationId,
    int? unreadCount,
  }) async {
    await logEvent('message_read', {
      'conversation_id': conversationId,
      if (unreadCount != null) 'unread_count': unreadCount,
    });
  }

  static Future<void> logCallStarted({
    required String conversationId,
    required bool isVideo,
    required bool isGroup,
  }) async {
    await logEvent('call_started', {
      'conversation_id': conversationId,
      'is_video': isVideo,
      'is_group': isGroup,
    });
  }

  static Future<void> logCallEnded({
    required String conversationId,
    required int durationSeconds,
    required bool wasConnected,
  }) async {
    await logEvent('call_ended', {
      'conversation_id': conversationId,
      'duration_seconds': durationSeconds,
      'was_connected': wasConnected,
    });
  }

  static Future<void> logReactionAdded({
    required String conversationId,
    required String emoji,
  }) async {
    await logEvent('reaction_added', {
      'conversation_id': conversationId,
      'emoji': emoji,
    });
  }

  static Future<void> logMediaViewed({
    required String type,
    required String source,
  }) async {
    await logEvent('media_viewed', {'type': type, 'source': source});
  }

  static Future<void> logSearchUsed({
    required String searchType,
    int? resultCount,
  }) async {
    await logEvent('search_used', {
      'search_type': searchType,
      if (resultCount != null) 'result_count': resultCount,
    });
  }

  static Future<void> addBreadcrumb(String message, {String? category}) async {
    if (kDebugMode) debugPrint('🍞 [${category ?? "app"}] $message');
    if (kIsWeb) return;
    try {
      await _crashlytics
          .log('${category != null ? "[$category] " : ""}$message');
    } catch (_) {}
  }

  static String _sanitizeEventName(String name) {
    return name
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
        .substring(0, name.length.clamp(0, 40));
  }

  static String _sanitizeParamKey(String key) {
    return key
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
        .substring(0, key.length.clamp(0, 40));
  }
}
