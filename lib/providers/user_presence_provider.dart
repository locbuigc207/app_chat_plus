
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class UserPresenceProvider {
  final FirebaseFirestore firebaseFirestore;
  Timer? _heartbeatTimer;

  final Map<String, Timer> _typingTimers = {};

  UserPresenceProvider({required this.firebaseFirestore});

  
  Future<void> setUserOnline(String userId) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .update({
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      });

      
      _startHeartbeat(userId);

      print('✅ User set online: $userId');
    } catch (e) {
      print('❌ Error setting user online: $e');
    }
  }

  
  Future<void> setUserOffline(String userId) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });

      _heartbeatTimer?.cancel();

      final typingDocs =
          await firebaseFirestore.collection('typing_status').get();

      final batch = firebaseFirestore.batch();
      for (var doc in typingDocs.docs) {
        final data = doc.data();
        if (data.containsKey(userId)) {
          batch.update(doc.reference, {
            userId: FieldValue.delete(),
          });
        }
      }
      await batch.commit();

      print('✅ User set offline: $userId');
    } catch (e) {
      print('❌ Error setting user offline: $e');
    }
  }

  
  void _startHeartbeat(String userId) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) async {
        try {
          await firebaseFirestore
              .collection(FirestoreConstants.pathUserCollection)
              .doc(userId)
              .update({
            'lastSeen': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          print('❌ Heartbeat error: $e');
        }
      },
    );
  }

  
  Future<void> setTypingStatus({
    required String conversationId,
    required String userId,
    required bool isTyping,
  }) async {
    try {
      
      _typingTimers[conversationId]?.cancel();

      await firebaseFirestore
          .collection('typing_status')
          .doc(conversationId)
          .set({
        userId: {
          'isTyping': isTyping,
          'timestamp': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      
      if (isTyping) {
        _typingTimers[conversationId] = Timer(Duration(seconds: 5), () {
          setTypingStatus(
            conversationId: conversationId,
            userId: userId,
            isTyping: false,
          );
        });
      }

      print('✅ Typing status updated: $isTyping');
    } catch (e) {
      print('❌ Error updating typing status: $e');
    }
  }

  
  Stream<Map<String, bool>> getTypingStatus(String conversationId) {
    return firebaseFirestore
        .collection('typing_status')
        .doc(conversationId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return {};

      final data = doc.data() as Map<String, dynamic>;
      final typingUsers = <String, bool>{};

      data.forEach((userId, value) {
        if (value is Map<String, dynamic>) {
          final isTyping = value['isTyping'] as bool? ?? false;
          final timestamp = value['timestamp'] as Timestamp?;

          
          if (timestamp != null && isTyping) {
            final now = DateTime.now();
            final diff = now.difference(timestamp.toDate()).inSeconds;
            if (diff < 5) {
              typingUsers[userId] = true;
            }
          }
        }
      });

      return typingUsers;
    });
  }

  
  Future<void> markMessagesAsRead({
    required String conversationId,
    required String userId,
  }) async {
    try {
      final messages = await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(conversationId)
          .collection(conversationId)
          .where(FirestoreConstants.idTo, isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = firebaseFirestore.batch();

      for (var doc in messages.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      print('✅ Messages marked as read');
    } catch (e) {
      print('❌ Error marking messages as read: $e');
    }
  }

  
  Stream<int> getUnreadCount(String conversationId, String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(conversationId)
        .collection(conversationId)
        .where(FirestoreConstants.idTo, isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  
  Stream<Map<String, dynamic>> getUserOnlineStatus(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) {
        return {
          'isOnline': false,
          'lastSeen': null,
        };
      }

      final data = doc.data()!;
      final isOnline = data['isOnline'] as bool? ?? false;
      final lastSeen = data['lastSeen'] as Timestamp?;

      
      if (lastSeen != null) {
        final diff = DateTime.now().difference(lastSeen.toDate()).inMinutes;
        if (diff > 1) {
          return {
            'isOnline': false,
            'lastSeen': lastSeen.toDate(),
          };
        }
      }

      return {
        'isOnline': isOnline,
        'lastSeen': lastSeen?.toDate(),
      };
    });
  }

  
  Stream<List<Map<String, dynamic>>> getOnlineFriends(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'nickname': data['nickname'] ?? '',
          'photoUrl': data['photoUrl'] ?? '',
          'isOnline': data['isOnline'] ?? false,
          'lastSeen': data['lastSeen'],
        };
      }).toList();
    });
  }

  void dispose() {
    _heartbeatTimer?.cancel();

    
    for (var timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
  }
}
