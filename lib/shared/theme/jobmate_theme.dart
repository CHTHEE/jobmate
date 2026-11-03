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
  static const controlRadius = 8.0;
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
      fontWeight: FontWeight.w500,
    );
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: teal,
        onPrimary: Colors.white,
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
            bodyLarge: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 14,
              height: 20 / 14,
              color: heading,
            ),
            bodyMedium: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 14,
              height: 20 / 14,
              color: heading,
            ),
            bodySmall: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 12,
              height: 16 / 12,
              color: body,
            ),
            titleLarge: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: heading,
            ),
            headlineLarge: const TextStyle(
              fontFamily: 'DM Serif Display',
              fontFamilyFallback: ['Georgia', 'serif'],
              fontSize: 24,
              height: 1.2,
              color: heading,
            ),
            headlineMedium: const TextStyle(
              fontFamily: 'DM Serif Display',
              fontFamilyFallback: ['Georgia', 'serif'],
              fontSize: 20,
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: divider),
        ),
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
          vertical: 12,
        ),
        border: outline(border),
        enabledBorder: outline(border),
        focusedBorder: outline(primary, 2),
        errorBorder: outline(error),
        focusedErrorBorder: outline(error, 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              backgroundColor: teal,
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              textStyle: buttonText,
              shape: shape,
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) return null;
                if (states.contains(WidgetState.pressed)) return teal800;
                return states.contains(WidgetState.hovered) ? darkTeal : teal;
              }),
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
