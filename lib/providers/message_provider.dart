import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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

  // ── Streams ───────────────────────────────────────────────────────────────

  Stream<QuerySnapshot> getMessages(
    String groupChatId, {
    int limit = 30,
    DocumentSnapshot? startAfter,
  }) {
    var query = _msgCollection(
      groupChatId,
    ).orderBy(FirestoreConstants.timestamp, descending: true).limit(limit);

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

  // ── Mutations ─────────────────────────────────────────────────────────────

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

      // Cập nhật lastMessage trên node Conversation nếu đây là tin nhắn cuối.
      // [SỬA LỖI BUG 8]: Đã gỡ bỏ logic gọi ChatBubbleService ra khỏi tầng Provider.
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
      final deletedText = 'This message was deleted';

      if (forEveryone) {
        await _msgCollection(groupChatId).doc(messageId).update({
          'isDeleted': true,
          'deletedAt': now,
          'autoDeleteAt': FieldValue.delete(),
        });
      } else {
        await _msgCollection(
          groupChatId,
        ).doc(messageId).update({'deletedBySender': true, 'deletedAt': now});
      }

      // Cập nhật LastMessage nếu tin nhắn vừa xóa là tin cuối cùng
      // [SỬA LỖI BUG 8]: Đã gỡ bỏ logic gọi ChatBubbleService.
      await _syncConversationLastMessage(groupChatId, messageId, deletedText);

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
      final deletedText = 'This message was deleted';

      for (final id in messageIds) {
        batch.update(_msgCollection(groupChatId).doc(id), {
          'isDeleted': true,
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

      final latestMsgDoc = await _msgCollection(
        groupChatId,
      ).orderBy(FirestoreConstants.timestamp, descending: true).limit(1).get();

      if (latestMsgDoc.docs.isNotEmpty &&
          messageIds.contains(latestMsgDoc.docs.first.id)) {
        await firebaseFirestore
            .collection(FirestoreConstants.pathConversationCollection)
            .doc(groupChatId)
            .update({FirestoreConstants.lastMessage: deletedText});
        // [SỬA LỖI BUG 8]: Đã gỡ bỏ logic gọi ChatBubbleService.
      }

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
        'pinnedAt': newPinned
            ? DateTime.now().millisecondsSinceEpoch.toString()
            : FieldValue.delete(),
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
        'starredBy': isStarred
            ? FieldValue.arrayRemove([userId])
            : FieldValue.arrayUnion([userId]),
      });
      return true;
    } catch (e) {
      debugPrint('❌ Error toggling star: $e');
      return false;
    }
  }

  // [SỬA LỖI BUG 9]: Bổ sung tham số `forwardedContent`. Controller (UI) sẽ chịu trách nhiệm
  // giải mã từ cuộc hội thoại cũ và mã hóa lại với session key của toGroupChatId trước khi truyền vào đây.
  Future<bool> forwardMessage({
    required String fromGroupChatId,
    required String messageId,
    required String toGroupChatId,
    required String senderId,
    required String forwardedContent,
  }) async {
    try {
      final original = await _msgCollection(
        fromGroupChatId,
      ).doc(messageId).get();
      if (!original.exists) return false;

      final data = Map<String, dynamic>.from(
        original.data() as Map<String, dynamic>,
      );

      data.remove('isPinned');
      data.remove('pinnedAt');
      data.remove('starredBy');
      data.remove('reactions');
      data.remove('autoDeleteAt');

      data[FirestoreConstants.idFrom] = senderId;
      data[FirestoreConstants.timestamp] = DateTime.now().millisecondsSinceEpoch
          .toString();
      data['isForwarded'] = true;
      data['forwardedFrom'] = fromGroupChatId;
      data[FirestoreConstants.content] = forwardedContent;

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
      final replyToDoc = await _msgCollection(
        groupChatId,
      ).doc(replyToMessageId).get();

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
          'preview': replyPreview.length > 100
              ? '${replyPreview.substring(0, 100)}…'
              : replyPreview,
          'senderId': replyToSender,
        },
      });

      return true;
    } catch (e) {
      debugPrint('❌ Error sending reply: $e');
      return false;
    }
  }

  // ── Read receipts ─────────────────────────────────────────────────────────

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

  Future<void> markAllMessagesRead(String groupChatId, String userId) async {
    try {
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

      // [SỬA LỖI BUG 8]: Đã gỡ bỏ ChatBubbleService.
    } catch (e) {
      debugPrint('❌ Error marking all messages read: $e');
    }
  }

  // ── Search ────────────────────────────────────────────────────────────────

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
        final content =
            (doc.data() as Map<String, dynamic>)[FirestoreConstants.content]
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

  // ── Internal ──────────────────────────────────────────────────────────────

  /// Cập nhật thông tin Last Message lên Conversation Node và trả về true
  /// nếu document thay đổi vừa rồi thực sự nằm cuối cùng chuỗi.
  Future<bool> _syncConversationLastMessage(
    String groupChatId,
    String messageId,
    String newContent,
  ) async {
    try {
      final latest = await _msgCollection(
        groupChatId,
      ).orderBy(FirestoreConstants.timestamp, descending: true).limit(1).get();

      if (latest.docs.isNotEmpty && latest.docs.first.id == messageId) {
        await firebaseFirestore
            .collection(FirestoreConstants.pathConversationCollection)
            .doc(groupChatId)
            .update({FirestoreConstants.lastMessage: newContent});
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Error syncing conversation last message: $e');
      return false;
    }
  }

  // [SỬA LỖI BUG 8]: Đã xóa toàn bộ hàm `_extractPeerId` vì logic tách chuỗi (split)
  // lấy giá trị `last` bị sai ID trong ~50% trường hợp khi currentUserId < peerId.
}
