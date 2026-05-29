import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Utilities {
  Utilities._();

  static bool isKeyboardShowing(BuildContext context) =>
      MediaQuery.of(context).viewInsets.bottom > 0;

  static void closeKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  static void closeKeyboardForContext(BuildContext context) => FocusScope.of(context).unfocus();

  static String getInitials(String name, {int maxLength = 2}) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0][0].toUpperCase();
    }
    return parts.take(maxLength).map((p) => p[0].toUpperCase()).join();
  }

  static String truncate(String text, int maxLength, {String ellipsis = '…'}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}$ellipsis';
  }

  static List<TextSpan> highlightText(
    String text,
    String query, {
    TextStyle? normalStyle,
    TextStyle? highlightStyle,
  }) {
    if (query.isEmpty) return [TextSpan(text: text, style: normalStyle)];

    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    int start = 0;

    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start), style: normalStyle));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(
          text: text.substring(start, idx),
          style: normalStyle,
        ));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: highlightStyle ??
            const TextStyle(
              color: Color(0xFF007AFF),
              fontWeight: FontWeight.bold,
            ),
      ));
      start = idx + query.length;
    }
    return spans;
  }

  static int wordCount(String text) =>
      text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

  static bool containsEmoji(String text) {
    final emojiRegex = RegExp(
      r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]',
      unicode: true,
    );
    return emojiRegex.hasMatch(text);
  }

  static bool isEmojiOnly(String text) {
    final stripped = text.replaceAll(
      RegExp(
        r'[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}'
        r'\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{FE00}-\u{FE0F}\s]',
        unicode: true,
      ),
      '',
    );
    return stripped.isEmpty && text.trim().isNotEmpty;
  }

  static String formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  static String formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (math.log(bytes) / math.log(1024)).floor();
    final size = bytes / math.pow(1024, i);
    return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  static Size screenSize(BuildContext context) => MediaQuery.sizeOf(context);

  static bool isTablet(BuildContext context) => MediaQuery.sizeOf(context).shortestSide >= 600;

  static EdgeInsets safePadding(BuildContext context) => MediaQuery.paddingOf(context);

  static Color colorFromName(String name) {
    const colors = [
      Color(0xFF5B8DEF),
      Color(0xFF9B59B6),
      Color(0xFF1ABC9C),
      Color(0xFFE74C3C),
      Color(0xFFF39C12),
      Color(0xFF2ECC71),
      Color(0xFF3498DB),
      Color(0xFFE67E22),
      Color(0xFF1E88E5),
      Color(0xFF00ACC1),
      Color(0xFF43A047),
      Color(0xFF8E24AA),
    ];
    if (name.isEmpty) return colors[0];
    int hash = 0;
    for (final char in name.codeUnits) {
      hash = (hash * 31 + char) & 0xFFFFFF;
    }
    return colors[hash % colors.length];
  }

  static Future<void> copyToClipboard(
    String text,
    BuildContext context, {
    String? successMessage,
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage ?? 'Đã sao chép'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static Future<String?> getFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  static bool isValidEmail(String email) {
    return RegExp(
      r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(email.trim());
  }

  static bool isValidPhone(String phone) {
    return RegExp(r'^[+]?[(]?[0-9]{1,4}[)]?[-\s./0-9]{7,14}$').hasMatch(phone.trim());
  }

  static bool isValidUrl(String url) {
    return RegExp(
      r'^https?://(www\.)?[-a-zA-Z0-9@:%._+~#=]{1,256}'
      r'\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_+.~#?&/=]*)$',
    ).hasMatch(url.trim());
  }

  static Future<void> lightHaptic() => HapticFeedback.lightImpact();

  static Future<void> mediumHaptic() => HapticFeedback.mediumImpact();

  static Future<void> heavyHaptic() => HapticFeedback.heavyImpact();

  static Future<void> selectionHaptic() => HapticFeedback.selectionClick();

  static void showSnackbar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    Color? backgroundColor,
    bool floating = true,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: duration,
          action: action,
          backgroundColor: backgroundColor,
          behavior: floating ? SnackBarBehavior.floating : SnackBarBehavior.fixed,
          shape: floating ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)) : null,
        ),
      );
  }

  static void showErrorSnackbar(BuildContext context, String message) {
    showSnackbar(
      context,
      message,
      backgroundColor: const Color(0xFFE53935),
    );
  }

  static void showSuccessSnackbar(BuildContext context, String message) {
    showSnackbar(
      context,
      message,
      backgroundColor: const Color(0xFF43A047),
    );
  }

  static Future<bool> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Xác nhận',
    String cancelLabel = 'Huỷ',
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: isDestructive
                ? TextButton.styleFrom(foregroundColor: const Color(0xFFE53935))
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;

  static bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isMobile => isAndroid || isIOS;

  static bool get isDesktop =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
}

extension StringUtilsExtension on String {
  String get initials => Utilities.getInitials(this);
  Color get avatarColor => Utilities.colorFromName(this);
  bool get isValidEmail => Utilities.isValidEmail(this);
  bool get isValidUrl => Utilities.isValidUrl(this);
  bool get isEmojiOnly => Utilities.isEmojiOnly(this);
  String truncated(int max) => Utilities.truncate(this, max);
}

extension BuildContextUtilsExtension on BuildContext {
  bool get isKeyboardShowing => Utilities.isKeyboardShowing(this);
  void closeKeyboard() => Utilities.closeKeyboardForContext(this);
  Size get screenSize => Utilities.screenSize(this);
  bool get isTablet => Utilities.isTablet(this);
  EdgeInsets get safePadding => Utilities.safePadding(this);

  void showSnackbar(String msg, {Color? backgroundColor}) =>
      Utilities.showSnackbar(this, msg, backgroundColor: backgroundColor);

  void showErrorSnackbar(String msg) => Utilities.showErrorSnackbar(this, msg);

  void showSuccessSnackbar(String msg) => Utilities.showSuccessSnackbar(this, msg);
}
