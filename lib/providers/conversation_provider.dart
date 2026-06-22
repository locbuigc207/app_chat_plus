import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

enum ConversationFilter { all, unread, archived, pinned }

class ConversationProvider {
  final FirebaseFirestore firebaseFirestore;

  static const int _batchSize = 500;

  ConversationProvider({required this.firebaseFirestore});

  // ── Streams ───────────────────────────────────────────────────────────────

  Stream<List<QueryDocumentSnapshot>> getConversationsWithPinned(
    String userId,
  ) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathConversationCollection)
        .where(FirestoreConstants.participants, arrayContains: userId)
        // SỬA LỖI A1: Đưa orderBy lên trước limit để lấy chính xác 50 hội thoại mới nhất
        .orderBy('isPinned', descending: true)
        .orderBy('lastMessageTime', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          // Lọc archivedBy ở client để tránh xung đột composite index trên Firestore
          return snapshot.docs.where((doc) {
            final archivedBy = List<String>.from(
              (doc.data() as Map<String, dynamic>)['archivedBy'] as List? ?? [],
            );
            return !archivedBy.contains(userId);
          }).toList();
        });
  }

  Stream<List<QueryDocumentSnapshot>> getArchivedConversations(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathConversationCollection)
        .where('archivedBy', arrayContains: userId)
        // SỬA LỖI A1: Sắp xếp danh sách lưu trữ trước khi cắt limit
        // Lưu ý: Cần thêm index (archivedBy ARRAY_CONTAINS, lastMessageTime DESC) trên Firebase
        .orderBy('lastMessageTime', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs);
  }

  Stream<List<QueryDocumentSnapshot>> getUnreadConversations(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathConversationCollection)
        .where(FirestoreConstants.participants, arrayContains: userId)
        // SỬA LỖI A1: Dùng chung luồng query chính để lấy 50 hội thoại mới nhất
        .orderBy('isPinned', descending: true)
        .orderBy('lastMessageTime', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          // SỬA LỖI B: Lọc unreadCount client-side để đồng bộ, hỗ trợ schema mới (Map)
          return snapshot.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final unreadData = data['unreadCount'];

            if (unreadData is Map) {
              return (unreadData[userId] as int? ?? 0) > 0;
            } else if (unreadData is int) {
              // Giữ fallback cho schema cũ tránh crash
              return unreadData > 0;
            }
            return false;
          }).toList();
        });
  }

  Stream<DocumentSnapshot> watchConversation(String conversationId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathConversationCollection)
        .doc(conversationId)
        .snapshots();
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  Future<bool> togglePinConversation(
    String conversationId,
    bool currentStatus,
  ) async {
    try {
      final newPinned = !currentStatus;
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update({
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

  Future<bool> toggleMuteConversation(
    String conversationId,
    bool currentStatus,
  ) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update({'isMuted': !currentStatus});
      return true;
    } catch (e) {
      debugPrint('❌ Error toggling mute: $e');
      return false;
    }
  }

  Future<bool> muteUntil(String conversationId, Duration? duration) async {
    try {
      final update = duration == null
          ? {'isMuted': false, 'mutedUntil': FieldValue.delete()}
          : {
              'isMuted': true,
              'mutedUntil': Timestamp.fromDate(DateTime.now().add(duration)),
            };

      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update(update);
      return true;
    } catch (e) {
      debugPrint('❌ Error muting conversation: $e');
      return false;
    }
  }

  Future<bool> toggleArchiveConversation(
    String conversationId,
    String currentUserId,
    bool isArchiving,
  ) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update({
            'archivedBy': isArchiving
                ? FieldValue.arrayUnion([currentUserId])
                : FieldValue.arrayRemove([currentUserId]),
          });
      return true;
    } catch (e) {
      debugPrint('❌ Error archiving conversation: $e');
      return false;
    }
  }

  Future<bool> markAsRead(String conversationId, String userId) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update({
            // SỬA LỖI B: Cập nhật unreadCount thành 0 cụ thể cho người đọc hiện tại (Schema Map)
            'unreadCount.$userId': 0,
            'lastReadBy.$userId': DateTime.now().millisecondsSinceEpoch
                .toString(),
          });
      return true;
    } catch (e) {
      debugPrint('❌ Error marking as read: $e');
      return false;
    }
  }

  // SỬA LỖI B: Đổi tham số từ excludeUserIds thành targetUserIds để cập nhật map dễ dàng hơn
  Future<bool> incrementUnreadCount(
    String conversationId,
    List<String> targetUserIds,
  ) async {
    try {
      if (targetUserIds.isEmpty) return true;

      final updates = <String, dynamic>{};
      for (final uid in targetUserIds) {
        updates['unreadCount.$uid'] = FieldValue.increment(1);
      }

      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update(updates);
      return true;
    } catch (e) {
      debugPrint('❌ Error incrementing unread: $e');
      return false;
    }
  }

  Future<bool> clearConversationHistory(String conversationId) async {
    try {
      final messagesSnapshot = await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(conversationId)
          .collection(conversationId)
          .get();

      if (messagesSnapshot.docs.isNotEmpty) {
        WriteBatch batch = firebaseFirestore.batch();
        int count = 0;

        for (final doc in messagesSnapshot.docs) {
          batch.delete(doc.reference);
          count++;
          if (count >= _batchSize) {
            await batch.commit();
            batch = firebaseFirestore.batch();
            count = 0;
          }
        }
        if (count > 0) await batch.commit();
      }

      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update({
            FirestoreConstants.lastMessage: '',
            FirestoreConstants.lastMessageTime: '0',
            FirestoreConstants.lastMessageType: 0,
            // Xóa việc set 'unreadCount': 0 ở đây để tránh phá vỡ schema Map,
            // có thể xử lý riêng việc đánh dấu đã đọc sau khi xóa nếu cần.
            'clearedAt': DateTime.now().millisecondsSinceEpoch.toString(),
          });

      return true;
    } catch (e) {
      debugPrint('❌ Error clearing conversation history: $e');
      return false;
    }
  }

  Future<bool> deleteConversationForUser(
    String conversationId,
    String userId,
  ) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update({
            'deletedBy': FieldValue.arrayUnion([userId]),
          });
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting conversation for user: $e');
      return false;
    }
  }

  // ── Typing ────────────────────────────────────────────────────────────────

  Future<void> setTypingStatus(
    String conversationId,
    String userId,
    bool isTyping,
  ) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update({
            'typingUsers.$userId': isTyping
                ? DateTime.now().millisecondsSinceEpoch.toString()
                : FieldValue.delete(),
          });
    } catch (e) {
      debugPrint('❌ Error setting typing status: $e');
    }
  }

  Stream<Map<String, dynamic>> watchTypingUsers(String conversationId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathConversationCollection)
        .doc(conversationId)
        .snapshots()
        .map((snap) {
          final data = snap.data();
          if (data == null) return {};

          final typingUsers =
              data['typingUsers'] as Map<String, dynamic>? ?? {};
          final now = DateTime.now().millisecondsSinceEpoch;

          return Map.fromEntries(
            typingUsers.entries.where((e) {
              final ts = int.tryParse(e.value.toString()) ?? 0;
              return now - ts < 10000;
            }),
          );
        });
  }
}
