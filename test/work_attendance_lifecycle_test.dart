import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_attendance_lifecycle.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';
import 'package:jobmate/features/work_attendance/work_status_presentation.dart';

import 'work_attendance_repository_test.dart' show assignment;

Map<String, dynamic> lifecycleRow({
  String? now = '2026-11-05T09:00:01Z',
  String? input,
  String? output,
  String status = 'scheduled',
  String verification = 'not_submitted',
  bool company = false,
}) => assignment(company: company)
  ..addAll({
    'attendance_as_of': now,
    'check_in_at': input,
    'check_out_at': output,
    'assignment_status': status,
    'verification_status': verification,
  });

void main() {
  test('verification semantics distinguish required action, success and neutral outcomes', () {
    expect(
      verificationTone(WorkVerificationStatus.pendingReview),
      AttendanceTone.pending,
    );
    expect(
      verificationTone(WorkVerificationStatus.moreEvidenceRequired),
      AttendanceTone.pending,
    );
    expect(
      verificationTone(WorkVerificationStatus.verified),
      AttendanceTone.positive,
    );
    expect(
      attendanceTone(AttendanceLifecycle.confirmedAbsent),
      AttendanceTone.neutral,
    );
    expect(attendanceTone(AttendanceLifecycle.missed), AttendanceTone.issue);
    expect(
      attendanceTone(AttendanceLifecycle.incomplete),
      AttendanceTone.issue,
    );
    expect(attendanceTone(AttendanceLifecycle.overdue), AttendanceTone.pending);
  });
  for (final (now, expected) in [
    ('2026-11-05T00:00:00Z', AttendanceLifecycle.ready),
    ('2026-11-04T23:59:59Z', AttendanceLifecycle.scheduled),
    ('2026-11-05T09:00:00Z', AttendanceLifecycle.ready),
    ('2026-11-05T09:00:00.000001Z', AttendanceLifecycle.missed),
  ]) {
    test('missing attendance row uses exact server boundary $now', () {
      final row = WorkerWorkAssignment.fromJson(lifecycleRow(now: now));
      expect(AttendanceLifecycle.of(row), expected);
      expect(row.checkInAt, isNull);
      expect(row.checkOutAt, isNull);
    });
  }
  for (final (now, expected) in [
    ('2026-11-05T09:00:00Z', AttendanceLifecycle.onShift),
    ('2026-11-05T09:00:01Z', AttendanceLifecycle.overdue),
    ('2026-11-06T09:00:00Z', AttendanceLifecycle.overdue),
    ('2026-11-06T09:00:00.000001Z', AttendanceLifecycle.incomplete),
  ]) {
    test('checked-in recovery classification at $now', () {
      final row = WorkerWorkAssignment.fromJson(
        lifecycleRow(now: now, input: '2026-11-05T01:00:00Z', status: 'active'),
      );
      expect(AttendanceLifecycle.of(row), expected);
      expect(row.assignmentStatus, WorkAssignmentStatus.active);
      expect(row.checkOutAt, isNull);
    });
  }
  test('no server snapshot never uses the device clock', () {
    final row = WorkerWorkAssignment.fromJson(lifecycleRow(now: null));
    expect(AttendanceLifecycle.of(row), AttendanceLifecycle.unavailable);
    expect(AttendanceHistoryFilter.issues.matches(row), isFalse);
  });
  test('terminal precedence and invalid historical timestamps', () {
    for (final (status, verification, expected) in [
      ('cancelled', 'verified', AttendanceLifecycle.cancelled),
      ('disputed', 'verified', AttendanceLifecycle.disputed),
      ('scheduled', 'disputed', AttendanceLifecycle.disputed),
      ('completed', 'verified', AttendanceLifecycle.verified),
    ]) {
      expect(
        AttendanceLifecycle.of(
          WorkerWorkAssignment.fromJson(
            lifecycleRow(status: status, verification: verification),
          ),
        ),
        expected,
      );
    }
    for (final raw in [
      lifecycleRow(output: '2026-11-05T08:00:00Z'),
      lifecycleRow(
        input: '2026-11-05T08:00:00Z',
        output: '2026-11-05T07:00:00Z',
      ),
      lifecycleRow(input: '2026-11-06T08:00:00Z', status: 'active'),
      lifecycleRow(status: 'active'),
      lifecycleRow(status: 'completed'),
      lifecycleRow()..['scheduled_end'] = '2026-11-05T00:00:00Z',
    ]) {
      expect(
        AttendanceLifecycle.of(WorkerWorkAssignment.fromJson(raw)),
        AttendanceLifecycle.inconsistent,
      );
    }
  });
  test(
    'history semantics keep cancellation and incomplete work out of Completed',
    () {
      final recorded = WorkerWorkAssignment.fromJson(
        lifecycleRow(
          input: '2026-11-05T01:00:00Z',
          output: '2026-11-05T08:00:00Z',
          status: 'awaiting_verification',
        ),
      );
      expect(AttendanceLifecycle.of(recorded), AttendanceLifecycle.recorded);
      expect(AttendanceHistoryFilter.recorded.matches(recorded), isTrue);
      expect(AttendanceHistoryFilter.issues.matches(recorded), isFalse);
      expect(recordedAttendanceDuration(recorded), '7h 0m');
      for (final raw in [
        lifecycleRow(),
        lifecycleRow(status: 'cancelled'),
        lifecycleRow(status: 'active', input: '2026-11-05T01:00:00Z'),
      ]) {
        final row = WorkerWorkAssignment.fromJson(raw);
        expect(AttendanceHistoryFilter.all.matches(row), isTrue);
        expect(AttendanceHistoryFilter.recorded.matches(row), isFalse);
        expect(recordedAttendanceDuration(row), isNull);
      }
    },
  );
  test('worker and company classifiers and filters agree on each sibling independently', () {
    for (final raw in [
      lifecycleRow(),
      lifecycleRow(now: null),
      lifecycleRow(input: '2026-11-05T01:00:00Z', status: 'active'),
    ]) {
      final worker = WorkerWorkAssignment.fromJson(raw);
      final company = CompanyWorkAssignment.fromJson({
        ...raw,
        'worker_id': raw['application_id'],
      });
      expect(AttendanceLifecycle.of(worker), AttendanceLifecycle.of(company));
      expect(
        matchesAttendanceShiftFilter(company, 'attendanceIssues'),
        AttendanceLifecycle.of(worker).isIssue,
      );
      expect(
        matchesAttendanceShiftFilter(
          company,
          'attendance:${AttendanceLifecycle.of(worker).name}',
        ),
        isTrue,
      );
      expect(matchesAttendanceShiftFilter(company, 'cancelled'), isFalse);
    }
  });
  test(
    'existing grace rule remains inclusive and independent of lifecycle',
    () {
      final start = DateTime.parse('2026-11-05T01:00:00Z');
      expect(workCheckInTimingLabel(start, null), isNull);
      expect(
        workCheckInTimingLabel(
          start,
          start.subtract(const Duration(minutes: 30)),
        ),
        'On Time',
      );
      expect(
        workCheckInTimingLabel(start, start.add(const Duration(minutes: 15))),
        'On Time',
      );
      expect(
        workCheckInTimingLabel(
          start,
          start.add(const Duration(minutes: 15, seconds: 1)),
        ),
        'Late',
      );
    },
  );
}
