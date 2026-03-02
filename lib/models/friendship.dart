import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

enum FriendRequestStatus {
  pending,
  accepted,
  rejected,
}

class FriendRequest {
  final String id;
  final String requesterId;
  final String receiverId;
  final String status;
  final String createdAt;

  const FriendRequest({
    required this.id,
    required this.requesterId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      FirestoreConstants.requesterId: requesterId,
      FirestoreConstants.receiverId: receiverId,
      FirestoreConstants.status: status,
      FirestoreConstants.createdAt: createdAt,
    };
  }

  factory FriendRequest.fromDocument(DocumentSnapshot doc) {
    return FriendRequest(
      id: doc.id,
      requesterId: doc.get(FirestoreConstants.requesterId),
      receiverId: doc.get(FirestoreConstants.receiverId),
      status: doc.get(FirestoreConstants.status),
      createdAt: doc.get(FirestoreConstants.createdAt),
    );
  }
}

class Friendship {
  final String id;
  final String userId1;
  final String userId2;
  final String createdAt;

  const Friendship({
    required this.id,
    required this.userId1,
    required this.userId2,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      FirestoreConstants.userId1: userId1,
      FirestoreConstants.userId2: userId2,
      FirestoreConstants.createdAt: createdAt,
    };
  }

  factory Friendship.fromDocument(DocumentSnapshot doc) {
    return Friendship(
      id: doc.id,
      userId1: doc.get(FirestoreConstants.userId1),
      userId2: doc.get(FirestoreConstants.userId2),
      createdAt: doc.get(FirestoreConstants.createdAt),
    );
  }
}