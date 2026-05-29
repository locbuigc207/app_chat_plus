import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

class AppDateUtils {
  AppDateUtils._();

  static const _secondsPerMinute = 60;
  static const _minutesPerHour = 60;
  static const _hoursPerDay = 24;
  static const _daysPerWeek = 7;
  static const _daysPerYear = 365;

  static String formatMessageTime(dynamic timestamp, BuildContext context) {
    try {
      final ms = timestamp is int ? timestamp : int.parse(timestamp.toString());
      final dateTime = DateTime.fromMillisecondsSinceEpoch(ms);
      return _formatRelative(dateTime, context, short: true);
    } catch (_) {
      return '';
    }
  }

  static String formatDateHeader(dynamic timestamp, BuildContext context) {
    try {
      final ms = timestamp is int ? timestamp : int.parse(timestamp.toString());
      final dateTime = DateTime.fromMillisecondsSinceEpoch(ms);
      final locale = _locale(context);
      final now = DateTime.now();

      if (_isSameDay(dateTime, now)) {
        return locale == 'vi' ? 'Hôm nay' : 'Today';
      } else if (_isSameDay(dateTime, now.subtract(const Duration(days: 1)))) {
        return locale == 'vi' ? 'Hôm qua' : 'Yesterday';
      } else if (now.difference(dateTime).inDays < _daysPerWeek) {
        return DateFormat.EEEE(locale).format(dateTime);
      } else if (dateTime.year == now.year) {
        return DateFormat('d MMM', locale).format(dateTime);
      } else {
        return DateFormat.yMMMd(locale).format(dateTime);
      }
    } catch (_) {
      return '';
    }
  }

  static String formatLastSeen(DateTime lastSeen, BuildContext context) {
    return _formatRelative(lastSeen, context, short: false);
  }

  static String formatReminderTime(dynamic timestamp, BuildContext context) {
    try {
      final ms = timestamp is int ? timestamp : int.parse(timestamp.toString());
      final dateTime = DateTime.fromMillisecondsSinceEpoch(ms);
      final locale = _locale(context);
      final now = DateTime.now();

      if (_isSameDay(dateTime, now)) {
        return '${locale == "vi" ? "Hôm nay" : "Today"} ${DateFormat.Hm(locale).format(dateTime)}';
      } else if (_isSameDay(dateTime, now.add(const Duration(days: 1)))) {
        return '${locale == "vi" ? "Ngày mai" : "Tomorrow"} ${DateFormat.Hm(locale).format(dateTime)}';
      }
      return DateFormat('MMM dd, HH:mm', locale).format(dateTime);
    } catch (_) {
      return '';
    }
  }

  static String formatFullDateTime(dynamic timestamp, BuildContext context) {
    try {
      final ms = timestamp is int ? timestamp : int.parse(timestamp.toString());
      final dateTime = DateTime.fromMillisecondsSinceEpoch(ms);
      final locale = _locale(context);
      return DateFormat('dd/MM/yyyy, HH:mm', locale).format(dateTime);
    } catch (_) {
      return '';
    }
  }

  static String formatCallDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String formatAudioDuration(Duration duration) {
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static bool isToday(DateTime date) => _isSameDay(date, DateTime.now());

  static bool isYesterday(DateTime date) =>
      _isSameDay(date, DateTime.now().subtract(const Duration(days: 1)));

  static bool isTomorrow(DateTime date) =>
      _isSameDay(date, DateTime.now().add(const Duration(days: 1)));

  static bool isThisWeek(DateTime date) {
    final now = DateTime.now();
    return now.difference(date).inDays < _daysPerWeek && date.isBefore(now);
  }

  static bool isThisYear(DateTime date) => date.year == DateTime.now().year;

  static bool isSameDay(DateTime a, DateTime b) => _isSameDay(a, b);

  static bool shouldShowDateHeader(dynamic prevTimestamp, dynamic currentTimestamp) {
    try {
      final prev = _parseMs(prevTimestamp);
      final curr = _parseMs(currentTimestamp);
      if (prev == null || curr == null) return false;
      return !_isSameDay(
        DateTime.fromMillisecondsSinceEpoch(prev),
        DateTime.fromMillisecondsSinceEpoch(curr),
      );
    } catch (_) {
      return false;
    }
  }

  static bool isWithinGroupingWindow(dynamic ts1, dynamic ts2,
      {Duration window = const Duration(minutes: 2)}) {
    try {
      final ms1 = _parseMs(ts1);
      final ms2 = _parseMs(ts2);
      if (ms1 == null || ms2 == null) return false;
      final diff = (ms1 - ms2).abs();
      return diff <= window.inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  static String _locale(BuildContext context) {
    try {
      return Localizations.localeOf(context).languageCode;
    } catch (_) {
      return 'en';
    }
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static int? _parseMs(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static String _formatRelative(
    DateTime dateTime,
    BuildContext context, {
    required bool short,
  }) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    final locale = _locale(context);
    final isVi = locale == 'vi';

    if (diff.inSeconds < _secondsPerMinute) {
      return isVi ? 'Vừa xong' : 'Just now';
    } else if (diff.inMinutes < _minutesPerHour) {
      final m = diff.inMinutes;
      if (short) return isVi ? '${m}ph' : '${m}m';
      return isVi ? '$m phút trước' : '${m}m ago';
    } else if (diff.inHours < _hoursPerDay) {
      if (short) return DateFormat.Hm(locale).format(dateTime);
      final h = diff.inHours;
      return isVi ? '$h giờ trước' : '${h}h ago';
    } else if (diff.inDays == 1) {
      return isVi
          ? 'Hôm qua ${DateFormat.Hm(locale).format(dateTime)}'
          : 'Yesterday ${DateFormat.Hm(locale).format(dateTime)}';
    } else if (diff.inDays < _daysPerWeek) {
      if (short) return DateFormat.E(locale).format(dateTime);
      final d = diff.inDays;
      return isVi ? '$d ngày trước' : '${d}d ago';
    } else if (diff.inDays < _daysPerYear) {
      return DateFormat('d MMM', locale).format(dateTime);
    } else {
      return DateFormat.yMMMd(locale).format(dateTime);
    }
  }

  static DateTime? parseTimestamp(dynamic timestamp) {
    try {
      final ms = _parseMs(timestamp);
      if (ms == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  static String toTimestamp(DateTime dateTime) => dateTime.millisecondsSinceEpoch.toString();

  static DateTime startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

  static DateTime endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
}
