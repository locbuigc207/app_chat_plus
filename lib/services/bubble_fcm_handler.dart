// lib/services/bubble_fcm_handler.dart
//
// Wires Firebase Cloud Messaging → Event Stream
// [SỬA LỖI P0]: Đã dọn dẹp các side-effect dư thừa (tự tạo bubble từ Dart)
// Vì trách nhiệm sinh Bubble giờ đây do Native Android (FcmService.kt + BubbleNotificationManager.kt) đảm nhận 100%
// để tương thích API 30+.

import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/services/services.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BUBBLE FCM HANDLER
// ═══════════════════════════════════════════════════════════════════════════

class BubbleFcmHandler {
  BubbleFcmHandler._();

  static final _seen = <String>{}; // dedup message IDs
  static const _maxSeen = 200;

  static final StreamController<RemoteMessage> _messageCtrl =
      StreamController<RemoteMessage>.broadcast();

  // SỬA LỖI: Thêm guard chặn đăng ký nhiều listener trùng lặp
  static bool _initialized = false;

  /// Stream of every FCM message handled (for UI / analytics).
  static Stream<RemoteMessage> get messageStream => _messageCtrl.stream;

  // ─── Initialise ─────────────────────────────────────────────────────────

  /// Call once from main() after Firebase.initializeApp().
  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid) return;

    // Đảm bảo chỉ khởi tạo listener ĐÚNG 1 LẦN
    if (_initialized) return;
    _initialized = true;

    // [FIX 25]: ĐÃ XÓA dòng FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
    // Firebase Cloud Messaging chỉ cho phép MỘT background handler duy nhất.
    // Handler đó đã được đặt chuẩn xác tại main.dart để gánh chung routing cho Group Call.
    // main.dart sẽ chủ động gọi BubbleFcmHandler.processMessage(..., fromBackground: true).

    // Request notification permission
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('🔔 FCM permission: ${settings.authorizationStatus.name}');

    // Foreground messages
    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint('🔔 [Foreground FCM] ${msg.messageId}');
      BubbleFcmHandler.processMessage(msg, fromBackground: false);
    });

    // App opened from notification tap
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      debugPrint('🔔 [FCM tap] ${msg.messageId}');
      BubbleFcmHandler.processMessage(
        msg,
        fromBackground: false,
        userTapped: true,
      );
    });

    // Check for initial message (app launched from terminated state via notif)
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      debugPrint('🔔 [FCM initial] ${initial.messageId}');
      BubbleFcmHandler.processMessage(
        initial,
        fromBackground: false,
        userTapped: true,
      );
    }

    debugPrint('✅ BubbleFcmHandler initialized');
  }

  // ─── Core message processor ─────────────────────────────────────────────

  static Future<void> processMessage(
    RemoteMessage msg, {
    bool fromBackground = false,
    bool userTapped = false,
  }) async {
    // Deduplication
    final msgId = msg.messageId ?? '';
    if (msgId.isNotEmpty) {
      if (_seen.contains(msgId)) return;
      _seen.add(msgId);
      if (_seen.length > _maxSeen) _seen.remove(_seen.first);
    }

    final data = msg.data;

    // ── Extract fields ───────────────────────────────────────────────────
    final userId = data['senderId'] ?? data['userId'] ?? '';
    final userName = data['senderName'] ?? data['userName'] ?? 'Unknown';
    final message =
        data['message'] ?? data['body'] ?? msg.notification?.body ?? '';
    final convId = data['conversationId'] ?? userId;

    if (userId.isEmpty) {
      debugPrint('⚠️ BubbleFcmHandler: no userId in payload');
      return;
    }

    // ── Contextual mode detection ─────────────────────────────────────────
    ContextualBubbleService.instance.updateContext(
      conversationId: convId,
      message: message,
    );

    // [SỬA LỖI P0]: Xóa logic tự tạo bubble bằng _svc.showChatBubble() hay _svc.updateBubbleMessage()
    // Tránh việc UI Dart giành việc với Native (FcmService.kt đã gọi BubbleNotificationManager
    // ngay khi tin nhắn đến, dù là Foreground hay Background).

    _messageCtrl.add(msg);

    debugPrint(
      '✅ FCM processed Event Stream: $userName '
      '(bg=$fromBackground, tap=$userTapped)',
    );
  }

  static void dispose() {
    _messageCtrl.close();
    _seen.clear();
    _initialized = false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FCM TOKEN MANAGER
// ═══════════════════════════════════════════════════════════════════════════

/// Manages the FCM device token lifecycle — refreshes on update and
/// persists to Firestore so the server can target this device.
class FcmTokenManager {
  FcmTokenManager._();

  static StreamSubscription? _tokenSub;
  // SỬA LỖI P0: Thêm cờ trạng thái
  static bool _initialized = false;

  static Future<void> initialize({
    required Future<void> Function(String token) onTokenAvailable,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;

    // SỬA LỖI: Thêm guard chặn gọi nhiều lần để tránh rò rỉ (leak) StreamSubscription
    // khi home_page.dart cũng gọi hàm này.
    if (_initialized) return;
    _initialized = true;

    // Get current token
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        debugPrint('📱 FCM token: ${token.substring(0, 20)}…');
        await onTokenAvailable(token);
      }
    } catch (e) {
      debugPrint('❌ FCM getToken: $e');
    }

    // Listen for token refreshes (token can change after reinstall etc.)
    _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) async {
        debugPrint('🔄 FCM token refreshed');
        try {
          await onTokenAvailable(token);
        } catch (e) {
          debugPrint('❌ onTokenRefresh: $e');
        }
      },
      onError: (e) => debugPrint('❌ tokenRefresh stream: $e'),
      cancelOnError: false,
    );
  }

  static void dispose() {
    _tokenSub?.cancel();
    _tokenSub = null;
    _initialized = false;
  }
}
