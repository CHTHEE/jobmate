import 'package:flutter/material.dart';

class RequiredFieldLabel extends StatelessWidget {
  const RequiredFieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: Text(text)),
      Text(' *', style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ],
  );
}

String? safeEvidenceDisplayName(String value) {
  final name = value.trim();
  if (name.isEmpty ||
      name.contains('/') ||
      name.contains(String.fromCharCode(92)) ||
      name.contains('?') ||
      name.contains('#') ||
      name.runes.any((r) => r < 32 || r == 127) ||
      RegExp(
        r'^(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{32})(?:[._-].*)?$',
        caseSensitive: false,
      ).hasMatch(name)) {
    return null;
  }
  return name;
}

DateTime _myt(DateTime value) => value.toUtc().add(const Duration(hours: 8));

String shiftDateLabel(DateTime value, {bool full = false}) {
  final date = _myt(value);
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final day = days[date.weekday - 1];
  final month = months[date.month - 1];
  return full
      ? '$day, ${date.day} $month ${date.year}'
      : '${day.substring(0, 3)}, ${date.day} ${month.substring(0, 3)} ${date.year}';
}

String shiftTimeLabel(DateTime value) {
  final time = _myt(value);
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '$hour:${time.minute.toString().padLeft(2, '0')} ${time.hour < 12 ? 'AM' : 'PM'}';
}

String shiftTimeRange(DateTime start, DateTime end) {
  final from = _myt(start);
  final to = _myt(end);
  final sameDay =
      from.year == to.year && from.month == to.month && from.day == to.day;
  return '${shiftTimeLabel(start)} – ${sameDay ? '' : '${shiftDateLabel(end)} '}${shiftTimeLabel(end)} MYT';
}

/// Presentation only: all values are supplied by existing authorized models.
class ShiftReviewTable extends StatelessWidget {
  const ShiftReviewTable({super.key, required this.rows});
  final List<(String, String)> rows;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: constraints.maxWidth < 320 ? 82 : 130,
                    child: Text(
                      rows[i].$1,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rows[i].$2,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class ShiftDetailPanel extends StatelessWidget {
  const ShiftDetailPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}

/// A small bounded row of attendance tiles, equal in height within each row.
class ShiftEqualHeightGrid extends StatelessWidget {
  const ShiftEqualHeightGrid({
    super.key,
    required this.children,
    this.columns = 4,
  });
  final List<Widget> children;
  final int columns;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count = constraints.maxWidth >= 780
          ? columns
          : constraints.maxWidth >= 480
          ? (columns < 2 ? columns : 2)
          : 1;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var start = 0; start < children.length; start += count) ...[
            if (start > 0) const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var offset = 0; offset < count; offset++) ...[
                    if (offset > 0) const SizedBox(width: 12),
                    Expanded(
                      child: start + offset < children.length
                          ? children[start + offset]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}
