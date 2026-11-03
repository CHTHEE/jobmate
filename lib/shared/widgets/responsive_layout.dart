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
  // Retain the workspace's existing sidebar/drawer switch on every screen.
  static const double navigationBreakpoint = 768;

  static bool usesSidebar(double width) => width >= navigationBreakpoint;

  static bool isCompactWidth(double width) => width < compactBreakpoint;

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
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

/// Cards get a responsive width and their natural content height. In particular,
/// long labels and accessibility text scaling must not be clipped by grid ratios.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 280,
    this.maxColumns = 3,
    this.spacing = 16,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (children.isEmpty) return const SizedBox.shrink();
      final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final minimum = minItemWidth * textScale.clamp(1.0, 2.0);
      final limit = children.length < maxColumns ? children.length : maxColumns;
      final columns = ((constraints.maxWidth + spacing) / (minimum + spacing))
          .floor()
          .clamp(1, limit);
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// A filter inside Wrap must use its parent's width, not the viewport width
/// (which also includes the workspace sidebar and page padding).
class ResponsiveFilter extends StatelessWidget {
  const ResponsiveFilter({super.key, required this.child, this.width = 220});
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SizedBox(
      width: ResponsiveLayout.isCompactWidth(constraints.maxWidth)
          ? constraints.maxWidth
          : width,
      child: child,
    ),
  );
}

class ResponsivePagination extends StatelessWidget {
  const ResponsivePagination({
    super.key,
    required this.page,
    this.onPrevious,
    this.onNext,
  });
  final int page;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final previous = TextButton(
        onPressed: onPrevious,
        child: const Text('Previous'),
      );
      final next = TextButton(onPressed: onNext, child: const Text('Next'));
      final label = Text('Page $page');
      if (constraints.maxWidth < 360 ||
          MediaQuery.textScalerOf(context).scale(14) > 20) {
        return Column(
          children: [
            label,
            const SizedBox(height: 8),
            Wrap(spacing: 16, runSpacing: 8, children: [previous, next]),
          ],
        );
      }
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [previous, label, next],
      );
    },
  );
}
