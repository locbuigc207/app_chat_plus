// lib/providers/view_once_provider.dart (FIXED - Auto Delete Working)
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class ViewOnceProvider {
  final FirebaseFirestore firebaseFirestore;

  ViewOnceProvider({required this.firebaseFirestore});

  // Send view-once message
  Future<bool> sendViewOnceMessage({
    required String groupChatId,
    required String currentUserId,
    required String peerId,
    required String content,
    required int type,
  }) async {
    try {
      final messageId = DateTime.now().millisecondsSinceEpoch.toString();

      await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .doc(messageId)
          .set({
        FirestoreConstants.idFrom: currentUserId,
        FirestoreConstants.idTo: peerId,
        FirestoreConstants.timestamp: messageId,
        FirestoreConstants.content: content,
        FirestoreConstants.type: type,
        'isViewOnce': true,
        'isViewed': false,
        'viewedAt': null,
        'viewedBy': null,
      });

      print(' View-once message sent');
      return true;
    } catch (e) {
      print(' Error sending view-once message: $e');
      return false;
    }
  }

  // Mark message as viewed and schedule deletion
  Future<bool> markAsViewed({
    required String groupChatId,
    required String messageId,
    required String userId,
  }) async {
    try {
      // Mark as viewed
      await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .doc(messageId)
          .update({
        'isViewed': true,
        'viewedAt': DateTime.now().millisecondsSinceEpoch.toString(),
        'viewedBy': userId,
      });

      print(' Message marked as viewed, scheduling deletion...');

      // Schedule auto-delete after 10 seconds
      Timer(const Duration(seconds: 10), () async {
        await _deleteViewOnceMessage(groupChatId, messageId);
      });

      return true;
    } catch (e) {
      print(' Error marking as viewed: $e');
      return false;
    }
  }

  // Delete view-once message
  Future<void> _deleteViewOnceMessage(
      String groupChatId, String messageId) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .doc(messageId)
          .update({
        'isDeleted': true,
        'content': 'This message was opened',
        'deletedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      });

      print(' View-once message deleted after viewing');
    } catch (e) {
      print(' Error deleting view-once message: $e');
    }
  }

  // Check if message is view-once and not viewed
  Future<bool> isViewOnceUnviewed({
    required String groupChatId,
    required String messageId,
  }) async {
    try {
      final doc = await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .doc(messageId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          final isViewOnce = data['isViewOnce'] ?? false;
          final isViewed = data['isViewed'] ?? false;
          return isViewOnce && !isViewed;
        }
      }

      return false;
    } catch (e) {
      print(' Error checking view-once status: $e');
      return false;
    }
  }
}