import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class ReactionSummary {
  final Map<String, int> counts; 
  final Map<String, bool> mine; 
  final int total;

  const ReactionSummary({
    required this.counts,
    required this.mine,
    required this.total,
  });

  factory ReactionSummary.empty() => const ReactionSummary(counts: {}, mine: {}, total: 0);

  List<MapEntry<String, int>> get sortedEntries =>
      counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

class ReactionProvider {
  final FirebaseFirestore firebaseFirestore;

  ReactionProvider({required this.firebaseFirestore});

  

  CollectionReference _reactionsRef(String groupChatId, String messageId) => firebaseFirestore
      .collection(FirestoreConstants.pathMessageCollection)
      .doc(groupChatId)
      .collection(groupChatId)
      .doc(messageId)
      .collection('reactions');

  

  Future<void> toggleReaction(
    String groupChatId,
    String messageId,
    String userId,
    String emoji,
  ) async {
    final ref = _reactionsRef(groupChatId, messageId);

    
    final existing = await ref
        .where('userId', isEqualTo: userId)
        .where('emoji', isEqualTo: emoji)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      
      await existing.docs.first.reference.delete();
    } else {
      
      final previous = await ref.where('userId', isEqualTo: userId).get();
      final batch = firebaseFirestore.batch();
      for (final doc in previous.docs) {
        batch.delete(doc.reference);
      }
      
      batch.set(ref.doc(), {
        'userId': userId,
        'emoji': emoji,
        'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      await batch.commit();
    }
  }

  

  Future<void> addReaction(
    String groupChatId,
    String messageId,
    String userId,
    String emoji,
  ) async {
    final ref = _reactionsRef(groupChatId, messageId);

    
    final existing = await ref
        .where('userId', isEqualTo: userId)
        .where('emoji', isEqualTo: emoji)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) return; 

    await ref.add({
      'userId': userId,
      'emoji': emoji,
      'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
    });
  }

  Future<void> removeReaction(
    String groupChatId,
    String messageId,
    String userId,
    String emoji,
  ) async {
    final existing = await _reactionsRef(groupChatId, messageId)
        .where('userId', isEqualTo: userId)
        .where('emoji', isEqualTo: emoji)
        .limit(1)
        .get();

    for (final doc in existing.docs) {
      await doc.reference.delete();
    }
  }

  Future<void> removeAllReactionsFromUser(
    String groupChatId,
    String messageId,
    String userId,
  ) async {
    final userReactions =
        await _reactionsRef(groupChatId, messageId).where('userId', isEqualTo: userId).get();

    final batch = firebaseFirestore.batch();
    for (final doc in userReactions.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  

  Stream<QuerySnapshot> getReactions(String groupChatId, String messageId) {
    return _reactionsRef(groupChatId, messageId)
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  Stream<ReactionSummary> watchReactionSummary(
    String groupChatId,
    String messageId,
    String currentUserId,
  ) {
    return _reactionsRef(groupChatId, messageId).snapshots().map((snapshot) {
      final counts = <String, int>{};
      final mine = <String, bool>{};

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final emoji = data['emoji'] as String? ?? '';
        final uid = data['userId'] as String? ?? '';

        counts[emoji] = (counts[emoji] ?? 0) + 1;
        if (uid == currentUserId) mine[emoji] = true;
      }

      return ReactionSummary(
        counts: counts,
        mine: mine,
        total: snapshot.docs.length,
      );
    });
  }

  

  Future<Map<String, int>> getAggregatedReactions(
    String groupChatId,
    String messageId,
  ) async {
    final snapshot = await _reactionsRef(groupChatId, messageId).get();

    final counts = <String, int>{};
    for (final doc in snapshot.docs) {
      final emoji = (doc.data() as Map<String, dynamic>)['emoji'] as String? ?? '';
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    return counts;
  }

  Future<Map<String, bool>> getUserReactions(
    String groupChatId,
    String messageId,
    String userId,
  ) async {
    final snapshot =
        await _reactionsRef(groupChatId, messageId).where('userId', isEqualTo: userId).get();

    return {
      for (final doc in snapshot.docs)
        (doc.data() as Map<String, dynamic>)['emoji'] as String? ?? '': true,
    };
  }

  Future<ReactionSummary> getReactionSummary(
    String groupChatId,
    String messageId,
    String currentUserId,
  ) async {
    final snapshot = await _reactionsRef(groupChatId, messageId).get();

    final counts = <String, int>{};
    final mine = <String, bool>{};

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final emoji = data['emoji'] as String? ?? '';
      final uid = data['userId'] as String? ?? '';

      counts[emoji] = (counts[emoji] ?? 0) + 1;
      if (uid == currentUserId) mine[emoji] = true;
    }

    return ReactionSummary(
      counts: counts,
      mine: mine,
      total: snapshot.docs.length,
    );
  }
}
