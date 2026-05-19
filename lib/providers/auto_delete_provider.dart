
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

enum AutoDeleteDuration {
  never,
  oneDay,
  sevenDays,
  thirtyDays,
  custom,
}

class AutoDeleteProvider {
  final FirebaseFirestore firebaseFirestore;
  Timer? _cleanupTimer;

  AutoDeleteProvider({required this.firebaseFirestore}) {
    _startCleanupTimer();
  }

  
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 5),
          (_) => _runGlobalCleanup(),
    );
    print(' Auto-delete cleanup timer started');
  }

  
  Future<void> _runGlobalCleanup() async {
    try {
      print(' Running global auto-delete cleanup...');

      
      final conversations = await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .where('autoDeleteEnabled', isEqualTo: true)
          .get();

      print('Found ${conversations.docs.length} conversations with auto-delete');

      for (var conv in conversations.docs) {
        final duration = conv.data()['autoDeleteDuration'] as int?;
        if (duration != null) {
          await deleteExpiredMessages(conv.id);
        }
      }

      print(' Global cleanup completed');
    } catch (e) {
      print(' Error in global cleanup: $e');
    }
  }

  
  Future<bool> setAutoDelete({
    required String conversationId,
    required AutoDeleteDuration duration,
    int? customHours,
  }) async {
    try {
      int? deleteAfterMillis;

      switch (duration) {
        case AutoDeleteDuration.oneDay:
          deleteAfterMillis = 24 * 60 * 60 * 1000;
          break;
        case AutoDeleteDuration.sevenDays:
          deleteAfterMillis = 7 * 24 * 60 * 60 * 1000;
          break;
        case AutoDeleteDuration.thirtyDays:
          deleteAfterMillis = 30 * 24 * 60 * 60 * 1000;
          break;
        case AutoDeleteDuration.custom:
          if (customHours != null) {
            deleteAfterMillis = customHours * 60 * 60 * 1000;
          }
          break;
        case AutoDeleteDuration.never:
          deleteAfterMillis = null;
          break;
      }

      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .set({
        'autoDeleteEnabled': duration != AutoDeleteDuration.never,
        'autoDeleteDuration': deleteAfterMillis,
        'autoDeleteUpdatedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      }, SetOptions(merge: true));

      print(' Auto-delete set: ${duration.name}, ${deleteAfterMillis}ms');

      
      if (deleteAfterMillis != null) {
        await deleteExpiredMessages(conversationId);
      }

      return true;
    } catch (e) {
      print(' Error setting auto-delete: $e');
      return false;
    }
  }

  
  Future<void> markMessageForDeletion({
    required String groupChatId,
    required String messageId,
    required int deleteAfterMillis,
  }) async {
    try {
      final deleteAt = DateTime.now().millisecondsSinceEpoch + deleteAfterMillis;

      await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .doc(messageId)
          .update({
        'autoDeleteAt': deleteAt.toString(),
      });

      print(' Message marked for deletion at: ${DateTime.fromMillisecondsSinceEpoch(deleteAt)}');
    } catch (e) {
      print(' Error marking message: $e');
    }
  }

  
  Future<void> deleteExpiredMessages(String groupChatId) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      
      final expiredMessages = await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .where('autoDeleteAt', isLessThanOrEqualTo: now.toString())
          .get();

      if (expiredMessages.docs.isEmpty) {
        return;
      }

      print(' Deleting ${expiredMessages.docs.length} expired messages');

      final batch = firebaseFirestore.batch();

      for (var doc in expiredMessages.docs) {
        
        batch.update(doc.reference, {
          'isDeleted': true,
          'content': 'This message was automatically deleted',
          'deletedAt': now.toString(),
        });
      }

      await batch.commit();
      print(' Expired messages deleted');
    } catch (e) {
      print(' Error deleting expired messages: $e');
    }
  }

  
  Future<Map<String, dynamic>?> getAutoDeleteSettings(
      String conversationId) async {
    try {
      final doc = await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null && data.containsKey('autoDeleteEnabled')) {
          return {
            'enabled': data['autoDeleteEnabled'] ?? false,
            'duration': data['autoDeleteDuration'],
          };
        }
      }

      return null;
    } catch (e) {
      print(' Error getting auto-delete settings: $e');
      return null;
    }
  }

  
  Future<void> scheduleMessageDeletion({
    required String groupChatId,
    required String messageId,
    required String conversationId,
  }) async {
    try {
      final settings = await getAutoDeleteSettings(conversationId);

      if (settings != null &&
          settings['enabled'] == true &&
          settings['duration'] != null) {
        await markMessageForDeletion(
          groupChatId: groupChatId,
          messageId: messageId,
          deleteAfterMillis: settings['duration'] as int,
        );

        
        final duration = settings['duration'] as int;
        Timer(Duration(milliseconds: duration + 5000), () {
          deleteExpiredMessages(groupChatId);
        });
      }
    } catch (e) {
      print(' Error scheduling message deletion: $e');
    }
  }

  
  void dispose() {
    _cleanupTimer?.cancel();
  }
}