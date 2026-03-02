import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class MessageReminder {
  final String id;
  final String messageId;
  final String conversationId;
  final String reminderTime;
  final String message;
  final bool isCompleted;

  const MessageReminder({
    required this.id,
    required this.messageId,
    required this.conversationId,
    required this.reminderTime,
    required this.message,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'conversationId': conversationId,
      'reminderTime': reminderTime,
      'message': message,
      'isCompleted': isCompleted,
    };
  }

  factory MessageReminder.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    if (data == null) {
      throw Exception('Reminder document data is null');
    }

    String _getStringValue(dynamic value) {
      if (value == null)
        return DateTime.now().millisecondsSinceEpoch.toString();
      if (value is String) return value;
      if (value is Timestamp) return value.millisecondsSinceEpoch.toString();
      if (value is int) return value.toString();
      return DateTime.now().millisecondsSinceEpoch.toString();
    }

    return MessageReminder(
      id: doc.id,
      messageId: data['messageId'] ?? '',
      conversationId: data['conversationId'] ?? '',
      reminderTime: _getStringValue(data['reminderTime']),
      message: data['message'] ?? '',
      isCompleted: data['isCompleted'] ?? false,
    );
  }
}

class ReminderProvider {
  final FirebaseFirestore firebaseFirestore;
  final FlutterLocalNotificationsPlugin notificationsPlugin;

  ReminderProvider({
    required this.firebaseFirestore,
    required this.notificationsPlugin,
  });

  // Schedule reminder with proper notification
  Future<bool> scheduleReminder({
    required String userId,
    required String messageId,
    required String conversationId,
    required DateTime reminderTime,
    required String message,
  }) async {
    try {
      // Ensure reminderTime is in the future
      if (reminderTime.isBefore(DateTime.now())) {
        print('Reminder time is in the past');
        return false;
      }

      // Create reminder document
      final reminderDoc = await firebaseFirestore.collection('reminders').add({
        'userId': userId,
        'messageId': messageId,
        'conversationId': conversationId,
        'reminderTime': reminderTime.millisecondsSinceEpoch.toString(),
        'message': message,
        'isCompleted': false,
        'createdAt': DateTime.now().millisecondsSinceEpoch.toString(),
      });

      // Schedule local notification
      await _scheduleNotification(
        id: reminderDoc.id.hashCode,
        title: 'Message Reminder',
        body: message.length > 50 ? '${message.substring(0, 50)}...' : message,
        scheduledDate: reminderTime,
      );

      print(' Reminder scheduled for: $reminderTime');
      return true;
    } catch (e) {
      print(' Error scheduling reminder: $e');
      return false;
    }
  }

  // Schedule notification with timezone support
  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    try {
      // Convert to TZ DateTime
      final tz.TZDateTime scheduledTZ = tz.TZDateTime.from(
        scheduledDate,
        tz.local,
      );

      print(' Scheduling notification for: $scheduledTZ');

      await notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTZ,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'message_reminders',
            'Message Reminders',
            channelDescription: 'Reminders for messages',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'app_icon',
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'default',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      print(' Notification scheduled successfully');
    } catch (e) {
      print(' Error scheduling notification: $e');
      rethrow;
    }
  }

  // Get user reminders
  Stream<QuerySnapshot> getUserReminders(String userId) {
    return firebaseFirestore
        .collection('reminders')
        .where('userId', isEqualTo: userId)
        .where('isCompleted', isEqualTo: false)
        .orderBy('reminderTime')
        .snapshots();
  }

  // Complete reminder
  Future<bool> completeReminder(String reminderId) async {
    try {
      await firebaseFirestore
          .collection('reminders')
          .doc(reminderId)
          .update({'isCompleted': true});

      // Cancel notification
      await notificationsPlugin.cancel(reminderId.hashCode);

      print(' Reminder completed');
      return true;
    } catch (e) {
      print(' Error completing reminder: $e');
      return false;
    }
  }

  // Delete reminder
  Future<bool> deleteReminder(String reminderId) async {
    try {
      await firebaseFirestore.collection('reminders').doc(reminderId).delete();

      await notificationsPlugin.cancel(reminderId.hashCode);

      return true;
    } catch (e) {
      print(' Error deleting reminder: $e');
      return false;
    }
  }

  // Check and clean expired reminders
  Future<void> checkExpiredReminders(String userId) async {
    try {
      final now = DateTime.now();
      final reminders = await firebaseFirestore
          .collection('reminders')
          .where('userId', isEqualTo: userId)
          .where('isCompleted', isEqualTo: false)
          .get();

      for (var doc in reminders.docs) {
        final reminder = MessageReminder.fromDocument(doc);
        final reminderTime = DateTime.fromMillisecondsSinceEpoch(
          int.parse(reminder.reminderTime),
        );

        // Auto-complete if time has passed
        if (reminderTime.isBefore(now)) {
          await completeReminder(reminder.id);
        }
      }
    } catch (e) {
      print('Error checking expired reminders: $e');
    }
  }
}
