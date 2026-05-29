import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

enum AutoDeleteDuration {
  never,
  oneDay,
  sevenDays,
  thirtyDays,
  custom,
}

extension AutoDeleteDurationExtension on AutoDeleteDuration {
  String get label {
    switch (this) {
      case AutoDeleteDuration.never:
        return 'Never';
      case AutoDeleteDuration.oneDay:
        return '1 Day';
      case AutoDeleteDuration.sevenDays:
        return '7 Days';
      case AutoDeleteDuration.thirtyDays:
        return '30 Days';
      case AutoDeleteDuration.custom:
        return 'Custom';
    }
  }

  int? get milliseconds {
    switch (this) {
      case AutoDeleteDuration.never:
        return null;
      case AutoDeleteDuration.oneDay:
        return 24 * 60 * 60 * 1000;
      case AutoDeleteDuration.sevenDays:
        return 7 * 24 * 60 * 60 * 1000;
      case AutoDeleteDuration.thirtyDays:
        return 30 * 24 * 60 * 60 * 1000;
      case AutoDeleteDuration.custom:
        return null;
    }
  }

  static AutoDeleteDuration fromMilliseconds(int? ms) {
    if (ms == null) return AutoDeleteDuration.never;
    if (ms == 24 * 60 * 60 * 1000) return AutoDeleteDuration.oneDay;
    if (ms == 7 * 24 * 60 * 60 * 1000) return AutoDeleteDuration.sevenDays;
    if (ms == 30 * 24 * 60 * 60 * 1000) return AutoDeleteDuration.thirtyDays;
    return AutoDeleteDuration.custom;
  }
}

class AutoDeleteSettings {
  final bool enabled;
  final AutoDeleteDuration duration;
  final int? customMilliseconds;
  final DateTime? updatedAt;

  const AutoDeleteSettings({
    required this.enabled,
    required this.duration,
    this.customMilliseconds,
    this.updatedAt,
  });

  int? get effectiveMilliseconds =>
      duration == AutoDeleteDuration.custom ? customMilliseconds : duration.milliseconds;

  factory AutoDeleteSettings.disabled() => const AutoDeleteSettings(
        enabled: false,
        duration: AutoDeleteDuration.never,
      );

  factory AutoDeleteSettings.fromMap(Map<String, dynamic> data) {
    final ms = data['autoDeleteDuration'] as int?;
    return AutoDeleteSettings(
      enabled: data['autoDeleteEnabled'] as bool? ?? false,
      duration: AutoDeleteDurationExtension.fromMilliseconds(ms),
      customMilliseconds: ms,
      updatedAt: data['autoDeleteUpdatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(data['autoDeleteUpdatedAt'].toString()) ?? 0)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'autoDeleteEnabled': enabled,
        'autoDeleteDuration': effectiveMilliseconds,
        'autoDeleteUpdatedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      };
}

class AutoDeleteProvider {
  final FirebaseFirestore firebaseFirestore;
  Timer? _cleanupTimer;
  bool _isRunning = false;

  static const Duration _cleanupInterval = Duration(minutes: 5);
  static const int _batchSize = 500;

  AutoDeleteProvider({required this.firebaseFirestore}) {
    _startCleanupTimer();
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => _runGlobalCleanup());
  }

  Future<void> _runGlobalCleanup() async {
    if (_isRunning) return;
    _isRunning = true;
    try {
      final conversations = await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .where('autoDeleteEnabled', isEqualTo: true)
          .get();

      final futures = conversations.docs
          .where((doc) => doc.data()['autoDeleteDuration'] != null)
          .map((doc) => deleteExpiredMessages(doc.id));

      await Future.wait(futures, eagerError: false);
    } catch (e) {
      debugPrint('❌ Error in global cleanup: $e');
    } finally {
      _isRunning = false;
    }
  }

  Future<bool> setAutoDelete({
    required String conversationId,
    required AutoDeleteDuration duration,
    int? customHours,
  }) async {
    try {
      int? deleteAfterMillis = duration == AutoDeleteDuration.custom
          ? (customHours != null ? customHours * 60 * 60 * 1000 : null)
          : duration.milliseconds;

      final settings = AutoDeleteSettings(
        enabled: duration != AutoDeleteDuration.never,
        duration: duration,
        customMilliseconds: deleteAfterMillis,
      );

      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .set(settings.toMap(), SetOptions(merge: true));

      if (deleteAfterMillis != null) {
        await deleteExpiredMessages(conversationId);
      }

      return true;
    } catch (e) {
      debugPrint('❌ Error setting auto-delete: $e');
      return false;
    }
  }

  Future<AutoDeleteSettings?> getAutoDeleteSettings(String conversationId) async {
    try {
      final doc = await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .get();

      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null || !data.containsKey('autoDeleteEnabled')) return null;
      return AutoDeleteSettings.fromMap(data);
    } catch (e) {
      debugPrint('❌ Error getting auto-delete settings: $e');
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
      if (settings == null || !settings.enabled || settings.effectiveMilliseconds == null) {
        return;
      }

      await markMessageForDeletion(
        groupChatId: groupChatId,
        messageId: messageId,
        deleteAfterMillis: settings.effectiveMilliseconds!,
      );

      Timer(
        Duration(milliseconds: settings.effectiveMilliseconds! + 5000),
        () => deleteExpiredMessages(groupChatId),
      );
    } catch (e) {
      debugPrint('❌ Error scheduling message deletion: $e');
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
          .update({'autoDeleteAt': deleteAt.toString()});
    } catch (e) {
      debugPrint('❌ Error marking message for deletion: $e');
    }
  }

  Future<int> deleteExpiredMessages(String groupChatId) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      final expiredMessages = await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .where('autoDeleteAt', isLessThanOrEqualTo: now.toString())
          .get();

      if (expiredMessages.docs.isEmpty) return 0;

      int deleted = 0;
      WriteBatch batch = firebaseFirestore.batch();
      int batchCount = 0;

      for (final doc in expiredMessages.docs) {
        batch.update(doc.reference, {
          'isDeleted': true,
          'content': 'This message was automatically deleted',
          'deletedAt': now.toString(),
          'autoDeleteAt': FieldValue.delete(),
        });
        batchCount++;
        deleted++;

        if (batchCount >= _batchSize) {
          await batch.commit();
          batch = firebaseFirestore.batch();
          batchCount = 0;
        }
      }

      if (batchCount > 0) await batch.commit();
      return deleted;
    } catch (e) {
      debugPrint('❌ Error deleting expired messages: $e');
      return 0;
    }
  }

  Future<void> cancelAutoDelete(String conversationId) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .update({
        'autoDeleteEnabled': false,
        'autoDeleteDuration': FieldValue.delete(),
        'autoDeleteUpdatedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      });

      final messages = await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(conversationId)
          .collection(conversationId)
          .where('autoDeleteAt', isGreaterThan: '0')
          .get();

      if (messages.docs.isNotEmpty) {
        WriteBatch batch = firebaseFirestore.batch();
        int count = 0;
        for (final doc in messages.docs) {
          batch.update(doc.reference, {'autoDeleteAt': FieldValue.delete()});
          count++;
          if (count >= _batchSize) {
            await batch.commit();
            batch = firebaseFirestore.batch();
            count = 0;
          }
        }
        if (count > 0) await batch.commit();
      }
    } catch (e) {
      debugPrint('❌ Error cancelling auto-delete: $e');
    }
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }
}
