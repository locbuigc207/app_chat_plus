
import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart'; 

class ErrorLogger {
  static final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  
  static Future<void> initialize() async {
    
    if (!kIsWeb) {
      try {
        
        await _crashlytics.setCrashlyticsCollectionEnabled(true);

        
        FlutterError.onError = (FlutterErrorDetails errorDetails) {
          _crashlytics.recordFlutterFatalError(errorDetails);
        };

        
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

  
  static Future<void> logError(
    dynamic error,
    StackTrace? stackTrace, {
    String? context,
    Map<String, dynamic>? additionalInfo,
  }) async {
    
    print('❌ Error in $context: $error');
    if (stackTrace != null) {
      print('Stack trace: $stackTrace');
    }

    
    if (!kIsWeb) {
      try {
        
        if (context != null) {
          await _crashlytics.setCustomKey('error_context', context);
        }

        if (additionalInfo != null) {
          for (var entry in additionalInfo.entries) {
            await _crashlytics.setCustomKey(entry.key, entry.value.toString());
          }
        }

        
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

  
  static Future<void> logEvent(
    String name,
    Map<String, dynamic>? params,
  ) async {
    try {
      
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

  
  static Future<void> logScreenView(String screenName) async {
    print('📱 Screen View: $screenName'); 
    await logEvent('screen_view', {
      'screen_name': screenName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  
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
