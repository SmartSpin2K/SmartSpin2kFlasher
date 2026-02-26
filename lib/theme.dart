import 'package:flutter/material.dart';

/// SmartSpin2k brand colors — single source of truth.
/// Change these values to restyle the entire app.
class SS2KColors {
  SS2KColors._();

  static const Color red = Color(0xFF7F0000);

  // Dark mode
  static const Color darkBg = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkSurfaceVariant = Color(0xFF2A2A2A);
  static const Color darkConsoleBg = Color(0xFF0A0A0A);
  static const Color darkBorder = Color(0xFF333333);
  static const Color darkTextMuted = Color(0xFF9E9E9E);

  // Light mode
  static const Color lightBg = Color(0xFFF5F5F5);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFEEEEEE);
  static const Color lightConsoleBg = Color(0xFFF8F8F8);
  static const Color lightBorder = Color(0xFFD0D0D0);
  static const Color lightTextMuted = Color(0xFF757575);

  /// Resolve colors by brightness.
  static Color bg(Brightness b) =>
      b == Brightness.dark ? darkBg : lightBg;
  static Color surface(Brightness b) =>
      b == Brightness.dark ? darkSurface : lightSurface;
  static Color surfaceVariant(Brightness b) =>
      b == Brightness.dark ? darkSurfaceVariant : lightSurfaceVariant;
  static Color consoleBg(Brightness b) =>
      b == Brightness.dark ? darkConsoleBg : lightConsoleBg;
  static Color border(Brightness b) =>
      b == Brightness.dark ? darkBorder : lightBorder;
  static Color textMuted(Brightness b) =>
      b == Brightness.dark ? darkTextMuted : lightTextMuted;
  static Color consoleText(Brightness b) =>
      b == Brightness.dark ? const Color(0xFFD9D9D9) : Colors.black87;
}

/// Builds the app-wide ThemeData from [SS2KColors].
ThemeData buildSS2KTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  final colorScheme = isDark
      ? const ColorScheme.dark(
          primary: SS2KColors.red,
          onPrimary: Colors.white,
          secondary: SS2KColors.red,
          onSecondary: Colors.white,
          surface: SS2KColors.darkSurface,
          onSurface: Color(0xFFD9D9D9),
          error: Color(0xFFCF6679),
        )
      : const ColorScheme.light(
          primary: SS2KColors.red,
          onPrimary: Colors.white,
          secondary: SS2KColors.red,
          onSecondary: Colors.white,
          surface: SS2KColors.lightSurface,
          onSurface: Colors.black87,
          error: Color(0xFFB00020),
        );

  return ThemeData(
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: SS2KColors.bg(brightness),
    appBarTheme: const AppBarTheme(
      backgroundColor: SS2KColors.red,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: SS2KColors.surfaceVariant(brightness),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SS2KColors.red,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SS2KColors.red,
        side: const BorderSide(color: SS2KColors.red),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: SS2KColors.border(brightness)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: SS2KColors.border(brightness)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: SS2KColors.red),
        ),
        filled: true,
        fillColor: SS2KColors.surfaceVariant(brightness),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: SS2KColors.border(brightness)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: SS2KColors.border(brightness)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: SS2KColors.red),
      ),
      filled: true,
      fillColor: SS2KColors.surfaceVariant(brightness),
    ),
    iconTheme: const IconThemeData(color: SS2KColors.red),
    dividerColor: SS2KColors.border(brightness),
  );
}
