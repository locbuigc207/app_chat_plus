// lib/services/notification_service.dart - COMPLETE FIXED VERSION
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/services/services.dart';

class NotificationService {
  final ChatBubbleService _bubbleService = ChatBubbleService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription? _messageSubscription;
  bool _isListening = false;

  // Track processed messages to avoid duplicates
  final Set<String> _processedMessages = {};

  /// ✅ MAIN: Listen for new messages and auto-create bubbles
  void listenForNewMessages(String currentUserId) {
    if (_isListening) {
      print('⚠️ Already listening for messages');
      return;
    }

    print('👂 Starting to listen for new messages for user: $currentUserId');

    _messageSubscription?.cancel();

    _messageSubscription = _firestore
        .collectionGroup(FirestoreConstants.pathMessageCollection)
        .where(FirestoreConstants.idTo, isEqualTo: currentUserId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen(
      (snapshot) async {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            await _handleNewMessage(change.doc, currentUserId);
          }
        }
      },
      onError: (error) {
        print('❌ Message listener error: $error');
        // Retry after 5 seconds
        Future.delayed(Duration(seconds: 5), () {
          if (!_isListening) {
            listenForNewMessages(currentUserId);
          }
        });
      },
    );

    _isListening = true;
    print('✅ Message listener active');
  }

  /// Handle new incoming message
  Future<void> _handleNewMessage(
    DocumentSnapshot messageDoc,
    String currentUserId,
  ) async {
    try {
      final messageId = messageDoc.id;

      // ✅ FIX #2: Check if already processed
      if (_processedMessages.contains(messageId)) {
        print('ℹ️ Message already processed: $messageId');
        return;
      }

      _processedMessages.add(messageId);
      print('✅ Processing new message: $messageId');

      // ✅ FIX #2: Cleanup old processed messages (keep last 100)
      if (_processedMessages.length > 100) {
        final toRemove = _processedMessages.length - 100;
        final oldIds = _processedMessages.take(toRemove).toList();
        _processedMessages.removeAll(oldIds);
        print('🗑️ Cleaned ${oldIds.length} old message IDs');
      }

      final data = messageDoc.data() as Map<String, dynamic>?;
      if (data == null) return;

      final senderId = data[FirestoreConstants.idFrom] as String?;
      if (senderId == null || senderId == currentUserId) return;

      print('📨 New message from: $senderId');

      // Check if sender bubble already exists
      if (_bubbleService.isBubbleActive(senderId)) {
        print('ℹ️ Bubble already exists for: $senderId');

        // Update bubble with new message
        final content = data[FirestoreConstants.content] as String? ?? '';
        await _bubbleService.updateBubbleMessage(
          userId: senderId,
          message: content,
        );
        return;
      }

      // Check if app is in background/foreground
      final appLifecycleState = WidgetsBinding.instance.lifecycleState;
      final isBackground = appLifecycleState != AppLifecycleState.resumed;

      print('📱 App state: $appLifecycleState (background: $isBackground)');

      // Only create bubble if app is in background
      if (!isBackground) {
        print('ℹ️ App in foreground, skip bubble creation');
        return;
      }

      // Get sender info
      final senderDoc = await _firestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(senderId)
          .get();

      if (!senderDoc.exists) {
        print('⚠️ Sender not found: $senderId');
        return;
      }

      final senderData = senderDoc.data()!;
      final senderName =
          senderData[FirestoreConstants.nickname] as String? ?? 'User';
      final senderAvatar =
          senderData[FirestoreConstants.photoUrl] as String? ?? '';
      final messageContent = data[FirestoreConstants.content] as String? ?? '';

      print('🎈 Creating bubble for: $senderName');

      // Create bubble
      final success = await _bubbleService.showChatBubble(
        userId: senderId,
        userName: senderName,
        avatarUrl: senderAvatar,
        lastMessage: messageContent,
      );

      if (success) {
        print('✅ Bubble created for: $senderName');
      } else {
        print('❌ Failed to create bubble for: $senderName');
      }
    } catch (e) {
      print('❌ Error handling new message: $e');
    }
  }

  /// ✅ NEW: Check app state and create bubble if needed
  Future<void> checkAndCreateBubble({
    required String userId,
    required String userName,
    required String avatarUrl,
    String? lastMessage,
  }) async {
    // Only create if app is in background
    final appLifecycleState = WidgetsBinding.instance.lifecycleState;
    if (appLifecycleState == AppLifecycleState.resumed) {
      print('ℹ️ App in foreground, skip bubble');
      return;
    }

    // Check if bubble already exists
    if (_bubbleService.isBubbleActive(userId)) {
      print('ℹ️ Bubble already exists');
      return;
    }

    // Create bubble
    await _bubbleService.showChatBubble(
      userId: userId,
      userName: userName,
      avatarUrl: avatarUrl,
      lastMessage: lastMessage,
    );
  }

  /// ✅ NEW: Manual trigger to create bubble
  Future<bool> createBubbleForUser(String userId) async {
    try {
      // Get user info
      final userDoc = await _firestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .get();

      if (!userDoc.exists) return false;

      final userData = userDoc.data()!;
      final userName = userData[FirestoreConstants.nickname] as String? ?? '';
      final avatarUrl = userData[FirestoreConstants.photoUrl] as String? ?? '';

      // Check for latest message
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return false;

      final conversationId = currentUserId.compareTo(userId) < 0
          ? '$currentUserId-$userId'
          : '$userId-$currentUserId';

      final messagesSnapshot = await _firestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(conversationId)
          .collection(conversationId)
          .orderBy(FirestoreConstants.timestamp, descending: true)
          .limit(1)
          .get();

      String? lastMessage;
      if (messagesSnapshot.docs.isNotEmpty) {
        final lastMsg = messagesSnapshot.docs.first;
        lastMessage = lastMsg.get(FirestoreConstants.content) as String?;
      }

      // Create bubble
      return await _bubbleService.showChatBubble(
        userId: userId,
        userName: userName,
        avatarUrl: avatarUrl,
        lastMessage: lastMessage,
      );
    } catch (e) {
      print('❌ Error creating bubble: $e');
      return false;
    }
  }

  /// Stop listening
  void stopListening() {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _isListening = false;
    _processedMessages.clear();
    print('🛑 Message listener stopped');
  }

  /// Dispose
  void dispose() {
    stopListening();
  }
}
