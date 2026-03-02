import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  light,
  dark,
  system,
}

enum ThemeColor {
  blue,
  green,
  purple,
  orange,
  pink,
}

class ThemeProvider extends ChangeNotifier {
  final SharedPreferences prefs;

  late AppThemeMode _themeMode;
  late ThemeColor _themeColor;

  ThemeProvider({required this.prefs}) {
    _loadThemePreferences();
  }

  AppThemeMode get themeMode => _themeMode;
  ThemeColor get themeColor => _themeColor;

  void _loadThemePreferences() {
    final themeModeString = prefs.getString('theme_mode') ?? 'system';
    _themeMode = AppThemeMode.values.firstWhere(
          (e) => e.toString() == 'AppThemeMode.$themeModeString',
      orElse: () => AppThemeMode.system,
    );

    final themeColorString = prefs.getString('theme_color') ?? 'blue';
    _themeColor = ThemeColor.values.firstWhere(
          (e) => e.toString() == 'ThemeColor.$themeColorString',
      orElse: () => ThemeColor.blue,
    );
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    _themeMode = mode;
    await prefs.setString('theme_mode', mode.toString().split('.').last);
    notifyListeners();
  }

  Future<void> setThemeColor(ThemeColor color) async {
    _themeColor = color;
    await prefs.setString('theme_color', color.toString().split('.').last);
    notifyListeners();
  }

  ThemeMode getFlutterThemeMode(BuildContext context) {
    switch (_themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  Color getPrimaryColor() {
    switch (_themeColor) {
      case ThemeColor.blue:
        return const Color(0xff2196f3);
      case ThemeColor.green:
        return const Color(0xff4caf50);
      case ThemeColor.purple:
        return const Color(0xff9c27b0);
      case ThemeColor.orange:
        return const Color(0xffff9800);
      case ThemeColor.pink:
        return const Color(0xffe91e63);
    }
  }
}



