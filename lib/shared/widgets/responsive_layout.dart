import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';

/// Shared screen-size rules for JobMate.
///
/// Flutter layouts should react to the available width, not a particular phone
/// model. A 360 px Android phone and a 430 px iPhone can therefore use the
/// same compact layout without separate device-specific code.
enum JobMateScreenSize { compact, medium, expanded }

abstract final class ResponsiveLayout {
  static const double cardGap = 16;
  static const double actionGap = 8;
  static const double actionHeight = 48;
  static const double compactBreakpoint = 600;
  static const double expandedBreakpoint = 840;
  static const double wideBreakpoint = 1200;
  // This controls Web presentation only, never the navigation platform.
  static const double navigationBreakpoint = expandedBreakpoint;

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
        return const EdgeInsets.all(24);
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
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
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
    this.spacing = ResponsiveLayout.cardGap,
    this.equalRowHeight = false,
    this.reserveEmptyColumns = false,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;
  final bool equalRowHeight;
  final bool reserveEmptyColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (children.isEmpty) return const SizedBox.shrink();
      final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final minimum = minItemWidth * textScale.clamp(1.0, 2.0);
      final limit = !reserveEmptyColumns && children.length < maxColumns
          ? children.length
          : maxColumns;
      final columns = ((constraints.maxWidth + spacing) / (minimum + spacing))
          .floor()
          .clamp(1, limit);
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      if (equalRowHeight && columns > 1) {
        return _EqualHeightGrid(
          columns: columns,
          spacing: spacing,
          textDirection: Directionality.of(context),
          children: children,
        );
      }
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

class _EqualHeightGrid extends MultiChildRenderObjectWidget {
  const _EqualHeightGrid({
    required this.columns,
    required this.spacing,
    required this.textDirection,
    required super.children,
  });

  final int columns;
  final double spacing;
  final TextDirection textDirection;

  @override
  _RenderEqualHeightGrid createRenderObject(BuildContext context) =>
      _RenderEqualHeightGrid(columns, spacing, textDirection);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEqualHeightGrid renderObject,
  ) => renderObject.update(columns, spacing, textDirection);
}

class _GridParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualHeightGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GridParentData> {
  _RenderEqualHeightGrid(this._columns, this._spacing, this._textDirection);

  int _columns;
  double _spacing;
  TextDirection _textDirection;

  void update(int columns, double spacing, TextDirection textDirection) {
    if (_columns == columns &&
        _spacing == spacing &&
        _textDirection == textDirection) {
      return;
    }
    _columns = columns;
    _spacing = spacing;
    _textDirection = textDirection;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GridParentData) {
      child.parentData = _GridParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final cellWidth = (width - _spacing * (_columns - 1)) / _columns;
    final naturalSize = BoxConstraints.tightFor(width: cellWidth);
    var next = firstChild;
    var top = 0.0;
    while (next != null) {
      final row = <RenderBox>[];
      var height = 0.0;
      while (next != null && row.length < _columns) {
        next.layout(naturalSize, parentUsesSize: true);
        height = math.max(height, next.size.height);
        row.add(next);
        next = childAfter(next);
      }
      final rowSize = BoxConstraints(
        minWidth: cellWidth,
        maxWidth: cellWidth,
        minHeight: height,
      );
      for (final (column, child) in row.indexed) {
        // Keep the parent's layout dependent on each card so expanding its
        // content recomputes the entire row height.
        if (child.size.height != height) {
          child.layout(rowSize, parentUsesSize: true);
        }
        final start = column * (cellWidth + _spacing);
        final left = _textDirection == TextDirection.ltr
            ? start
            : width - start - cellWidth;
        (child.parentData! as _GridParentData).offset = Offset(left, top);
      }
      top += height;
      if (next != null) top += _spacing;
    }
    size = constraints.constrain(Size(width, top));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
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
