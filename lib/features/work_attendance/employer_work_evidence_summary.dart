import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/responsive_layout.dart';

import 'work_attendance_models.dart';
import 'work_attendance_lifecycle.dart';
import 'work_shift_ui.dart';
import 'work_status_presentation.dart';

/// Presentation only; uses the existing authorized assignment projection.
class EmployerWorkEvidenceSummary extends StatelessWidget {
  const EmployerWorkEvidenceSummary({
    super.key,
    required this.assignment,
    this.workerName,
    this.onGps,
    this.upcoming = false,
    this.hasWorkflow = false,
  });
  final WorkAssignment assignment;
  final String? workerName;
  final VoidCallback? onGps;
  final bool upcoming;
  final bool hasWorkflow;
  @override
  Widget build(BuildContext context) {
    final row = assignment;
    if (upcoming) {
      final theme = Theme.of(context);
      return WorkspaceCard(
        title: row.jobTitle,
        leading: const WorkHeadingIcon(LucideIcons.briefcase),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              workerName == null ? 'Assigned worker' : 'Worker: $workerName',
            ),
            const SizedBox(height: 8),
            const AttendanceStatusBadge(
              label: 'Upcoming / Scheduled',
              tone: AttendanceTone.information,
            ),
            const SizedBox(height: 12),
            Text('Shift information', style: theme.textTheme.titleSmall),
            Text('Date: ${shiftDateLabel(row.scheduledStart, full: true)}'),
            Text(
              'Time: ${shiftTimeRange(row.scheduledStart, row.scheduledEnd)}',
            ),
            if (row.workplaceLocation.trim().isNotEmpty)
              Text('Workplace: ${row.workplaceLocation}'),
            WorkplaceMapAction(uri: row.workplaceMapLink),
            const SizedBox(height: 12),
            Text('Attendance status', style: theme.textTheme.titleSmall),
            const Text('Awaiting scheduled shift.'),
            Text(AttendanceLifecycle.scheduled.guidance),
          ],
        ),
      );
    }
    final state = AttendanceLifecycle.of(row);
    final confirmedAbsent = row.resolution?.decision == 'confirmed_absent';
    final timing = attendanceTimingBadge(row);
    final verified = row.verificationStatus == WorkVerificationStatus.verified;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
          minItemWidth: 370,
          maxColumns: 2,
          equalRowHeight: true,
          children: [
            WorkspaceCard(
              title: row.jobTitle,
              leading: const WorkHeadingIcon(LucideIcons.briefcase),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workerName == null
                        ? 'Assigned worker'
                        : 'Worker: $workerName',
                  ),
                  const SizedBox(height: 8),
                  Text(shiftDateLabel(row.scheduledStart, full: true)),
                  Text(shiftTimeRange(row.scheduledStart, row.scheduledEnd)),
                  if (row.workplaceLocation.trim().isNotEmpty)
                    Text('Workplace: ${row.workplaceLocation}'),
                  WorkplaceMapAction(uri: row.workplaceMapLink),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      AttendanceStatusBadge(
                        label: state.label,
                        tone: attendanceTone(state),
                      ),
                      if (!verified && !hasWorkflow && !confirmedAbsent)
                        AttendanceStatusBadge(
                          label:
                              'Verification: ${workVerificationStatusLabel(row.verificationStatus)}',
                          tone: verificationTone(row.verificationStatus),
                        ),
                      ?timing,
                    ],
                  ),
                ],
              ),
            ),
            Card.outlined(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ShiftAttendanceSummary(
                      assignment: row,
                      employer: true,
                      showMissingTimes: true,
                      showGuidance: !confirmedAbsent,
                    ),
                    if (confirmedAbsent)
                      const Text(
                        'Absence confirmed. No evidence submission is required. No work or payment has been approved for this shift.',
                      ),
                    if (onGps != null &&
                        (row.checkInAt != null || row.checkOutAt != null))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: onGps,
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('View attendance GPS'),
                        ),
                      ),
                    if (onGps != null &&
                        (row.checkInAt != null || row.checkOutAt != null))
                      const Text(
                        'GPS refers to original device records. Opening a map shares coordinates with Google.',
                        style: TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (hasDistinctAttendanceAudit(row)) ...[
          const SizedBox(height: 12),
          Card.outlined(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AttendanceRecordDetails(assignment: row),
            ),
          ),
        ],
        if (!hasWorkflow && verified) ...[
          const SizedBox(height: 12),
          WorkspaceCard(
            title: 'Evidence and verification',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (row.verifiedAt case final time?)
                  Text(
                    'Verified at: ${shiftDateLabel(time)} ${shiftTimeLabel(time)} MYT',
                  ),
                const Text(
                  'Work verification does not confirm payment approval.',
                ),
                const Text('No further evidence submission is due.'),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
