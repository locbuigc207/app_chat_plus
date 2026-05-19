import 'package:flutter/material.dart';

class AppThemes {
  
  static const double spaceXS = 4.0;
  static const double spaceSM = 8.0;
  static const double spaceMD = 16.0;
  static const double spaceLG = 24.0;
  static const double spaceXL = 32.0;
  static const double spaceXXL = 48.0;

  
  static const double radiusSM = 8.0;
  static const double radiusMD = 12.0;
  static const double radiusLG = 16.0;
  static const double radiusXL = 24.0;
  static const double radiusFull = 100.0;

  
  static List<BoxShadow> shadowSM(Color color) => [
        BoxShadow(
          color: color.withOpacity(0.08),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> shadowMD(Color color) => [
        BoxShadow(
          color: color.withOpacity(0.12),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> shadowLG(Color color) => [
        BoxShadow(
          color: color.withOpacity(0.16),
          blurRadius: 32,
          offset: const Offset(0, 8),
        ),
      ];

  
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 24,
          offset: const Offset(0, 8),
          spreadRadius: 0,
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.02),
          blurRadius: 8,
          offset: const Offset(0, 4),
          spreadRadius: 0,
        ),
      ];

  
  static ThemeData lightTheme(Color primaryColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
      surface: const Color(0xFFF8F9FC),
      background: const Color(0xFFF0F2F8),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: const Color(0xFFF0F2F8),
      fontFamily: 'Inter',

      
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withOpacity(0.06),
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Color(0xFF1A1D2E),
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: primaryColor, size: 22),
        actionsIconTheme: IconThemeData(color: primaryColor, size: 22),
      ),

      
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXL),
        ),
        shadowColor: Colors.black.withOpacity(0.06),
        margin: EdgeInsets.zero,
      ),

      
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),

      
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),

      
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF0F2F8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLG),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLG),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLG),
          borderSide: BorderSide(color: primaryColor, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spaceMD,
          vertical: spaceSM + 4,
        ),
        hintStyle: const TextStyle(
          color: Color(0xFFAAB0C4),
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
      ),

      
      dividerTheme: DividerThemeData(
        color: const Color(0xFF8E8E93).withOpacity(0.15),
        thickness: 1,
        space: 1,
      ),

      
      listTileTheme: const ListTileThemeData(
        contentPadding:
            EdgeInsets.symmetric(horizontal: spaceMD, vertical: spaceXS),
        minVerticalPadding: spaceXS,
      ),

      
      textTheme: _buildTextTheme(const Color(0xFF1A1D2E)),
    );
  }

  
  static ThemeData darkTheme(Color primaryColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
      surface: const Color(0xFF1E2130),
      background: const Color(0xFF141622),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: const Color(0xFF141622),
      fontFamily: 'Inter',
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF1E2130),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Color(0xFFF0F2F8),
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: primaryColor, size: 22),
        actionsIconTheme: IconThemeData(color: primaryColor, size: 22),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E2130),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXL),
        ),
        margin: EdgeInsets.zero,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF1E2130),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF252A3D),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLG),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLG),
          borderSide: const BorderSide(color: Color(0xFF2E3448), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLG),
          borderSide: BorderSide(color: primaryColor, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spaceMD,
          vertical: spaceSM + 4,
        ),
        hintStyle: const TextStyle(
          color: Color(0xFF5A6080),
          fontSize: 14,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF252A3D),
        thickness: 1,
        space: 1,
      ),
      textTheme: _buildTextTheme(const Color(0xFFF0F2F8)),
    );
  }

  static TextTheme _buildTextTheme(Color baseColor) {
    return TextTheme(
      displayLarge: TextStyle(
        color: baseColor,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1.2,
      ),
      displayMedium: TextStyle(
        color: baseColor,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.25,
      ),
      headlineLarge: TextStyle(
        color: baseColor,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      headlineMedium: TextStyle(
        color: baseColor,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      headlineSmall: TextStyle(
        color: baseColor,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: baseColor,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleMedium: TextStyle(
        color: baseColor,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: TextStyle(
        color: baseColor,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        color: baseColor.withOpacity(0.75),
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
      bodySmall: TextStyle(
        color: baseColor.withOpacity(0.55),
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.3,
      ),
      labelLarge: TextStyle(
        color: baseColor,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
    );
  }
}
