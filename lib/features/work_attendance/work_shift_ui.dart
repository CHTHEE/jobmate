import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/theme/jobmate_theme.dart';
import 'work_attendance_lifecycle.dart';
import 'work_attendance_models.dart';
import 'work_status_presentation.dart';

class WorkHeadingIcon extends StatelessWidget {
  const WorkHeadingIcon(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: JobMateTheme.teal50,
      borderRadius: BorderRadius.circular(JobMateTheme.controlRadius),
    ),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Icon(icon, size: 18, color: JobMateTheme.darkTeal),
    ),
  );
}

bool isUpcomingShift(WorkAssignment row) {
  final asOf = row.attendanceAsOf;
  return asOf != null &&
      row.scheduledStart.isAfter(asOf) &&
      {
        AttendanceLifecycle.scheduled,
        AttendanceLifecycle.ready,
      }.contains(AttendanceLifecycle.of(row));
}

int compareShiftDisplayOrder(
  WorkAssignment a,
  WorkAssignment b, {
  required bool aNeedsAction,
  required bool bNeedsAction,
}) {
  if (aNeedsAction != bNeedsAction) return aNeedsAction ? -1 : 1;
  final aUpcoming = isUpcomingShift(a);
  final bUpcoming = isUpcomingShift(b);
  if (aUpcoming != bUpcoming) return aUpcoming ? -1 : 1;
  // Keep legacy rows chronological when the server snapshot is unavailable.
  final aUnknown = a.attendanceAsOf == null;
  final bUnknown = b.attendanceAsOf == null;
  if (aUnknown != bUnknown) return aUnknown ? 1 : -1;
  final start = a.scheduledStart.compareTo(b.scheduledStart);
  if (start != 0) return aUpcoming || aUnknown ? start : -start;
  return a.assignmentId.compareTo(b.assignmentId);
}

WorkAssignment? nextUpcomingShift(Iterable<WorkAssignment> shifts) {
  WorkAssignment? next;
  for (final row in shifts.where(isUpcomingShift)) {
    if (next == null || row.scheduledStart.isBefore(next.scheduledStart)) {
      next = row;
    }
  }
  return next;
}

class UpcomingShiftPreview extends StatelessWidget {
  const UpcomingShiftPreview({super.key, required this.shift});

  final WorkAssignment shift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.primary.withValues(alpha: .06),
          colors.surface,
        ),
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: colors.primary,
              ),
              Text('Next upcoming shift', style: theme.textTheme.titleSmall),
              const AttendanceStatusBadge(
                label: 'Upcoming',
                tone: AttendanceTone.information,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            shiftDateLabel(shift.scheduledStart),
            style: theme.textTheme.titleSmall,
          ),
          Text(
            shiftTimeRange(shift.scheduledStart, shift.scheduledEnd),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (shift.workplaceLocation.trim().isNotEmpty)
            Text(
              shift.workplaceLocation,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class WorkplaceMapAction extends StatelessWidget {
  const WorkplaceMapAction({super.key, required this.uri});

  final Uri? uri;

  @override
  Widget build(BuildContext context) {
    final map = uri;
    if (map == null) return const SizedBox.shrink();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: () async {
          try {
            if (await launchUrl(map, mode: LaunchMode.externalApplication)) {
              return;
            }
          } catch (_) {
            // Treat a platform launch error the same as an unavailable app.
          }
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to open Google Maps.')),
          );
        },
        icon: const Icon(Icons.map_outlined),
        label: const Text('View workplace on map'),
      ),
    );
  }
}

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

String shiftTimeLabel(DateTime value, {bool showSeconds = false}) {
  final time = _myt(value);
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final seconds = showSeconds && time.second != 0
      ? ':${time.second.toString().padLeft(2, '0')}'
      : '';
  return '$hour:${time.minute.toString().padLeft(2, '0')}$seconds ${time.hour < 12 ? 'AM' : 'PM'}';
}

String shiftTimeRange(DateTime start, DateTime end) {
  final from = _myt(start);
  final to = _myt(end);
  final sameDay =
      from.year == to.year && from.month == to.month && from.day == to.day;
  return '${shiftTimeLabel(start)} – ${sameDay ? '' : '${shiftDateLabel(end)} '}${shiftTimeLabel(end)} MYT';
}

/// Presentation only: all values are supplied by existing authorized models.
class ShiftAttendanceSummary extends StatelessWidget {
  const ShiftAttendanceSummary({
    super.key,
    required this.assignment,
    this.employer = false,
    this.inShiftCard = false,
    this.workerRecord = false,
    this.showMissingTimes = false,
    this.showGuidance = true,
  });

  final WorkAssignment assignment;
  final bool employer;
  final bool inShiftCard;
  final bool workerRecord;
  final bool showMissingTimes;
  final bool showGuidance;

  @override
  Widget build(BuildContext context) {
    final row = assignment;
    final checkIn = row.effectiveCheckInAt;
    final checkout = row.effectiveCheckOutAt;
    final corrected = row.resolution?.decision == 'corrected';
    final state = AttendanceLifecycle.of(row);
    final timing = employer ? null : attendanceTimingBadge(row);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              workerRecord
                  ? 'Recorded attendance'
                  : employer || inShiftCard
                  ? 'Attendance summary'
                  : 'Attendance status',
              style: theme.textTheme.titleSmall,
            ),
            ?timing,
          ],
        ),
        const SizedBox(height: 8),
        if (workerRecord ||
            showMissingTimes ||
            checkIn != null ||
            checkout != null) ...[
          ShiftEqualHeightGrid(
            columns: 2,
            children: [
              for (final (label, icon, value) in [
                ('Check-in', Icons.login, checkIn),
                ('Checkout', Icons.logout, checkout),
              ])
                ShiftDetailPanel(
                  title: employer && corrected
                      ? 'Corrected ${label.toLowerCase()}'
                      : label,
                  icon: icon,
                  children: [
                    Text(
                      value == null
                          ? 'Not recorded'
                          : shiftTimeLabel(
                              value,
                              showSeconds: workerRecord || employer,
                            ),
                      style: theme.textTheme.titleLarge,
                    ),
                    if (value != null) ...[
                      Text(
                        inShiftCard
                            ? '${corrected ? 'Employer-corrected' : 'Device-recorded'} · MYT'
                            : '${shiftDateLabel(value)} · MYT',
                        style: inShiftCard ? null : theme.textTheme.bodySmall,
                      ),
                      if (!inShiftCard)
                        Text(
                          corrected ? 'Employer-corrected' : 'Device-recorded',
                        )
                      else if (!DateUtils.isSameDay(
                        _myt(value),
                        _myt(row.scheduledStart),
                      ))
                        Text(
                          shiftDateLabel(value),
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (checkIn != null &&
              checkout != null &&
              !checkout.isBefore(checkIn)) ...[
            Text(
              '${inShiftCard
                  ? 'Duration'
                  : corrected
                  ? 'Corrected duration'
                  : 'Effective duration'}: ${_attendanceDuration(checkout.difference(checkIn))}',
              style: theme.textTheme.titleSmall,
            ),
            if (!inShiftCard || !corrected)
              const Text(
                'Attendance duration does not establish approved payable time.',
              ),
          ],
        ],
        if (inShiftCard && corrected)
          const Text(
            'These times were corrected by the employer. Duration does not confirm approved payable time.',
          )
        else if (corrected)
          Text(
            row.checkInAt == null && row.checkOutAt == null
                ? 'Original device attendance was not recorded. These times were corrected by the employer.'
                : 'The employer corrected these times. Original device records remain separate.',
          )
        else if (workerRecord && state == AttendanceLifecycle.confirmedAbsent)
          const Text(
            'The employer confirmed your absence. No evidence submission is required.',
          )
        else if (workerRecord && state == AttendanceLifecycle.missed)
          const Text('Attendance resolution: Pending employer review')
        else if (!inShiftCard && showGuidance)
          Text(
            state.guidanceFor(
              employer: employer,
              recoveryEnforced: row.resolution?.recoveryEnforced == true,
            ),
          ),
      ],
    );
  }
}

/// The recorded verification outcome. Attendance eligibility is rendered
/// separately and actions still use the existing evidence workflow.
class WorkerVerificationOutcome extends StatelessWidget {
  const WorkerVerificationOutcome({super.key, required this.assignment});

  final WorkAssignment assignment;

  @override
  Widget build(BuildContext context) {
    final row = assignment;
    final status = row.verificationStatus;
    if (AttendanceLifecycle.of(row) == AttendanceLifecycle.confirmedAbsent) {
      return const SizedBox.shrink();
    }
    final (label, icon) = switch (status) {
      WorkVerificationStatus.verified => (
        'Work verified by employer',
        Icons.verified_outlined,
      ),
      WorkVerificationStatus.pendingReview => (
        'Evidence awaiting employer review',
        Icons.rate_review_outlined,
      ),
      WorkVerificationStatus.moreEvidenceRequired => (
        'Revision requested · Review employer feedback',
        Icons.feedback_outlined,
      ),
      _ => (
        'Verification: ${workVerificationStatusLabel(status)}',
        Icons.assignment_outlined,
      ),
    };
    final (background, foreground) = attendanceToneColors(
      context,
      verificationTone(status),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(JobMateTheme.controlRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (status == WorkVerificationStatus.verified)
                    if (row.verifiedAt case final time?)
                      Text(
                        attendanceMyt(time),
                        style: TextStyle(color: foreground),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget? attendanceTimingBadge(WorkAssignment row) {
  final timing = workCheckInTimingLabel(
    row.scheduledStart,
    row.effectiveCheckInAt,
  );
  if (timing == null) return null;
  final corrected = row.resolution?.decision == 'corrected';
  return AttendanceStatusBadge(
    label: corrected ? 'Corrected · $timing' : timing,
    tone: timing == 'Late' ? AttendanceTone.pending : AttendanceTone.positive,
  );
}

String _attendanceDuration(Duration duration) {
  if (duration.inMinutes == 0 && duration.inSeconds > 0) {
    return '${duration.inSeconds} ${duration.inSeconds == 1 ? 'second' : 'seconds'}';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final minuteLabel = '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  if (hours == 0) return minuteLabel;
  final hourLabel = '$hours ${hours == 1 ? 'hour' : 'hours'}';
  return minutes == 0 ? hourLabel : '$hourLabel $minuteLabel';
}

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
