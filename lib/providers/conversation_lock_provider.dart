import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

enum LockType { pin, none }

class LockStatus {
  final bool isLocked;
  final LockType lockType;
  final int failedAttempts;
  final bool temporarilyLocked;
  final DateTime? lockedUntil;
  final bool messagesAutoDeleted;

  const LockStatus({
    required this.isLocked,
    required this.lockType,
    required this.failedAttempts,
    required this.temporarilyLocked,
    this.lockedUntil,
    this.messagesAutoDeleted = false,
  });

  bool get isAccessible => !temporarilyLocked;
  int get remainingAttempts => (5 - failedAttempts).clamp(0, 5);

  factory LockStatus.unlocked() => const LockStatus(
        isLocked: false,
        lockType: LockType.none,
        failedAttempts: 0,
        temporarilyLocked: false,
      );

  factory LockStatus.fromMap(Map<String, dynamic> data) {
    final lockedUntil = data['lockedUntil'] as Timestamp?;
    final unlockTime = lockedUntil?.toDate();
    final isTemporarilyLocked = unlockTime != null && DateTime.now().isBefore(unlockTime);

    return LockStatus(
      isLocked: data['isLocked'] as bool? ?? true,
      lockType: LockType.pin,
      failedAttempts: data['failedAttempts'] as int? ?? 0,
      temporarilyLocked: isTemporarilyLocked,
      lockedUntil: unlockTime,
      messagesAutoDeleted: data['messagesAutoDeleted'] as bool? ?? false,
    );
  }
}

class VerifyResult {
  final bool success;
  final String message;
  final int failedAttempts;
  final bool locked;

  const VerifyResult({
    required this.success,
    required this.message,
    required this.failedAttempts,
    this.locked = false,
  });
}

class ConversationLockProvider {
  final FirebaseFirestore firebaseFirestore;

  static const int _maxFailedAttempts = 5;
  static const int _lockDurationMinutes = 30;
  static const int _batchSize = 500;
  static const String _locksCollection = 'conversation_locks';

  ConversationLockProvider({required this.firebaseFirestore});

  

  String _hashPIN(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  

  Future<bool> setConversationPIN({
    required String conversationId,
    required String pin,
  }) async {
    try {
      if (pin.length < 4) return false;

      final hashedPin = _hashPIN(pin);
      final now = FieldValue.serverTimestamp();

      final batch = firebaseFirestore.batch();

      final lockRef = firebaseFirestore.collection(_locksCollection).doc(conversationId);

      batch.set(lockRef, {
        'conversationId': conversationId,
        'hashedPin': hashedPin,
        'isLocked': true,
        'failedAttempts': 0,
        'lockedUntil': null,
        'messagesAutoDeleted': false,
        'createdAt': now,
        'updatedAt': now,
      });

      final convRef = firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId);

      batch.set(
          convRef,
          {
            'isLocked': true,
            'lockType': 'pin',
            'lockedAt': DateTime.now().millisecondsSinceEpoch.toString(),
          },
          SetOptions(merge: true));

      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('❌ Error setting PIN: $e');
      return false;
    }
  }

  Future<bool> changePIN({
    required String conversationId,
    required String currentPin,
    required String newPin,
  }) async {
    try {
      final verifyResult = await verifyPIN(
        conversationId: conversationId,
        enteredPin: currentPin,
      );
      if (!verifyResult.success) return false;

      return setConversationPIN(
        conversationId: conversationId,
        pin: newPin,
      );
    } catch (e) {
      debugPrint('❌ Error changing PIN: $e');
      return false;
    }
  }

  Future<bool> removeConversationLock(String conversationId) async {
    try {
      final batch = firebaseFirestore.batch();

      batch.delete(
        firebaseFirestore.collection(_locksCollection).doc(conversationId),
      );

      batch.set(
        firebaseFirestore
            .collection(FirestoreConstants.pathConversationCollection)
            .doc(conversationId),
        {'isLocked': false, 'lockType': null},
        SetOptions(merge: true),
      );

      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('❌ Error removing lock: $e');
      return false;
    }
  }

  

  Future<VerifyResult> verifyPIN({
    required String conversationId,
    required String enteredPin,
  }) async {
    try {
      final lockDoc =
          await firebaseFirestore.collection(_locksCollection).doc(conversationId).get();

      if (!lockDoc.exists) {
        return const VerifyResult(
          success: false,
          message: 'No PIN set for this conversation',
          failedAttempts: 0,
        );
      }

      final data = lockDoc.data()!;
      final savedHash = data['hashedPin'] as String;
      final failedAttempts = data['failedAttempts'] as int? ?? 0;
      final lockedUntil = data['lockedUntil'] as Timestamp?;

      
      if (lockedUntil != null) {
        final now = DateTime.now();
        final unlockTime = lockedUntil.toDate();

        if (now.isBefore(unlockTime)) {
          final remaining = unlockTime.difference(now).inMinutes + 1;
          return VerifyResult(
            success: false,
            message: 'Too many failed attempts. Try again in $remaining minutes.',
            failedAttempts: failedAttempts,
            locked: true,
          );
        } else {
          
          await firebaseFirestore
              .collection(_locksCollection)
              .doc(conversationId)
              .update({'lockedUntil': null, 'failedAttempts': 0});
        }
      }

      final isCorrect = _hashPIN(enteredPin) == savedHash;

      if (isCorrect) {
        await firebaseFirestore.collection(_locksCollection).doc(conversationId).update({
          'failedAttempts': 0,
          'lockedUntil': null,
          'lastAccessedAt': FieldValue.serverTimestamp(),
        });

        return const VerifyResult(
          success: true,
          message: 'Access granted',
          failedAttempts: 0,
        );
      } else {
        final newFailed = failedAttempts + 1;
        final Map<String, dynamic> update = {
          'failedAttempts': newFailed,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        bool willLock = false;
        if (newFailed >= _maxFailedAttempts) {
          willLock = true;
          update['lockedUntil'] = Timestamp.fromDate(
            DateTime.now().add(Duration(minutes: _lockDurationMinutes)),
          );
        }

        await firebaseFirestore.collection(_locksCollection).doc(conversationId).update(update);

        
        if (willLock) {
          await autoDeleteMessagesAfterFailedAttempts(conversationId: conversationId);
        }

        final remaining = _maxFailedAttempts - newFailed;
        return VerifyResult(
          success: false,
          message: willLock
              ? 'Too many failed attempts. Conversation locked for $_lockDurationMinutes minutes and messages deleted.'
              : 'Incorrect PIN. $remaining attempt${remaining == 1 ? '' : 's'} remaining.',
          failedAttempts: newFailed,
          locked: willLock,
        );
      }
    } catch (e) {
      debugPrint('❌ Error verifying PIN: $e');
      return VerifyResult(
        success: false,
        message: 'An error occurred. Please try again.',
        failedAttempts: 0,
      );
    }
  }

  

  Future<void> autoDeleteMessagesAfterFailedAttempts({
    required String conversationId,
  }) async {
    try {
      final messagesSnapshot = await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(conversationId)
          .collection(conversationId)
          .get();

      if (messagesSnapshot.docs.isEmpty) return;

      WriteBatch batch = firebaseFirestore.batch();
      int count = 0;
      int total = 0;
      final now = DateTime.now().millisecondsSinceEpoch.toString();

      for (final doc in messagesSnapshot.docs) {
        batch.update(doc.reference, {
          'isDeleted': true,
          'content': 'Messages deleted due to security breach',
          'deletedAt': now,
        });
        count++;
        total++;

        if (count >= _batchSize) {
          await batch.commit();
          batch = firebaseFirestore.batch();
          count = 0;
        }
      }

      if (count > 0) await batch.commit();

      await firebaseFirestore.collection(_locksCollection).doc(conversationId).update({
        'messagesAutoDeleted': true,
        'autoDeletedAt': FieldValue.serverTimestamp(),
      });

      
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update({
        FirestoreConstants.lastMessage: '🔒 Messages were cleared',
        FirestoreConstants.lastMessageTime: DateTime.now().millisecondsSinceEpoch.toString(),
      });

      debugPrint('✅ Auto-deleted $total messages due to security breach');
    } catch (e) {
      debugPrint('❌ Error auto-deleting messages: $e');
      rethrow;
    }
  }

  

  Future<LockStatus?> getConversationLockStatus(String conversationId) async {
    try {
      final lockDoc =
          await firebaseFirestore.collection(_locksCollection).doc(conversationId).get();

      if (!lockDoc.exists) return null;
      return LockStatus.fromMap(lockDoc.data()!);
    } catch (e) {
      debugPrint('❌ Error getting lock status: $e');
      return null;
    }
  }

  Future<int> getFailedAttempts(String conversationId) async {
    try {
      final doc = await firebaseFirestore.collection(_locksCollection).doc(conversationId).get();
      return (doc.data()?['failedAttempts'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Stream<LockStatus?> watchLockStatus(String conversationId) {
    return firebaseFirestore
        .collection(_locksCollection)
        .doc(conversationId)
        .snapshots()
        .map((snap) => snap.exists ? LockStatus.fromMap(snap.data()!) : null);
  }
}
