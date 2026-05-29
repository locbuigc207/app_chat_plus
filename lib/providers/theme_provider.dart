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
}

enum BubbleStyle { modern, classic, minimal, rounded }

enum FontSize { small, medium, large, extraLarge }





class ThemePalette {
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color onPrimary;
  final Color onBackground;
  final Color onSurface;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;
  final Color divider;
  final Color outgoingBubble;
  final Color incomingBubble;
  final Color outgoingText;
  final Color incomingText;
  final Color inputBackground;
  final Color navBarBackground;
  final Color appBarBackground;
  final Color shadow;
  final Color unreadBadge;
  final Color onlineIndicator;
  final Color typingIndicator;

  const ThemePalette({
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.onPrimary,
    required this.onBackground,
    required this.onSurface,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.divider,
    required this.outgoingBubble,
    required this.incomingBubble,
    required this.outgoingText,
    required this.incomingText,
    required this.inputBackground,
    required this.navBarBackground,
    required this.appBarBackground,
    required this.shadow,
    required this.unreadBadge,
    required this.onlineIndicator,
    required this.typingIndicator,
  });
}





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

  
  static const _kThemeMode = 'theme_mode';
  static const _kThemeColor = 'theme_color';
  static const _kBubbleStyle = 'bubble_style';
  static const _kFontSize = 'font_size';
  static const _kDynamicColor = 'dynamic_color';
  static const _kShowAvatars = 'show_avatars_chat';
  static const _kCompactMode = 'compact_mode';
  static const _kWallpaperOpacity = 'wallpaper_opacity';

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

  Color get primaryColor => _primaryColorFor(_themeColor);
  Color get primaryLightColor => _primaryLightFor(_themeColor);
  Color get primaryDarkColor => _primaryDarkFor(_themeColor);
  Color get accentColor => _accentColorFor(_themeColor);

  ThemePalette get palette => isDark ? _darkPalette : _lightPalette;

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

  BorderRadius get bubbleBorderRadiusOutgoing => _bubbleBROutgoing(_bubbleStyle);
  BorderRadius get bubbleBorderRadiusIncoming => _bubbleBRIncoming(_bubbleStyle);
  EdgeInsets get bubblePadding => _bubblePadding(_bubbleStyle);
  double get bubbleElevation => _bubbleElevation(_bubbleStyle);

  
  
  

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

  Future<void> resetToDefaults() async {
    await setThemeMode(AppThemeMode.system);
    await setThemeColor(ThemeColor.blue);
    await setBubbleStyle(BubbleStyle.modern);
    await setFontSize(FontSize.medium);
    await setUseDynamicColor(false);
    await setShowAvatarsInChat(true);
    await setCompactMode(false);
    await setChatWallpaperOpacity(0.05);
  }

  
  
  

  ThemeData get lightTheme => _buildThemeData(isLight: true);
  ThemeData get darkTheme => _buildThemeData(isLight: false);

  ThemeData _buildThemeData({required bool isLight}) {
    final p = isLight ? _lightPalette : _darkPalette;
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
          fontSize: 18 * fontSizeMultiplier,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: TextStyle(
            fontSize: 15 * fontSizeMultiplier,
            fontWeight: FontWeight.w600,
          ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
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
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primaryLightColor : p.divider),
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

  
  
  

  ThemePalette get _lightPalette => ThemePalette(
        primary: primaryColor,
        primaryLight: primaryLightColor,
        primaryDark: primaryDarkColor,
        accent: accentColor,
        background: const Color(0xFFF5F5F5),
        surface: Colors.white,
        surfaceVariant: const Color(0xFFF0F0F0),
        onPrimary: Colors.white,
        onBackground: const Color(0xFF1A1A1A),
        onSurface: const Color(0xFF1A1A1A),
        textPrimary: const Color(0xFF1A1A1A),
        textSecondary: const Color(0xFF6E6E6E),
        textHint: const Color(0xFFAAAAAA),
        divider: const Color(0xFFE0E0E0),
        outgoingBubble: primaryColor,
        incomingBubble: Colors.white,
        outgoingText: Colors.white,
        incomingText: const Color(0xFF1A1A1A),
        inputBackground: const Color(0xFFEEEEEE),
        navBarBackground: Colors.white,
        appBarBackground: Colors.white,
        shadow: Colors.black.withValues(alpha: 0.08),
        unreadBadge: primaryColor,
        onlineIndicator: const Color(0xFF4CAF50),
        typingIndicator: primaryColor,
      );

  ThemePalette get _darkPalette => ThemePalette(
        primary: primaryLightColor,
        primaryLight: primaryLightColor,
        primaryDark: primaryDarkColor,
        accent: accentColor,
        background: const Color(0xFF121212),
        surface: const Color(0xFF1E1E1E),
        surfaceVariant: const Color(0xFF2A2A2A),
        onPrimary: Colors.white,
        onBackground: const Color(0xFFF5F5F5),
        onSurface: const Color(0xFFF5F5F5),
        textPrimary: const Color(0xFFF5F5F5),
        textSecondary: const Color(0xFFB0B0B0),
        textHint: const Color(0xFF707070),
        divider: const Color(0xFF2E2E2E),
        outgoingBubble: primaryDarkColor,
        incomingBubble: const Color(0xFF2A2A2A),
        outgoingText: Colors.white,
        incomingText: const Color(0xFFF5F5F5),
        inputBackground: const Color(0xFF2A2A2A),
        navBarBackground: const Color(0xFF1A1A1A),
        appBarBackground: const Color(0xFF1A1A1A),
        shadow: Colors.black.withValues(alpha: 0.4),
        unreadBadge: primaryLightColor,
        onlineIndicator: const Color(0xFF66BB6A),
        typingIndicator: primaryLightColor,
      );

  
  
  

  Color _primaryColorFor(ThemeColor c) {
    switch (c) {
      case ThemeColor.blue:
        return const Color(0xFF2196F3);
      case ThemeColor.green:
        return const Color(0xFF43A047);
      case ThemeColor.purple:
        return const Color(0xFF8E24AA);
      case ThemeColor.orange:
        return const Color(0xFFEF6C00);
      case ThemeColor.pink:
        return const Color(0xFFE91E63);
      case ThemeColor.teal:
        return const Color(0xFF009688);
      case ThemeColor.red:
        return const Color(0xFFE53935);
      case ThemeColor.indigo:
        return const Color(0xFF3949AB);
    }
  }

  Color _primaryLightFor(ThemeColor c) {
    switch (c) {
      case ThemeColor.blue:
        return const Color(0xFF64B5F6);
      case ThemeColor.green:
        return const Color(0xFF81C784);
      case ThemeColor.purple:
        return const Color(0xFFCE93D8);
      case ThemeColor.orange:
        return const Color(0xFFFFB74D);
      case ThemeColor.pink:
        return const Color(0xFFF48FB1);
      case ThemeColor.teal:
        return const Color(0xFF80CBC4);
      case ThemeColor.red:
        return const Color(0xFFEF9A9A);
      case ThemeColor.indigo:
        return const Color(0xFF9FA8DA);
    }
  }

  Color _primaryDarkFor(ThemeColor c) {
    switch (c) {
      case ThemeColor.blue:
        return const Color(0xFF1565C0);
      case ThemeColor.green:
        return const Color(0xFF1B5E20);
      case ThemeColor.purple:
        return const Color(0xFF4A148C);
      case ThemeColor.orange:
        return const Color(0xFFBF360C);
      case ThemeColor.pink:
        return const Color(0xFF880E4F);
      case ThemeColor.teal:
        return const Color(0xFF004D40);
      case ThemeColor.red:
        return const Color(0xFFB71C1C);
      case ThemeColor.indigo:
        return const Color(0xFF1A237E);
    }
  }

  Color _accentColorFor(ThemeColor c) {
    switch (c) {
      case ThemeColor.blue:
        return const Color(0xFFFF6D00);
      case ThemeColor.green:
        return const Color(0xFFFF6D00);
      case ThemeColor.purple:
        return const Color(0xFFFFD600);
      case ThemeColor.orange:
        return const Color(0xFF0288D1);
      case ThemeColor.pink:
        return const Color(0xFF1DE9B6);
      case ThemeColor.teal:
        return const Color(0xFFFF4081);
      case ThemeColor.red:
        return const Color(0xFF00B0FF);
      case ThemeColor.indigo:
        return const Color(0xFFFF6E40);
    }
  }

  
  
  

  BorderRadius _bubbleBROutgoing(BubbleStyle s) {
    switch (s) {
      case BubbleStyle.modern:
        return const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(4),
        );
      case BubbleStyle.classic:
        return const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(2),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        );
      case BubbleStyle.minimal:
        return BorderRadius.circular(8);
      case BubbleStyle.rounded:
        return BorderRadius.circular(24);
    }
  }

  BorderRadius _bubbleBRIncoming(BubbleStyle s) {
    switch (s) {
      case BubbleStyle.modern:
        return const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        );
      case BubbleStyle.classic:
        return const BorderRadius.only(
          topLeft: Radius.circular(2),
          topRight: Radius.circular(12),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        );
      case BubbleStyle.minimal:
        return BorderRadius.circular(8);
      case BubbleStyle.rounded:
        return BorderRadius.circular(24);
    }
  }

  EdgeInsets _bubblePadding(BubbleStyle s) {
    switch (s) {
      case BubbleStyle.modern:
        return const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
      case BubbleStyle.classic:
        return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
      case BubbleStyle.minimal:
        return const EdgeInsets.symmetric(horizontal: 10, vertical: 7);
      case BubbleStyle.rounded:
        return const EdgeInsets.symmetric(horizontal: 16, vertical: 11);
    }
  }

  double _bubbleElevation(BubbleStyle s) {
    switch (s) {
      case BubbleStyle.modern:
        return 1.0;
      case BubbleStyle.classic:
        return 0.5;
      case BubbleStyle.minimal:
        return 0.0;
      case BubbleStyle.rounded:
        return 2.0;
    }
  }

  
  
  

  LinearGradient get primaryGradient => LinearGradient(
        colors: [primaryColor, primaryDarkColor],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get outgoingBubbleGradient => LinearGradient(
        colors: [primaryLightColor, primaryColor],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  
  
  

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
    _chatWallpaperOpacity = prefs.getDouble(_kWallpaperOpacity) ?? 0.05;
  }
}
