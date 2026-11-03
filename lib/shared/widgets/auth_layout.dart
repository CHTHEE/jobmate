import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'auth_style.dart';
import 'mobile_back_action.dart';
import 'responsive_layout.dart';

class AuthLayout extends StatelessWidget {
  final Widget child;
  final bool branded;
  final bool showMobileBackButton;
  final double contentMaxWidth;

  const AuthLayout({
    super.key,
    required this.child,
    this.branded = false,
    this.showMobileBackButton = false,
    this.contentMaxWidth = 384,
  });

  @override
  Widget build(BuildContext context) {
    if (!branded) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final padding = ResponsiveLayout.pagePaddingForWidth(
            constraints.maxWidth,
          );
          return SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                child: Padding(
                  padding: padding,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: child,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    return Theme(
      data: AuthStyle.theme(context),
      child: Material(
        color: AuthStyle.background,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop =
                  ResponsiveLayout.forWidth(constraints.maxWidth) ==
                  JobMateScreenSize.expanded;
              final pagePadding = ResponsiveLayout.pagePaddingForWidth(
                constraints.maxWidth,
              );
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
                                  fontSize: 30,
                                  height: 1.375,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'AI-assisted recruitment and workforce management. Connect talent with opportunity through JobMate.',
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.625,
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
                        padding: EdgeInsets.symmetric(
                          horizontal: pagePadding.left,
                          vertical: desktop ? 40 : pagePadding.top + 16,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: contentMaxWidth,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!desktop ||
                                  (showMobileBackButton && !kIsWeb)) ...[
                                Row(
                                  children: [
                                    if (showMobileBackButton && !kIsWeb) ...[
                                      const MobileBackAction(),
                                      const SizedBox(width: 8),
                                    ],
                                    if (!desktop)
                                      const Flexible(child: AuthWordmark()),
                                  ],
                                ),
                                SizedBox(height: desktop ? 16 : 40),
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
