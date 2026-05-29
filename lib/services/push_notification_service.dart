// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'e2ee_service.dart';





const _kChannelId = 'e2ee_chat_channel';
const _kChannelName = 'Chat Notifications';
const _kChannelDesc = 'Thông báo tin nhắn mã hóa đầu cuối';
const _kDefaultTitle = 'Tin nhắn mới';
const _kLockedBody = '🔒 Bạn có một tin nhắn mã hóa mới';
const _kIcon = '@mipmap/ic_launcher';







@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  
  await Firebase.initializeApp();

  debugPrint('[PushNotif] 📲 Background message: ${message.messageId}');

  if (!message.data.containsKey('encryptedContent')) return;

  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) {
    debugPrint('[PushNotif] ⚠️ Không có user — bỏ qua background decrypt');
    return;
  }

  final data = _NotificationData.fromMap(message.data, currentUser.uid);

  try {
    
    final e2ee = E2EEService();
    final keyLoaded = await e2ee.loadLocalKeys();

    if (!keyLoaded) {
      debugPrint('[PushNotif] ⚠️ Chưa có khóa cục bộ — hiển thị placeholder');
      await PushNotificationService.showLocalNotification(
        id: data.notificationId,
        title: data.senderName,
        body: _kLockedBody,
        payload: data.toPayloadString(),
      );
      return;
    }

    final decryptedText = await e2ee.decryptPayload(
      data.encryptedContent,
      data.conversationId,
      data.participantIds,
      currentUser.uid,
    );

    await PushNotificationService.showLocalNotification(
      id: data.notificationId,
      title: data.senderName,
      body: decryptedText,
      payload: data.toPayloadString(),
    );
  } catch (e) {
    debugPrint('[PushNotif] ❌ Background decrypt error: $e');
    await PushNotificationService.showLocalNotification(
      id: data.notificationId,
      title: data.senderName,
      body: _kLockedBody,
      payload: data.toPayloadString(),
    );
  }
}





class _NotificationData {
  final String encryptedContent;
  final String conversationId;
  final String senderId;
  final String senderName;
  final List<String> participantIds;
  final int notificationId;
  final String? avatarUrl;
  final String? messageType; 

  const _NotificationData({
    required this.encryptedContent,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.participantIds,
    required this.notificationId,
    this.avatarUrl,
    this.messageType,
  });

  factory _NotificationData.fromMap(
    Map<String, dynamic> data,
    String currentUserId,
  ) {
    final senderId = data['senderId'] as String? ?? '';
    final conversationId = data['conversationId'] as String? ?? '';

    
    List<String> participantIds = [currentUserId, senderId];
    final rawParticipants = data['participantIds'];
    if (rawParticipants is String && rawParticipants.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawParticipants);
        if (decoded is List) {
          participantIds = decoded.cast<String>();
        }
      } catch (_) {}
    }

    
    final notificationId = conversationId.hashCode.abs() % 100000;

    return _NotificationData(
      encryptedContent: data['encryptedContent'] as String? ?? '',
      conversationId: conversationId,
      senderId: senderId,
      senderName: data['senderName'] as String? ?? _kDefaultTitle,
      participantIds: participantIds,
      notificationId: notificationId,
      avatarUrl: data['avatarUrl'] as String?,
      messageType: data['messageType'] as String?,
    );
  }

  String toPayloadString() => jsonEncode({
        'conversationId': conversationId,
        'senderId': senderId,
      });
}





class PushNotificationService {
  PushNotificationService._();

  
  static final FlutterLocalNotificationsPlugin _localPlugin = FlutterLocalNotificationsPlugin();

  
  static final StreamController<Map<String, dynamic>> _notificationTapController =
      StreamController<Map<String, dynamic>>.broadcast();

  
  
  static Stream<Map<String, dynamic>> get onNotificationTapped => _notificationTapController.stream;

  
  static final StreamController<String> _fcmTokenController = StreamController<String>.broadcast();

  static Stream<String> get onFcmTokenRefreshed => _fcmTokenController.stream;

  
  
  

  static Future<void> initialize({
    void Function(Map<String, dynamic> payload)? onNotificationTap,
  }) async {
    
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    
    await _initLocalNotifications();

    
    await _requestPermissions();

    
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationOpen(message.data);
      onNotificationTap?.call(message.data);
    });

    
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      
      await Future.delayed(const Duration(milliseconds: 500));
      _handleNotificationOpen(initialMessage.data);
      onNotificationTap?.call(initialMessage.data);
    }

    
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      debugPrint('[PushNotif] 🔄 FCM token refreshed');
      _fcmTokenController.add(token);
    });

    
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: false, 
      badge: true,
      sound: false,
    );

    debugPrint('[PushNotif] ✅ Khởi tạo Push Notification Service hoàn tất');
  }

  
  
  

  static Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(_kIcon);
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          try {
            final payload = jsonDecode(response.payload!) as Map<String, dynamic>;
            _notificationTapController.add(payload);
            debugPrint('[PushNotif] 👆 Notification tapped: $payload');
          } catch (e) {
            debugPrint('[PushNotif] ⚠️ Parse payload error: $e');
          }
        }
      },
      onDidReceiveBackgroundNotificationResponse: _backgroundNotificationResponseHandler,
    );

    
    await _createNotificationChannel();
  }

  @pragma('vm:entry-point')
  static void _backgroundNotificationResponseHandler(NotificationResponse response) {
    debugPrint('[PushNotif] 📲 Background notification tap: ${response.payload}');
  }

  static Future<void> _createNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      _kChannelId,
      _kChannelName,
      description: _kChannelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await _localPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  
  
  

  static Future<NotificationSettings> _requestPermissions() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      criticalAlert: false,
    );
    debugPrint('[PushNotif] 🔔 Permission: ${settings.authorizationStatus.name}');
    return settings;
  }

  
  
  

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('[PushNotif] 📩 Foreground message: ${message.messageId}');

    if (!message.data.containsKey('encryptedContent')) {
      
      final notification = message.notification;
      if (notification != null) {
        await showLocalNotification(
          id: message.hashCode.abs() % 100000,
          title: notification.title ?? _kDefaultTitle,
          body: notification.body ?? '',
        );
      }
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final data = _NotificationData.fromMap(message.data, currentUser.uid);

    try {
      final e2ee = E2EEService();
      if (!e2ee.isInitialized) await e2ee.loadLocalKeys();

      final decryptedText = await e2ee.decryptPayload(
        data.encryptedContent,
        data.conversationId,
        data.participantIds,
        currentUser.uid,
      );

      await showLocalNotification(
        id: data.notificationId,
        title: data.senderName,
        body: _buildNotificationBody(decryptedText, data.messageType),
        payload: data.toPayloadString(),
        isGroupable: true,
        groupKey: 'conv_${data.conversationId}',
      );
    } catch (e) {
      debugPrint('[PushNotif] ❌ Foreground decrypt error: $e');
      await showLocalNotification(
        id: data.notificationId,
        title: data.senderName,
        body: _kLockedBody,
        payload: data.toPayloadString(),
      );
    }
  }

  
  
  

  static String _buildNotificationBody(String text, String? messageType) {
    switch (messageType) {
      case 'image':
        return '📷 Hình ảnh';
      case 'video':
        return '🎥 Video';
      case 'file':
        return '📎 Tệp đính kèm';
      case 'audio':
        return '🎵 Tin nhắn thoại';
      case 'sticker':
        return '😊 Sticker';
      default:
        
        return text.length > 120 ? '${text.substring(0, 120)}…' : text;
    }
  }

  
  
  

  static Future<void> showLocalNotification({
    required String title,
    required String body,
    int? id,
    String? payload,
    bool isGroupable = false,
    String? groupKey,
    String? largeIconUrl,
  }) async {
    final notificationId = id ?? DateTime.now().millisecond;

    final androidDetails = AndroidNotificationDetails(
      _kChannelId,
      _kChannelName,
      channelDescription: _kChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      icon: _kIcon,
      groupKey: isGroupable ? groupKey : null,
      setAsGroupSummary: false,
      styleInformation: BigTextStyleInformation(body),
      ticker: title,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: _kChannelId,
    );

    final platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localPlugin.show(
      notificationId,
      title,
      body,
      platformDetails,
      payload: payload,
    );
  }

  
  
  

  static Future<void> cancelNotification(int id) => _localPlugin.cancel(id);

  static Future<void> cancelAllNotifications() => _localPlugin.cancelAll();

  static Future<void> cancelConversationNotification(String conversationId) async {
    final id = conversationId.hashCode.abs() % 100000;
    await _localPlugin.cancel(id);
  }

  
  
  

  static Future<String?> getFcmToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('[PushNotif] ❌ getFcmToken error: $e');
      return null;
    }
  }

  static Future<void> deleteToken() async {
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('[PushNotif] ❌ deleteToken error: $e');
    }
  }

  
  
  

  static Future<void> subscribeToTopic(String topic) =>
      FirebaseMessaging.instance.subscribeToTopic(topic);

  static Future<void> unsubscribeFromTopic(String topic) =>
      FirebaseMessaging.instance.unsubscribeFromTopic(topic);

  
  
  

  static void _handleNotificationOpen(Map<String, dynamic> data) {
    debugPrint('[PushNotif] 🚀 App opened via notification: $data');
    _notificationTapController.add(data);
  }

  
  
  

  static Future<void> dispose() async {
    await _notificationTapController.close();
    await _fcmTokenController.close();
  }
}
