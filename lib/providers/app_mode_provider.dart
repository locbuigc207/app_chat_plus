import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppMode { student, work, elder }

class AppModeProvider with ChangeNotifier {
  AppMode _currentMode = AppMode.student;

  AppMode get currentMode => _currentMode;

  AppModeProvider() {
    _loadMode();
  }

  void setMode(AppMode mode) async {
    _currentMode = mode;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_mode', mode.index);
  }

  void _loadMode() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int? modeIndex = prefs.getInt('app_mode');
    if (modeIndex != null) {
      _currentMode = AppMode.values[modeIndex];
      notifyListeners();
    }
  }

  ThemeData getThemeData() {
    switch (_currentMode) {
      case AppMode.elder:
        return ThemeData(
          primarySwatch: Colors.blue,
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            bodyMedium: TextStyle(fontSize: 22),
          ),
          iconTheme: const IconThemeData(size: 40),
        );
      case AppMode.work:
        return ThemeData(
          brightness: Brightness.dark,
          primaryColor: Colors.blueGrey,
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 14),
            bodyMedium: TextStyle(fontSize: 14),
          ),
        );
      case AppMode.student:
      default:
        return ThemeData(
          primarySwatch: Colors.purple,
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 16),
            bodyMedium: TextStyle(fontSize: 16),
          ),
        );
    }
  }
}
