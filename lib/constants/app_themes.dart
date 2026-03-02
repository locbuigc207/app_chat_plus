import 'package:flutter/material.dart';

class AppThemes {
  static ThemeData lightTheme(Color primaryColor) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: primaryColor,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: primaryColor),
      ),
      cardColor: const Color(0xfff5f5f5),
      dividerColor: const Color(0xffe0e0e0),
    );
  }

  static ThemeData darkTheme(Color primaryColor) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: primaryColor,
      scaffoldBackgroundColor: const Color(0xff121212),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xff1e1e1e),
        elevation: 0,
      ),
      cardColor: const Color(0xff1e1e1e),
      dividerColor: const Color(0xff2c2c2c),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
      ),
    );
  }
}
