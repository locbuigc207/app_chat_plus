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
        .limit(50)
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs.where((doc) {
            final archivedBy = List<String>.from(
              doc.data()['archivedBy'] as List? ?? [],
            );
            return !archivedBy.contains(userId);
          }).toList();

          docs.sort((a, b) {
            final aData = a.data();
            final bData = b.data();
            final aPinned = aData['isPinned'] as bool? ?? false;
            final bPinned = bData['isPinned'] as bool? ?? false;

            // Ưu tiên hội thoại được ghim lên đầu
            if (aPinned != bPinned) return aPinned ? -1 : 1;

            // Sắp xếp theo thời gian tin nhắn mới nhất
            final aTime =
                int.tryParse(aData['lastMessageTime']?.toString() ?? '0') ?? 0;
            final bTime =
                int.tryParse(bData['lastMessageTime']?.toString() ?? '0') ?? 0;
            return bTime.compareTo(aTime);
          });

          return docs;
        });
  }

  Stream<List<QueryDocumentSnapshot>> getArchivedConversations(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathConversationCollection)
        .where('archivedBy', arrayContains: userId)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs.toList();

          docs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>? ?? {};
            final bData = b.data() as Map<String, dynamic>? ?? {};

            final aTime =
                int.tryParse(aData['lastMessageTime']?.toString() ?? '0') ?? 0;
            final bTime =
                int.tryParse(bData['lastMessageTime']?.toString() ?? '0') ?? 0;

            return bTime.compareTo(aTime);
          });

          return docs;
        });
  }

  Stream<List<QueryDocumentSnapshot>> getUnreadConversations(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathConversationCollection)
        .where(FirestoreConstants.participants, arrayContains: userId)
        // [FIX P0]: Không dùng .where() với unreadCount vì nó là dạng Map, lọc ở client-side
        .limit(50)
        .snapshots()
        .map((snapshot) {
          // Lọc Client-side để kiểm tra số lượng unread của chính xác userId
          final unreadDocs = snapshot.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final rawUnread = data['unreadCount'];

            if (rawUnread is int) return rawUnread > 0;
            if (rawUnread is Map) {
              final userUnread = rawUnread[userId];
              return (userUnread is int) && userUnread > 0;
            }
            return false;
          }).toList();

          unreadDocs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>? ?? {};
            final bData = b.data() as Map<String, dynamic>? ?? {};

            final aTime =
                int.tryParse(aData['lastMessageTime']?.toString() ?? '0') ?? 0;
            final bTime =
                int.tryParse(bData['lastMessageTime']?.toString() ?? '0') ?? 0;

            return bTime.compareTo(aTime);
          });

          return unreadDocs;
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
      final docRef = firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId);

      // [FIX P0]: Chỉnh sửa unreadCount theo định dạng Map per-user
      await docRef.update({
        'unreadCount.$userId': 0,
        'lastReadBy.$userId': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      return true;
    } catch (e) {
      // Cơ chế Fallback an toàn: Nếu doc cũ đang lưu unreadCount là int,
      // Firestore sẽ ném lỗi khi dùng dot notation. Lúc này ta ép thành Map.
      try {
        await firebaseFirestore
            .collection(FirestoreConstants.pathConversationCollection)
            .doc(conversationId)
            .update({
              'unreadCount': {userId: 0},
              'lastReadBy.$userId': DateTime.now().millisecondsSinceEpoch
                  .toString(),
            });
        return true;
      } catch (fallbackErr) {
        debugPrint('❌ Error marking as read: $fallbackErr');
        return false;
      }
    }
  }

  Future<bool> incrementUnreadCount(
    String conversationId,
    List<String> excludeUserIds,
  ) async {
    try {
      final docRef = firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId);

      final docSnap = await docRef.get();
      final data = docSnap.data();
      if (data == null) return false;

      final participants = List<String>.from(
        data[FirestoreConstants.participants] ?? [],
      );
      final Map<String, dynamic> updates = {};

      // [FIX P0]: Tăng unreadCount dạng Map cho những người không bị exclude
      for (final p in participants) {
        if (!excludeUserIds.contains(p)) {
          updates['unreadCount.$p'] = FieldValue.increment(1);
        }
      }

      if (updates.isNotEmpty) {
        await docRef.update(updates);
      }
      return true;
    } catch (e) {
      // Cơ chế Fallback giống markAsRead nếu doc cũ đang là int
      try {
        final docRef = firebaseFirestore
            .collection(FirestoreConstants.pathConversationCollection)
            .doc(conversationId);

        final docSnap = await docRef.get();
        final participants = List<String>.from(
          docSnap.data()?[FirestoreConstants.participants] ?? [],
        );

        final Map<String, int> newUnreadMap = {};
        for (final p in participants) {
          newUnreadMap[p] = excludeUserIds.contains(p) ? 0 : 1;
        }

        await docRef.update({'unreadCount': newUnreadMap});
        return true;
      } catch (fallbackErr) {
        debugPrint('❌ Error incrementing unread: $fallbackErr');
        return false;
      }
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
            // [FIX P0]: Dùng Map rỗng để reset tin nhắn chưa đọc nhưng giữ cấu trúc dữ liệu
            'unreadCount': {},
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
