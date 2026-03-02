import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class MessageProvider {
  final FirebaseFirestore firebaseFirestore;

  MessageProvider({required this.firebaseFirestore});

  // Edit message
  Future<bool> editMessage(
      String groupChatId,
      String messageId,
      String newContent,
      ) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .doc(messageId)
          .update({
        FirestoreConstants.content: newContent,
        'editedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      });

      // Update conversation last message if it was the latest
      await _updateConversationIfNeeded(groupChatId, messageId, newContent);

      return true;
    } catch (e) {
      print('Error editing message: $e');
      return false;
    }
  }

  // Delete message (soft delete)
  Future<bool> deleteMessage(
      String groupChatId,
      String messageId,
      ) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .doc(messageId)
          .update({
        'isDeleted': true,
        FirestoreConstants.content: 'This message was deleted',
        'deletedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      });

      return true;
    } catch (e) {
      print('Error deleting message: $e');
      return false;
    }
  }

  // Pin/Unpin message
  Future<bool> togglePinMessage(
      String groupChatId,
      String messageId,
      bool currentPinStatus,
      ) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .doc(messageId)
          .update({
        'isPinned': !currentPinStatus,
        'pinnedAt': !currentPinStatus
            ? DateTime.now().millisecondsSinceEpoch.toString()
            : null,
      });

      return true;
    } catch (e) {
      print('Error toggling pin: $e');
      return false;
    }
  }

  // Get pinned messages
  Stream<QuerySnapshot> getPinnedMessages(String groupChatId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .where('isPinned', isEqualTo: true)
        .orderBy('pinnedAt', descending: true)
        .snapshots();
  }

  Future<void> _updateConversationIfNeeded(
      String groupChatId,
      String messageId,
      String newContent,
      ) async {
    // Get latest message
    final latestMessage = await firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .orderBy(FirestoreConstants.timestamp, descending: true)
        .limit(1)
        .get();

    if (latestMessage.docs.isNotEmpty &&
        latestMessage.docs.first.id == messageId) {
      // This is the latest message, update conversation
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(groupChatId)
          .update({
        FirestoreConstants.lastMessage: newContent,
      });
    }
  }
}