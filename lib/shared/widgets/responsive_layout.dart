import 'package:flutter/material.dart';

/// Shared screen-size rules for JobMate.
///
/// Flutter layouts should react to the available width, not a particular phone
/// model. A 360 px Android phone and a 430 px iPhone can therefore use the
/// same compact layout without separate device-specific code.
enum JobMateScreenSize { compact, medium, expanded }

abstract final class ResponsiveLayout {
  static const double compactBreakpoint = 600;
  static const double expandedBreakpoint = 1024;

  static JobMateScreenSize of(BuildContext context) {
    return forWidth(MediaQuery.sizeOf(context).width);
  }

  static JobMateScreenSize forWidth(double width) {
    if (width < compactBreakpoint) return JobMateScreenSize.compact;
    if (width < expandedBreakpoint) return JobMateScreenSize.medium;
    return JobMateScreenSize.expanded;
  }

  static bool isCompact(BuildContext context) {
    return of(context) == JobMateScreenSize.compact;
  }

  static EdgeInsets pagePadding(BuildContext context) {
    return pagePaddingForWidth(MediaQuery.sizeOf(context).width);
  }

  static EdgeInsets pagePaddingForWidth(double width) {
    switch (forWidth(width)) {
      case JobMateScreenSize.compact:
        return const EdgeInsets.all(16);
      case JobMateScreenSize.medium:
        return const EdgeInsets.all(24);
      case JobMateScreenSize.expanded:
        return const EdgeInsets.all(32);
    }
  }
}

/// Centers wide content on tablets and web, while keeping it full-width on a
/// phone after the responsive page padding has been applied.
class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth = 840,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
