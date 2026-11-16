import 'package:flutter/material.dart';

import 'work_attendance_models.dart';
import 'work_attendance_lifecycle.dart';
import 'work_shift_ui.dart';
import 'work_status_presentation.dart';

/// Employer presentation only. No queries or attendance/verification writes.
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
  String stamp(DateTime? value) => value == null
      ? 'Not recorded'
      : '${shiftDateLabel(value)} · ${shiftTimeLabel(value)} MYT';
  String duration(DateTime start, DateTime end) =>
      '${end.difference(start).inHours}h ${end.difference(start).inMinutes.remainder(60)}m';
  String gpsStatus(String? status, DateTime? original) => original == null
      ? 'Unavailable — no recorded attendance'
      : switch (status) {
          'denied' => 'Unavailable — permission denied',
          'unavailable' => 'Unavailable',
          'granted' => 'Permission granted; view recorded details',
          _ => 'Details available separately',
        };
  @override
  Widget build(BuildContext context) {
    final row = assignment;
    final corrected = row.resolution?.decision == 'corrected';
    final state = AttendanceLifecycle.of(row);
    final timing = workCheckInTimingLabel(
      row.scheduledStart,
      row.effectiveCheckInAt,
    );
    final initials =
        (workerName
            ?.trim()
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .take(2)
            .map((p) => p.characters.first.toUpperCase())
            .join()) ??
        '';
    final tiles = <Widget>[
      ShiftDetailPanel(
        title: 'Scheduled time',
        icon: Icons.calendar_month_outlined,
        children: [
          Text(
            '${shiftDateLabel(row.scheduledStart)}\n${shiftTimeRange(row.scheduledStart, row.scheduledEnd)}',
          ),
          Text(
            'Scheduled duration: ${duration(row.scheduledStart, row.scheduledEnd)}',
          ),
        ],
      ),
      ShiftDetailPanel(
        title: 'Check-in',
        icon: Icons.login,
        children: [
          Text(
            '${corrected ? 'Corrected: ' : ''}${stamp(row.effectiveCheckInAt)}',
          ),
          if (timing != null)
            Text(
              '${corrected ? 'Corrected timing' : 'Check-in timing'}: $timing (15-minute grace period)',
            ),
          if (corrected) Text('Original: ${stamp(row.checkInAt)}'),
        ],
      ),
      ShiftDetailPanel(
        title: 'Check-out',
        icon: Icons.logout,
        children: [
          Text(
            '${corrected ? 'Corrected: ' : ''}${stamp(row.effectiveCheckOutAt)}',
          ),
          if (corrected) Text('Original: ${stamp(row.checkOutAt)}'),
        ],
      ),
      ShiftDetailPanel(
        title: 'Recorded attendance duration',
        icon: Icons.timelapse,
        children: [
          Text(recordedAttendanceDuration(row) ?? 'Not recorded'),
          if (corrected)
            Text(
              'Corrected duration: ${duration(row.effectiveCheckInAt!, row.effectiveCheckOutAt!)}',
            ),
          const Text('Attendance duration is not approved payable time.'),
        ],
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      child: initials.isEmpty
                          ? const Icon(Icons.person_outline)
                          : Text(initials),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            workerName == null
                                ? 'Assigned worker'
                                : 'Worker: $workerName',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            row.jobTitle,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    AttendanceStatusBadge(
                      label: state.label,
                      tone: attendanceTone(state),
                    ),
                    if (row.verificationStatus !=
                        WorkVerificationStatus.verified)
                      AttendanceStatusBadge(
                        label:
                            'Verification: ${workVerificationStatusLabel(row.verificationStatus)}',
                        tone: verificationTone(row.verificationStatus),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  state.guidanceFor(
                    employer: true,
                    recoveryEnforced: row.resolution?.recoveryEnforced == true,
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${shiftDateLabel(row.scheduledStart)} · ${shiftTimeRange(row.scheduledStart, row.scheduledEnd)}',
                ),
                Text('Workplace: ${row.workplaceLocation}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ShiftEqualHeightGrid(children: tiles),
        const SizedBox(height: 12),
        ShiftDetailPanel(
          title: 'Workplace & GPS',
          icon: Icons.location_on_outlined,
          children: [
            Text(row.workplaceLocation),
            Text(
              'Check-in GPS: ${gpsStatus(row.resolution?.originalCheckInLocationStatus, row.checkInAt)}',
            ),
            Text(
              'Check-out GPS: ${gpsStatus(row.resolution?.originalCheckOutLocationStatus, row.checkOutAt)}',
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
              )
            else if (row.checkInAt != null || row.checkOutAt != null)
              const Text('GPS details are available from Work Verification.'),
            const Text(
              'Device-reported location does not prove attendance. Opening a map shares these coordinates with Google.',
            ),
          ],
        ),
        if (row.resolution?.decision != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ShiftDetailPanel(
              title: 'Attendance resolution audit',
              icon: Icons.fact_check_outlined,
              children: [
                Text('Resolution reason: ${row.resolution!.reason}'),
                Text('Resolved: ${attendanceMyt(row.resolution!.resolvedAt!)}'),
                const Text('Original attendance and GPS remain preserved.'),
              ],
            ),
          ),
        if (row.verificationStatus == WorkVerificationStatus.verified)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ShiftDetailPanel(
              title: 'Work Verified',
              icon: Icons.verified_outlined,
              children: [
                if (row.verifiedAt != null)
                  Text('Verified at: ${stamp(row.verifiedAt)}'),
                const Text(
                  'Work verification does not confirm payment. No further evidence submission is due.',
                ),
              ],
            ),
          ),
        ExpansionTile(
          title: const Text('Attendance record details'),
          tilePadding: EdgeInsets.zero,
          children: [
            Text('Scheduled start: ${attendanceMyt(row.scheduledStart)}'),
            Text('Scheduled end: ${attendanceMyt(row.scheduledEnd)}'),
            Text(
              'Original check-in: ${row.checkInAt == null ? 'Not recorded' : attendanceMyt(row.checkInAt!)}',
            ),
            Text(
              'Original check-out: ${row.checkOutAt == null ? 'Not recorded' : attendanceMyt(row.checkOutAt!)}',
            ),
            if (row.attendanceAsOf != null)
              Text(
                'Server snapshot: ${attendanceMyt(row.attendanceAsOf!)}. Refresh to update.',
              ),
          ],
        ),
      ],
    );
  }
}
