// lib/providers/conversation_lock_provider.dart
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

  Future<Map<String, dynamic>> verifyPIN({
    required String conversationId,
    required String enteredPin,
  }) async {
    try {
      print('🔍 Verifying PIN for: $conversationId');
      final lockDoc = await firebaseFirestore
          .collection('conversation_locks')
          .doc(conversationId)
          .get();

      if (!lockDoc.exists) {
        return {'success': false, 'message': 'No PIN set', 'failedAttempts': 0};
      }

      final data = lockDoc.data()!;
      final savedHashedPin = data['hashedPin'] as String;
      final failedAttempts = (data['failedAttempts'] as int?) ?? 0;
      final lockedUntil = data['lockedUntil'] as Timestamp?;

      if (lockedUntil != null) {
        final now = DateTime.now();
        final unlockTime = lockedUntil.toDate();
        if (now.isBefore(unlockTime)) {
          final remaining = unlockTime.difference(now).inMinutes + 1;
          return {
            'success': false,
            'message': 'Locked for $remaining minutes.',
            'failedAttempts': failedAttempts,
            'locked': true,
          };
        } else {
          await firebaseFirestore
              .collection('conversation_locks')
              .doc(conversationId)
              .update({'lockedUntil': null, 'failedAttempts': 0});
        }
      }

      final isCorrect = _hashPIN(enteredPin) == savedHashedPin;
      if (isCorrect) {
        await firebaseFirestore
            .collection('conversation_locks')
            .doc(conversationId)
            .update({
          'failedAttempts': 0,
          'lockedUntil': null,
          'lastAccessedAt': FieldValue.serverTimestamp(),
        });
        return {'success': true, 'message': 'PIN correct', 'failedAttempts': 0};
      } else {
        final newFailed = failedAttempts + 1;
        final Map<String, dynamic> updateData = {
          'failedAttempts': newFailed,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (newFailed >= 5) {
          updateData['lockedUntil'] = Timestamp.fromDate(
              DateTime.now().add(const Duration(minutes: 30)));
        }
        await firebaseFirestore
            .collection('conversation_locks')
            .doc(conversationId)
            .update(updateData);
        return {
          'success': false,
          'message': newFailed >= 5
              ? 'Too many failed attempts. Locked 30 minutes.'
              : 'Incorrect PIN. ${5 - newFailed} attempts remaining.',
          'failedAttempts': newFailed,
          'locked': newFailed >= 5,
        };
      }
    } catch (e) {
      print('❌ Error verifying PIN: $e');
      return {'success': false, 'message': 'Error: $e', 'failedAttempts': 0};
    }
  }

  /// FIX #3b: Batch reuse bug — tạo batch MỚI sau mỗi 500 operations.
  ///
  /// Trước (BUG):
  ///   final batch = db.batch();  // tạo 1 lần
  ///   ...
  ///   if (count >= 500) {
  ///     await batch.commit();    // commit lần 1 OK
  ///     count = 0;               // reset count nhưng dùng lại batch cũ!
  ///   }
  ///   if (count > 0) {
  ///     await batch.commit();    // commit lần 2 trên batch đã commit → CRASH
  ///   }
  ///
  /// Sau (FIX):
  ///   WriteBatch currentBatch = db.batch();  // tái tạo batch khi cần
  ///   ...
  ///   if (count >= 500) {
  ///     await currentBatch.commit();
  ///     currentBatch = db.batch();  // tạo INSTANCE MỚI
  ///     count = 0;
  ///   }
  Future<void> autoDeleteMessagesAfterFailedAttempts({
    required String conversationId,
  }) async {
    try {
      print('🗑️ Starting auto-delete for: $conversationId');

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

      // FIX: Dùng WriteBatch variable, tái tạo sau mỗi 500 ops
      WriteBatch currentBatch = firebaseFirestore.batch();
      int count = 0;
      int totalDeleted = 0;

      for (final doc in messagesSnapshot.docs) {
        currentBatch.update(doc.reference, {
          'isDeleted': true,
          'content': 'Messages deleted due to security breach',
          'deletedAt': DateTime.now().millisecondsSinceEpoch.toString(),
        });
        count++;
        totalDeleted++;

        if (count >= 500) {
          await currentBatch.commit();
          // FIX: Tạo INSTANCE MỚI, không reuse instance đã committed
          currentBatch = firebaseFirestore.batch();
          count = 0;
          print('✅ Committed batch (${totalDeleted} total so far)');
        }
      }

      // Commit remaining operations trong batch cuối
      if (count > 0) {
        await currentBatch.commit();
        print('✅ Committed final batch');
      }

      print('✅ All $totalDeleted messages deleted');

      await firebaseFirestore
          .collection('conversation_locks')
          .doc(conversationId)
          .update({
        'messagesAutoDeleted': true,
        'autoDeletedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Error auto-deleting messages: $e');
      rethrow;
    }
  }

  Future<bool> removeConversationLock(String conversationId) async {
    try {
      await firebaseFirestore
          .collection('conversation_locks')
          .doc(conversationId)
          .delete();
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .set({'isLocked': false, 'lockType': null}, SetOptions(merge: true));
      return true;
    } catch (e) {
      print('❌ Error removing lock: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getConversationLockStatus(
      String conversationId) async {
    try {
      final lockDoc = await firebaseFirestore
          .collection('conversation_locks')
          .doc(conversationId)
          .get();

      if (!lockDoc.exists) return null;

      final data = lockDoc.data()!;
      final lockedUntil = data['lockedUntil'] as Timestamp?;
      final failedAttempts = (data['failedAttempts'] as int?) ?? 0;
      bool isTemporarilyLocked = false;
      DateTime? unlockTime;

      if (lockedUntil != null) {
        unlockTime = lockedUntil.toDate();
        isTemporarilyLocked = DateTime.now().isBefore(unlockTime);
      }

      return {
        'isLocked': data['isLocked'] ?? true,
        'lockType': 'pin',
        'failedAttempts': failedAttempts,
        'temporarilyLocked': isTemporarilyLocked,
        'lockedUntil': unlockTime,
      };
    } catch (e) {
      print('❌ Error getting lock status: $e');
      return null;
    }
  }

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
      return 0;
    }
  }
}
