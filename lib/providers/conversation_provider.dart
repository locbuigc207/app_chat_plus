// lib/providers/conversation_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class ConversationProvider {
  final FirebaseFirestore firebaseFirestore;

  ConversationProvider({required this.firebaseFirestore});

  // ── Pin / Unpin ─────────────────────────────────────────────────────────────

  /// Pin hoặc unpin một conversation.
  Future<bool> togglePinConversation(
      String conversationId, bool currentStatus) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update({
        'isPinned': !currentStatus,
        'pinnedAt': !currentStatus
            ? DateTime.now().millisecondsSinceEpoch.toString()
            : null,
      });
      return true;
    } catch (e) {
      print('Error toggling pin: $e');
      return false;
    }
  }

  // ── Mute / Unmute ───────────────────────────────────────────────────────────

  /// Mute hoặc unmute thông báo của một conversation.
  Future<bool> toggleMuteConversation(
      String conversationId, bool currentStatus) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update({
        'isMuted': !currentStatus,
      });
      return true;
    } catch (e) {
      print('Error toggling mute: $e');
      return false;
    }
  }

  // ── Archive / Unarchive ─────────────────────────────────────────────────────

  /// Archive hoặc unarchive conversation cho một user cụ thể.
  /// Dùng arrayUnion/arrayRemove để hỗ trợ nhiều user archive độc lập.
  Future<bool> toggleArchiveConversation(
      String conversationId, String currentUserId, bool isArchiving) async {
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
      print('Error archiving conversation: $e');
      return false;
    }
  }

  // ── Clear History ───────────────────────────────────────────────────────────

  /// Xóa toàn bộ tin nhắn trong conversation, giữ nguyên trạng thái bạn bè.
  /// Batch delete theo từng chunk 500 (giới hạn Firestore).
  Future<bool> clearConversationHistory(String conversationId) async {
    try {
      final messagesSnapshot = await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(conversationId)
          .collection(conversationId)
          .get();

      if (messagesSnapshot.docs.isEmpty) return true;

      final batch = firebaseFirestore.batch();
      int count = 0;

      for (final doc in messagesSnapshot.docs) {
        batch.delete(doc.reference);
        count++;

        if (count >= 500) {
          await batch.commit();
          count = 0;
        }
      }

      if (count > 0) {
        await batch.commit();
      }

      // Reset lastMessage sau khi xóa
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update({
        FirestoreConstants.lastMessage: '',
        FirestoreConstants.lastMessageTime: '0',
        FirestoreConstants.lastMessageType: 0,
      });

      print('✅ Cleared conversation history: $conversationId');
      return true;
    } catch (e) {
      print('❌ Error clearing conversation history: $e');
      return false;
    }
  }

  // ── Streams ─────────────────────────────────────────────────────────────────

  /// Stream danh sách conversation của user, pinned lên đầu,
  /// sau đó sắp xếp theo lastMessageTime giảm dần.
  Stream<List<QueryDocumentSnapshot>> getConversationsWithPinned(
      String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathConversationCollection)
        .where(FirestoreConstants.participants, arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      final docs = snapshot.docs;

      docs.sort((a, b) {
        final aData = a.data();
        final bData = b.data();

        final aPinned = (aData['isPinned'] as bool?) ?? false;
        final bPinned = (bData['isPinned'] as bool?) ?? false;

        if (aPinned && !bPinned) return -1;
        if (!aPinned && bPinned) return 1;

        final aTime =
            int.tryParse(aData['lastMessageTime'] as String? ?? '0') ?? 0;
        final bTime =
            int.tryParse(bData['lastMessageTime'] as String? ?? '0') ?? 0;
        return bTime.compareTo(aTime);
      });

      return docs;
    });
  }
}
