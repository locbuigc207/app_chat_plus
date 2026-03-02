// lib/utils/app_date_utils.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppDateUtils {
  /// Format message timestamp với localization
  static String formatMessageTime(String timestamp, BuildContext context) {
    try {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(
        int.parse(timestamp),
      );
      final now = DateTime.now();
      final diff = now.difference(dateTime);

      final locale = Localizations.localeOf(context).languageCode;

      if (diff.inSeconds < 60) {
        return locale == 'vi' ? 'Vừa xong' : 'Just now';
      } else if (diff.inMinutes < 60) {
        return locale == 'vi'
            ? '${diff.inMinutes} phút trước'
            : '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        return DateFormat.Hm(locale).format(dateTime);
      } else if (diff.inDays < 7) {
        return DateFormat.E(locale).format(dateTime);
      } else {
        return DateFormat.yMMMd(locale).format(dateTime);
      }
    } catch (_) {
      return '';
    }
  }

  /// Format last seen time
  static String formatLastSeen(DateTime lastSeen, BuildContext context) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);
    final locale = Localizations.localeOf(context).languageCode;

    if (diff.inMinutes < 1) {
      return locale == 'vi' ? 'Vừa xong' : 'Just now';
    } else if (diff.inMinutes < 60) {
      return locale == 'vi'
          ? '${diff.inMinutes} phút trước'
          : '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return locale == 'vi'
          ? '${diff.inHours} giờ trước'
          : '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return locale == 'vi'
          ? '${diff.inDays} ngày trước'
          : '${diff.inDays}d ago';
    } else {
      return DateFormat.yMMMd(locale).format(lastSeen);
    }
  }

  /// Format reminder time
  static String formatReminderTime(String timestamp, BuildContext context) {
    try {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(
        int.parse(timestamp),
      );
      final locale = Localizations.localeOf(context).languageCode;

      return DateFormat('MMM dd, HH:mm', locale).format(dateTime);
    } catch (_) {
      return '';
    }
  }

  /// Check if date is today
  static bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// Check if date is yesterday
  static bool isYesterday(DateTime date) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day;
  }
}
