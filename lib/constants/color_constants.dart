import 'package:flutter/material.dart';

class ColorConstants {
  // ── Brand Colors ───────────────────────────────────────────
  static const themeColor = Color(0xFF2196F3);
  static const primaryColor = Color(0xFF1565C0);
  static const primaryLight = Color(0xFF42A5F5);
  static const primaryDark = Color(0xFF0D47A1);

  // ── Accent ─────────────────────────────────────────────────
  static const accentGreen = Color(0xFF00C853);
  static const accentOrange = Color(0xFFFF6D00);
  static const accentRed = Color(0xFFE53935);
  static const accentPurple = Color(0xFF7B1FA2);

  // ── Neutral Light ──────────────────────────────────────────
  static const greyColor = Color(0xFF8A92A6);
  static const greyColor2 = Color(0xFFEEF0F6);
  static const greyColor3 = Color(0xFFD6DAE8);
  static const backgroundLight = Color(0xFFF0F2F8);
  static const surfaceLight = Color(0xFFFFFFFF);

  // ── Neutral Dark ───────────────────────────────────────────
  static const backgroundDark = Color(0xFF141622);
  static const surfaceDark = Color(0xFF1E2130);
  static const surfaceDark2 = Color(0xFF252A3D);
  static const borderDark = Color(0xFF2E3448);

  // ── Semantic ───────────────────────────────────────────────
  static const successColor = Color(0xFF00C853);
  static const warningColor = Color(0xFFFFAB00);
  static const errorColor = Color(0xFFE53935);
  static const infoColor = Color(0xFF2196F3);

  // ── Gradients ──────────────────────────────────────────────
  static const List<Color> primaryGradient = [
    Color(0xFF1976D2),
    Color(0xFF42A5F5),
  ];

  static const List<Color> messageSentGradient = [
    Color(0xFF1565C0),
    Color(0xFF1976D2),
  ];

  static const List<Color> onlineGradient = [
    Color(0xFF00C853),
    Color(0xFF69F0AE),
  ];

  // ── Message Bubble ─────────────────────────────────────────
  static const sentBubble = Color(0xFF1976D2);
  static const receivedBubble = Color(0xFFF0F2F8);
  static const sentBubbleDark = Color(0xFF1565C0);
  static const receivedBubbleDark = Color(0xFF252A3D);

  // ── Avatar Palette ─────────────────────────────────────────
  static const List<Color> avatarColors = [
    Color(0xFF1976D2),
    Color(0xFF388E3C),
    Color(0xFFE64A19),
    Color(0xFF7B1FA2),
    Color(0xFF0097A7),
    Color(0xFFAD1457),
    Color(0xFF455A64),
    Color(0xFF5D4037),
    Color(0xFFF57C00),
    Color(0xFF00838F),
  ];
}
