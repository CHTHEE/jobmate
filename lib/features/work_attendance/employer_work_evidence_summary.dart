import 'package:flutter/material.dart';

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
  });
  final WorkAssignment assignment;
  final String? workerName;
  final VoidCallback? onGps;
  @override
  Widget build(BuildContext context) {
    final row = assignment;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              workerName == null ? 'Assigned worker' : 'Worker: $workerName',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(row.jobTitle, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              '${shiftDateLabel(row.scheduledStart)} · ${shiftTimeRange(row.scheduledStart, row.scheduledEnd)}',
            ),
            Text('Workplace: ${row.workplaceLocation}'),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                AttendanceStatusBadge(
                  label: AttendanceLifecycle.of(row).label,
                  tone: attendanceTone(AttendanceLifecycle.of(row)),
                ),
                AttendanceStatusBadge(
                  label:
                      'Verification: ${workVerificationStatusLabel(row.verificationStatus)}',
                  tone: verificationTone(row.verificationStatus),
                ),
              ],
            ),
            AttendanceLifecycleNotice(
              assignment: row,
              employer: true,
              showHeading: false,
            ),
            WorkCheckInTiming(assignment: row),
            if (row.verifiedAt != null)
              Text('Verified at: ${attendanceMyt(row.verifiedAt!)}'),
            if (row.verificationStatus == WorkVerificationStatus.verified)
              const Text(
                'Work verification does not confirm payment. No further evidence submission is due.',
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
            const Text(
              'GPS refers to original device records. Opening a map shares coordinates with Google.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
