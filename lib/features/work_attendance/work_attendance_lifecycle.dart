import 'package:flutter/material.dart';

import 'work_attendance_models.dart';

enum AttendanceLifecycle {
  unavailable,
  inconsistent,
  scheduled,
  ready,
  onShift,
  missed,
  overdue,
  incomplete,
  recorded,
  lateCheckout,
  cancelled,
  disputed,
  confirmedAbsent,
  corrected,
  verified;

  static AttendanceLifecycle of(WorkAssignment row) {
    if (row.assignmentStatus == WorkAssignmentStatus.cancelled) {
      return cancelled;
    }
    if (row.assignmentStatus == WorkAssignmentStatus.disputed ||
        row.verificationStatus == WorkVerificationStatus.disputed) {
      return disputed;
    }
    if (row.verificationStatus == WorkVerificationStatus.verified) {
      return verified;
    }
    if (row.resolution?.decision == 'confirmed_absent') return confirmedAbsent;
    if (row.resolution?.decision == 'corrected') return corrected;
    final start = row.scheduledStart;
    final end = row.scheduledEnd;
    final input = row.checkInAt;
    final output = row.checkOutAt;
    final now = row.attendanceAsOf;
    if (!end.isAfter(start) ||
        (output != null && (input == null || output.isBefore(input))) ||
        (now != null &&
            ((input != null && input.isAfter(now)) ||
                (output != null && output.isAfter(now))))) {
      return inconsistent;
    }
    if (input != null && output != null) {
      return output.isAfter(end) ? lateCheckout : recorded;
    }
    if ((row.assignmentStatus == WorkAssignmentStatus.completed ||
            row.assignmentStatus ==
                WorkAssignmentStatus.awaitingVerification) ||
        (input == null &&
            row.assignmentStatus == WorkAssignmentStatus.active) ||
        (input != null &&
            row.assignmentStatus == WorkAssignmentStatus.scheduled)) {
      return inconsistent;
    }
    if (now == null) return unavailable;
    if (input != null) {
      // Informational in Batch 1: ordinary checkout remains available even here.
      if (now.isAfter(end.add(const Duration(hours: 24)))) return incomplete;
      return now.isAfter(end) ? overdue : onShift;
    }
    if (now.isAfter(end)) return missed;
    return now.isBefore(start.subtract(const Duration(minutes: 60)))
        ? scheduled
        : ready;
  }

  bool get isIssue => switch (this) {
    missed ||
    overdue ||
    incomplete ||
    inconsistent ||
    disputed ||
    lateCheckout => true,
    _ => false,
  };

  String get label => switch (this) {
    unavailable => 'Attendance timing unavailable',
    inconsistent => 'Attendance needs review',
    scheduled => 'Upcoming / Scheduled',
    ready => 'Ready for Check-in',
    onShift => 'Checked In / On Shift',
    missed => 'Missed Attendance',
    overdue => 'Check-out Overdue',
    incomplete => 'Incomplete Attendance',
    recorded => 'Attendance Recorded',
    lateCheckout => 'Attendance Recorded / Late checkout',
    cancelled => 'Cancelled',
    disputed => 'Disputed',
    confirmedAbsent => 'Confirmed Absent',
    corrected => 'Corrected Attendance',
    verified => 'Work Verified',
  };

  String get guidance => switch (this) {
    unavailable => 'Refresh to obtain server attendance timing. Existing actions remain server-validated.',
    inconsistent => 'Recorded attendance is inconsistent. Contact the employer; no timestamps have been inferred.',
    scheduled => 'Check-in opens 60 minutes before the scheduled start. Refresh then to update availability.',
    ready => 'Check-in is within the server snapshot window. The server rechecks when you submit.',
    onShift => 'Check out when work finishes, then submit evidence.',
    missed => 'The shift ended without recorded attendance. This is not confirmed absence. Contact the employer.',
    overdue => 'The shift ended without checkout. Record checkout if you have finished; the actual server time is retained.',
    incomplete => 'Checkout is still missing more than 24 hours after scheduled end. Contact the employer. Ordinary checkout remains available in this release.',
    recorded => 'Attendance is recorded. Work evidence and employer verification remain separate.',
    lateCheckout => 'Checkout was recorded after the scheduled end. Employer review is required; elapsed time is not approved payable time.',
    cancelled => 'This shift was cancelled. Recorded details remain available.',
    disputed => 'Review the recorded details and existing dispute process.',
    confirmedAbsent => 'Absence confirmed by the employer. No work or payment has been approved for this shift.',
    corrected => 'Attendance was manually corrected by the employer. Original timestamps and GPS remain preserved. Evidence and work verification are still required.',
    verified =>
      'The employer has verified this work. This does not confirm payment.',
  };

  String guidanceFor({required bool employer, bool recoveryEnforced = false}) {
    if (this == incomplete && recoveryEnforced) {
      return employer
          ? 'The ordinary checkout recovery window has ended. Employer attendance correction is required; original records stay preserved.'
          : 'The ordinary checkout recovery window has ended. Ask the employer to review and correct attendance.';
    }
    if (!employer) return guidance;
    return switch (this) {
      missed => 'No attendance was recorded before this shift ended. Employer review is required; this is not confirmed absence.',
      overdue => 'The worker checked in but has not checked out. The actual checkout time will be retained when recorded.',
      incomplete => 'Checkout is missing more than 24 hours after scheduled end. Employer attendance review is required. The current checkout rules remain unchanged.',
      inconsistent => 'Attendance records need employer review. No missing timestamps or GPS results have been inferred.',
      ready => 'This shift is within the server check-in window. Attendance is recorded by the assigned worker.',
      onShift => 'The worker has checked in. Evidence submission follows recorded checkout.',
      _ => guidance,
    };
  }
}

/// Shared employer predicate: apply to individual shifts before grouping.
bool matchesAttendanceShiftFilter(WorkAssignment row, String filter) {
  if (filter.isEmpty) return true;
  final state = AttendanceLifecycle.of(row);
  if (filter == 'attendanceIssues') return state.isIssue;
  if (filter.startsWith('attendance:')) {
    return filter == 'attendance:${state.name}';
  }
  return filter == row.assignmentStatus.name;
}

enum AttendanceHistoryFilter {
  all,
  recorded,
  issues;

  bool matches(WorkAssignment row) {
    if (!isAttendanceHistoryRow(row)) return false;
    final state = AttendanceLifecycle.of(row);
    return switch (this) {
      all => true,
      recorded =>
        (state == AttendanceLifecycle.recorded ||
                state == AttendanceLifecycle.lateCheckout ||
                state == AttendanceLifecycle.corrected ||
                state == AttendanceLifecycle.verified) &&
            row.effectiveCheckInAt != null &&
            row.effectiveCheckOutAt != null,
      issues => state.isIssue,
    };
  }
}

/// Past-shift history uses the server snapshot. Without it, only actual recorded
/// checkout can establish a historical attendance record; never use device time.
bool isAttendanceHistoryRow(WorkAssignment row) => row.attendanceAsOf != null
    ? row.attendanceAsOf!.isAfter(row.scheduledEnd)
    : row.checkInAt != null && row.checkOutAt != null;

enum AttendanceTone { neutral, positive, pending, issue }

AttendanceTone verificationTone(WorkVerificationStatus status) =>
    switch (status) {
      WorkVerificationStatus.verified => AttendanceTone.positive,
      WorkVerificationStatus.pendingReview ||
      WorkVerificationStatus.moreEvidenceRequired => AttendanceTone.pending,
      WorkVerificationStatus.disputed => AttendanceTone.issue,
      _ => AttendanceTone.neutral,
    };

AttendanceTone attendanceTone(AttendanceLifecycle state) => switch (state) {
  AttendanceLifecycle.verified ||
  AttendanceLifecycle.recorded ||
  AttendanceLifecycle.corrected => AttendanceTone.positive,
  AttendanceLifecycle.overdue ||
  AttendanceLifecycle.onShift ||
  AttendanceLifecycle.ready ||
  AttendanceLifecycle.lateCheckout => AttendanceTone.pending,
  AttendanceLifecycle.missed ||
  AttendanceLifecycle.incomplete ||
  AttendanceLifecycle.inconsistent ||
  AttendanceLifecycle.disputed => AttendanceTone.issue,
  _ => AttendanceTone.neutral,
};

(Color, Color) attendanceToneColors(BuildContext context, AttendanceTone tone) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  final amber = ColorScheme.fromSeed(
    seedColor: Colors.amber,
    brightness: theme.brightness,
  );
  return switch (tone) {
    AttendanceTone.neutral => (
      colors.surfaceContainerHighest,
      colors.onSurface,
    ),
    AttendanceTone.positive => (
      colors.secondaryContainer,
      colors.onSecondaryContainer,
    ),
    AttendanceTone.pending => (
      amber.primaryContainer,
      amber.onPrimaryContainer,
    ),
    AttendanceTone.issue => (colors.errorContainer, colors.onErrorContainer),
  };
}

class AttendanceStatusBadge extends StatelessWidget {
  const AttendanceStatusBadge({
    super.key,
    required this.label,
    this.tone = AttendanceTone.neutral,
  });
  final String label;
  final AttendanceTone tone;
  @override
  Widget build(BuildContext context) {
    final (background, foreground) = attendanceToneColors(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: foreground),
      ),
    );
  }
}

String? recordedAttendanceDuration(WorkAssignment row) {
  final input = row.checkInAt;
  final output = row.checkOutAt;
  if (input == null || output == null || output.isBefore(input)) return null;
  final duration = output.difference(input);
  return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
}

String attendanceMyt(DateTime timestamp) {
  final time = timestamp.toUtc().add(const Duration(hours: 8));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.day)}/${two(time.month)}/${time.year} ${two(time.hour)}:${two(time.minute)}:${two(time.second)} MYT';
}

/// One presentation for worker, history, evidence and employer views.
class AttendanceLifecycleNotice extends StatelessWidget {
  const AttendanceLifecycleNotice({
    super.key,
    required this.assignment,
    this.employer = false,
    this.showGuidance = true,
    this.showHeading = true,
  });
  final WorkAssignment assignment;
  final bool employer;
  final bool showGuidance;
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final state = AttendanceLifecycle.of(assignment);
    final (background, foreground) = attendanceToneColors(
      context,
      attendanceTone(state),
    );
    return Semantics(
      container: true,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showHeading)
                Text(
                  state.label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: foreground,
                  ),
                ),
              const SizedBox(height: 4),
              if (showGuidance)
                Text(
                  state.guidanceFor(
                    employer: employer,
                    recoveryEnforced:
                        assignment.resolution?.recoveryEnforced == true,
                  ),
                ),
              if (assignment.resolution?.decision != null) ...[
                const Text('Original attendance and GPS remain preserved.'),
                Text('Resolution reason: ${assignment.resolution!.reason}'),
                Text(
                  'Resolved: ${attendanceMyt(assignment.resolution!.resolvedAt!)}',
                ),
                if (assignment.resolution!.decision == 'corrected') ...[
                  Text(
                    'Corrected check-in: ${attendanceMyt(assignment.effectiveCheckInAt!)}',
                  ),
                  Text(
                    'Corrected checkout: ${attendanceMyt(assignment.effectiveCheckOutAt!)}',
                  ),
                  Text(
                    'Corrected duration: ${assignment.effectiveCheckOutAt!.difference(assignment.effectiveCheckInAt!).inHours}h ${assignment.effectiveCheckOutAt!.difference(assignment.effectiveCheckInAt!).inMinutes.remainder(60)}m (not approved payable time)',
                  ),
                  const Text(
                    'Manually corrected attendance; GPS refers only to the original device records.',
                  ),
                ],
              ],
              if (assignment.attendanceAsOf case final snapshot?)
                Material(
                  color: background,
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Technical details'),
                    children: [
                      Text(
                        'As of ${attendanceMyt(snapshot)} (server snapshot; refresh to update)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              if (recordedAttendanceDuration(assignment) case final duration?)
                Text(
                  'Recorded duration: $duration (not approved payable time)',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
