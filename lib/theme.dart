import 'package:flutter/material.dart';

class AppTheme {
  // Core Colors
  static const Color primaryOrange = Color(0xFFFF9900);
  static const Color secondaryOrange = Color(0xFFFF6B35);

  // Background Colors - Modern Dark Theme
  static const Color darkBlue = Color(0xFF0D1117);
  static const Color darkBlueMid = Color(0xFF161B22);
  static const Color darkBlueLight = Color(0xFF21262D);

  // Accent Colors for Book Tiles
  static const Color accentPurple = Color(0xFF8B5CF6);
  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color accentPink = Color(0xFFEC4899);
  static const Color accentTeal = Color(0xFF14B8A6);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color accentRed = Color(0xFFEF4444);
  static const Color accentGreen = Color(0xFF10B981);
  static const Color accentIndigo = Color(0xFF6366F1);
  static const Color accentCyan = Color(0xFF06B6D4);
  static const Color accentRose = Color(0xFFF43F5E);
  static const Color accentEmerald = Color(0xFF34D399);

  static const List<Color> bookColors = [
    accentIndigo,
    accentPurple,
    accentPink,
    accentTeal,
    accentAmber,
    accentRed,
    accentGreen,
    accentBlue,
    accentCyan,
    accentRose,
    accentEmerald,
  ];

  // Modern Gradient Backgrounds
  static const LinearGradient mainBackground = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D1117), Color(0xFF111827), Color(0xFF1F2937)],
    stops: [0.0, 0.5, 1.0],
  );

  // Card Gradient
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1F2937), Color(0xFF111827)],
  );

  // Glassmorphism Effect
  static BoxDecoration glassDecoration({double radius = 16}) => BoxDecoration(
    color: Colors.white.withOpacity(0.05),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
  );

  // Modern Card Shadow
  static List<BoxShadow> modernShadow = [
    BoxShadow(
      color: Colors.black.withOpacity(0.3),
      blurRadius: 20,
      offset: const Offset(0, 10),
      spreadRadius: -5,
    ),
  ];

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryOrange,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryOrange,
        brightness: Brightness.dark,
      ),
    );
  }
}
