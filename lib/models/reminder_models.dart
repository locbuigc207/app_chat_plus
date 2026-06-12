// lib/models/reminder_models.dart
// Tất cả data models cho hệ thống AI Reminders nâng cấp
// Bao gồm: EnhancedReminder, ExtractedReminder, ReminderSuggestion,
//          ReminderExtractionResult, SnoozeOption, Enums

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────────────────────

enum ReminderPriority { low, medium, high }

extension ReminderPriorityX on ReminderPriority {
  String get label {
    switch (this) {
      case ReminderPriority.low:
        return 'Thấp';
      case ReminderPriority.medium:
        return 'Trung bình';
      case ReminderPriority.high:
        return 'Cao';
    }
  }

  String get emoji {
    switch (this) {
      case ReminderPriority.low:
        return '🟢';
      case ReminderPriority.medium:
        return '🟡';
      case ReminderPriority.high:
        return '🔴';
    }
  }

  Color get color {
    switch (this) {
      case ReminderPriority.low:
        return const Color(0xFF22C55E);
      case ReminderPriority.medium:
        return const Color(0xFFF59E0B);
      case ReminderPriority.high:
        return const Color(0xFFEF4444);
    }
  }

  static ReminderPriority fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'high':
        return ReminderPriority.high;
      case 'medium':
        return ReminderPriority.medium;
      default:
        return ReminderPriority.low;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

enum ReminderCategory { meeting, deadline, payment, personal, work, other }

extension ReminderCategoryX on ReminderCategory {
  String get label {
    switch (this) {
      case ReminderCategory.meeting:
        return 'Cuộc hẹn';
      case ReminderCategory.deadline:
        return 'Deadline';
      case ReminderCategory.payment:
        return 'Thanh toán';
      case ReminderCategory.personal:
        return 'Cá nhân';
      case ReminderCategory.work:
        return 'Công việc';
      case ReminderCategory.other:
        return 'Khác';
    }
  }

  String get emoji {
    switch (this) {
      case ReminderCategory.meeting:
        return '🤝';
      case ReminderCategory.deadline:
        return '⏰';
      case ReminderCategory.payment:
        return '💳';
      case ReminderCategory.personal:
        return '👤';
      case ReminderCategory.work:
        return '💼';
      case ReminderCategory.other:
        return '📌';
    }
  }

  static ReminderCategory fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'meeting':
        return ReminderCategory.meeting;
      case 'deadline':
        return ReminderCategory.deadline;
      case 'payment':
        return ReminderCategory.payment;
      case 'personal':
        return ReminderCategory.personal;
      case 'work':
        return ReminderCategory.work;
      default:
        return ReminderCategory.other;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

enum ReminderRepeat { none, daily, weekly, monthly }

extension ReminderRepeatX on ReminderRepeat {
  String get label {
    switch (this) {
      case ReminderRepeat.none:
        return 'Không lặp';
      case ReminderRepeat.daily:
        return 'Hàng ngày';
      case ReminderRepeat.weekly:
        return 'Hàng tuần';
      case ReminderRepeat.monthly:
        return 'Hàng tháng';
    }
  }

  String get shortLabel {
    switch (this) {
      case ReminderRepeat.none:
        return '';
      case ReminderRepeat.daily:
        return '↻ ngày';
      case ReminderRepeat.weekly:
        return '↻ tuần';
      case ReminderRepeat.monthly:
        return '↻ tháng';
    }
  }

  static ReminderRepeat fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'daily':
        return ReminderRepeat.daily;
      case 'weekly':
        return ReminderRepeat.weekly;
      case 'monthly':
        return ReminderRepeat.monthly;
      default:
        return ReminderRepeat.none;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

enum SnoozeOption { fifteenMinutes, thirtyMinutes, oneHour, twoHours, tomorrow }

extension SnoozeOptionX on SnoozeOption {
  String get label {
    switch (this) {
      case SnoozeOption.fifteenMinutes:
        return '15 phút';
      case SnoozeOption.thirtyMinutes:
        return '30 phút';
      case SnoozeOption.oneHour:
        return '1 giờ';
      case SnoozeOption.twoHours:
        return '2 giờ';
      case SnoozeOption.tomorrow:
        return 'Ngày mai 9:00';
    }
  }

  String get icon {
    switch (this) {
      case SnoozeOption.fifteenMinutes:
        return '⚡';
      case SnoozeOption.thirtyMinutes:
        return '⏱';
      case SnoozeOption.oneHour:
        return '⏰';
      case SnoozeOption.twoHours:
        return '🕑';
      case SnoozeOption.tomorrow:
        return '☀️';
    }
  }

  Duration get duration {
    switch (this) {
      case SnoozeOption.fifteenMinutes:
        return const Duration(minutes: 15);
      case SnoozeOption.thirtyMinutes:
        return const Duration(minutes: 30);
      case SnoozeOption.oneHour:
        return const Duration(hours: 1);
      case SnoozeOption.twoHours:
        return const Duration(hours: 2);
      case SnoozeOption.tomorrow:
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day + 1, 9, 0).difference(now);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ENHANCED REMINDER MODEL
// ─────────────────────────────────────────────────────────────────────────────

class EnhancedReminder {
  final String id;
  final String userId;
  final String? conversationId;
  final String? messageId;
  final String message;
  final DateTime reminderTime;
  final bool isCompleted;
  final bool isAutoGenerated;
  final ReminderPriority priority;
  final ReminderCategory category;
  final String? deadline;
  final int snoozeCount;
  final bool notificationSent;
  final String? calendarEventId;
  final ReminderRepeat repeat;
  final DateTime createdAt;
  final DateTime? completedAt;

  const EnhancedReminder({
    required this.id,
    required this.userId,
    this.conversationId,
    this.messageId,
    required this.message,
    required this.reminderTime,
    this.isCompleted = false,
    this.isAutoGenerated = false,
    this.priority = ReminderPriority.medium,
    this.category = ReminderCategory.other,
    this.deadline,
    this.snoozeCount = 0,
    this.notificationSent = false,
    this.calendarEventId,
    this.repeat = ReminderRepeat.none,
    required this.createdAt,
    this.completedAt,
  });

  // ── Computed ───────────────────────────────────────────────────────────────

  bool get isHighPriority => priority == ReminderPriority.high;
  bool get isExpired => reminderTime.isBefore(DateTime.now()) && !isCompleted;

  bool get isDueSoon {
    if (isCompleted) return false;
    final diff = reminderTime.difference(DateTime.now());
    return !diff.isNegative && diff.inMinutes <= 60;
  }

  bool get isOverdue {
    if (isCompleted) return false;
    return reminderTime.isBefore(DateTime.now());
  }

  int get minutesUntilDue => reminderTime.difference(DateTime.now()).inMinutes;

  // ── CopyWith ──────────────────────────────────────────────────────────────

  EnhancedReminder copyWith({
    bool? isCompleted,
    DateTime? reminderTime,
    ReminderPriority? priority,
    ReminderCategory? category,
    int? snoozeCount,
    bool? notificationSent,
    String? calendarEventId,
    DateTime? completedAt,
  }) =>
      EnhancedReminder(
        id: id,
        userId: userId,
        conversationId: conversationId,
        messageId: messageId,
        message: message,
        reminderTime: reminderTime ?? this.reminderTime,
        isCompleted: isCompleted ?? this.isCompleted,
        isAutoGenerated: isAutoGenerated,
        priority: priority ?? this.priority,
        category: category ?? this.category,
        deadline: deadline,
        snoozeCount: snoozeCount ?? this.snoozeCount,
        notificationSent: notificationSent ?? this.notificationSent,
        calendarEventId: calendarEventId ?? this.calendarEventId,
        repeat: repeat,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
      );

  // ── Serialization ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'userId': userId,
        if (conversationId != null) 'conversationId': conversationId,
        if (messageId != null) 'messageId': messageId,
        'message': message,
        'task': message,
        'reminderTime': reminderTime.millisecondsSinceEpoch.toString(),
        'isCompleted': isCompleted,
        'isAutoGenerated': isAutoGenerated,
        'priority': priority.name,
        'category': category.name,
        if (deadline != null) 'deadline': deadline,
        'snoozeCount': snoozeCount,
        'notificationSent': notificationSent,
        if (calendarEventId != null) 'calendarEventId': calendarEventId,
        'repeat': repeat.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        if (completedAt != null)
          'completedAt': completedAt!.millisecondsSinceEpoch.toString(),
      };

  factory EnhancedReminder.fromMap(String id, Map<String, dynamic> map) =>
      EnhancedReminder(
        id: id,
        userId: map['userId'] as String? ?? '',
        conversationId: map['conversationId'] as String?,
        messageId: map['messageId'] as String?,
        message: map['message'] as String? ?? map['task'] as String? ?? '',
        reminderTime: _parseDateTime(map['reminderTime']) ??
            DateTime.now().add(const Duration(hours: 1)),
        isCompleted: map['isCompleted'] as bool? ?? false,
        isAutoGenerated: map['isAutoGenerated'] as bool? ?? false,
        priority: ReminderPriorityX.fromString(map['priority'] as String?),
        category: ReminderCategoryX.fromString(map['category'] as String?),
        deadline: map['deadline'] as String?,
        snoozeCount: map['snoozeCount'] as int? ?? 0,
        notificationSent: map['notificationSent'] as bool? ?? false,
        calendarEventId: map['calendarEventId'] as String?,
        repeat: ReminderRepeatX.fromString(map['repeat'] as String?),
        createdAt: _parseDateTime(map['createdAt']) ?? DateTime.now(),
        completedAt: _parseDateTime(map['completedAt']),
      );

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) {
      final ms = int.tryParse(v);
      return ms != null
          ? DateTime.fromMillisecondsSinceEpoch(ms)
          : DateTime.tryParse(v);
    }
    return null;
  }

  @override
  String toString() =>
      'EnhancedReminder(id:$id priority:${priority.name} due:$reminderTime)';
}

// ─────────────────────────────────────────────────────────────────────────────
// AI EXTRACTION MODELS
// ─────────────────────────────────────────────────────────────────────────────

/// Kết quả từ Cloud Function extractReminderWithPriority
class ReminderExtractionResult {
  final bool hasReminder;
  final List<ExtractedReminder> reminders;

  const ReminderExtractionResult({
    required this.hasReminder,
    required this.reminders,
  });

  factory ReminderExtractionResult.empty() => const ReminderExtractionResult(
        hasReminder: false,
        reminders: [],
      );

  factory ReminderExtractionResult.fromMap(Map<String, dynamic> map) {
    final rawList = map['reminders'] as List? ?? [];
    return ReminderExtractionResult(
      hasReminder: map['hasReminder'] as bool? ?? false,
      reminders: rawList
          .map((r) =>
              ExtractedReminder.fromMap(Map<String, dynamic>.from(r as Map)))
          .where((r) => r.task.isNotEmpty)
          .toList(),
    );
  }

  bool get isEmpty => reminders.isEmpty;
  bool get isNotEmpty => reminders.isNotEmpty;
}

/// Một tác vụ được AI bóc tách từ tin nhắn
class ExtractedReminder {
  final String task;
  final ReminderPriority priority;
  final ReminderCategory category;
  final String? deadline;
  final String? reminderTimeHint; // raw string from AI
  final String? context;
  final String? messageId;

  const ExtractedReminder({
    required this.task,
    this.priority = ReminderPriority.medium,
    this.category = ReminderCategory.other,
    this.deadline,
    this.reminderTimeHint,
    this.context,
    this.messageId,
  });

  factory ExtractedReminder.fromMap(Map<String, dynamic> m) =>
      ExtractedReminder(
        task: m['task'] as String? ?? '',
        priority: ReminderPriorityX.fromString(m['priority'] as String?),
        category: ReminderCategoryX.fromString(m['category'] as String?),
        deadline: m['deadline'] as String?,
        reminderTimeHint: m['reminderTime'] as String?,
        context: m['context'] as String?,
        messageId: m['messageId'] as String?,
      );

  /// Parse reminderTimeHint → DateTime
  DateTime get parsedReminderTime =>
      _parseHint(reminderTimeHint) ??
      DateTime.now().add(const Duration(hours: 1));

  static DateTime? _parseHint(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    // ISO parse
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;

    final now = DateTime.now();
    final lower = raw.toLowerCase();

    // Ngày mai / tomorrow
    if (lower.contains('ngày mai') || lower.contains('tomorrow')) {
      final m = RegExp(r'(\d{1,2})[h:]\s*(\d{0,2})').firstMatch(lower);
      final h = m != null ? (int.tryParse(m.group(1) ?? '9') ?? 9) : 9;
      final mn = m != null ? (int.tryParse(m.group(2) ?? '0') ?? 0) : 0;
      return DateTime(now.year, now.month, now.day + 1, h, mn);
    }

    // Hôm nay / today
    if (lower.contains('hôm nay') || lower.contains('today')) {
      final m = RegExp(r'(\d{1,2})[h:]\s*(\d{0,2})').firstMatch(lower);
      if (m != null) {
        final h = int.tryParse(m.group(1) ?? '9') ?? 9;
        final mn = int.tryParse(m.group(2) ?? '0') ?? 0;
        final t = DateTime(now.year, now.month, now.day, h, mn);
        return t.isAfter(now) ? t : t.add(const Duration(days: 1));
      }
    }

    // Time only: "10h", "14:30", "10:00"
    final to = RegExp(r'^(\d{1,2})[h:]?\s*(\d{0,2})$').firstMatch(lower.trim());
    if (to != null) {
      final h = int.tryParse(to.group(1) ?? '9') ?? 9;
      final mn = int.tryParse(to.group(2) ?? '0') ?? 0;
      final t = DateTime(now.year, now.month, now.day, h, mn);
      return t.isAfter(now) ? t : t.add(const Duration(days: 1));
    }

    return null;
  }

  /// Convert sang EnhancedReminder để lưu vào Firestore
  EnhancedReminder toEnhancedReminder({
    required String userId,
    String? conversationId,
    String? msgId,
  }) =>
      EnhancedReminder(
        id: '',
        userId: userId,
        conversationId: conversationId,
        messageId: msgId ?? messageId,
        message: task,
        reminderTime: parsedReminderTime,
        priority: priority,
        category: category,
        deadline: deadline,
        isAutoGenerated: true,
        createdAt: DateTime.now(),
      );

  @override
  String toString() =>
      'ExtractedReminder(task:$task p:${priority.name} cat:${category.name})';
}

/// Gợi ý nhắc nhở AI
class ReminderSuggestion {
  final String task;
  final ReminderPriority priority;
  final String? timeHint;
  final String? reason;

  const ReminderSuggestion({
    required this.task,
    this.priority = ReminderPriority.medium,
    this.timeHint,
    this.reason,
  });

  factory ReminderSuggestion.fromMap(Map<String, dynamic> m) =>
      ReminderSuggestion(
        task: m['task'] as String? ?? '',
        priority: ReminderPriorityX.fromString(m['priority'] as String?),
        timeHint: m['timeHint'] as String?,
        reason: m['reason'] as String?,
      );

  @override
  String toString() => 'ReminderSuggestion(task:$task p:${priority.name})';
}
