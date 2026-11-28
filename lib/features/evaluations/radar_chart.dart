import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/theme/jobmate_theme.dart';

enum RadarChartPresentation { compact, regular }

@immutable
class RadarChartCriterion {
  const RadarChartCriterion({
    required this.id,
    required this.label,
    required this.score,
    this.notObserved = false,
  }) : assert(score == null || (score >= 0 && score <= 5));

  final String id;
  final String label;
  final double? score;
  final bool notObserved;
}

List<Offset> radarVertices(int count, Offset center, double radius) {
  if (count < 3) return const [];
  return List.generate(count, (index) {
    final angle = -math.pi / 2 + (2 * math.pi * index / count);
    return center + Offset(math.cos(angle), math.sin(angle)) * radius;
  }, growable: false);
}

List<(int, int)> radarObservedEdges(List<RadarChartCriterion> criteria) {
  if (criteria.length < 2) return const [];
  final edges = <(int, int)>[];
  for (var index = 0; index < criteria.length; index++) {
    final next = (index + 1) % criteria.length;
    final currentObserved =
        !criteria[index].notObserved && criteria[index].score != null;
    final nextObserved =
        !criteria[next].notObserved && criteria[next].score != null;
    if (currentObserved && nextObserved) edges.add((index, next));
  }
  return edges;
}

String compactRadarLabel(RadarChartCriterion criterion) {
  final id = criterion.id.trim().toLowerCase();
  return switch (id) {
    'communication' => 'Comms',
    'responsibility' => 'Responsible',
    'professionalism' => 'Professional',
    'job_description_accuracy' => 'Job accuracy',
    'work_organization' => 'Organization',
    'fair_treatment' => 'Fairness',
    _ => criterion.label.trim(),
  };
}

class EvaluationRadarChart extends StatelessWidget {
  const EvaluationRadarChart({
    super.key,
    required this.criteria,
    this.presentation = RadarChartPresentation.regular,
    this.emptyMessage = 'Not enough comparable ratings for a radar chart.',
    this.height,
  });

  final List<RadarChartCriterion> criteria;
  final RadarChartPresentation presentation;
  final String emptyMessage;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (criteria.length < 3) {
      return Semantics(
        label: 'Soft skill profile unavailable',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(emptyMessage, textAlign: TextAlign.center),
        ),
      );
    }
    final compact = presentation == RadarChartPresentation.compact;
    final semantics = criteria
        .map((criterion) {
          final value = criterion.notObserved
              ? 'Not Observed'
              : criterion.score == null
              ? 'Not rated'
              : '${criterion.score!.toStringAsFixed(2)} out of 5';
          return '${criterion.label}: $value';
        })
        .join(', ');
    return Semantics(
      label: 'Soft skill radar chart',
      value: semantics,
      readOnly: true,
      child: RepaintBoundary(
        child: SizedBox(
          key: ValueKey('radar-chart-${criteria.length}-${presentation.name}'),
          height: height ?? (compact ? 180 : 250),
          width: double.infinity,
          child: ExcludeSemantics(
            child: CustomPaint(
              painter: _RadarChartPainter(
                criteria: criteria,
                compact: compact,
                textStyle: Theme.of(context).textTheme.bodySmall,
                textScale: MediaQuery.textScalerOf(context).scale(10) / 10,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarChartPainter extends CustomPainter {
  const _RadarChartPainter({
    required this.criteria,
    required this.compact,
    required this.textStyle,
    required this.textScale,
  });

  final List<RadarChartCriterion> criteria;
  final bool compact;
  final TextStyle? textStyle;
  final double textScale;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final effectiveTextScale = textScale.clamp(1.0, compact ? 1.25 : 1.5);
    final labelWidth = math.min(
      compact ? 92.0 : 132.0,
      size.width * (compact ? .42 : .44),
    );
    final horizontalReserve = math.min(
      labelWidth * (compact ? .68 : .7),
      size.width * .3,
    );
    final verticalReserve =
        (compact ? 24.0 : 34.0) +
        (compact ? 10.0 : 12.0) * effectiveTextScale * 1.5;
    final radius = math.max(
      22.0,
      math.min(
        (size.width - horizontalReserve * 2) / 2,
        (size.height - verticalReserve * 2) / 2,
      ),
    );
    final vertices = radarVertices(criteria.length, center, radius);
    final gridPaint = Paint()
      ..color = JobMateTheme.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var ring = 1; ring <= 5; ring++) {
      final factor = ring / 5;
      final path = Path()
        ..moveTo(
          center.dx + (vertices.first.dx - center.dx) * factor,
          center.dy + (vertices.first.dy - center.dy) * factor,
        );
      for (final vertex in vertices.skip(1)) {
        path.lineTo(
          center.dx + (vertex.dx - center.dx) * factor,
          center.dy + (vertex.dy - center.dy) * factor,
        );
      }
      canvas.drawPath(path..close(), gridPaint);
    }
    for (final vertex in vertices) {
      canvas.drawLine(center, vertex, gridPaint);
    }

    final complete = criteria.every(
      (criterion) => !criterion.notObserved && criterion.score != null,
    );
    final scorePoints = List<Offset?>.filled(criteria.length, null);
    for (var index = 0; index < criteria.length; index++) {
      final criterion = criteria[index];
      final score = criterion.notObserved ? null : criterion.score;
      if (score == null) continue;
      final factor = score.clamp(0, 5) / 5;
      scorePoints[index] =
          center + (vertices[index] - center) * factor.toDouble();
    }
    if (complete) {
      final observedPoints = scorePoints.cast<Offset>();
      final path = Path()
        ..moveTo(observedPoints.first.dx, observedPoints.first.dy);
      for (final point in observedPoints.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = JobMateTheme.teal.withValues(alpha: .18)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = JobMateTheme.teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    } else {
      final partialFill = Paint()
        ..color = JobMateTheme.teal.withValues(alpha: .12)
        ..style = PaintingStyle.fill;
      final partialLine = Paint()
        ..color = JobMateTheme.teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (final edge in radarObservedEdges(criteria)) {
        final first = scorePoints[edge.$1]!;
        final second = scorePoints[edge.$2]!;
        canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy)
            ..lineTo(first.dx, first.dy)
            ..lineTo(second.dx, second.dy)
            ..close(),
          partialFill,
        );
        canvas.drawLine(first, second, partialLine);
      }
    }
    final markerPaint = Paint()
      ..color = JobMateTheme.darkTeal
      ..style = PaintingStyle.fill;
    for (final point in scorePoints.whereType<Offset>()) {
      canvas.drawCircle(point, compact ? 3 : 4, markerPaint);
    }

    final unavailablePaint = Paint()
      ..color = JobMateTheme.body
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 1.4 : 1.8;
    for (var index = 0; index < criteria.length; index++) {
      if (!criteria[index].notObserved) continue;
      final point = center + (vertices[index] - center) * .9;
      final markerRadius = compact ? 4.0 : 5.0;
      canvas.drawCircle(point, markerRadius, unavailablePaint);
      canvas.drawLine(
        point + Offset(-markerRadius * .65, -markerRadius * .65),
        point + Offset(markerRadius * .65, markerRadius * .65),
        unavailablePaint,
      );
    }

    final labelRadius = radius + (compact ? 18 : 26);
    final labelStyle = (textStyle ?? const TextStyle(fontSize: 12)).copyWith(
      color: JobMateTheme.heading,
      fontSize: (compact ? 10.0 : 12.0) * effectiveTextScale,
      height: 1.1,
    );
    for (var index = 0; index < criteria.length; index++) {
      final angle = -math.pi / 2 + (2 * math.pi * index / criteria.length);
      final direction = Offset(math.cos(angle), math.sin(angle));
      final anchor = center + direction * labelRadius;
      final label = compact
          ? compactRadarLabel(criteria[index])
          : criteria[index].label.trim();
      final words = label.split(RegExp(r'\s+'));
      var fittedStyle = labelStyle;
      final longestWord = words.reduce(
        (left, right) => left.length >= right.length ? left : right,
      );
      final wordMeasure = TextPainter(
        text: TextSpan(text: longestWord, style: fittedStyle),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout();
      if (wordMeasure.width > labelWidth) {
        final fit = (labelWidth / wordMeasure.width).clamp(.75, 1.0);
        fittedStyle = fittedStyle.copyWith(
          fontSize: (fittedStyle.fontSize ?? 12) * fit,
        );
      }
      final criterion = criteria[index];
      final missing = criterion.notObserved
          ? 'Not Observed'
          : criterion.score == null
          ? 'Not rated'
          : null;
      final painter = TextPainter(
        text: TextSpan(
          style: fittedStyle,
          children: [
            TextSpan(text: label),
            if (missing != null)
              TextSpan(
                text: '\n$missing',
                style: TextStyle(
                  color: JobMateTheme.body,
                  fontSize: fittedStyle.fontSize! * .9,
                ),
              ),
          ],
        ),
        textAlign: direction.dx.abs() < .2
            ? TextAlign.center
            : direction.dx > 0
            ? TextAlign.left
            : TextAlign.right,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines:
            (words.length == 1 ? 1 : (compact ? 2 : 3)) +
            (missing == null ? 0 : 1),
        ellipsis: '…',
      )..layout(maxWidth: labelWidth);
      var left = direction.dx.abs() < .2
          ? anchor.dx - painter.width / 2
          : direction.dx > 0
          ? anchor.dx
          : anchor.dx - painter.width;
      var top = anchor.dy - painter.height / 2;
      left = left.clamp(0, math.max(0, size.width - painter.width));
      top = top.clamp(0, math.max(0, size.height - painter.height));
      painter.paint(canvas, Offset(left, top));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter oldDelegate) {
    if (oldDelegate.compact != compact ||
        oldDelegate.textStyle != textStyle ||
        oldDelegate.textScale != textScale ||
        oldDelegate.criteria.length != criteria.length) {
      return true;
    }
    for (var index = 0; index < criteria.length; index++) {
      final before = oldDelegate.criteria[index];
      final after = criteria[index];
      if (before.id != after.id ||
          before.label != after.label ||
          before.score != after.score ||
          before.notObserved != after.notObserved) {
        return true;
      }
    }
    return false;
  }
}
