import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// COLOUR PALETTE
// ═══════════════════════════════════════════════════════════════════════════

abstract class _Palette {
  // Blues
  static const blue500 = Color(0xFF2979FF);
  static const blue700 = Color(0xFF1E88E5);
  static const blue900 = Color(0xFF1565C0);
  static const blueDeep = Color(0xFF0D47A1);

  // Work — dark navy
  static const work900 = Color(0xFF0D1B2A);
  static const work800 = Color(0xFF162032);
  static const work700 = Color(0xFF1E2D40);
  static const workAccent = Color(0xFF66BB6A);

  // Location — greens
  static const loc900 = Color(0xFF1B5E20);
  static const loc700 = Color(0xFF388E3C);
  static const locAccent = Color(0xFF69F0AE);

  // Secure — midnight + teal
  static const sec900 = Color(0xFF0A0E1A);
  static const sec800 = Color(0xFF0D1F3C);
  static const sec700 = Color(0xFF1A2A50);
  static const secAccent = Color(0xFF64FFDA);

  // Media — pink
  static const media900 = Color(0xFF880E4F);
  static const media700 = Color(0xFFAD1457);

  // Shared — purple
  static const share900 = Color(0xFF311B92);
  static const share700 = Color(0xFF5E35B1);

  // Status
  static const online = Color(0xFF4CAF50);
  static const onlineG = Color(0xFF69F0AE);
  static const unread = Color(0xFFFF5252);
  static const scamBg = Color(0xFFFFF3E0);
  static const scamBdr = Color(0xFFFFA726);
  static const scamTxt = Color(0xFF7B3F00);

  // My bubble gradient
  static const myStart = Color(0xFF2979FF);
  static const myEnd = Color(0xFF1565C0);

  // Peer bubble
  static const peerLight = Color(0xFFF0F4FF);
  static const peerDark = Color(0xFF1E2233);
}

// ═══════════════════════════════════════════════════════════════════════════
// SHADOW TOKENS
// ═══════════════════════════════════════════════════════════════════════════

class BubbleShadows {
  static List<BoxShadow> card(Color seed) => [
        BoxShadow(
          color: seed.withOpacity(0.18),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get bubble => [
        BoxShadow(
          color: Colors.black.withOpacity(0.12),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> header(Color seed) => [
        BoxShadow(
          color: seed.withOpacity(0.22),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get miniChat => [
        BoxShadow(
          color: Colors.black.withOpacity(0.28),
          blurRadius: 32,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];
}

// ═══════════════════════════════════════════════════════════════════════════
// TYPOGRAPHY TOKENS
// ═══════════════════════════════════════════════════════════════════════════

class BubbleTypography {
  final double messageSize;
  final double timeSize;
  final double headerNameSize;
  final double headerSubSize;
  final double badgeSize;
  final FontWeight messageFontWeight;

  const BubbleTypography.normal()
      : messageSize = 15,
        timeSize = 10.5,
        headerNameSize = 14,
        headerSubSize = 11,
        badgeSize = 10,
        messageFontWeight = FontWeight.w400;

  const BubbleTypography.large()
      : messageSize = 18,
        timeSize = 13,
        headerNameSize = 17,
        headerSubSize = 13,
        badgeSize = 12,
        messageFontWeight = FontWeight.w400;

  const BubbleTypography.small()
      : messageSize = 13,
        timeSize = 9,
        headerNameSize = 12,
        headerSubSize = 10,
        badgeSize = 9,
        messageFontWeight = FontWeight.w400;
}

// ═══════════════════════════════════════════════════════════════════════════
// BUBBLE THEME EXTENSION
// ═══════════════════════════════════════════════════════════════════════════

class BubbleTheme extends ThemeExtension<BubbleTheme> {
  // ── My bubble ─────────────────────────────────────────────────────────
  final Color myBubbleStart;
  final Color myBubbleEnd;
  final Color myBubbleText;

  // ── Peer bubble ────────────────────────────────────────────────────────
  final Color peerBubble;
  final Color peerBubbleText;

  // ── Status ─────────────────────────────────────────────────────────────
  final Color onlineColor;
  final Color onlineGlow;
  final Color unreadColor;

  // ── Scam warning ───────────────────────────────────────────────────────
  final Color scamBg;
  final Color scamBorder;
  final Color scamText;

  // ── Bubble widget ──────────────────────────────────────────────────────
  final double bubblePadding;
  final double bubbleRadius;

  // ── Typography ─────────────────────────────────────────────────────────
  final BubbleTypography typography;

  // ── Brightness ────────────────────────────────────────────────────────
  final bool isDark;

  const BubbleTheme({
    required this.myBubbleStart,
    required this.myBubbleEnd,
    required this.myBubbleText,
    required this.peerBubble,
    required this.peerBubbleText,
    required this.onlineColor,
    required this.onlineGlow,
    required this.unreadColor,
    required this.scamBg,
    required this.scamBorder,
    required this.scamText,
    this.bubblePadding = 12,
    this.bubbleRadius = 18,
    this.typography = const BubbleTypography.normal(),
    this.isDark = false,
  });

  // ── Factory ────────────────────────────────────────────────────────────

  factory BubbleTheme.of(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return BubbleTheme(
      myBubbleStart: _Palette.myStart,
      myBubbleEnd: _Palette.myEnd,
      myBubbleText: Colors.white,
      peerBubble: dark ? _Palette.peerDark : _Palette.peerLight,
      peerBubbleText: dark ? Colors.white.withOpacity(0.92) : Colors.black87,
      onlineColor: _Palette.online,
      onlineGlow: _Palette.onlineG,
      unreadColor: _Palette.unread,
      scamBg: _Palette.scamBg,
      scamBorder: _Palette.scamBdr,
      scamText: _Palette.scamTxt,
      isDark: dark,
    );
  }

  // ── Mode-aware helpers ─────────────────────────────────────────────────

  /// Primary colour for the given [BubbleMode] — used in headers & accents.
  Color modeColor(BubbleMode mode) => switch (mode) {
        BubbleMode.work => _Palette.work900,
        BubbleMode.media => _Palette.media900,
        BubbleMode.location => _Palette.loc900,
        BubbleMode.secure => _Palette.sec900,
        BubbleMode.shared => _Palette.share900,
        _ => _Palette.blue700,
      };

  /// Gradient colours for the header of the given [BubbleMode].
  List<Color> modeGradient(BubbleMode mode) => switch (mode) {
        BubbleMode.work => [_Palette.work900, _Palette.work700],
        BubbleMode.media => [_Palette.media900, _Palette.media700],
        BubbleMode.location => [_Palette.loc900, _Palette.loc700],
        BubbleMode.secure => [_Palette.sec900, _Palette.sec700],
        BubbleMode.shared => [_Palette.share900, _Palette.share700],
        _ => [_Palette.blue700, _Palette.blueDeep],
      };

  /// Accent colour (badge, indicator) for the given [BubbleMode].
  Color modeAccent(BubbleMode mode) => switch (mode) {
        BubbleMode.work => _Palette.workAccent,
        BubbleMode.location => _Palette.locAccent,
        BubbleMode.secure => _Palette.secAccent,
        _ => _Palette.onlineG,
      };

  /// Emoji/label for the mode badge.
  String modeEmoji(BubbleMode mode) => switch (mode) {
        BubbleMode.work => '💼',
        BubbleMode.media => '🎵',
        BubbleMode.location => '📍',
        BubbleMode.secure => '🔒',
        BubbleMode.shared => '🎨',
        _ => '💬',
      };

  /// Shadow for a card seeded with the mode colour.
  List<BoxShadow> modeCardShadow(BubbleMode mode) =>
      BubbleShadows.card(modeColor(mode));

  // ── ThemeExtension impl ────────────────────────────────────────────────

  @override
  BubbleTheme copyWith({
    Color? myBubbleStart,
    Color? myBubbleEnd,
    Color? myBubbleText,
    Color? peerBubble,
    Color? peerBubbleText,
    Color? onlineColor,
    Color? onlineGlow,
    Color? unreadColor,
    Color? scamBg,
    Color? scamBorder,
    Color? scamText,
    double? bubblePadding,
    double? bubbleRadius,
    BubbleTypography? typography,
    bool? isDark,
  }) =>
      BubbleTheme(
        myBubbleStart: myBubbleStart ?? this.myBubbleStart,
        myBubbleEnd: myBubbleEnd ?? this.myBubbleEnd,
        myBubbleText: myBubbleText ?? this.myBubbleText,
        peerBubble: peerBubble ?? this.peerBubble,
        peerBubbleText: peerBubbleText ?? this.peerBubbleText,
        onlineColor: onlineColor ?? this.onlineColor,
        onlineGlow: onlineGlow ?? this.onlineGlow,
        unreadColor: unreadColor ?? this.unreadColor,
        scamBg: scamBg ?? this.scamBg,
        scamBorder: scamBorder ?? this.scamBorder,
        scamText: scamText ?? this.scamText,
        bubblePadding: bubblePadding ?? this.bubblePadding,
        bubbleRadius: bubbleRadius ?? this.bubbleRadius,
        typography: typography ?? this.typography,
        isDark: isDark ?? this.isDark,
      );

  @override
  BubbleTheme lerp(BubbleTheme? other, double t) {
    if (other == null) return this;
    return BubbleTheme(
      myBubbleStart: Color.lerp(myBubbleStart, other.myBubbleStart, t)!,
      myBubbleEnd: Color.lerp(myBubbleEnd, other.myBubbleEnd, t)!,
      myBubbleText: Color.lerp(myBubbleText, other.myBubbleText, t)!,
      peerBubble: Color.lerp(peerBubble, other.peerBubble, t)!,
      peerBubbleText: Color.lerp(peerBubbleText, other.peerBubbleText, t)!,
      onlineColor: Color.lerp(onlineColor, other.onlineColor, t)!,
      onlineGlow: Color.lerp(onlineGlow, other.onlineGlow, t)!,
      unreadColor: Color.lerp(unreadColor, other.unreadColor, t)!,
      scamBg: Color.lerp(scamBg, other.scamBg, t)!,
      scamBorder: Color.lerp(scamBorder, other.scamBorder, t)!,
      scamText: Color.lerp(scamText, other.scamText, t)!,
      bubblePadding: lerpDouble(bubblePadding, other.bubblePadding, t)!,
      bubbleRadius: lerpDouble(bubbleRadius, other.bubbleRadius, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }

  /// Convenience accessor — throws if BubbleTheme not registered.
  static BubbleTheme read(BuildContext context) =>
      Theme.of(context).extension<BubbleTheme>()!;

  /// Safe accessor — falls back to light defaults.
  static BubbleTheme readOrDefault(BuildContext context) =>
      Theme.of(context).extension<BubbleTheme>() ??
      BubbleTheme.of(Brightness.light);
}
