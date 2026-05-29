import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

enum FriendRequestStatus { none, sent, received, friends }

class FriendProvider {
  final FirebaseFirestore firebaseFirestore;

  FriendProvider({required this.firebaseFirestore});

  Future<bool> sendFriendRequest(String requesterId, String receiverId) async {
    try {
      if (requesterId == receiverId) return false;

      final checks = await Future.wait([
        firebaseFirestore
            .collection(FirestoreConstants.pathFriendRequestCollection)
            .where(FirestoreConstants.requesterId, isEqualTo: requesterId)
            .where(FirestoreConstants.receiverId, isEqualTo: receiverId)
            .limit(1)
            .get(),
        firebaseFirestore
            .collection(FirestoreConstants.pathFriendRequestCollection)
            .where(FirestoreConstants.requesterId, isEqualTo: receiverId)
            .where(FirestoreConstants.receiverId, isEqualTo: requesterId)
            .limit(1)
            .get(),
      ]);

      if (checks[0].docs.isNotEmpty || checks[1].docs.isNotEmpty) {
        return false;
      }

      if (await areFriends(requesterId, receiverId)) return false;

      await firebaseFirestore.collection(FirestoreConstants.pathFriendRequestCollection).add({
        FirestoreConstants.requesterId: requesterId,
        FirestoreConstants.receiverId: receiverId,
        FirestoreConstants.status: 'pending',
        FirestoreConstants.createdAt: DateTime.now().millisecondsSinceEpoch.toString(),
      });

      return true;
    } catch (e) {
      debugPrint('❌ Error sending friend request: $e');
      return false;
    }
  }

  Future<bool> acceptFriendRequest(
    String requestId,
    String userId1,
    String userId2,
  ) async {
    try {
      final batch = firebaseFirestore.batch();

      batch.update(
        firebaseFirestore.collection(FirestoreConstants.pathFriendRequestCollection).doc(requestId),
        {FirestoreConstants.status: 'accepted'},
      );

      final friendshipId = _getFriendshipId(userId1, userId2);
      final sorted = _sortedIds(userId1, userId2);

      batch.set(
        firebaseFirestore.collection(FirestoreConstants.pathFriendshipCollection).doc(friendshipId),
        {
          FirestoreConstants.userId1: sorted[0],
          FirestoreConstants.userId2: sorted[1],
          FirestoreConstants.createdAt: DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );

      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('❌ Error accepting friend request: $e');
      return false;
    }
  }

  Future<bool> declineFriendRequest(String requestId) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathFriendRequestCollection)
          .doc(requestId)
          .update({FirestoreConstants.status: 'declined'});
      return true;
    } catch (e) {
      debugPrint('❌ Error declining friend request: $e');
      return false;
    }
  }

  Future<bool> cancelFriendRequest(String requesterId, String receiverId) async {
    try {
      final request = await firebaseFirestore
          .collection(FirestoreConstants.pathFriendRequestCollection)
          .where(FirestoreConstants.requesterId, isEqualTo: requesterId)
          .where(FirestoreConstants.receiverId, isEqualTo: receiverId)
          .where(FirestoreConstants.status, isEqualTo: 'pending')
          .limit(1)
          .get();

      if (request.docs.isEmpty) return false;
      await request.docs.first.reference.delete();
      return true;
    } catch (e) {
      debugPrint('❌ Error cancelling friend request: $e');
      return false;
    }
  }

  Future<bool> unfriend(String userId1, String userId2) async {
    try {
      final friendshipId = _getFriendshipId(userId1, userId2);
      await firebaseFirestore
          .collection(FirestoreConstants.pathFriendshipCollection)
          .doc(friendshipId)
          .delete();
      return true;
    } catch (e) {
      debugPrint('❌ Error unfriending: $e');
      return false;
    }
  }

  Future<bool> areFriends(String userId1, String userId2) async {
    try {
      final doc = await firebaseFirestore
          .collection(FirestoreConstants.pathFriendshipCollection)
          .doc(_getFriendshipId(userId1, userId2))
          .get();
      return doc.exists;
    } catch (e) {
      debugPrint('❌ Error checking friendship: $e');
      return false;
    }
  }

  Future<FriendRequestStatus> getFriendStatus(String userId1, String userId2) async {
    try {
      if (await areFriends(userId1, userId2)) {
        return FriendRequestStatus.friends;
      }

      final results = await Future.wait([
        firebaseFirestore
            .collection(FirestoreConstants.pathFriendRequestCollection)
            .where(FirestoreConstants.requesterId, isEqualTo: userId1)
            .where(FirestoreConstants.receiverId, isEqualTo: userId2)
            .where(FirestoreConstants.status, isEqualTo: 'pending')
            .limit(1)
            .get(),
        firebaseFirestore
            .collection(FirestoreConstants.pathFriendRequestCollection)
            .where(FirestoreConstants.requesterId, isEqualTo: userId2)
            .where(FirestoreConstants.receiverId, isEqualTo: userId1)
            .where(FirestoreConstants.status, isEqualTo: 'pending')
            .limit(1)
            .get(),
      ]);

      if (results[0].docs.isNotEmpty) return FriendRequestStatus.sent;
      if (results[1].docs.isNotEmpty) return FriendRequestStatus.received;
      return FriendRequestStatus.none;
    } catch (e) {
      debugPrint('❌ Error getting friend status: $e');
      return FriendRequestStatus.none;
    }
  }

  Future<String?> checkFriendRequest(String userId1, String userId2) async {
    try {
      final results = await Future.wait([
        firebaseFirestore
            .collection(FirestoreConstants.pathFriendRequestCollection)
            .where(FirestoreConstants.requesterId, isEqualTo: userId1)
            .where(FirestoreConstants.receiverId, isEqualTo: userId2)
            .where(FirestoreConstants.status, isEqualTo: 'pending')
            .limit(1)
            .get(),
        firebaseFirestore
            .collection(FirestoreConstants.pathFriendRequestCollection)
            .where(FirestoreConstants.requesterId, isEqualTo: userId2)
            .where(FirestoreConstants.receiverId, isEqualTo: userId1)
            .where(FirestoreConstants.status, isEqualTo: 'pending')
            .limit(1)
            .get(),
      ]);

      if (results[0].docs.isNotEmpty) return 'sent';
      if (results[1].docs.isNotEmpty) return results[1].docs.first.id;
      return null;
    } catch (e) {
      debugPrint('❌ Error checking friend request: $e');
      return null;
    }
  }

  Stream<QuerySnapshot> getFriendsList(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathFriendshipCollection)
        .where(FirestoreConstants.userId1, isEqualTo: userId)
        .snapshots();
  }

  Stream<QuerySnapshot> getFriendsList2(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathFriendshipCollection)
        .where(FirestoreConstants.userId2, isEqualTo: userId)
        .snapshots();
  }

  Stream<List<String>> getFriendIds(String userId) {
    final s1 = firebaseFirestore
        .collection(FirestoreConstants.pathFriendshipCollection)
        .where(FirestoreConstants.userId1, isEqualTo: userId)
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()[FirestoreConstants.userId2] as String).toList());

    final s2 = firebaseFirestore
        .collection(FirestoreConstants.pathFriendshipCollection)
        .where(FirestoreConstants.userId2, isEqualTo: userId)
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()[FirestoreConstants.userId1] as String).toList());

    return s1.asyncMap((ids1) async {
      final snap2 = await firebaseFirestore
          .collection(FirestoreConstants.pathFriendshipCollection)
          .where(FirestoreConstants.userId2, isEqualTo: userId)
          .get();
      final ids2 = snap2.docs.map((d) => d.data()[FirestoreConstants.userId1] as String).toList();
      return [...ids1, ...ids2];
    });
  }

  Stream<QuerySnapshot> getPendingRequestsReceived(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathFriendRequestCollection)
        .where(FirestoreConstants.receiverId, isEqualTo: userId)
        .where(FirestoreConstants.status, isEqualTo: 'pending')
        .orderBy(FirestoreConstants.createdAt, descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> getPendingRequestsSent(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathFriendRequestCollection)
        .where(FirestoreConstants.requesterId, isEqualTo: userId)
        .where(FirestoreConstants.status, isEqualTo: 'pending')
        .snapshots();
  }

  Stream<QuerySnapshot> getConversations(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathConversationCollection)
        .where(FirestoreConstants.participants, arrayContains: userId)
        .orderBy(FirestoreConstants.lastMessageTime, descending: true)
        .snapshots();
  }

  Future<void> updateConversationLastMessage(
    String conversationId,
    String message,
    int messageType,
  ) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update({
        FirestoreConstants.lastMessage: message,
        FirestoreConstants.lastMessageTime: DateTime.now().millisecondsSinceEpoch.toString(),
        FirestoreConstants.lastMessageType: messageType,
      });
    } catch (e) {
      debugPrint('❌ Error updating conversation: $e');
    }
  }

  Future<String> getOrCreateConversation(
    String userId1,
    String userId2,
    bool isGroup,
  ) async {
    try {
      if (isGroup) return '';

      final conversationId = _getFriendshipId(userId1, userId2);
      final doc = await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .get();

      if (!doc.exists) {
        await firebaseFirestore
            .collection(FirestoreConstants.pathConversationCollection)
            .doc(conversationId)
            .set({
          FirestoreConstants.isGroup: false,
          FirestoreConstants.participants: [userId1, userId2],
          FirestoreConstants.lastMessage: '',
          FirestoreConstants.lastMessageTime: '0',
          FirestoreConstants.lastMessageType: 0,
          'unreadCount': 0,
          'isPinned': false,
          'isMuted': false,
          'isLocked': false,
          'archivedBy': [],
          'createdAt': DateTime.now().millisecondsSinceEpoch.toString(),
        });
      }

      return conversationId;
    } catch (e) {
      debugPrint('❌ Error creating conversation: $e');
      return '';
    }
  }

  String _getFriendshipId(String a, String b) => a.compareTo(b) < 0 ? '$a-$b' : '$b-$a';

  List<String> _sortedIds(String a, String b) => a.compareTo(b) < 0 ? [a, b] : [b, a];
}
