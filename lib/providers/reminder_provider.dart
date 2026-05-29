import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;





enum ReminderRepeat { none, daily, weekly, monthly }

class MessageReminder {
  final String id;
  final String userId;
  final String messageId;
  final String conversationId;
  final DateTime reminderTime;
  final String message;
  final String? senderName;
  final String? senderAvatar;
  final bool isCompleted;
  final ReminderRepeat repeat;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? note;

  const MessageReminder({
    required this.id,
    required this.userId,
    required this.messageId,
    required this.conversationId,
    required this.reminderTime,
    required this.message,
    this.senderName,
    this.senderAvatar,
    this.isCompleted = false,
    this.repeat = ReminderRepeat.none,
    required this.createdAt,
    this.completedAt,
    this.note,
  });

  bool get isExpired => reminderTime.isBefore(DateTime.now()) && !isCompleted;

  bool get isDueWithinHour =>
      !isCompleted &&
      reminderTime.isAfter(DateTime.now()) &&
      reminderTime.difference(DateTime.now()).inMinutes <= 60;

  Duration get timeUntilReminder => reminderTime.difference(DateTime.now());

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'messageId': messageId,
        'conversationId': conversationId,
        'reminderTime': reminderTime.millisecondsSinceEpoch.toString(),
        'message': message,
        'senderName': senderName,
        'senderAvatar': senderAvatar,
        'isCompleted': isCompleted,
        'repeat': repeat.name,
        'createdAt': createdAt.millisecondsSinceEpoch.toString(),
        'completedAt': completedAt?.millisecondsSinceEpoch.toString(),
        'note': note,
      };

  MessageReminder copyWith({
    String? id,
    String? userId,
    String? messageId,
    String? conversationId,
    DateTime? reminderTime,
    String? message,
    String? senderName,
    String? senderAvatar,
    bool? isCompleted,
    ReminderRepeat? repeat,
    DateTime? createdAt,
    DateTime? completedAt,
    String? note,
  }) =>
      MessageReminder(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        messageId: messageId ?? this.messageId,
        conversationId: conversationId ?? this.conversationId,
        reminderTime: reminderTime ?? this.reminderTime,
        message: message ?? this.message,
        senderName: senderName ?? this.senderName,
        senderAvatar: senderAvatar ?? this.senderAvatar,
        isCompleted: isCompleted ?? this.isCompleted,
        repeat: repeat ?? this.repeat,
        createdAt: createdAt ?? this.createdAt,
        completedAt: completedAt ?? this.completedAt,
        note: note ?? this.note,
      );

  factory MessageReminder.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) throw Exception('Reminder document data is null');

    DateTime parseDateTime(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is String) {
        final ms = int.tryParse(value);
        return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : DateTime.now();
      }
      if (value is Timestamp) return value.toDate();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      return DateTime.now();
    }

    return MessageReminder(
      id: doc.id,
      userId: data['userId'] ?? '',
      messageId: data['messageId'] ?? '',
      conversationId: data['conversationId'] ?? '',
      reminderTime: parseDateTime(data['reminderTime']),
      message: data['message'] ?? '',
      senderName: data['senderName'] as String?,
      senderAvatar: data['senderAvatar'] as String?,
      isCompleted: data['isCompleted'] ?? false,
      repeat: ReminderRepeat.values.firstWhere(
        (r) => r.name == (data['repeat'] ?? 'none'),
        orElse: () => ReminderRepeat.none,
      ),
      createdAt: parseDateTime(data['createdAt']),
      completedAt: data['completedAt'] != null ? parseDateTime(data['completedAt']) : null,
      note: data['note'] as String?,
    );
  }
}





class ReminderProvider {
  final FirebaseFirestore firebaseFirestore;
  final FlutterLocalNotificationsPlugin notificationsPlugin;

  static const String _collection = 'reminders';

  
  static const String _channelId = 'message_reminders';
  static const String _channelName = 'Message Reminders';
  static const String _urgentChannelId = 'urgent_reminders';
  static const String _urgentChannelName = 'Urgent Reminders';

  ReminderProvider({
    required this.firebaseFirestore,
    required this.notificationsPlugin,
  });

  
  
  

  
  Future<MessageReminder?> scheduleReminder({
    required String userId,
    required String messageId,
    required String conversationId,
    required DateTime reminderTime,
    required String message,
    String? senderName,
    String? senderAvatar,
    ReminderRepeat repeat = ReminderRepeat.none,
    String? note,
  }) async {
    try {
      if (reminderTime.isBefore(DateTime.now())) {
        debugPrint('⚠️ Reminder time is in the past');
        return null;
      }

      final data = MessageReminder(
        id: '', 
        userId: userId,
        messageId: messageId,
        conversationId: conversationId,
        reminderTime: reminderTime,
        message: message,
        senderName: senderName,
        senderAvatar: senderAvatar,
        isCompleted: false,
        repeat: repeat,
        createdAt: DateTime.now(),
        note: note,
      );

      final docRef = await firebaseFirestore.collection(_collection).add(data.toJson());

      final notifId = docRef.id.hashCode.abs() % 2147483647;
      await _scheduleNotification(
        id: notifId,
        title: senderName != null ? 'Reminder from $senderName' : 'Message Reminder',
        body: message.length > 60 ? '${message.substring(0, 60)}…' : message,
        scheduledDate: reminderTime,
        payload: '$conversationId|${docRef.id}',
        isUrgent: reminderTime.difference(DateTime.now()).inMinutes <= 15,
      );

      debugPrint('✅ Reminder scheduled → ${reminderTime.toIso8601String()}');
      return data.copyWith(id: docRef.id);
    } catch (e) {
      debugPrint('❌ Error scheduling reminder: $e');
      return null;
    }
  }

  
  Future<bool> updateReminder({
    required String reminderId,
    required DateTime newReminderTime,
    String? newNote,
  }) async {
    try {
      if (newReminderTime.isBefore(DateTime.now())) {
        debugPrint('⚠️ New reminder time is in the past');
        return false;
      }

      final updates = <String, dynamic>{
        'reminderTime': newReminderTime.millisecondsSinceEpoch.toString(),
        if (newNote != null) 'note': newNote,
      };

      await firebaseFirestore.collection(_collection).doc(reminderId).update(updates);

      
      final oldId = reminderId.hashCode.abs() % 2147483647;
      await notificationsPlugin.cancel(oldId);

      final doc = await firebaseFirestore.collection(_collection).doc(reminderId).get();
      if (doc.exists) {
        final reminder = MessageReminder.fromDocument(doc);
        await _scheduleNotification(
          id: oldId,
          title: reminder.senderName != null
              ? 'Reminder from ${reminder.senderName}'
              : 'Message Reminder',
          body: reminder.message.length > 60
              ? '${reminder.message.substring(0, 60)}…'
              : reminder.message,
          scheduledDate: newReminderTime,
          payload: '${reminder.conversationId}|$reminderId',
          isUrgent: newReminderTime.difference(DateTime.now()).inMinutes <= 15,
        );
      }

      debugPrint('✅ Reminder updated → ${newReminderTime.toIso8601String()}');
      return true;
    } catch (e) {
      debugPrint('❌ Error updating reminder: $e');
      return false;
    }
  }

  
  
  

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
    bool isUrgent = false,
  }) async {
    try {
      final tz.TZDateTime scheduledTZ = tz.TZDateTime.from(scheduledDate, tz.local);

      final channelId = isUrgent ? _urgentChannelId : _channelId;
      final channelName = isUrgent ? _urgentChannelName : _channelName;

      await notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTZ,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: 'Scheduled message reminders',
            importance: isUrgent ? Importance.max : Importance.high,
            priority: isUrgent ? Priority.max : Priority.high,
            icon: 'app_icon',
            largeIcon: const DrawableResourceAndroidBitmap('app_icon'),
            playSound: true,
            enableVibration: true,
            styleInformation: BigTextStyleInformation(body),
            color: const Color(0xFF2196F3),
            category: AndroidNotificationCategory.reminder,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'default',
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );

      debugPrint('🔔 Notification scheduled → id:$id at $scheduledTZ');
    } catch (e) {
      debugPrint('❌ Error scheduling notification: $e');
      rethrow;
    }
  }

  
  
  

  Future<bool> completeReminder(String reminderId) async {
    try {
      await firebaseFirestore.collection(_collection).doc(reminderId).update({
        'isCompleted': true,
        'completedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      });

      await notificationsPlugin.cancel(reminderId.hashCode.abs() % 2147483647);

      debugPrint('✅ Reminder completed: $reminderId');
      return true;
    } catch (e) {
      debugPrint('❌ Error completing reminder: $e');
      return false;
    }
  }

  Future<bool> deleteReminder(String reminderId) async {
    try {
      await firebaseFirestore.collection(_collection).doc(reminderId).delete();
      await notificationsPlugin.cancel(reminderId.hashCode.abs() % 2147483647);
      debugPrint('✅ Reminder deleted: $reminderId');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting reminder: $e');
      return false;
    }
  }

  
  Future<bool> snoozeReminder(
    String reminderId, {
    Duration snoozeDuration = const Duration(minutes: 10),
  }) async {
    try {
      final newTime = DateTime.now().add(snoozeDuration);
      return await updateReminder(
        reminderId: reminderId,
        newReminderTime: newTime,
      );
    } catch (e) {
      debugPrint('❌ Error snoozing reminder: $e');
      return false;
    }
  }

  
  
  

  
  Stream<List<MessageReminder>> getUserRemindersStream(String userId) {
    return firebaseFirestore
        .collection(_collection)
        .where('userId', isEqualTo: userId)
        .where('isCompleted', isEqualTo: false)
        .orderBy('reminderTime')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(MessageReminder.fromDocument).toList());
  }

  
  Stream<List<MessageReminder>> getCompletedRemindersStream(
    String userId, {
    int limit = 50,
  }) {
    return firebaseFirestore
        .collection(_collection)
        .where('userId', isEqualTo: userId)
        .where('isCompleted', isEqualTo: true)
        .orderBy('completedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(MessageReminder.fromDocument).toList());
  }

  
  Future<List<MessageReminder>> getUpcomingReminders(
    String userId, {
    int minutes = 60,
  }) async {
    try {
      final now = DateTime.now();
      final cutoff = now.add(Duration(minutes: minutes));

      final snapshot = await firebaseFirestore
          .collection(_collection)
          .where('userId', isEqualTo: userId)
          .where('isCompleted', isEqualTo: false)
          .get();

      return snapshot.docs
          .map(MessageReminder.fromDocument)
          .where((r) => r.reminderTime.isAfter(now) && r.reminderTime.isBefore(cutoff))
          .toList()
        ..sort((a, b) => a.reminderTime.compareTo(b.reminderTime));
    } catch (e) {
      debugPrint('❌ Error getting upcoming reminders: $e');
      return [];
    }
  }

  
  Stream<int> getActiveReminderCount(String userId) {
    return firebaseFirestore
        .collection(_collection)
        .where('userId', isEqualTo: userId)
        .where('isCompleted', isEqualTo: false)
        .snapshots()
        .map((s) => s.size);
  }

  
  
  

  
  Future<void> checkExpiredReminders(String userId) async {
    try {
      final now = DateTime.now();
      final snapshot = await firebaseFirestore
          .collection(_collection)
          .where('userId', isEqualTo: userId)
          .where('isCompleted', isEqualTo: false)
          .get();

      for (final doc in snapshot.docs) {
        final reminder = MessageReminder.fromDocument(doc);
        if (reminder.reminderTime.isBefore(now)) {
          if (reminder.repeat != ReminderRepeat.none) {
            final nextTime = _nextRepeatTime(reminder);
            if (nextTime != null) {
              await updateReminder(
                reminderId: reminder.id,
                newReminderTime: nextTime,
              );
              continue;
            }
          }
          await completeReminder(reminder.id);
        }
      }
      debugPrint('✅ Expired reminders checked for user: $userId');
    } catch (e) {
      debugPrint('❌ Error checking expired reminders: $e');
    }
  }

  DateTime? _nextRepeatTime(MessageReminder reminder) {
    final base = reminder.reminderTime;
    switch (reminder.repeat) {
      case ReminderRepeat.daily:
        return base.add(const Duration(days: 1));
      case ReminderRepeat.weekly:
        return base.add(const Duration(days: 7));
      case ReminderRepeat.monthly:
        return DateTime(base.year, base.month + 1, base.day, base.hour, base.minute);
      case ReminderRepeat.none:
        return null;
    }
  }

  
  Future<void> cleanupOldReminders(
    String userId, {
    Duration olderThan = const Duration(days: 30),
  }) async {
    try {
      final cutoff = DateTime.now().subtract(olderThan);
      final snapshot = await firebaseFirestore
          .collection(_collection)
          .where('userId', isEqualTo: userId)
          .where('isCompleted', isEqualTo: true)
          .get();

      final batch = firebaseFirestore.batch();
      int count = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final completedAt = data['completedAt'];
        if (completedAt != null) {
          final ms = int.tryParse(completedAt.toString()) ?? 0;
          final dt = DateTime.fromMillisecondsSinceEpoch(ms);
          if (dt.isBefore(cutoff)) {
            batch.delete(doc.reference);
            count++;
          }
        }
      }
      await batch.commit();
      debugPrint('✅ Cleaned up $count old reminders for user: $userId');
    } catch (e) {
      debugPrint('❌ Error cleaning up old reminders: $e');
    }
  }

  
  Future<void> cancelAllNotifications() async {
    await notificationsPlugin.cancelAll();
    debugPrint('✅ All notifications cancelled');
  }
}
