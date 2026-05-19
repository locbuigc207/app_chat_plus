import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class ReactionProvider {
  final FirebaseFirestore firebaseFirestore;

  ReactionProvider({required this.firebaseFirestore});

  
  Future<void> toggleReaction(
      String groupChatId,
      String messageId,
      String userId,
      String emoji,
      ) async {
    final reactionsRef = firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .doc(messageId)
        .collection('reactions');

    
    final existingReaction = await reactionsRef
        .where('userId', isEqualTo: userId)
        .where('emoji', isEqualTo: emoji)
        .get();

    if (existingReaction.docs.isNotEmpty) {
      
      await reactionsRef.doc(existingReaction.docs.first.id).delete();
    } else {
      
      final userReactions = await reactionsRef
          .where('userId', isEqualTo: userId)
          .get();

      for (var doc in userReactions.docs) {
        await doc.reference.delete();
      }

      
      await reactionsRef.add({
        'userId': userId,
        'emoji': emoji,
        'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
      });
    }
  }

  
  Stream<QuerySnapshot> getReactions(String groupChatId, String messageId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .doc(messageId)
        .collection('reactions')
        .snapshots();
  }

  
  Future<Map<String, int>> getAggregatedReactions(
      String groupChatId,
      String messageId,
      ) async {
    final snapshot = await firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .doc(messageId)
        .collection('reactions')
        .get();

    final Map<String, int> reactions = {};
    for (var doc in snapshot.docs) {
      final emoji = doc.get('emoji') as String;
      reactions[emoji] = (reactions[emoji] ?? 0) + 1;
    }

    return reactions;
  }

  
  Future<Map<String, bool>> getUserReactions(
      String groupChatId,
      String messageId,
      String userId,
      ) async {
    final snapshot = await firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .doc(messageId)
        .collection('reactions')
        .where('userId', isEqualTo: userId)
        .get();

    final Map<String, bool> userReactions = {};
    for (var doc in snapshot.docs) {
      final emoji = doc.get('emoji') as String;
      userReactions[emoji] = true;
    }

    return userReactions;
  }
}