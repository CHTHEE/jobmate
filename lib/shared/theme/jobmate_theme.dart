import 'package:flutter/material.dart';

/// Shared visual tokens. Feature-specific status meanings stay in their widgets.
abstract final class JobMateTheme {
  static const primary = Color(0xFF0F766E);
  static const teal = Color(0xFF0D9488);
  static const background = Color(0xFFF8FAFC);
  static const heading = Color(0xFF0F172A);
  static const body = Color(0xFF64748B);
  static const border = Color(0xFFCBD5E1);
  static const divider = Color(0xFFE2E8F0);
  static const error = Color(0xFFDC2626);
  static const controlRadius = 12.0;
  static const dialogRadius = 16.0;

  static ThemeData light() => apply(ThemeData(useMaterial3: true));

  /// Preserve inherited platform, typography and accessibility configuration.
  static ThemeData apply(ThemeData base) {
    OutlineInputBorder outline(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: color, width: width),
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );
    const buttonText = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: heading,
        error: error,
      ),
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme.apply(
        bodyColor: heading,
        displayColor: heading,
      ),
      cardColor: Colors.white,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: shape.copyWith(side: const BorderSide(color: divider)),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: heading,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        border: outline(border),
        enabledBorder: outline(border),
        focusedBorder: outline(primary, 2),
        errorBorder: outline(error),
        focusedErrorBorder: outline(error, 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: buttonText,
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: buttonText,
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: buttonText,
          shape: shape,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(dialogRadius),
        ),
      ),
      dividerTheme: const DividerThemeData(color: divider, thickness: 1),
    );
  }
}
