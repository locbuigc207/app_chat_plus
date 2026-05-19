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
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          textTheme: const TextTheme(
            bodyLarge: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
            bodyMedium: TextStyle(fontSize: 22, color: Colors.black87),
            labelLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          iconTheme: const IconThemeData(size: 38, color: Colors.blue),
          appBarTheme: const AppBarTheme(
            iconTheme: IconThemeData(size: 38, color: Colors.blue),
            titleTextStyle: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              textStyle:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
        );

      case AppMode.work:
        
        return ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueGrey,
            brightness: Brightness.light,
          ),
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 15, color: Colors.black87),
            bodyMedium: TextStyle(fontSize: 14, color: Colors.black87),
          ),
          appBarTheme: const AppBarTheme(
            elevation: 1,
            centerTitle: false,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
          ),
        );

      case AppMode.student:
      default:
        
        return ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF007AFF), 
            brightness: Brightness.light,
          ),
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 16, color: Colors.black87),
            bodyMedium: TextStyle(fontSize: 15, color: Colors.black87),
          ),
          appBarTheme: const AppBarTheme(
            elevation: 0,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
          ),
        );
    }
  }
}
