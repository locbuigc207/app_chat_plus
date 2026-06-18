// lib/services/bubble_fcm_handler.dart
//
// Wires Firebase Cloud Messaging → UnifiedBubbleService so every incoming
// push notification automatically spawns or updates a chat bubble.
//
// Usage in main.dart
// ──────────────────
//   void main() async {
//     WidgetsFlutterBinding.ensureInitialized();
//     await Firebase.initializeApp();
//     await BubbleFcmHandler.initialize();
//     runApp(BubbleSystemWrapper(child: MyApp()));
//   }

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

  static final _svc = UnifiedBubbleService();
  static final _seen = <String>{}; // dedup message IDs
  static const _maxSeen = 200;

  static final StreamController<RemoteMessage> _messageCtrl =
      StreamController<RemoteMessage>.broadcast();

  /// Stream of every FCM message handled (for UI / analytics).
  static Stream<RemoteMessage> get messageStream => _messageCtrl.stream;

  // ─── Initialise ─────────────────────────────────────────────────────────

  /// Call once from main() after Firebase.initializeApp().
  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid) return;

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
    final avatarUrl = data['avatarUrl'] ?? data['photoUrl'] ?? '';
    final message =
        data['message'] ?? data['body'] ?? msg.notification?.body ?? '';
    final msgType = data['messageType'] ?? 'text';
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

    // ── Show / update bubble ──────────────────────────────────────────────
    if (!fromBackground) {
      // Foreground: update or show bubble
      if (_svc.isBubbleActive(userId)) {
        await _svc.updateBubbleMessage(
          userId: userId,
          message: _preview(message, msgType),
        );
      } else {
        await _svc.showChatBubble(
          userId: userId,
          userName: userName,
          avatarUrl: avatarUrl,
          lastMessage: _preview(message, msgType),
          isOnline: true,
        );
      }
    }
    // Background messages are handled natively by BubbleNotificationService
    // on Android; we just forward the event stream here.

    _messageCtrl.add(msg);

    debugPrint(
      '✅ FCM processed → bubble: $userName '
      '(bg=$fromBackground, tap=$userTapped)',
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  static String _preview(String message, String type) {
    switch (type.toLowerCase()) {
      case 'image':
      case '1':
        return '📷 Hình ảnh';
      case 'video':
      case '2':
        return '🎬 Video';
      case 'voice':
      case '3':
        return '🎤 Tin nhắn thoại';
      case 'file':
      case '4':
      case '5':
        return '📎 Tệp đính kèm';
      case 'poll':
      case '6':
        return '📊 Bình chọn';
      case 'sticker':
      case '10':
        return '😊 Nhãn dán';
      case 'location':
      case '11':
        return '📍 Vị trí';
      default:
        return message.length > 60 ? '${message.substring(0, 60)}…' : message;
    }
  }

  static void dispose() {
    _messageCtrl.close();
    _seen.clear();
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

  static Future<void> initialize({
    required Future<void> Function(String token) onTokenAvailable,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;

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
  }
}
