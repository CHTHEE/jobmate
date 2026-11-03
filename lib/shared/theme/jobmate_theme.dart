import 'package:flutter/material.dart';

/// Shared visual tokens. Feature-specific status meanings stay in their widgets.
abstract final class JobMateTheme {
  static const primary = Color(0xFF14B8A6);
  static const darkTeal = Color(0xFF0F766E);
  static const teal50 = Color(0xFFF0FDFA);
  static const teal100 = Color(0xFFCCFBF1);
  static const teal200 = Color(0xFF99F6E4);
  static const teal300 = Color(0xFF5EEAD4);
  static const teal400 = Color(0xFF2DD4BF);
  static const teal800 = Color(0xFF115E59);
  static const teal900 = Color(0xFF134E4A);
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
    const buttonText = TextStyle(
      fontFamily: 'Outfit',
      fontFamilyFallback: ['Arial', 'sans-serif'],
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        onPrimary: heading,
        surface: Colors.white,
        onSurface: heading,
        error: error,
      ),
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme
          .apply(
            fontFamily: 'Outfit',
            fontFamilyFallback: const ['Arial', 'sans-serif'],
            bodyColor: heading,
            displayColor: heading,
          )
          .copyWith(
            headlineLarge: const TextStyle(
              fontFamily: 'DM Serif Display',
              fontFamilyFallback: ['Georgia', 'serif'],
              fontSize: 34,
              height: 1.2,
              color: heading,
            ),
            headlineMedium: const TextStyle(
              fontFamily: 'DM Serif Display',
              fontFamilyFallback: ['Georgia', 'serif'],
              fontSize: 28,
              height: 1.25,
              color: heading,
            ),
          ),
      cardColor: Colors.white,
      visualDensity: VisualDensity.standard,
      listTileTheme: const ListTileThemeData(
        iconColor: body,
        textColor: heading,
        minVerticalPadding: 10,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: darkTeal,
        linearTrackColor: Color(0xFFCCFBF1),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: const Color(0xFFF8FAFC),
        selectedColor: const Color(0xFFCCFBF1),
        side: const BorderSide(color: divider),
        labelStyle: const TextStyle(
          fontFamily: 'Outfit',
          fontFamilyFallback: ['Arial'],
          fontSize: 12,
          color: heading,
        ),
        shape: const StadiumBorder(),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: darkTeal,
        unselectedLabelColor: body,
        indicatorColor: darkTeal,
        dividerColor: divider,
      ),
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
          backgroundColor: darkTeal,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: buttonText,
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkTeal,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: buttonText,
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkTeal,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
