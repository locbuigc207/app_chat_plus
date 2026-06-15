import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

enum ConversationFilter { all, unread, archived, pinned }

class ConversationSummary {
  final String id;
  final bool isPinned;
  final bool isMuted;
  final bool isLocked;
  final int unreadCount;
  final int lastMessageTime;
  final String lastMessage;
  final List<String> participants;
  final bool isGroup;
  final List<String> archivedBy;

  const ConversationSummary({
    required this.id,
    required this.isPinned,
    required this.isMuted,
    required this.isLocked,
    required this.unreadCount,
    required this.lastMessageTime,
    required this.lastMessage,
    required this.participants,
    required this.isGroup,
    required this.archivedBy,
  });

  factory ConversationSummary.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ConversationSummary(
      id: doc.id,
      isPinned: data['isPinned'] as bool? ?? false,
      isMuted: data['isMuted'] as bool? ?? false,
      isLocked: data['isLocked'] as bool? ?? false,
      unreadCount: data['unreadCount'] as int? ?? 0,
      lastMessageTime:
          int.tryParse(data['lastMessageTime']?.toString() ?? '0') ?? 0,
      lastMessage: data['lastMessage'] as String? ?? '',
      participants: List<String>.from(data['participants'] as List? ?? []),
      isGroup: data['isGroup'] as bool? ?? false,
      archivedBy: List<String>.from(data['archivedBy'] as List? ?? []),
    );
  }

  bool isArchivedBy(String userId) => archivedBy.contains(userId);
}

class ConversationProvider {
  final FirebaseFirestore firebaseFirestore;

  static const int _batchSize = 500;

  ConversationProvider({required this.firebaseFirestore});

  // ── Streams ───────────────────────────────────────────────────────────────

  Stream<List<QueryDocumentSnapshot>> getConversationsWithPinned(
      String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathConversationCollection)
        .where(FirestoreConstants.participants, arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      final docs = snapshot.docs.where((doc) {
        final archivedBy =
            List<String>.from(doc.data()['archivedBy'] as List? ?? []);
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
        .where(FirestoreConstants.participants, arrayContains: userId)
        .where('archivedBy', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      final docs = snapshot.docs;

      // Bổ sung sắp xếp cho danh sách lưu trữ
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
        .where('unreadCount', isGreaterThan: 0)
        .snapshots()
        .map((snapshot) {
      final docs = snapshot.docs;

      // Bổ sung sắp xếp cho danh sách chưa đọc (Fix lỗi 4 trong phân tích)
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

  Stream<DocumentSnapshot> watchConversation(String conversationId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathConversationCollection)
        .doc(conversationId)
        .snapshots();
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  Future<bool> togglePinConversation(
      String conversationId, bool currentStatus) async {
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
      String conversationId, bool currentStatus) async {
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
        'unreadCount': 0,
        'lastReadBy.$userId': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      return true;
    } catch (e) {
      debugPrint('❌ Error marking as read: $e');
      return false;
    }
  }

  Future<bool> incrementUnreadCount(
      String conversationId, List<String> excludeUserIds) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update({'unreadCount': FieldValue.increment(1)});
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
        'unreadCount': 0,
        'clearedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      });

      return true;
    } catch (e) {
      debugPrint('❌ Error clearing conversation history: $e');
      return false;
    }
  }

  Future<bool> deleteConversationForUser(
      String conversationId, String userId) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update({
        'deletedBy': FieldValue.arrayUnion([userId])
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

      final typingUsers = data['typingUsers'] as Map<String, dynamic>? ?? {};
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
