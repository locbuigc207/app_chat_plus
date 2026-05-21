// ==============================================================
// 2. CẤU HÌNH BACKGROUND HANDLER CHO PUSH NOTIFICATION (E2EE)
// File: lib/services/push_notification_service.dart
// ==============================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'encryption_service.dart';

// ĐIỂM VÀO LUỒNG NỀN (BACKGROUND ENTRY POINT)
// Hàm này bắt buộc phải là top-level function để chạy khi app bị tắt
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  // Kiểm tra xem message có mang dữ liệu mã hóa từ backend không
  if (message.data.containsKey('encryptedContent')) {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final encryptedContent = message.data['encryptedContent'];
      final conversationId = message.data['conversationId'];
      final senderId = message.data['senderId'];
      final senderName = message.data['senderName'] ?? "Tin nhắn mới";

      // TIẾN HÀNH GIẢI MÃ DƯỚI NỀN BẰNG PRIVATE KEY CỦA THIẾT BỊ
      final decryptedText = await EncryptionService().decryptPayload(
        encryptedContent,
        conversationId,
        [currentUser.uid, senderId],
        currentUser.uid,
      );

      // SAU KHI GIẢI MÃ XONG, HIỂN THỊ LÊN KHAY HỆ THỐNG
      await PushNotificationService.showLocalNotification(
        title: senderName,
        body: decryptedText,
      );
    } catch (e) {
      print("Lỗi giải mã background: $e");
      // Fallback: Nếu lỗi, hiện thông báo che giấu
      await PushNotificationService.showLocalNotification(
        title: "Tin nhắn mới",
        body: "🔒 Bạn có một tin nhắn mã hóa mới",
      );
    }
  }
}

class PushNotificationService {
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // 1. Cấu hình Local Notifications
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await _localNotificationsPlugin.initialize(initSettings);

    // 2. Yêu cầu quyền thông báo
    await FirebaseMessaging.instance.requestPermission();

    // 3. Đăng ký Handler chạy dưới nền (App bị kill hoặc chạy ngầm)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 4. Lắng nghe khi App đang mở (Foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      if (message.data.containsKey('encryptedContent')) {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) return;

        final encryptedContent = message.data['encryptedContent'];
        final conversationId = message.data['conversationId'];
        final senderId = message.data['senderId'];
        final senderName = message.data['senderName'] ?? "Tin nhắn mới";

        try {
          final decryptedText = await EncryptionService().decryptPayload(
            encryptedContent,
            conversationId,
            [currentUser.uid, senderId],
            currentUser.uid,
          );

          showLocalNotification(title: senderName, body: decryptedText);
        } catch (e) {
          showLocalNotification(
              title: senderName, body: "🔒 Tin nhắn mã hóa an toàn");
        }
      }
    });
  }

  static Future<void> showLocalNotification({
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'e2ee_chat_channel',
      'Chat Notifications',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);

    await _localNotificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      platformDetails,
    );
  }
}
