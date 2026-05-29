import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

enum MessageType { text, image, video, audio, file, location, sticker, gif }

class MessageProvider {
  final FirebaseFirestore firebaseFirestore;

  static const int _batchSize = 500;

  MessageProvider({required this.firebaseFirestore});

  CollectionReference _msgCollection(String groupChatId) => firebaseFirestore
      .collection(FirestoreConstants.pathMessageCollection)
      .doc(groupChatId)
      .collection(groupChatId);

  Stream<QuerySnapshot> getMessages(
    String groupChatId, {
    int limit = 30,
    DocumentSnapshot? startAfter,
  }) {
    var query = _msgCollection(groupChatId)
        .orderBy(FirestoreConstants.timestamp, descending: true)
        .limit(limit);

    if (startAfter != null) query = query.startAfterDocument(startAfter);
    return query.snapshots();
  }

  Stream<QuerySnapshot> getPinnedMessages(String groupChatId) {
    return _msgCollection(groupChatId)
        .where('isPinned', isEqualTo: true)
        .orderBy('pinnedAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> getStarredMessages(String groupChatId, String userId) {
    return _msgCollection(groupChatId)
        .where('starredBy', arrayContains: userId)
        .orderBy(FirestoreConstants.timestamp, descending: true)
        .snapshots();
  }

  Future<bool> editMessage(
    String groupChatId,
    String messageId,
    String newContent,
  ) async {
    try {
      await _msgCollection(groupChatId).doc(messageId).update({
        FirestoreConstants.content: newContent,
        'editedAt': DateTime.now().millisecondsSinceEpoch.toString(),
        'isEdited': true,
      });

      await _syncConversationLastMessage(groupChatId, messageId, newContent);
      return true;
    } catch (e) {
      debugPrint('❌ Error editing message: $e');
      return false;
    }
  }

  Future<bool> deleteMessage(
    String groupChatId,
    String messageId, {
    bool forEveryone = true,
  }) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch.toString();

      if (forEveryone) {
        await _msgCollection(groupChatId).doc(messageId).update({
          'isDeleted': true,
          FirestoreConstants.content: 'This message was deleted',
          'deletedAt': now,
          'autoDeleteAt': FieldValue.delete(),
        });
      } else {
        await _msgCollection(groupChatId).doc(messageId).update({
          'deletedBySender': true,
          'deletedAt': now,
        });
      }

      return true;
    } catch (e) {
      debugPrint('❌ Error deleting message: $e');
      return false;
    }
  }

  Future<int> deleteMultipleMessages(
    String groupChatId,
    List<String> messageIds,
  ) async {
    try {
      WriteBatch batch = firebaseFirestore.batch();
      int count = 0;
      int deleted = 0;
      final now = DateTime.now().millisecondsSinceEpoch.toString();

      for (final id in messageIds) {
        batch.update(_msgCollection(groupChatId).doc(id), {
          'isDeleted': true,
          FirestoreConstants.content: 'This message was deleted',
          'deletedAt': now,
        });
        count++;
        deleted++;

        if (count >= _batchSize) {
          await batch.commit();
          batch = firebaseFirestore.batch();
          count = 0;
        }
      }

      if (count > 0) await batch.commit();
      return deleted;
    } catch (e) {
      debugPrint('❌ Error deleting multiple messages: $e');
      return 0;
    }
  }

  Future<bool> togglePinMessage(
    String groupChatId,
    String messageId,
    bool currentPinStatus,
  ) async {
    try {
      final newPinned = !currentPinStatus;
      await _msgCollection(groupChatId).doc(messageId).update({
        'isPinned': newPinned,
        'pinnedAt':
            newPinned ? DateTime.now().millisecondsSinceEpoch.toString() : FieldValue.delete(),
      });
      return true;
    } catch (e) {
      debugPrint('❌ Error toggling pin: $e');
      return false;
    }
  }

  Future<bool> toggleStarMessage(
    String groupChatId,
    String messageId,
    String userId,
    bool isStarred,
  ) async {
    try {
      await _msgCollection(groupChatId).doc(messageId).update({
        'starredBy': isStarred ? FieldValue.arrayRemove([userId]) : FieldValue.arrayUnion([userId]),
      });
      return true;
    } catch (e) {
      debugPrint('❌ Error toggling star: $e');
      return false;
    }
  }

  Future<bool> forwardMessage({
    required String fromGroupChatId,
    required String messageId,
    required String toGroupChatId,
    required String senderId,
  }) async {
    try {
      final original = await _msgCollection(fromGroupChatId).doc(messageId).get();
      if (!original.exists) return false;

      final data = Map<String, dynamic>.from(original.data() as Map<String, dynamic>);

      data.remove('isPinned');
      data.remove('pinnedAt');
      data.remove('starredBy');
      data.remove('reactions');
      data.remove('autoDeleteAt');

      data[FirestoreConstants.idFrom] = senderId;
      data[FirestoreConstants.timestamp] = DateTime.now().millisecondsSinceEpoch.toString();
      data['isForwarded'] = true;
      data['forwardedFrom'] = fromGroupChatId;

      await _msgCollection(toGroupChatId).add(data);
      return true;
    } catch (e) {
      debugPrint('❌ Error forwarding message: $e');
      return false;
    }
  }

  Future<bool> sendReply({
    required String groupChatId,
    required String replyToMessageId,
    required Map<String, dynamic> messageData,
  }) async {
    try {
      final replyToDoc = await _msgCollection(groupChatId).doc(replyToMessageId).get();

      String replyPreview = '';
      String replyToSender = '';
      if (replyToDoc.exists) {
        final d = replyToDoc.data() as Map<String, dynamic>;
        replyPreview = d[FirestoreConstants.content] as String? ?? '';
        replyToSender = d[FirestoreConstants.idFrom] as String? ?? '';
      }

      await _msgCollection(groupChatId).add({
        ...messageData,
        'replyTo': {
          'messageId': replyToMessageId,
          'preview':
              replyPreview.length > 100 ? '${replyPreview.substring(0, 100)}…' : replyPreview,
          'senderId': replyToSender,
        },
      });

      return true;
    } catch (e) {
      debugPrint('❌ Error sending reply: $e');
      return false;
    }
  }

  Future<void> markMessageRead(
    String groupChatId,
    String messageId,
    String userId,
  ) async {
    try {
      await _msgCollection(groupChatId).doc(messageId).update({
        'readBy': FieldValue.arrayUnion([userId]),
        'readAt.$userId': DateTime.now().millisecondsSinceEpoch.toString(),
      });
    } catch (e) {
      debugPrint('❌ Error marking message read: $e');
    }
  }

  Future<void> markAllMessagesRead(
    String groupChatId,
    String userId,
  ) async {
    try {
      final unread = await _msgCollection(groupChatId)
          .where('readBy', arrayContainsAny: ['NOT_${userId}_PLACEHOLDER']).get();

      final all = await _msgCollection(groupChatId)
          .where(FirestoreConstants.idTo, isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      if (all.docs.isEmpty) return;

      WriteBatch batch = firebaseFirestore.batch();
      int count = 0;

      for (final doc in all.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': DateTime.now().millisecondsSinceEpoch.toString(),
        });
        count++;
        if (count >= _batchSize) {
          await batch.commit();
          batch = firebaseFirestore.batch();
          count = 0;
        }
      }

      if (count > 0) await batch.commit();
    } catch (e) {
      debugPrint('❌ Error marking all messages read: $e');
    }
  }

  Future<List<QueryDocumentSnapshot>> searchMessages(
    String groupChatId,
    String query,
  ) async {
    try {
      final trimmed = query.trim().toLowerCase();
      if (trimmed.isEmpty) return [];

      final snapshot = await _msgCollection(groupChatId)
          .where('isDeleted', isEqualTo: false)
          .orderBy(FirestoreConstants.timestamp, descending: true)
          .get();

      return snapshot.docs.where((doc) {
        final content = (doc.data() as Map<String, dynamic>)[FirestoreConstants.content]
                ?.toString()
                .toLowerCase() ??
            '';
        return content.contains(trimmed);
      }).toList();
    } catch (e) {
      debugPrint('❌ Error searching messages: $e');
      return [];
    }
  }

  Future<void> _syncConversationLastMessage(
    String groupChatId,
    String messageId,
    String newContent,
  ) async {
    try {
      final latest = await _msgCollection(groupChatId)
          .orderBy(FirestoreConstants.timestamp, descending: true)
          .limit(1)
          .get();

      if (latest.docs.isNotEmpty && latest.docs.first.id == messageId) {
        await firebaseFirestore
            .collection(FirestoreConstants.pathConversationCollection)
            .doc(groupChatId)
            .update({FirestoreConstants.lastMessage: newContent});
      }
    } catch (e) {
      debugPrint('❌ Error syncing conversation last message: $e');
    }
  }
}
