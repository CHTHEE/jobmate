import 'package:flutter/material.dart';

import '../theme/jobmate_theme.dart';

/// Authentication presentation layered over the shared application tokens.
abstract final class AuthStyle {
  static const teal = JobMateTheme.teal;
  static const darkTeal = JobMateTheme.darkTeal;
  static const background = JobMateTheme.background;
  static const heading = JobMateTheme.heading;
  static const body = JobMateTheme.body;
  static const label = Color(0xFF334155);
  static const border = JobMateTheme.border;
  static const muted = Color(0xFF94A3B8);
  static const error = JobMateTheme.error;
  static const success = Color(0xFF22C55E);
  static const title = TextStyle(
    fontFamily: 'DM Serif Display',
    fontFamilyFallback: ['Georgia', 'serif'],
    fontSize: 32,
    color: heading,
  );
  
  static ThemeData theme(BuildContext context) {
    final base = JobMateTheme.apply(Theme.of(context));
    OutlineInputBorder outline(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color, width: width),
        );
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: darkTeal,
        onPrimary: Colors.white,
        error: error,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: 'Outfit',
        bodyColor: body,
        displayColor: heading,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        counterStyle: const TextStyle(fontSize: 0, height: 0),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: const TextStyle(color: label, fontSize: 14),
        hintStyle: const TextStyle(color: muted, fontSize: 14),
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: outline(border),
        enabledBorder: outline(border),
        focusedBorder: outline(teal, 2),
        errorBorder: outline(error),
        focusedErrorBorder: outline(error, 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkTeal,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          textStyle: const TextStyle(
            fontFamily: 'Outfit',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class AuthWordmark extends StatelessWidget {
  const AuthWordmark({super.key, this.light = false, this.compact = false});
  final bool light;
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.work_outline_rounded,
        color: light ? Colors.white : AuthStyle.teal,
        size: compact ? 32 : 28,
      ),
      const SizedBox(width: 10),
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'JobMate',
            style: TextStyle(
              fontFamily: compact ? 'Outfit' : 'DM Serif Display',
              fontFamilyFallback: const ['Arial', 'sans-serif'],
              fontWeight: compact ? FontWeight.w700 : FontWeight.w400,
              fontSize: compact ? 16 : 28,
              color: light ? Colors.white : AuthStyle.heading,
            ),
          ),
        ),
      ),
    ],
  );
}

class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    this.password = false,
    this.keyboardType,
    this.hintText,
    this.showCounter = true,
    this.onChanged,
    this.maxLength,
    this.autofillHints,
    this.bottomSpacing = 16,
  });
  final double bottomSpacing;
  final String label;
  final TextEditingController controller;
  final bool password;
  final TextInputType? keyboardType;
  final String? hintText;
  final bool showCounter;
  final ValueChanged<String>? onChanged;
  final int? maxLength;
  final Iterable<String>? autofillHints;
  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _hidden = true;
  @override
  Widget build(BuildContext context) => Padding(
   padding: EdgeInsets.only(bottom: widget.bottomSpacing),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: AuthStyle.label,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller,
          obscureText: widget.password && _hidden,
          keyboardType: widget.keyboardType,
          textCapitalization: widget.keyboardType == TextInputType.name
              ? TextCapitalization.words
              : TextCapitalization.none,
          autofillHints: widget.autofillHints,
          autocorrect:
              !widget.password &&
              widget.keyboardType != TextInputType.emailAddress,
          enableSuggestions:
              !widget.password &&
              widget.keyboardType != TextInputType.emailAddress,
          maxLength: widget.maxLength,
          onChanged: widget.onChanged,
          textInputAction: TextInputAction.next,
          style: const TextStyle(fontSize: 14, color: AuthStyle.heading),
          decoration: InputDecoration(
            hintText: widget.hintText,
            counterText: widget.showCounter ? null : '',
            suffixIcon: widget.password
                ? IconButton(
                    tooltip: _hidden ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _hidden = !_hidden),
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                  )
                : null,
          ),
        ),
      ],
    ),
  );
}
