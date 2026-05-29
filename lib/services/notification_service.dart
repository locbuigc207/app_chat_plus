import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationPayload {
  final String senderId;
  final String senderName;
  final String avatarUrl;
  final String content;
  final String conversationId;
  final int timestamp;

  const NotificationPayload({
    required this.senderId,
    required this.senderName,
    required this.avatarUrl,
    required this.content,
    required this.conversationId,
    required this.timestamp,
  });
}

class NotificationService {
  final ChatBubbleService _bubbleService = ChatBubbleService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  StreamSubscription<QuerySnapshot>? _messageSubscription;
  bool _isListening = false;

  final Set<String> _processedIds = {};
  static const int _maxProcessedIds = 200;

  final Set<String> _mutedConversations = {};

  void Function(NotificationPayload)? onNotificationTapped;
  void Function(NotificationPayload)? onInAppNotification;

  Future<void> initialize() async {
    await _initLocalNotifications();
    await _requestFCMPermissions();
    _setupFCMHandlers();
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        _onLocalNotificationTapped(details.payload);
      },
    );

    const channel = AndroidNotificationChannel(
      'chat_messages',
      'Chat Messages',
      description: 'Notifications for new chat messages',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(channel);
  }

  Future<void> _requestFCMPermissions() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('🔔 FCM permission: ${settings.authorizationStatus}');
  }

  void _setupFCMHandlers() {
    FirebaseMessaging.onMessage.listen((message) {
      _handleFCMMessage(message, isBackground: false);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleFCMTap(message);
    });
  }

  Future<void> _handleFCMMessage(
    RemoteMessage message, {
    required bool isBackground,
  }) async {
    final data = message.data;
    if (data.isEmpty) return;

    final senderId = data['senderId'] as String?;
    if (senderId == null) return;
    if (_mutedConversations.contains(data['conversationId'])) return;

    if (!isBackground) {
      await _showLocalNotification(
        title: data['senderName'] ?? 'New Message',
        body: data['content'] ?? '',
        payload: data['conversationId'] ?? '',
        senderId: senderId,
      );
    }
  }

  void _handleFCMTap(RemoteMessage message) {
    final data = message.data;
    if (data.isEmpty) return;

    onNotificationTapped?.call(NotificationPayload(
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      avatarUrl: data['avatarUrl'] ?? '',
      content: data['content'] ?? '',
      conversationId: data['conversationId'] ?? '',
      timestamp: int.tryParse(data['timestamp'] ?? '0') ?? 0,
    ));
  }

  void _onLocalNotificationTapped(String? payload) {
    if (payload == null || payload.isEmpty) return;
    debugPrint('🔔 Notification tapped, conversationId: $payload');
  }

  void listenForNewMessages(String currentUserId) {
    if (_isListening) return;

    _messageSubscription?.cancel();
    _isListening = true;

    _messageSubscription = _firestore
        .collectionGroup(FirestoreConstants.pathMessageCollection)
        .where(FirestoreConstants.idTo, isEqualTo: currentUserId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen(
      (snapshot) async {
        final newDocs = snapshot.docChanges
            .where((c) => c.type == DocumentChangeType.added)
            .map((c) => c.doc)
            .toList();

        for (final doc in newDocs) {
          await _handleNewMessage(doc, currentUserId);
        }
      },
      onError: (Object error) {
        debugPrint('❌ Message listener error: $error');
        _isListening = false;

        _retryListen(currentUserId);
      },
      cancelOnError: true,
    );

    debugPrint('👂 Message listener active for: $currentUserId');
  }

  int _retryCount = 0;
  Timer? _retryTimer;

  void _retryListen(String userId) {
    _retryCount++;
    final delay = Duration(seconds: (2 << _retryCount.clamp(0, 5)));
    debugPrint('🔄 Retrying listener in ${delay.inSeconds}s (attempt $_retryCount)');
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (!_isListening) listenForNewMessages(userId);
    });
  }

  Future<void> _handleNewMessage(
    DocumentSnapshot doc,
    String currentUserId,
  ) async {
    try {
      if (_isDuplicate(doc.id)) return;
      _trackProcessed(doc.id);

      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return;

      final senderId = data[FirestoreConstants.idFrom] as String?;
      if (senderId == null || senderId == currentUserId) return;

      final payload = await _buildPayload(data, senderId, doc);
      if (payload == null) return;

      if (_mutedConversations.contains(payload.conversationId)) return;

      final isResumed = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

      if (isResumed) {
        onInAppNotification?.call(payload);
        await _showLocalNotification(
          title: payload.senderName,
          body: _formatPreview(payload.content),
          payload: payload.conversationId,
          senderId: senderId,
          silent: true,
        );
        _updateExistingBubble(senderId, payload.content);
      } else {
        await _maybeCreateBubble(payload);
      }
    } catch (e) {
      debugPrint('❌ Error handling message: $e');
    }
  }

  Future<void> _maybeCreateBubble(NotificationPayload payload) async {
    if (_bubbleService.isBubbleActive(payload.senderId)) {
      await _bubbleService.updateBubbleMessage(
        userId: payload.senderId,
        message: payload.content,
      );
      return;
    }

    final success = await _bubbleService.showChatBubble(
      userId: payload.senderId,
      userName: payload.senderName,
      avatarUrl: payload.avatarUrl,
      lastMessage: payload.content,
    );

    debugPrint(success
        ? '✅ Bubble created: ${payload.senderName}'
        : '❌ Bubble failed: ${payload.senderName}');
  }

  void _updateExistingBubble(String senderId, String content) {
    if (_bubbleService.isBubbleActive(senderId)) {
      _bubbleService.updateBubbleMessage(userId: senderId, message: content);
    }
  }

  Future<bool> createBubbleForUser(String targetUserId) async {
    try {
      final userDoc = await _firestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(targetUserId)
          .get();
      if (!userDoc.exists) return false;

      final userData = userDoc.data()!;
      final name = userData[FirestoreConstants.nickname] as String? ?? 'User';
      final avatar = userData[FirestoreConstants.photoUrl] as String? ?? '';

      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid == null) return false;

      final convId = currentUid.compareTo(targetUserId) < 0
          ? '$currentUid-$targetUserId'
          : '$targetUserId-$currentUid';

      final lastSnap = await _firestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(convId)
          .collection(convId)
          .orderBy(FirestoreConstants.timestamp, descending: true)
          .limit(1)
          .get();

      final lastMsg = lastSnap.docs.isNotEmpty
          ? lastSnap.docs.first.get(FirestoreConstants.content) as String?
          : null;

      return _bubbleService.showChatBubble(
        userId: targetUserId,
        userName: name,
        avatarUrl: avatar,
        lastMessage: lastMsg,
      );
    } catch (e) {
      debugPrint('❌ Error creating bubble: $e');
      return false;
    }
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required String payload,
    required String senderId,
    bool silent = false,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'chat_messages',
      'Chat Messages',
      channelDescription: 'New chat messages',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: silent
          ? const AndroidNotificationDetails(
              'chat_messages',
              'Chat Messages',
              importance: Importance.low,
              priority: Priority.low,
              playSound: false,
              enableVibration: false,
            )
          : androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      senderId.hashCode,
      title,
      body,
      details,
      payload: payload,
    );
  }

  Future<void> cancelNotification(String senderId) async {
    await _localNotifications.cancel(senderId.hashCode);
  }

  Future<void> cancelAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  Future<String?> getFCMToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('❌ Error getting FCM token: $e');
      return null;
    }
  }

  Future<void> saveFCMToken(String userId) async {
    try {
      final token = await getFCMToken();
      if (token == null) return;

      await _firestore.collection(FirestoreConstants.pathUserCollection).doc(userId).update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      debugPrint('✅ FCM token saved');
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
    }
  }

  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  void muteConversation(String conversationId) {
    _mutedConversations.add(conversationId);
  }

  void unmuteConversation(String conversationId) {
    _mutedConversations.remove(conversationId);
  }

  bool isConversationMuted(String conversationId) => _mutedConversations.contains(conversationId);

  Future<NotificationPayload?> _buildPayload(
    Map<String, dynamic> data,
    String senderId,
    DocumentSnapshot doc,
  ) async {
    final senderDoc =
        await _firestore.collection(FirestoreConstants.pathUserCollection).doc(senderId).get();

    if (!senderDoc.exists) return null;

    final senderData = senderDoc.data() as Map<String, dynamic>;
    final content = data[FirestoreConstants.content] as String? ?? '';

    final pathSegments = doc.reference.path.split('/');
    final conversationId = pathSegments.length >= 2 ? pathSegments[1] : senderId;

    return NotificationPayload(
      senderId: senderId,
      senderName: senderData[FirestoreConstants.nickname] as String? ?? 'User',
      avatarUrl: senderData[FirestoreConstants.photoUrl] as String? ?? '',
      content: content,
      conversationId: conversationId,
      timestamp: int.tryParse(data[FirestoreConstants.timestamp]?.toString() ?? '0') ?? 0,
    );
  }

  bool _isDuplicate(String id) => _processedIds.contains(id);

  void _trackProcessed(String id) {
    if (_processedIds.length >= _maxProcessedIds) {
      final toRemove = (_maxProcessedIds * 0.2).ceil();
      final old = _processedIds.take(toRemove).toList();
      _processedIds.removeAll(old);
    }
    _processedIds.add(id);
  }

  String _formatPreview(String content) {
    if (content.length <= 80) return content;
    return '${content.substring(0, 77)}…';
  }

  void stopListening() {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _retryTimer?.cancel();
    _isListening = false;
    _processedIds.clear();
    debugPrint('🛑 Message listener stopped');
  }

  void dispose() {
    stopListening();
    _mutedConversations.clear();
  }
}
