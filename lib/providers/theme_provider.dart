import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:shared_preferences/shared_preferences.dart';





enum AppThemeMode { light, dark, system }

enum ThemeColor {
  
  blue,
  green,
  purple,
  orange,
  pink,
  teal,
  red,
  
  indigo,
  violet,
  rose,
  amber,
  emerald,
  sky,
  coral,
  slate,
}

enum BubbleStyle { modern, classic, minimal, rounded, sharp }

enum FontSize { small, medium, large, extraLarge }

enum ChatWallpaper { none, dots, grid, waves, diagonal, circuit }





class ThemePalette {
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color primaryContainer;
  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color surfaceElevated;
  final Color onPrimary;
  final Color onBackground;
  final Color onSurface;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;
  final Color textOnBubble;
  final Color divider;
  final Color outgoingBubble;
  final Color incomingBubble;
  final Color outgoingText;
  final Color incomingText;
  final Color inputBackground;
  final Color inputBorder;
  final Color navBarBackground;
  final Color appBarBackground;
  final Color shadow;
  final Color shadowStrong;
  final Color unreadBadge;
  final Color onlineIndicator;
  final Color typingIndicator;
  final Color reactionBackground;
  final Color pinnedBackground;
  final Color scamWarning;
  final Color reminderAccent;
  final Color successColor;
  final Color dangerColor;
  final Color warningColor;
  final Color infoColor;
  final bool isDark;

  const ThemePalette({
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.primaryContainer,
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.surfaceElevated,
    required this.onPrimary,
    required this.onBackground,
    required this.onSurface,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.textOnBubble,
    required this.divider,
    required this.outgoingBubble,
    required this.incomingBubble,
    required this.outgoingText,
    required this.incomingText,
    required this.inputBackground,
    required this.inputBorder,
    required this.navBarBackground,
    required this.appBarBackground,
    required this.shadow,
    required this.shadowStrong,
    required this.unreadBadge,
    required this.onlineIndicator,
    required this.typingIndicator,
    required this.reactionBackground,
    required this.pinnedBackground,
    required this.scamWarning,
    required this.reminderAccent,
    required this.successColor,
    required this.dangerColor,
    required this.warningColor,
    required this.infoColor,
    required this.isDark,
  });
}





class _ColorSwatch {
  final String name;
  final String nameVi;
  final Color base;
  final Color light;
  final Color dark;
  final Color container;
  final Color accent;

  const _ColorSwatch({
    required this.name,
    required this.nameVi,
    required this.base,
    required this.light,
    required this.dark,
    required this.container,
    required this.accent,
  });
}

const _swatches = <ThemeColor, _ColorSwatch>{
  
  ThemeColor.blue: _ColorSwatch(
    name: 'Blue',
    nameVi: 'Xanh dương',
    base: Color(0xFF2196F3),
    light: Color(0xFF64B5F6),
    dark: Color(0xFF1565C0),
    container: Color(0xFFE3F2FD),
    accent: Color(0xFFFF6D00),
  ),
  ThemeColor.green: _ColorSwatch(
    name: 'Green',
    nameVi: 'Xanh lá',
    base: Color(0xFF43A047),
    light: Color(0xFF81C784),
    dark: Color(0xFF1B5E20),
    container: Color(0xFFE8F5E9),
    accent: Color(0xFFFF6D00),
  ),
  ThemeColor.purple: _ColorSwatch(
    name: 'Purple',
    nameVi: 'Tím cổ điển',
    base: Color(0xFF8E24AA),
    light: Color(0xFFCE93D8),
    dark: Color(0xFF4A148C),
    container: Color(0xFFF3E5F5),
    accent: Color(0xFFFFD600),
  ),
  ThemeColor.orange: _ColorSwatch(
    name: 'Orange',
    nameVi: 'Cam',
    base: Color(0xFFEF6C00),
    light: Color(0xFFFFB74D),
    dark: Color(0xFFBF360C),
    container: Color(0xFFFFF3E0),
    accent: Color(0xFF0288D1),
  ),
  ThemeColor.pink: _ColorSwatch(
    name: 'Pink',
    nameVi: 'Hồng phấn',
    base: Color(0xFFE91E63),
    light: Color(0xFFF48FB1),
    dark: Color(0xFF880E4F),
    container: Color(0xFFFCE4EC),
    accent: Color(0xFF1DE9B6),
  ),
  ThemeColor.teal: _ColorSwatch(
    name: 'Teal',
    nameVi: 'Xanh cổ vịt',
    base: Color(0xFF009688),
    light: Color(0xFF80CBC4),
    dark: Color(0xFF004D40),
    container: Color(0xFFE0F2F1),
    accent: Color(0xFFFF4081),
  ),
  ThemeColor.red: _ColorSwatch(
    name: 'Red',
    nameVi: 'Đỏ',
    base: Color(0xFFE53935),
    light: Color(0xFFEF9A9A),
    dark: Color(0xFFB71C1C),
    container: Color(0xFFFFEBEE),
    accent: Color(0xFF00B0FF),
  ),
  
  ThemeColor.indigo: _ColorSwatch(
    name: 'Indigo',
    nameVi: 'Chàm',
    base: Color(0xFF5A67D8),
    light: Color(0xFF7F8CF7),
    dark: Color(0xFF3D4DB7),
    container: Color(0xFFEEF0FD),
    accent: Color(0xFFFF6B6B),
  ),
  ThemeColor.violet: _ColorSwatch(
    name: 'Violet',
    nameVi: 'Tím',
    base: Color(0xFF7C3AED),
    light: Color(0xFFA78BFA),
    dark: Color(0xFF5B21B6),
    container: Color(0xFFF3EEFF),
    accent: Color(0xFFFFB347),
  ),
  ThemeColor.rose: _ColorSwatch(
    name: 'Rose',
    nameVi: 'Hồng',
    base: Color(0xFFE11D48),
    light: Color(0xFFFB7185),
    dark: Color(0xFF9F1239),
    container: Color(0xFFFFF1F3),
    accent: Color(0xFF06B6D4),
  ),
  ThemeColor.amber: _ColorSwatch(
    name: 'Amber',
    nameVi: 'Hổ phách',
    base: Color(0xFFD97706),
    light: Color(0xFFFBBF24),
    dark: Color(0xFF92400E),
    container: Color(0xFFFFFBEB),
    accent: Color(0xFF8B5CF6),
  ),
  ThemeColor.emerald: _ColorSwatch(
    name: 'Emerald',
    nameVi: 'Xanh ngọc',
    base: Color(0xFF059669),
    light: Color(0xFF34D399),
    dark: Color(0xFF064E3B),
    container: Color(0xFFECFDF5),
    accent: Color(0xFFEC4899),
  ),
  ThemeColor.sky: _ColorSwatch(
    name: 'Sky',
    nameVi: 'Xanh trời',
    base: Color(0xFF0284C7),
    light: Color(0xFF38BDF8),
    dark: Color(0xFF0C4A6E),
    container: Color(0xFFF0F9FF),
    accent: Color(0xFFF97316),
  ),
  ThemeColor.coral: _ColorSwatch(
    name: 'Coral',
    nameVi: 'San hô',
    base: Color(0xFFEA580C),
    light: Color(0xFFFB923C),
    dark: Color(0xFF7C2D12),
    container: Color(0xFFFFF7ED),
    accent: Color(0xFF14B8A6),
  ),
  ThemeColor.slate: _ColorSwatch(
    name: 'Slate',
    nameVi: 'Xám xanh',
    base: Color(0xFF475569),
    light: Color(0xFF94A3B8),
    dark: Color(0xFF1E293B),
    container: Color(0xFFF8FAFC),
    accent: Color(0xFFEF4444),
  ),
};





class ThemeProvider extends ChangeNotifier {
  final SharedPreferences prefs;

  late AppThemeMode _themeMode;
  late ThemeColor _themeColor;
  late BubbleStyle _bubbleStyle;
  late FontSize _fontSize;
  late bool _useDynamicColor;
  late bool _showAvatarsInChat;
  late bool _compactMode;
  late double _chatWallpaperOpacity;
  late ChatWallpaper _chatWallpaper;
  late bool _useGradientBubble;
  late bool _showTimestampAlways;
  late bool _enableBlurEffects;

  static const _kThemeMode = 'theme_mode_v2';
  static const _kThemeColor = 'theme_color_v2';
  static const _kBubbleStyle = 'bubble_style_v2';
  static const _kFontSize = 'font_size_v2';
  static const _kDynamicColor = 'dynamic_color_v2';
  static const _kShowAvatars = 'show_avatars_chat_v2';
  static const _kCompactMode = 'compact_mode_v2';
  static const _kWallpaperOpacity = 'wallpaper_opacity_v2';
  static const _kChatWallpaper = 'chat_wallpaper_v2';
  static const _kGradientBubble = 'gradient_bubble_v2';
  static const _kTimestampAlways = 'timestamp_always_v2';
  static const _kBlurEffects = 'blur_effects_v2';

  ThemeProvider({required this.prefs}) {
    _load();
  }

  

  AppThemeMode get themeMode => _themeMode;
  ThemeColor get themeColor => _themeColor;
  BubbleStyle get bubbleStyle => _bubbleStyle;
  FontSize get fontSize => _fontSize;
  bool get useDynamicColor => _useDynamicColor;
  bool get showAvatarsInChat => _showAvatarsInChat;
  bool get compactMode => _compactMode;
  double get chatWallpaperOpacity => _chatWallpaperOpacity;
  ChatWallpaper get chatWallpaper => _chatWallpaper;
  bool get useGradientBubble => _useGradientBubble;
  bool get showTimestampAlways => _showTimestampAlways;
  bool get enableBlurEffects => _enableBlurEffects;

  bool get isDark {
    if (_themeMode == AppThemeMode.system) {
      final brightness = SchedulerBinding.instance.platformDispatcher.platformBrightness;
      return brightness == Brightness.dark;
    }
    return _themeMode == AppThemeMode.dark;
  }

  ThemeMode get flutterThemeMode {
    switch (_themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  _ColorSwatch get _swatch => _swatches[_themeColor] ?? _swatches[ThemeColor.blue]!;

  Color get primaryColor => _swatch.base;
  Color get primaryLightColor => _swatch.light;
  Color get primaryDarkColor => _swatch.dark;
  Color get primaryContainerColor => _swatch.container;
  Color get accentColor => _swatch.accent;
  String get colorName => _swatch.nameVi;

  ThemePalette get palette => isDark ? _buildDarkPalette() : _buildLightPalette();

  double get fontSizeMultiplier {
    switch (_fontSize) {
      case FontSize.small:
        return 0.85;
      case FontSize.medium:
        return 1.0;
      case FontSize.large:
        return 1.15;
      case FontSize.extraLarge:
        return 1.30;
    }
  }

  double get bubbleMaxWidthFactor => _compactMode ? 0.65 : 0.72;
  EdgeInsets get bubblePadding => _getBubblePadding();
  BorderRadius outgoingRadius(bool isLastInGroup) => _getOutgoingRadius(isLastInGroup);
  BorderRadius incomingRadius(bool isLastInGroup) => _getIncomingRadius(isLastInGroup);

  

  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await prefs.setString(_kThemeMode, mode.name);
    notifyListeners();
  }

  Future<void> setThemeColor(ThemeColor color) async {
    if (_themeColor == color) return;
    _themeColor = color;
    await prefs.setString(_kThemeColor, color.name);
    notifyListeners();
  }

  Future<void> setBubbleStyle(BubbleStyle style) async {
    if (_bubbleStyle == style) return;
    _bubbleStyle = style;
    await prefs.setString(_kBubbleStyle, style.name);
    notifyListeners();
  }

  Future<void> setFontSize(FontSize size) async {
    if (_fontSize == size) return;
    _fontSize = size;
    await prefs.setString(_kFontSize, size.name);
    notifyListeners();
  }

  Future<void> setUseDynamicColor(bool value) async {
    if (_useDynamicColor == value) return;
    _useDynamicColor = value;
    await prefs.setBool(_kDynamicColor, value);
    notifyListeners();
  }

  Future<void> setShowAvatarsInChat(bool value) async {
    if (_showAvatarsInChat == value) return;
    _showAvatarsInChat = value;
    await prefs.setBool(_kShowAvatars, value);
    notifyListeners();
  }

  Future<void> setCompactMode(bool value) async {
    if (_compactMode == value) return;
    _compactMode = value;
    await prefs.setBool(_kCompactMode, value);
    notifyListeners();
  }

  Future<void> setChatWallpaperOpacity(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    if (_chatWallpaperOpacity == clamped) return;
    _chatWallpaperOpacity = clamped;
    await prefs.setDouble(_kWallpaperOpacity, clamped);
    notifyListeners();
  }

  Future<void> setChatWallpaper(ChatWallpaper wallpaper) async {
    if (_chatWallpaper == wallpaper) return;
    _chatWallpaper = wallpaper;
    await prefs.setString(_kChatWallpaper, wallpaper.name);
    notifyListeners();
  }

  Future<void> setUseGradientBubble(bool value) async {
    if (_useGradientBubble == value) return;
    _useGradientBubble = value;
    await prefs.setBool(_kGradientBubble, value);
    notifyListeners();
  }

  Future<void> setShowTimestampAlways(bool value) async {
    if (_showTimestampAlways == value) return;
    _showTimestampAlways = value;
    await prefs.setBool(_kTimestampAlways, value);
    notifyListeners();
  }

  Future<void> setEnableBlurEffects(bool value) async {
    if (_enableBlurEffects == value) return;
    _enableBlurEffects = value;
    await prefs.setBool(_kBlurEffects, value);
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _themeMode = AppThemeMode.system;
    _themeColor = ThemeColor.blue; 
    _bubbleStyle = BubbleStyle.modern;
    _fontSize = FontSize.medium;
    _useDynamicColor = false;
    _showAvatarsInChat = true;
    _compactMode = false;
    _chatWallpaperOpacity = 0.06;
    _chatWallpaper = ChatWallpaper.none;
    _useGradientBubble = true;
    _showTimestampAlways = false;
    _enableBlurEffects = true;

    
    await prefs.remove(_kThemeMode);
    await prefs.remove(_kThemeColor);
    await prefs.remove(_kBubbleStyle);
    await prefs.remove(_kFontSize);
    await prefs.remove(_kDynamicColor);
    await prefs.remove(_kShowAvatars);
    await prefs.remove(_kCompactMode);
    await prefs.remove(_kWallpaperOpacity);
    await prefs.remove(_kChatWallpaper);
    await prefs.remove(_kGradientBubble);
    await prefs.remove(_kTimestampAlways);
    await prefs.remove(_kBlurEffects);

    notifyListeners();
  }

  

  ThemeData get lightTheme => _buildThemeData(isLight: true);
  ThemeData get darkTheme => _buildThemeData(isLight: false);

  ThemeData _buildThemeData({required bool isLight}) {
    final p = isLight ? _buildLightPalette() : _buildDarkPalette();
    final base = isLight ? ThemeData.light() : ThemeData.dark();
    final scheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: isLight ? Brightness.light : Brightness.dark,
    ).copyWith(
      primary: primaryColor,
      secondary: accentColor,
      surface: p.surface,
    );

    return base.copyWith(
      colorScheme: scheme,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: p.background,
      dividerColor: p.divider,
      appBarTheme: AppBarTheme(
        backgroundColor: p.appBarBackground,
        foregroundColor: p.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: p.textPrimary,
          fontSize: 17 * fontSizeMultiplier,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
      textTheme: _buildTextTheme(base.textTheme, p),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: TextStyle(color: p.textHint),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: p.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: TextStyle(
            fontSize: 15 * fontSizeMultiplier,
            fontWeight: FontWeight.w600,
          ),
          elevation: 0,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.divider, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.navBarBackground,
        selectedItemColor: primaryColor,
        unselectedItemColor: p.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: p.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      iconTheme: IconThemeData(color: p.textSecondary),
      dividerTheme: DividerThemeData(
        color: p.divider,
        thickness: 0.5,
        space: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primaryColor : p.textHint),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primaryColor.withValues(alpha: 0.3) : p.divider),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: TextStyle(color: p.textPrimary, fontSize: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surface,
        contentTextStyle: TextStyle(color: p.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          color: p.textPrimary,
          fontSize: 18 * fontSizeMultiplier,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  TextTheme _buildTextTheme(TextTheme base, ThemePalette p) {
    final m = fontSizeMultiplier;
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(color: p.textPrimary, fontSize: 57 * m),
      displayMedium: base.displayMedium?.copyWith(color: p.textPrimary, fontSize: 45 * m),
      displaySmall: base.displaySmall?.copyWith(color: p.textPrimary, fontSize: 36 * m),
      headlineLarge: base.headlineLarge
          ?.copyWith(color: p.textPrimary, fontSize: 32 * m, fontWeight: FontWeight.w700),
      headlineMedium: base.headlineMedium
          ?.copyWith(color: p.textPrimary, fontSize: 28 * m, fontWeight: FontWeight.w600),
      headlineSmall: base.headlineSmall
          ?.copyWith(color: p.textPrimary, fontSize: 24 * m, fontWeight: FontWeight.w600),
      titleLarge: base.titleLarge
          ?.copyWith(color: p.textPrimary, fontSize: 22 * m, fontWeight: FontWeight.w600),
      titleMedium: base.titleMedium
          ?.copyWith(color: p.textPrimary, fontSize: 16 * m, fontWeight: FontWeight.w500),
      titleSmall: base.titleSmall
          ?.copyWith(color: p.textPrimary, fontSize: 14 * m, fontWeight: FontWeight.w500),
      bodyLarge: base.bodyLarge?.copyWith(color: p.textPrimary, fontSize: 16 * m),
      bodyMedium: base.bodyMedium?.copyWith(color: p.textPrimary, fontSize: 14 * m),
      bodySmall: base.bodySmall?.copyWith(color: p.textSecondary, fontSize: 12 * m),
      labelLarge: base.labelLarge
          ?.copyWith(color: p.textPrimary, fontSize: 14 * m, fontWeight: FontWeight.w600),
      labelMedium: base.labelMedium?.copyWith(color: p.textSecondary, fontSize: 12 * m),
      labelSmall: base.labelSmall?.copyWith(color: p.textHint, fontSize: 11 * m),
    );
  }

  

  ThemePalette _buildLightPalette() => ThemePalette(
        primary: primaryColor,
        primaryLight: primaryLightColor,
        primaryDark: primaryDarkColor,
        primaryContainer: primaryContainerColor,
        accent: accentColor,
        background: const Color(0xFFF6F7FB),
        surface: Colors.white,
        surfaceVariant: const Color(0xFFF0F1F7),
        surfaceElevated: Colors.white,
        onPrimary: Colors.white,
        onBackground: const Color(0xFF1A1D2E),
        onSurface: const Color(0xFF1A1D2E),
        textPrimary: const Color(0xFF1A1D2E),
        textSecondary: const Color(0xFF6B7280),
        textHint: const Color(0xFFB0B7C3),
        textOnBubble: Colors.white,
        divider: const Color(0xFFE8EAF0),
        outgoingBubble: primaryColor,
        incomingBubble: Colors.white,
        outgoingText: Colors.white,
        incomingText: const Color(0xFF1A1D2E),
        inputBackground: const Color(0xFFF0F1F7),
        inputBorder: const Color(0xFFE8EAF0),
        navBarBackground: Colors.white,
        appBarBackground: Colors.white,
        shadow: Colors.black.withValues(alpha: 0.05),
        shadowStrong: Colors.black.withValues(alpha: 0.12),
        unreadBadge: primaryColor,
        onlineIndicator: const Color(0xFF22C55E),
        typingIndicator: primaryColor,
        reactionBackground: const Color(0xFFF0F1F7),
        pinnedBackground: primaryContainerColor,
        scamWarning: const Color(0xFFFEF2F2),
        reminderAccent: const Color(0xFF3B82F6),
        successColor: const Color(0xFF22C55E),
        dangerColor: const Color(0xFFEF4444),
        warningColor: const Color(0xFFF59E0B),
        infoColor: const Color(0xFF3B82F6),
        isDark: false,
      );

  ThemePalette _buildDarkPalette() => ThemePalette(
        primary: primaryLightColor,
        primaryLight: primaryLightColor,
        primaryDark: primaryColor,
        primaryContainer: primaryColor.withValues(alpha: 0.15),
        accent: accentColor,
        background: const Color(0xFF0D0F14),
        surface: const Color(0xFF181B24),
        surfaceVariant: const Color(0xFF1E2233),
        surfaceElevated: const Color(0xFF252A3A),
        onPrimary: Colors.white,
        onBackground: const Color(0xFFEEF2FF),
        onSurface: const Color(0xFFEEF2FF),
        textPrimary: const Color(0xFFEEF2FF),
        textSecondary: const Color(0xFF8B93B0),
        textHint: const Color(0xFF4B5568),
        textOnBubble: Colors.white,
        divider: const Color(0xFF252A3A),
        outgoingBubble: primaryDarkColor,
        incomingBubble: const Color(0xFF1E2233),
        outgoingText: Colors.white,
        incomingText: const Color(0xFFEEF2FF),
        inputBackground: const Color(0xFF1E2233),
        inputBorder: const Color(0xFF252A3A),
        navBarBackground: const Color(0xFF181B24),
        appBarBackground: const Color(0xFF0D0F14),
        shadow: Colors.black.withValues(alpha: 0.3),
        shadowStrong: Colors.black.withValues(alpha: 0.5),
        unreadBadge: primaryLightColor,
        onlineIndicator: const Color(0xFF34D399),
        typingIndicator: primaryLightColor,
        reactionBackground: const Color(0xFF252A3A),
        pinnedBackground: primaryColor.withValues(alpha: 0.12),
        scamWarning: const Color(0xFF3B0E0E),
        reminderAccent: const Color(0xFF60A5FA),
        successColor: const Color(0xFF34D399),
        dangerColor: const Color(0xFFF87171),
        warningColor: const Color(0xFFFBBF24),
        infoColor: const Color(0xFF60A5FA),
        isDark: true,
      );

  

  BorderRadius _getOutgoingRadius(bool isLastInGroup) {
    final tail = isLastInGroup ? 4.0 : 18.0;
    switch (_bubbleStyle) {
      case BubbleStyle.modern:
        return BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: const Radius.circular(20),
          bottomRight: Radius.circular(tail),
        );
      case BubbleStyle.classic:
        return BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(2),
          bottomLeft: const Radius.circular(14),
          bottomRight: const Radius.circular(14),
        );
      case BubbleStyle.minimal:
        return BorderRadius.circular(10);
      case BubbleStyle.rounded:
        return BorderRadius.only(
          topLeft: const Radius.circular(28),
          topRight: const Radius.circular(28),
          bottomLeft: const Radius.circular(28),
          bottomRight: Radius.circular(tail),
        );
      case BubbleStyle.sharp:
        return BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: const Radius.circular(16),
          bottomRight: const Radius.circular(2),
        );
    }
  }

  BorderRadius _getIncomingRadius(bool isLastInGroup) {
    final tail = isLastInGroup ? 4.0 : 18.0;
    switch (_bubbleStyle) {
      case BubbleStyle.modern:
        return BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(tail),
          bottomRight: const Radius.circular(20),
        );
      case BubbleStyle.classic:
        return BorderRadius.only(
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(14),
          bottomLeft: const Radius.circular(14),
          bottomRight: const Radius.circular(14),
        );
      case BubbleStyle.minimal:
        return BorderRadius.circular(10);
      case BubbleStyle.rounded:
        return BorderRadius.only(
          topLeft: const Radius.circular(28),
          topRight: const Radius.circular(28),
          bottomLeft: Radius.circular(tail),
          bottomRight: const Radius.circular(28),
        );
      case BubbleStyle.sharp:
        return BorderRadius.only(
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(16),
          bottomLeft: const Radius.circular(16),
          bottomRight: const Radius.circular(16),
        );
    }
  }

  EdgeInsets _getBubblePadding() {
    switch (_bubbleStyle) {
      case BubbleStyle.modern:
        return const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
      case BubbleStyle.classic:
        return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
      case BubbleStyle.minimal:
        return const EdgeInsets.symmetric(horizontal: 10, vertical: 7);
      case BubbleStyle.rounded:
        return const EdgeInsets.symmetric(horizontal: 18, vertical: 12);
      case BubbleStyle.sharp:
        return const EdgeInsets.symmetric(horizontal: 13, vertical: 9);
    }
  }

  

  LinearGradient get primaryGradient => LinearGradient(
        colors: [primaryLightColor, primaryColor],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient outgoingBubbleGradient(bool isDark) => LinearGradient(
        colors: isDark
            ? [primaryDarkColor, primaryDarkColor.withBlue(primaryDarkColor.blue + 20)]
            : [primaryLightColor.withValues(alpha: 0.9), primaryColor],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  

  static String wallpaperName(ChatWallpaper w) {
    switch (w) {
      case ChatWallpaper.none:
        return 'Không có';
      case ChatWallpaper.dots:
        return 'Chấm bi';
      case ChatWallpaper.grid:
        return 'Lưới';
      case ChatWallpaper.waves:
        return 'Sóng';
      case ChatWallpaper.diagonal:
        return 'Chéo';
      case ChatWallpaper.circuit:
        return 'Mạch in';
    }
  }

  static String bubbleStyleName(BubbleStyle s) {
    switch (s) {
      case BubbleStyle.modern:
        return 'Hiện đại';
      case BubbleStyle.classic:
        return 'Cổ điển';
      case BubbleStyle.minimal:
        return 'Tối giản';
      case BubbleStyle.rounded:
        return 'Bo tròn';
      case BubbleStyle.sharp:
        return 'Góc cạnh';
    }
  }

  static String fontSizeName(FontSize s) {
    switch (s) {
      case FontSize.small:
        return 'Nhỏ';
      case FontSize.medium:
        return 'Vừa';
      case FontSize.large:
        return 'Lớn';
      case FontSize.extraLarge:
        return 'Rất lớn';
    }
  }

  

  void _load() {
    
    _themeMode = AppThemeMode.values.firstWhere(
      (e) => e.name == (prefs.getString(_kThemeMode) ?? 'system'),
      orElse: () => AppThemeMode.system,
    );
    _themeColor = ThemeColor.values.firstWhere(
      (e) => e.name == (prefs.getString(_kThemeColor) ?? 'blue'),
      orElse: () => ThemeColor.blue,
    );
    _bubbleStyle = BubbleStyle.values.firstWhere(
      (e) => e.name == (prefs.getString(_kBubbleStyle) ?? 'modern'),
      orElse: () => BubbleStyle.modern,
    );
    _fontSize = FontSize.values.firstWhere(
      (e) => e.name == (prefs.getString(_kFontSize) ?? 'medium'),
      orElse: () => FontSize.medium,
    );
    _useDynamicColor = prefs.getBool(_kDynamicColor) ?? false;
    _showAvatarsInChat = prefs.getBool(_kShowAvatars) ?? true;
    _compactMode = prefs.getBool(_kCompactMode) ?? false;
    _chatWallpaperOpacity = prefs.getDouble(_kWallpaperOpacity) ?? 0.06;
    _chatWallpaper = ChatWallpaper.values.firstWhere(
      (e) => e.name == (prefs.getString(_kChatWallpaper) ?? 'none'),
      orElse: () => ChatWallpaper.none,
    );
    _useGradientBubble = prefs.getBool(_kGradientBubble) ?? true;
    _showTimestampAlways = prefs.getBool(_kTimestampAlways) ?? false;
    _enableBlurEffects = prefs.getBool(_kBlurEffects) ?? true;
  }
}
