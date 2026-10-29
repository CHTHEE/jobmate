import 'package:flutter/material.dart';

import 'auth_style.dart';

class AuthLayout extends StatelessWidget {
  final Widget child;
  final bool branded;
  const AuthLayout({super.key, required this.child, this.branded = false});

  @override
  Widget build(BuildContext context) {
    if (!branded) {
      return Align(
        alignment: Alignment.center,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: child,
            ),
          ),
        ),
      );
    }
    return Theme(
      data: AuthStyle.theme(context),
      child: Material(
        color: AuthStyle.background,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 1024;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (desktop)
                    SizedBox(
                      width: 420,
                      child: Material(
                        color: AuthStyle.darkTeal,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 40,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const AuthWordmark(light: true),
                              const SizedBox(height: 100),
                              const Text(
                                'Your next chapter\nstarts here.',
                                style: TextStyle(
                                  fontFamily: 'DM Serif Display',
                                  fontFamilyFallback: ['Georgia', 'serif'],
                                  fontSize: 42,
                                  height: 1.2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'AI-assisted recruitment and workforce management. Connect talent with opportunity through JobMate.',
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.7,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 40,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 384),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!desktop) ...[
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: AuthWordmark(),
                                ),
                                const SizedBox(height: 40),
                              ],
                              child,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
