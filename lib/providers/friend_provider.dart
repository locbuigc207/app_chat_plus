import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class FriendProvider {
  final FirebaseFirestore firebaseFirestore;

  FriendProvider({required this.firebaseFirestore});

  
  Future<bool> sendFriendRequest(String requesterId, String receiverId) async {
    try {
      
      final existingRequest = await firebaseFirestore
          .collection(FirestoreConstants.pathFriendRequestCollection)
          .where(FirestoreConstants.requesterId, isEqualTo: requesterId)
          .where(FirestoreConstants.receiverId, isEqualTo: receiverId)
          .get();

      if (existingRequest.docs.isNotEmpty) {
        return false; 
      }

      
      final reverseRequest = await firebaseFirestore
          .collection(FirestoreConstants.pathFriendRequestCollection)
          .where(FirestoreConstants.requesterId, isEqualTo: receiverId)
          .where(FirestoreConstants.receiverId, isEqualTo: requesterId)
          .get();

      if (reverseRequest.docs.isNotEmpty) {
        return false; 
      }

      
      await firebaseFirestore
          .collection(FirestoreConstants.pathFriendRequestCollection)
          .add({
        FirestoreConstants.requesterId: requesterId,
        FirestoreConstants.receiverId: receiverId,
        FirestoreConstants.status: 'pending',
        FirestoreConstants.createdAt:
        DateTime.now().millisecondsSinceEpoch.toString(),
      });

      return true;
    } catch (e) {
      print('Error sending friend request: $e');
      return false;
    }
  }

  
  Future<bool> acceptFriendRequest(String requestId, String userId1, String userId2) async {
    try {
      
      await firebaseFirestore
          .collection(FirestoreConstants.pathFriendRequestCollection)
          .doc(requestId)
          .update({FirestoreConstants.status: 'accepted'});

      
      final friendshipId = userId1.compareTo(userId2) < 0
          ? '$userId1-$userId2'
          : '$userId2-$userId1';

      await firebaseFirestore
          .collection(FirestoreConstants.pathFriendshipCollection)
          .doc(friendshipId)
          .set({
        FirestoreConstants.userId1: userId1.compareTo(userId2) < 0 ? userId1 : userId2,
        FirestoreConstants.userId2: userId1.compareTo(userId2) < 0 ? userId2 : userId1,
        FirestoreConstants.createdAt:
        DateTime.now().millisecondsSinceEpoch.toString(),
      });

      return true;
    } catch (e) {
      print('Error accepting friend request: $e');
      return false;
    }
  }

  
  Future<bool> areFriends(String userId1, String userId2) async {
    try {
      final friendshipId = userId1.compareTo(userId2) < 0
          ? '$userId1-$userId2'
          : '$userId2-$userId1';

      final doc = await firebaseFirestore
          .collection(FirestoreConstants.pathFriendshipCollection)
          .doc(friendshipId)
          .get();

      return doc.exists;
    } catch (e) {
      print('Error checking friendship: $e');
      return false;
    }
  }

  
  Future<String?> checkFriendRequest(String userId1, String userId2) async {
    try {
      
      final sentRequest = await firebaseFirestore
          .collection(FirestoreConstants.pathFriendRequestCollection)
          .where(FirestoreConstants.requesterId, isEqualTo: userId1)
          .where(FirestoreConstants.receiverId, isEqualTo: userId2)
          .where(FirestoreConstants.status, isEqualTo: 'pending')
          .get();

      if (sentRequest.docs.isNotEmpty) {
        return 'sent';
      }

      
      final receivedRequest = await firebaseFirestore
          .collection(FirestoreConstants.pathFriendRequestCollection)
          .where(FirestoreConstants.requesterId, isEqualTo: userId2)
          .where(FirestoreConstants.receiverId, isEqualTo: userId1)
          .where(FirestoreConstants.status, isEqualTo: 'pending')
          .get();

      if (receivedRequest.docs.isNotEmpty) {
        return receivedRequest.docs.first.id; 
      }

      return null;
    } catch (e) {
      print('Error checking friend request: $e');
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
        FirestoreConstants.lastMessageTime:
        DateTime.now().millisecondsSinceEpoch.toString(),
        FirestoreConstants.lastMessageType: messageType,
      });
    } catch (e) {
      print('Error updating conversation: $e');
    }
  }

  
  Future<String> getOrCreateConversation(
      String userId1,
      String userId2,
      bool isGroup,
      ) async {
    try {
      if (!isGroup) {
        
        final conversationId = userId1.compareTo(userId2) < 0
            ? '$userId1-$userId2'
            : '$userId2-$userId1';

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
          });
        }

        return conversationId;
      }

      return '';
    } catch (e) {
      print('Error creating conversation: $e');
      return '';
    }
  }
}