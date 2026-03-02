import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class ConversationProvider {
  final FirebaseFirestore firebaseFirestore;

  ConversationProvider({required this.firebaseFirestore});

  /// Pin/Unpin conversation
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

  /// Mute/Unmute conversation
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

  /// Xóa lịch sử conversation (chỉ xóa tin nhắn, giữ trạng thái bạn bè)
  Future<bool> clearConversationHistory(String conversationId) async {
    try {
      // Xóa tất cả tin nhắn trong conversation
      final messagesSnapshot = await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(conversationId)
          .collection(conversationId)
          .get();

      if (messagesSnapshot.docs.isEmpty) {
        return true; // Không có tin nhắn để xóa
      }

      // Batch delete messages
      final batch = firebaseFirestore.batch();
      int count = 0;

      for (var doc in messagesSnapshot.docs) {
        batch.delete(doc.reference);
        count++;

        // Commit mỗi 500 operations (giới hạn của Firestore)
        if (count >= 500) {
          await batch.commit();
          count = 0;
        }
      }

      // Commit các operations còn lại
      if (count > 0) {
        await batch.commit();
      }

      // Cập nhật conversation với lastMessage rỗng
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

  /// Lấy danh sách conversation của user, ưu tiên pinned lên đầu
  Stream<List<QueryDocumentSnapshot>> getConversationsWithPinned(
      String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathConversationCollection)
        .where(FirestoreConstants.participants, arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      final docs = snapshot.docs;

      // Sắp xếp: pinned trước, sau đó theo lastMessageTime
      docs.sort((a, b) {
        final aData = a.data();
        final bData = b.data();

        final aPinned = aData['isPinned'] ?? false;
        final bPinned = bData['isPinned'] ?? false;

        if (aPinned && !bPinned) return -1;
        if (!aPinned && bPinned) return 1;

        // Cả hai pinned hoặc không pinned -> so theo thời gian tin nhắn cuối
        final aTime = int.tryParse(aData['lastMessageTime'] ?? '0') ?? 0;
        final bTime = int.tryParse(bData['lastMessageTime'] ?? '0') ?? 0;
        return bTime.compareTo(aTime);
      });

      return docs;
    });
  }
}
