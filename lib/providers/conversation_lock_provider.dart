// lib/providers/conversation_lock_provider.dart (COMPLETE FIX)
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class ConversationLockProvider {
  final FirebaseFirestore firebaseFirestore;

  ConversationLockProvider({required this.firebaseFirestore});

  String _hashPIN(String pin) {
    final bytes = utf8.encode(pin);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  // Set PIN for conversation
  Future<bool> setConversationPIN({
    required String conversationId,
    required String pin,
  }) async {
    try {
      final hashedPin = _hashPIN(pin);

      await firebaseFirestore
          .collection('conversation_locks')
          .doc(conversationId)
          .set({
        'conversationId': conversationId,
        'hashedPin': hashedPin,
        'isLocked': true,
        'failedAttempts': 0,
        'lockedUntil': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .set({
        'isLocked': true,
        'lockType': 'pin',
        'lockedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      }, SetOptions(merge: true));

      print('✅ PIN lock set successfully');
      return true;
    } catch (e) {
      print('❌ Error setting PIN: $e');
      return false;
    }
  }

  // Verify PIN - CRITICAL FIX
  Future<Map<String, dynamic>> verifyPIN({
    required String conversationId,
    required String enteredPin,
  }) async {
    try {
      print('🔍 Verifying PIN for conversation: $conversationId');

      final lockDoc = await firebaseFirestore
          .collection('conversation_locks')
          .doc(conversationId)
          .get();

      if (!lockDoc.exists) {
        print('❌ No lock document found');
        return {
          'success': false,
          'message': 'No PIN set for this conversation',
          'failedAttempts': 0,
        };
      }

      final data = lockDoc.data()!;
      final savedHashedPin = data['hashedPin'] as String;
      final failedAttempts = (data['failedAttempts'] as int?) ?? 0;
      final lockedUntil = data['lockedUntil'] as Timestamp?;

      print('🔐 Current failed attempts: $failedAttempts');

      // Check if temporarily locked
      if (lockedUntil != null) {
        final now = DateTime.now();
        final unlockTime = lockedUntil.toDate();

        if (now.isBefore(unlockTime)) {
          final remainingMinutes = unlockTime.difference(now).inMinutes + 1;
          print('⏰ Still locked for $remainingMinutes minutes');

          return {
            'success': false,
            'message':
                'Too many failed attempts. Try again in $remainingMinutes minutes.',
            'failedAttempts': failedAttempts,
            'locked': true,
          };
        } else {
          // Time expired, reset lock
          print('🔓 Lock expired, resetting...');
          await firebaseFirestore
              .collection('conversation_locks')
              .doc(conversationId)
              .update({
            'lockedUntil': null,
            'failedAttempts': 0,
          });
        }
      }

      // Verify PIN
      final enteredHashedPin = _hashPIN(enteredPin);
      final isCorrect = enteredHashedPin == savedHashedPin;

      print('🔑 PIN match: $isCorrect');

      if (isCorrect) {
        // CRITICAL: Reset failed attempts on success
        await firebaseFirestore
            .collection('conversation_locks')
            .doc(conversationId)
            .update({
          'failedAttempts': 0,
          'lockedUntil': null,
          'lastAccessedAt': FieldValue.serverTimestamp(),
        });

        print('✅ PIN verified successfully, failed attempts reset');

        return {
          'success': true,
          'message': 'PIN correct',
          'failedAttempts': 0,
        };
      } else {
        // Increment failed attempts
        final newFailedAttempts = failedAttempts + 1;
        print('❌ Incorrect PIN. Attempt $newFailedAttempts/5');

        Map<String, dynamic> updateData = {
          'failedAttempts': newFailedAttempts,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // Lock for 30 minutes after 5 failed attempts
        if (newFailedAttempts >= 5) {
          final lockUntil = DateTime.now().add(Duration(minutes: 30));
          updateData['lockedUntil'] = Timestamp.fromDate(lockUntil);
          print('🔒 Locking conversation for 30 minutes');
        }

        await firebaseFirestore
            .collection('conversation_locks')
            .doc(conversationId)
            .update(updateData);

        return {
          'success': false,
          'message': newFailedAttempts >= 5
              ? 'Too many failed attempts. Locked for 30 minutes.'
              : 'Incorrect PIN. ${5 - newFailedAttempts} attempts remaining.',
          'failedAttempts': newFailedAttempts,
          'locked': newFailedAttempts >= 5,
        };
      }
    } catch (e) {
      print('❌ Error verifying PIN: $e');
      return {
        'success': false,
        'message': 'Error verifying PIN: $e',
        'failedAttempts': 0,
      };
    }
  }

  // Auto-delete messages - FIXED
  Future<void> autoDeleteMessagesAfterFailedAttempts({
    required String conversationId,
  }) async {
    try {
      print('🗑️ Starting auto-delete for conversation: $conversationId');

      // Get all messages
      final messagesSnapshot = await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(conversationId)
          .collection(conversationId)
          .get();

      if (messagesSnapshot.docs.isEmpty) {
        print('ℹ️ No messages to delete');
        return;
      }

      print('🗑️ Deleting ${messagesSnapshot.docs.length} messages');

      // Batch delete
      final batch = firebaseFirestore.batch();
      int count = 0;

      for (var doc in messagesSnapshot.docs) {
        batch.update(doc.reference, {
          'isDeleted': true,
          'content': 'Messages deleted due to security breach',
          'deletedAt': DateTime.now().millisecondsSinceEpoch.toString(),
        });
        count++;

        // Commit every 500 operations (Firestore batch limit)
        if (count >= 500) {
          await batch.commit();
          count = 0;
        }
      }

      // Commit remaining
      if (count > 0) {
        await batch.commit();
      }

      print('✅ All messages deleted successfully');

      // Update lock status
      await firebaseFirestore
          .collection('conversation_locks')
          .doc(conversationId)
          .update({
        'messagesAutoDeleted': true,
        'autoDeletedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Lock status updated');
    } catch (e) {
      print('❌ Error auto-deleting messages: $e');
      rethrow;
    }
  }

  // Remove lock
  Future<bool> removeConversationLock(String conversationId) async {
    try {
      await firebaseFirestore
          .collection('conversation_locks')
          .doc(conversationId)
          .delete();

      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .set({
        'isLocked': false,
        'lockType': null,
      }, SetOptions(merge: true));

      print('✅ Lock removed successfully');
      return true;
    } catch (e) {
      print('❌ Error removing lock: $e');
      return false;
    }
  }

  // Get lock status - FIXED
  Future<Map<String, dynamic>?> getConversationLockStatus(
      String conversationId) async {
    try {
      print('🔍 Getting lock status for: $conversationId');

      final lockDoc = await firebaseFirestore
          .collection('conversation_locks')
          .doc(conversationId)
          .get();

      if (lockDoc.exists) {
        final data = lockDoc.data()!;
        final lockedUntil = data['lockedUntil'] as Timestamp?;
        final failedAttempts = (data['failedAttempts'] as int?) ?? 0;

        bool isTemporarilyLocked = false;
        DateTime? unlockTime;

        if (lockedUntil != null) {
          unlockTime = lockedUntil.toDate();
          isTemporarilyLocked = DateTime.now().isBefore(unlockTime);
        }

        print(
            '🔐 Lock status: attempts=$failedAttempts, locked=$isTemporarilyLocked');

        return {
          'isLocked': data['isLocked'] ?? true,
          'lockType': 'pin',
          'failedAttempts': failedAttempts,
          'temporarilyLocked': isTemporarilyLocked,
          'lockedUntil': unlockTime,
        };
      }

      print('ℹ️ No lock found');
      return null;
    } catch (e) {
      print('❌ Error getting lock status: $e');
      return null;
    }
  }

  // Get failed attempts count
  Future<int> getFailedAttempts(String conversationId) async {
    try {
      final lockDoc = await firebaseFirestore
          .collection('conversation_locks')
          .doc(conversationId)
          .get();

      if (lockDoc.exists) {
        return (lockDoc.data()?['failedAttempts'] as int?) ?? 0;
      }
      return 0;
    } catch (e) {
      print('❌ Error getting failed attempts: $e');
      return 0;
    }
  }
}
