import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// ENUM & CONSTANTS
// ============================================================

enum AppMode { student, work, elder }

extension AppModeExtension on AppMode {
  String get label {
    switch (this) {
      case AppMode.student:
        return 'Học sinh / SV';
      case AppMode.work:
        return 'Chuyên nghiệp';
      case AppMode.elder:
        return 'Người lớn tuổi';
    }
  }

  String get emoji {
    switch (this) {
      case AppMode.student:
        return '🎓';
      case AppMode.work:
        return '💼';
      case AppMode.elder:
        return '🌿';
    }
  }

  String get description {
    switch (this) {
      case AppMode.student:
        return 'Font nhỏ, màu sắc, năng động';
      case AppMode.work:
        return 'Gọn gàng, chuyên nghiệp, tối giản';
      case AppMode.elder:
        return 'Chữ lớn, dễ đọc, tương phản cao';
    }
  }

  IconData get icon {
    switch (this) {
      case AppMode.student:
        return Icons.school_rounded;
      case AppMode.work:
        return Icons.business_center_rounded;
      case AppMode.elder:
        return Icons.elderly_rounded;
    }
  }

  String get accessibilityHint {
    switch (this) {
      case AppMode.student:
        return 'Giao diện trẻ trung với màu sắc rực rỡ và font chữ nhỏ';
      case AppMode.work:
        return 'Giao diện tối giản chuyên nghiệp';
      case AppMode.elder:
        return 'Giao diện chữ lớn, tương phản cao, dễ đọc';
    }
  }
}

// ============================================================
// THEME TOKENS PER MODE
// ============================================================

class AppModeTokens {
  // Colors
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final Color myBubbleGradientStart;
  final Color myBubbleGradientEnd;
  final Color peerBubbleColor;
  final Color myBubbleTextColor;
  final Color peerBubbleTextColor;
  final Color inputBarColor;
  final Color inputBorderColor;
  final Color scaffoldBg;
  final Color chatBg;
  final Color appBarBg;
  final Color timestampColor;
  final Color unreadBadgeColor;
  final Color onlineIndicatorColor;
  final Color reactionBubbleColor;
  final Color dividerColor;
  final Color surfaceColor;
  final Color errorColor;

  // Typography
  final double bubbleFontSize;
  final double inputFontSize;
  final double captionFontSize;
  final double titleFontSize;
  final double headerFontSize;
  final FontWeight bubbleFontWeight;
  final double lineHeightMultiplier;
  final double letterSpacing;

  // Layout
  final double bubblePadding;
  final double bubbleRadius;
  final double avatarSize;
  final double inputBarHeight;
  final double reactionSize;
  final double iconSize;
  final double appBarHeight;
  final double messageSpacing;
  final double sectionSpacing;

  // Shadows & Elevation
  final List<BoxShadow> bubbleShadow;
  final List<BoxShadow> inputShadow;
  final List<BoxShadow> appBarShadow;
  final double elevation;

  // Animation
  final Duration animationDuration;
  final Duration longAnimationDuration;
  final Curve animationCurve;

  // Accessibility
  final double minTouchTarget;
  final bool highContrast;
  final double focusRingWidth;

  const AppModeTokens({
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.myBubbleGradientStart,
    required this.myBubbleGradientEnd,
    required this.peerBubbleColor,
    required this.myBubbleTextColor,
    required this.peerBubbleTextColor,
    required this.inputBarColor,
    required this.inputBorderColor,
    required this.scaffoldBg,
    required this.chatBg,
    required this.appBarBg,
    required this.timestampColor,
    required this.unreadBadgeColor,
    required this.onlineIndicatorColor,
    required this.reactionBubbleColor,
    required this.dividerColor,
    required this.surfaceColor,
    required this.errorColor,
    required this.bubbleFontSize,
    required this.inputFontSize,
    required this.captionFontSize,
    required this.titleFontSize,
    required this.headerFontSize,
    required this.bubbleFontWeight,
    required this.lineHeightMultiplier,
    required this.letterSpacing,
    required this.bubblePadding,
    required this.bubbleRadius,
    required this.avatarSize,
    required this.inputBarHeight,
    required this.reactionSize,
    required this.iconSize,
    required this.appBarHeight,
    required this.messageSpacing,
    required this.sectionSpacing,
    required this.bubbleShadow,
    required this.inputShadow,
    required this.appBarShadow,
    required this.elevation,
    required this.animationDuration,
    required this.longAnimationDuration,
    required this.animationCurve,
    required this.minTouchTarget,
    required this.highContrast,
    required this.focusRingWidth,
  });

  // Convenience getters
  Gradient get myBubbleGradient => LinearGradient(
        colors: [myBubbleGradientStart, myBubbleGradientEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  Color get myBubbleGradientMid => Color.lerp(
        myBubbleGradientStart,
        myBubbleGradientEnd,
        0.5,
      )!;
}

// ============================================================
// PROVIDER
// ============================================================

class AppModeProvider with ChangeNotifier {
  AppMode _currentMode = AppMode.student;
  bool _isDark = false;
  bool _useHaptics = true;
  bool _reduceMotion = false;
  double _textScaleFactor = 1.0;
  bool _isLoading = true;

  AppMode get currentMode => _currentMode;
  bool get isDark => _isDark;
  bool get useHaptics => _useHaptics;
  bool get reduceMotion => _reduceMotion;
  double get textScaleFactor => _textScaleFactor;
  bool get isLoading => _isLoading;

  AppModeProvider() {
    _loadPrefs();
  }

  // ----------------------------------------------------------
  // PUBLIC SETTERS
  // ----------------------------------------------------------

  Future<void> setMode(AppMode mode) async {
    if (_currentMode == mode) return;
    _currentMode = mode;
    _triggerHaptic(HapticFeedbackType.selectionClick);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_mode', mode.index);
  }

  Future<void> toggleDark() async {
    _isDark = !_isDark;
    _triggerHaptic(HapticFeedbackType.lightImpact);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_dark', _isDark);
  }

  Future<void> setDark(bool value) async {
    if (_isDark == value) return;
    _isDark = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_dark', _isDark);
  }

  Future<void> toggleHaptics() async {
    _useHaptics = !_useHaptics;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_haptics', _useHaptics);
  }

  Future<void> toggleReduceMotion() async {
    _reduceMotion = !_reduceMotion;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reduce_motion', _reduceMotion);
  }

  Future<void> setTextScaleFactor(double factor) async {
    final clamped = factor.clamp(0.8, 2.0);
    if (_textScaleFactor == clamped) return;
    _textScaleFactor = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('text_scale', _textScaleFactor);
  }

  // Haptic wrapper respecting user preference
  void _triggerHaptic(HapticFeedbackType type) {
    if (!_useHaptics) return;
    switch (type) {
      case HapticFeedbackType.selectionClick:
        HapticFeedback.selectionClick();
        break;
      case HapticFeedbackType.lightImpact:
        HapticFeedback.lightImpact();
        break;
      case HapticFeedbackType.mediumImpact:
        HapticFeedback.mediumImpact();
        break;
      case HapticFeedbackType.heavyImpact:
        HapticFeedback.heavyImpact();
        break;
    }
  }

  void triggerMessageSentHaptic() =>
      _triggerHaptic(HapticFeedbackType.lightImpact);
  void triggerReactionHaptic() =>
      _triggerHaptic(HapticFeedbackType.selectionClick);
  void triggerErrorHaptic() => _triggerHaptic(HapticFeedbackType.heavyImpact);
  void triggerSuccessHaptic() =>
      _triggerHaptic(HapticFeedbackType.mediumImpact);

  // ----------------------------------------------------------
  // LOAD
  // ----------------------------------------------------------

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeIndex = prefs.getInt('app_mode');
      final dark = prefs.getBool('app_dark') ?? false;
      final haptics = prefs.getBool('use_haptics') ?? true;
      final reduceMotion = prefs.getBool('reduce_motion') ?? false;
      final textScale = prefs.getDouble('text_scale') ?? 1.0;

      if (modeIndex != null && modeIndex < AppMode.values.length) {
        _currentMode = AppMode.values[modeIndex];
      }
      _isDark = dark;
      _useHaptics = haptics;
      _reduceMotion = reduceMotion;
      _textScaleFactor = textScale.clamp(0.8, 2.0);
    } catch (_) {
      // Use defaults on error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ----------------------------------------------------------
  // DESIGN TOKENS
  // ----------------------------------------------------------

  AppModeTokens get tokens {
    switch (_currentMode) {
      // ─────────────────────────────────────────
      // STUDENT
      // ─────────────────────────────────────────
      case AppMode.student:
        return _isDark
            ? const AppModeTokens(
                primaryColor: Color(0xFF9B59FB),
                secondaryColor: Color(0xFFFF9F43),
                accentColor: Color(0xFFFF6B9D),
                myBubbleGradientStart: Color(0xFF9B59FB),
                myBubbleGradientEnd: Color(0xFF6C3FC6),
                peerBubbleColor: Color(0xFF2A2A3D),
                myBubbleTextColor: Colors.white,
                peerBubbleTextColor: Color(0xFFE8E8F0),
                inputBarColor: Color(0xFF1A1A2E),
                inputBorderColor: Color(0xFF3D3D5C),
                scaffoldBg: Color(0xFF0D0D1A),
                chatBg: Color(0xFF121226),
                appBarBg: Color(0xFF1A1A2E),
                timestampColor: Color(0xFF8888AA),
                unreadBadgeColor: Color(0xFFFF6B9D),
                onlineIndicatorColor: Color(0xFF4ECCA3),
                reactionBubbleColor: Color(0xFF2A2A3D),
                dividerColor: Color(0xFF2A2A3D),
                surfaceColor: Color(0xFF1F1F35),
                errorColor: Color(0xFFFF6B6B),
                bubbleFontSize: 15.5,
                inputFontSize: 15.0,
                captionFontSize: 11.0,
                titleFontSize: 18.0,
                headerFontSize: 22.0,
                bubbleFontWeight: FontWeight.w400,
                lineHeightMultiplier: 1.4,
                letterSpacing: 0.1,
                bubblePadding: 12.0,
                bubbleRadius: 20.0,
                avatarSize: 40.0,
                inputBarHeight: 52.0,
                reactionSize: 28.0,
                iconSize: 24.0,
                appBarHeight: 60.0,
                messageSpacing: 4.0,
                sectionSpacing: 16.0,
                bubbleShadow: [
                  BoxShadow(
                    color: Color(0x449B59FB),
                    blurRadius: 12,
                    spreadRadius: 0,
                    offset: Offset(0, 4),
                  ),
                ],
                inputShadow: [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
                appBarShadow: [],
                elevation: 0,
                animationDuration: Duration(milliseconds: 220),
                longAnimationDuration: Duration(milliseconds: 450),
                animationCurve: Curves.easeOutCubic,
                minTouchTarget: 44.0,
                highContrast: false,
                focusRingWidth: 2.0,
              )
            : const AppModeTokens(
                primaryColor: Color(0xFF7C4DFF),
                secondaryColor: Color(0xFFFF9F43),
                accentColor: Color(0xFFFF4081),
                myBubbleGradientStart: Color(0xFF7C4DFF),
                myBubbleGradientEnd: Color(0xFF9B59FB),
                peerBubbleColor: Color(0xFFF0EEFF),
                myBubbleTextColor: Colors.white,
                peerBubbleTextColor: Color(0xFF1A1A2E),
                inputBarColor: Color(0xFFFAFAFF),
                inputBorderColor: Color(0xFFDDD8FF),
                scaffoldBg: Color(0xFFF5F4FF),
                chatBg: Color(0xFFEFEEFF),
                appBarBg: Colors.white,
                timestampColor: Color(0xFF9999BB),
                unreadBadgeColor: Color(0xFFFF4081),
                onlineIndicatorColor: Color(0xFF00C853),
                reactionBubbleColor: Color(0xFFF0EEFF),
                dividerColor: Color(0xFFEEEEF8),
                surfaceColor: Color(0xFFFAFAFF),
                errorColor: Color(0xFFE53935),
                bubbleFontSize: 15.5,
                inputFontSize: 15.0,
                captionFontSize: 11.0,
                titleFontSize: 18.0,
                headerFontSize: 22.0,
                bubbleFontWeight: FontWeight.w400,
                lineHeightMultiplier: 1.4,
                letterSpacing: 0.1,
                bubblePadding: 12.0,
                bubbleRadius: 20.0,
                avatarSize: 40.0,
                inputBarHeight: 52.0,
                reactionSize: 28.0,
                iconSize: 24.0,
                appBarHeight: 60.0,
                messageSpacing: 4.0,
                sectionSpacing: 16.0,
                bubbleShadow: [
                  BoxShadow(
                    color: Color(0x337C4DFF),
                    blurRadius: 8,
                    spreadRadius: 0,
                    offset: Offset(0, 3),
                  ),
                ],
                inputShadow: [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
                appBarShadow: [
                  BoxShadow(
                    color: Color(0x0A7C4DFF),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
                elevation: 0,
                animationDuration: Duration(milliseconds: 220),
                longAnimationDuration: Duration(milliseconds: 450),
                animationCurve: Curves.easeOutCubic,
                minTouchTarget: 44.0,
                highContrast: false,
                focusRingWidth: 2.0,
              );

      // ─────────────────────────────────────────
      // WORK
      // ─────────────────────────────────────────
      case AppMode.work:
        return _isDark
            ? const AppModeTokens(
                primaryColor: Color(0xFF2E86DE),
                secondaryColor: Color(0xFF1ABC9C),
                accentColor: Color(0xFFF39C12),
                myBubbleGradientStart: Color(0xFF2E86DE),
                myBubbleGradientEnd: Color(0xFF1B6BBE),
                peerBubbleColor: Color(0xFF1E2430),
                myBubbleTextColor: Colors.white,
                peerBubbleTextColor: Color(0xFFD0D8E8),
                inputBarColor: Color(0xFF141920),
                inputBorderColor: Color(0xFF2A3345),
                scaffoldBg: Color(0xFF0C1117),
                chatBg: Color(0xFF111720),
                appBarBg: Color(0xFF141920),
                timestampColor: Color(0xFF607090),
                unreadBadgeColor: Color(0xFF2E86DE),
                onlineIndicatorColor: Color(0xFF1ABC9C),
                reactionBubbleColor: Color(0xFF1E2430),
                dividerColor: Color(0xFF1E2430),
                surfaceColor: Color(0xFF1A2030),
                errorColor: Color(0xFFE74C3C),
                bubbleFontSize: 14.0,
                inputFontSize: 14.0,
                captionFontSize: 11.0,
                titleFontSize: 17.0,
                headerFontSize: 20.0,
                bubbleFontWeight: FontWeight.w400,
                lineHeightMultiplier: 1.5,
                letterSpacing: 0.0,
                bubblePadding: 10.0,
                bubbleRadius: 8.0,
                avatarSize: 36.0,
                inputBarHeight: 48.0,
                reactionSize: 24.0,
                iconSize: 22.0,
                appBarHeight: 56.0,
                messageSpacing: 2.0,
                sectionSpacing: 12.0,
                bubbleShadow: [
                  BoxShadow(
                    color: Color(0x222E86DE),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
                inputShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 4,
                    offset: Offset(0, -1),
                  ),
                ],
                appBarShadow: [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 1,
                    offset: Offset(0, 1),
                  ),
                ],
                elevation: 0.5,
                animationDuration: Duration(milliseconds: 160),
                longAnimationDuration: Duration(milliseconds: 300),
                animationCurve: Curves.easeOut,
                minTouchTarget: 44.0,
                highContrast: false,
                focusRingWidth: 2.0,
              )
            : const AppModeTokens(
                primaryColor: Color(0xFF2E86DE),
                secondaryColor: Color(0xFF1ABC9C),
                accentColor: Color(0xFFF39C12),
                myBubbleGradientStart: Color(0xFF2E86DE),
                myBubbleGradientEnd: Color(0xFF3A9AEF),
                peerBubbleColor: Color(0xFFF0F4FA),
                myBubbleTextColor: Colors.white,
                peerBubbleTextColor: Color(0xFF1A2540),
                inputBarColor: Colors.white,
                inputBorderColor: Color(0xFFDDE4EF),
                scaffoldBg: Color(0xFFF4F7FC),
                chatBg: Color(0xFFECF1F8),
                appBarBg: Colors.white,
                timestampColor: Color(0xFF8095B0),
                unreadBadgeColor: Color(0xFF2E86DE),
                onlineIndicatorColor: Color(0xFF1ABC9C),
                reactionBubbleColor: Color(0xFFF0F4FA),
                dividerColor: Color(0xFFE0E8F0),
                surfaceColor: Colors.white,
                errorColor: Color(0xFFE74C3C),
                bubbleFontSize: 14.0,
                inputFontSize: 14.0,
                captionFontSize: 11.0,
                titleFontSize: 17.0,
                headerFontSize: 20.0,
                bubbleFontWeight: FontWeight.w400,
                lineHeightMultiplier: 1.5,
                letterSpacing: 0.0,
                bubblePadding: 10.0,
                bubbleRadius: 8.0,
                avatarSize: 36.0,
                inputBarHeight: 48.0,
                reactionSize: 24.0,
                iconSize: 22.0,
                appBarHeight: 56.0,
                messageSpacing: 2.0,
                sectionSpacing: 12.0,
                bubbleShadow: [
                  BoxShadow(
                    color: Color(0x182E86DE),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
                inputShadow: [
                  BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 4,
                    offset: Offset(0, -1),
                  ),
                ],
                appBarShadow: [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 1,
                    offset: Offset(0, 1),
                  ),
                ],
                elevation: 0.5,
                animationDuration: Duration(milliseconds: 160),
                longAnimationDuration: Duration(milliseconds: 300),
                animationCurve: Curves.easeOut,
                minTouchTarget: 44.0,
                highContrast: false,
                focusRingWidth: 2.0,
              );

      // ─────────────────────────────────────────
      // ELDER
      // ─────────────────────────────────────────
      case AppMode.elder:
        return _isDark
            ? const AppModeTokens(
                primaryColor: Color(0xFF4CAF82),
                secondaryColor: Color(0xFFFFD369),
                accentColor: Color(0xFF64B5F6),
                myBubbleGradientStart: Color(0xFF4CAF82),
                myBubbleGradientEnd: Color(0xFF357A5A),
                peerBubbleColor: Color(0xFF1C2A22),
                myBubbleTextColor: Colors.white,
                peerBubbleTextColor: Color(0xFFD4EDE0),
                inputBarColor: Color(0xFF131D17),
                inputBorderColor: Color(0xFF2D4A38),
                scaffoldBg: Color(0xFF0C140F),
                chatBg: Color(0xFF101810),
                appBarBg: Color(0xFF131D17),
                timestampColor: Color(0xFF6A9A7A),
                unreadBadgeColor: Color(0xFFFFD369),
                onlineIndicatorColor: Color(0xFF4CAF82),
                reactionBubbleColor: Color(0xFF1C2A22),
                dividerColor: Color(0xFF1C2A22),
                surfaceColor: Color(0xFF172217),
                errorColor: Color(0xFFFF6B6B),
                bubbleFontSize: 20.0,
                inputFontSize: 20.0,
                captionFontSize: 14.0,
                titleFontSize: 24.0,
                headerFontSize: 28.0,
                bubbleFontWeight: FontWeight.w500,
                lineHeightMultiplier: 1.6,
                letterSpacing: 0.2,
                bubblePadding: 18.0,
                bubbleRadius: 16.0,
                avatarSize: 52.0,
                inputBarHeight: 68.0,
                reactionSize: 40.0,
                iconSize: 32.0,
                appBarHeight: 72.0,
                messageSpacing: 8.0,
                sectionSpacing: 24.0,
                bubbleShadow: [
                  BoxShadow(
                    color: Color(0x444CAF82),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
                inputShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 8,
                    offset: Offset(0, -3),
                  ),
                ],
                appBarShadow: [],
                elevation: 0,
                animationDuration: Duration(milliseconds: 300),
                longAnimationDuration: Duration(milliseconds: 600),
                animationCurve: Curves.easeInOutCubic,
                minTouchTarget: 56.0,
                highContrast: true,
                focusRingWidth: 3.0,
              )
            : const AppModeTokens(
                primaryColor: Color(0xFF2E7D32),
                secondaryColor: Color(0xFFF9A825),
                accentColor: Color(0xFF1565C0),
                myBubbleGradientStart: Color(0xFF388E3C),
                myBubbleGradientEnd: Color(0xFF2E7D32),
                peerBubbleColor: Color(0xFFF1F8F4),
                myBubbleTextColor: Colors.white,
                peerBubbleTextColor: Color(0xFF1B3A25),
                inputBarColor: Colors.white,
                inputBorderColor: Color(0xFFC8E6C9),
                scaffoldBg: Color(0xFFF1F9F3),
                chatBg: Color(0xFFE8F5EC),
                appBarBg: Colors.white,
                timestampColor: Color(0xFF4A7A56),
                unreadBadgeColor: Color(0xFFF9A825),
                onlineIndicatorColor: Color(0xFF2E7D32),
                reactionBubbleColor: Color(0xFFF1F8F4),
                dividerColor: Color(0xFFC8E6C9),
                surfaceColor: Colors.white,
                errorColor: Color(0xFFC62828),
                bubbleFontSize: 20.0,
                inputFontSize: 20.0,
                captionFontSize: 14.0,
                titleFontSize: 24.0,
                headerFontSize: 28.0,
                bubbleFontWeight: FontWeight.w500,
                lineHeightMultiplier: 1.6,
                letterSpacing: 0.2,
                bubblePadding: 18.0,
                bubbleRadius: 16.0,
                avatarSize: 52.0,
                inputBarHeight: 68.0,
                reactionSize: 40.0,
                iconSize: 32.0,
                appBarHeight: 72.0,
                messageSpacing: 8.0,
                sectionSpacing: 24.0,
                bubbleShadow: [
                  BoxShadow(
                    color: Color(0x332E7D32),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
                inputShadow: [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 8,
                    offset: Offset(0, -3),
                  ),
                ],
                appBarShadow: [
                  BoxShadow(
                    color: Color(0x0A2E7D32),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
                elevation: 0,
                animationDuration: Duration(milliseconds: 300),
                longAnimationDuration: Duration(milliseconds: 600),
                animationCurve: Curves.easeInOutCubic,
                minTouchTarget: 56.0,
                highContrast: true,
                focusRingWidth: 3.0,
              );
    }
  }

  // ----------------------------------------------------------
  // EFFECTIVE ANIMATION DURATION (respects reduceMotion)
  // ----------------------------------------------------------

  Duration get effectiveAnimationDuration => _reduceMotion
      ? const Duration(milliseconds: 1)
      : tokens.animationDuration;

  Duration get effectiveLongAnimationDuration => _reduceMotion
      ? const Duration(milliseconds: 1)
      : tokens.longAnimationDuration;

  // ----------------------------------------------------------
  // THEME DATA (Material 3)
  // ----------------------------------------------------------

  ThemeData get themeData {
    final t = tokens;
    final brightness = _isDark ? Brightness.dark : Brightness.light;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: t.primaryColor,
        brightness: brightness,
        primary: t.primaryColor,
        secondary: t.secondaryColor,
        tertiary: t.accentColor,
        surface: t.surfaceColor,
        error: t.errorColor,
      ),
      scaffoldBackgroundColor: t.scaffoldBg,
      fontFamily: _fontFamily,
      textTheme: _buildTextTheme(t),
      appBarTheme: AppBarTheme(
        backgroundColor: t.appBarBg,
        foregroundColor: _isDark ? Colors.white : const Color(0xFF1A1A2E),
        elevation: t.elevation,
        shadowColor: t.appBarShadow.isNotEmpty
            ? t.appBarShadow.first.color
            : Colors.transparent,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: t.appBarHeight,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: t.titleFontSize,
          fontWeight: FontWeight.w700,
          color: _isDark ? Colors.white : const Color(0xFF1A1A2E),
          letterSpacing: t.letterSpacing,
        ),
        iconTheme: IconThemeData(
          size: t.iconSize,
          color: t.primaryColor,
        ),
        actionsIconTheme: IconThemeData(
          size: t.iconSize,
          color: t.primaryColor,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.primaryColor,
          foregroundColor: t.myBubbleTextColor,
          minimumSize: Size(88, t.minTouchTarget),
          padding: EdgeInsets.symmetric(
            vertical: _currentMode == AppMode.elder ? 16 : 12,
            horizontal: _currentMode == AppMode.elder ? 28 : 20,
          ),
          textStyle: TextStyle(
            fontSize: t.inputFontSize,
            fontWeight: FontWeight.w600,
            fontFamily: _fontFamily,
            letterSpacing: t.letterSpacing,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              _currentMode == AppMode.work ? 6 : 12,
            ),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.primaryColor,
          minimumSize: Size(88, t.minTouchTarget),
          side: BorderSide(color: t.primaryColor, width: 1.5),
          padding: EdgeInsets.symmetric(
            vertical: _currentMode == AppMode.elder ? 16 : 12,
            horizontal: _currentMode == AppMode.elder ? 28 : 20,
          ),
          textStyle: TextStyle(
            fontSize: t.inputFontSize,
            fontWeight: FontWeight.w600,
            fontFamily: _fontFamily,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              _currentMode == AppMode.work ? 6 : 12,
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.primaryColor,
          minimumSize: Size(44, t.minTouchTarget),
          textStyle: TextStyle(
            fontSize: t.inputFontSize,
            fontWeight: FontWeight.w600,
            fontFamily: _fontFamily,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.inputBarColor,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: _currentMode == AppMode.elder ? 16 : 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            _currentMode == AppMode.work ? 6 : 24,
          ),
          borderSide: BorderSide(color: t.inputBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            _currentMode == AppMode.work ? 6 : 24,
          ),
          borderSide: BorderSide(color: t.inputBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            _currentMode == AppMode.work ? 6 : 24,
          ),
          borderSide:
              BorderSide(color: t.primaryColor, width: t.focusRingWidth),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            _currentMode == AppMode.work ? 6 : 24,
          ),
          borderSide: BorderSide(color: t.errorColor, width: 1.5),
        ),
        hintStyle: TextStyle(
          fontSize: t.inputFontSize,
          color: _isDark ? Colors.white38 : Colors.black38,
          fontFamily: _fontFamily,
        ),
      ),
      iconTheme: IconThemeData(
        size: t.iconSize,
        color: t.primaryColor,
      ),
      dividerTheme: DividerThemeData(
        color: t.dividerColor,
        thickness: _currentMode == AppMode.elder ? 1.0 : 0.5,
      ),
      cardTheme: CardThemeData(
        color: t.surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            _currentMode == AppMode.work ? 8 : 16,
          ),
          side: BorderSide(color: t.dividerColor, width: 0.5),
        ),
        margin: EdgeInsets.symmetric(
          vertical: t.messageSpacing,
          horizontal: 0,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.peerBubbleColor,
        labelStyle: TextStyle(
          fontSize: t.captionFontSize,
          fontFamily: _fontFamily,
          color: t.peerBubbleTextColor,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: _currentMode == AppMode.elder ? 12 : 8,
          vertical: _currentMode == AppMode.elder ? 8 : 4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: t.inputBorderColor, width: 0.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.surfaceColor,
        contentTextStyle: TextStyle(
          fontSize: t.inputFontSize,
          fontFamily: _fontFamily,
          color: _isDark ? Colors.white : const Color(0xFF1A1A2E),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.appBarBg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        elevation: 8,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.appBarBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            _currentMode == AppMode.work ? 8 : 20,
          ),
        ),
        titleTextStyle: TextStyle(
          fontSize: t.titleFontSize,
          fontWeight: FontWeight.w700,
          fontFamily: _fontFamily,
          color: _isDark ? Colors.white : const Color(0xFF1A1A2E),
        ),
        contentTextStyle: TextStyle(
          fontSize: t.inputFontSize,
          fontFamily: _fontFamily,
          color: _isDark ? Colors.white70 : Colors.black87,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return t.primaryColor;
          return _isDark ? Colors.white54 : Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return t.primaryColor.withOpacity(0.4);
          }
          return _isDark ? Colors.white12 : Colors.black12;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: t.primaryColor,
        thumbColor: t.primaryColor,
        inactiveTrackColor: t.primaryColor.withOpacity(0.3),
        trackHeight: _currentMode == AppMode.elder ? 6.0 : 4.0,
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: _currentMode == AppMode.elder ? 14.0 : 10.0,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.primaryColor,
        circularTrackColor: t.primaryColor.withOpacity(0.2),
      ),
    );
  }

  // ----------------------------------------------------------
  // HELPERS
  // ----------------------------------------------------------

  String get _fontFamily {
    switch (_currentMode) {
      case AppMode.student:
        return 'Nunito';
      case AppMode.work:
        return 'IBM Plex Sans';
      case AppMode.elder:
        return 'Lato';
    }
  }

  TextTheme _buildTextTheme(AppModeTokens t) {
    final bodyColor =
        _isDark ? const Color(0xFFE8E8F0) : const Color(0xFF1A1A2E);
    final secondaryColor = _isDark ? Colors.white70 : Colors.black54;
    final captionColor = _isDark ? Colors.white54 : Colors.black45;

    return TextTheme(
      displayLarge: TextStyle(
        fontSize: t.headerFontSize + 12,
        fontWeight: FontWeight.w800,
        color: bodyColor,
        fontFamily: _fontFamily,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      displayMedium: TextStyle(
        fontSize: t.headerFontSize + 6,
        fontWeight: FontWeight.w700,
        color: bodyColor,
        fontFamily: _fontFamily,
        height: 1.25,
      ),
      displaySmall: TextStyle(
        fontSize: t.headerFontSize,
        fontWeight: FontWeight.w700,
        color: bodyColor,
        fontFamily: _fontFamily,
        height: 1.3,
      ),
      headlineMedium: TextStyle(
        fontSize: t.titleFontSize + 2,
        fontWeight: FontWeight.w700,
        color: bodyColor,
        fontFamily: _fontFamily,
      ),
      headlineSmall: TextStyle(
        fontSize: t.titleFontSize,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        fontFamily: _fontFamily,
      ),
      titleLarge: TextStyle(
        fontSize: t.titleFontSize - 2,
        fontWeight: FontWeight.w700,
        color: bodyColor,
        fontFamily: _fontFamily,
        letterSpacing: t.letterSpacing,
      ),
      titleMedium: TextStyle(
        fontSize: t.bubbleFontSize + 2,
        fontWeight: FontWeight.w700,
        color: bodyColor,
        fontFamily: _fontFamily,
        letterSpacing: t.letterSpacing,
      ),
      titleSmall: TextStyle(
        fontSize: t.bubbleFontSize,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        fontFamily: _fontFamily,
      ),
      bodyLarge: TextStyle(
        fontSize: t.bubbleFontSize + 0.5,
        fontWeight: t.bubbleFontWeight,
        color: bodyColor,
        fontFamily: _fontFamily,
        height: t.lineHeightMultiplier,
        letterSpacing: t.letterSpacing,
      ),
      bodyMedium: TextStyle(
        fontSize: t.bubbleFontSize - 1,
        color: bodyColor,
        fontFamily: _fontFamily,
        height: t.lineHeightMultiplier,
      ),
      bodySmall: TextStyle(
        fontSize: t.captionFontSize + 1,
        color: secondaryColor,
        fontFamily: _fontFamily,
      ),
      labelLarge: TextStyle(
        fontSize: t.inputFontSize,
        fontWeight: FontWeight.w600,
        fontFamily: _fontFamily,
        letterSpacing: t.letterSpacing,
      ),
      labelMedium: TextStyle(
        fontSize: t.captionFontSize + 1,
        fontWeight: FontWeight.w500,
        fontFamily: _fontFamily,
      ),
      labelSmall: TextStyle(
        fontSize: t.captionFontSize,
        color: captionColor,
        fontFamily: _fontFamily,
        letterSpacing: 0.4,
      ),
    );
  }

  // ----------------------------------------------------------
  // UTILITY: SystemUI Overlay Style
  // ----------------------------------------------------------

  SystemUiOverlayStyle get systemOverlayStyle {
    final t = tokens;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: _isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: t.appBarBg,
      systemNavigationBarIconBrightness:
          _isDark ? Brightness.light : Brightness.dark,
    );
  }

  // ----------------------------------------------------------
  // DEBUG
  // ----------------------------------------------------------

  Map<String, dynamic> exportConfig() => {
        'mode': _currentMode.name,
        'isDark': _isDark,
        'useHaptics': _useHaptics,
        'reduceMotion': _reduceMotion,
        'textScaleFactor': _textScaleFactor,
        'fontFamily': _fontFamily,
      };
}

// ============================================================
// HAPTIC FEEDBACK TYPE ENUM (internal helper)
// ============================================================

enum HapticFeedbackType {
  selectionClick,
  lightImpact,
  mediumImpact,
  heavyImpact,
}
