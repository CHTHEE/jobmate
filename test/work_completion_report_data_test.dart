import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';
import 'package:jobmate/features/work_attendance/work_completion_report_data.dart';
import 'package:jobmate/features/work_attendance/work_completion_report_format.dart';

WorkCompletionReportData report({
  String? type,
  Duration checkInOffset = Duration.zero,
  Duration checkOutOffset = Duration.zero,
  List<String> descriptions = const [],
}) {
  final start = DateTime.utc(2026, 11, 20, 14);
  final end = DateTime.utc(2026, 11, 20, 17);
  return WorkCompletionReportData(
    generatedAt: DateTime.utc(2026, 11, 22),
    jobTitle: 'Retail assistant',
    companyName: 'Example Company',
    employmentType: type,
    workplaceLocation: 'Kuala Lumpur',
    scheduledStart: start,
    scheduledEnd: end,
    checkInAt: start.add(checkInOffset),
    checkOutAt: end.add(checkOutOffset),
    attendanceSource: ReportAttendanceSource.original,
    checkInLocation: (status: null, originalEventAt: start),
    checkOutLocation: (status: null, originalEventAt: end),
    verifiedRound: 2,
    submittedFileCount: 2,
    submittedDescriptions: descriptions,
    verifiedAt: DateTime.utc(2026, 11, 21),
  );
}

void main() {
  test('MYT rolls an overnight UTC schedule into the next calendar date', () {
    final data = report();
    final format = WorkReportFormat(data);
    expect(format.workDates, '20 Nov 2026 – 21 Nov 2026');
    expect(format.end, '21 Nov 2026, 1:00 AM MYT');
    expect(format.filename, 'JobMate_Work_Report_2026-11-20.pdf');
    expect(data.scheduledDuration, const Duration(hours: 3));
    expect(data.checkInOffset, Duration.zero);
    expect(data.checkOutOffset, Duration.zero);
  });

  test('displayed whole-second timestamps and derived durations agree', () {
    final data = report(
      checkInOffset: const Duration(seconds: -144, milliseconds: -100),
      checkOutOffset: const Duration(seconds: -1149, milliseconds: -300),
    );
    final format = WorkReportFormat(data);
    expect(format.checkIn, '20 Nov 2026, 9:57:35 PM MYT');
    expect(format.checkOut, '21 Nov 2026, 12:40:50 AM MYT');
    expect(format.checkInTiming, '2 min 25 s early');
    expect(format.checkOutTiming, '19 min 10 s before scheduled end');
    expect(format.recordedDuration, '2 h 43 min 15 s');
    expect(data.checkInOffset.inMilliseconds, -144100);
  });

  test('preserves sub-second direction and exact equality', () {
    final base = WorkReportFormat(report());
    expect(base.checkInTiming, 'On scheduled time');
    expect(base.checkOutTiming, 'On scheduled time');
    final close = WorkReportFormat(
      report(
        checkInOffset: const Duration(milliseconds: 180),
        checkOutOffset: const Duration(milliseconds: -180),
      ),
    );
    expect(close.checkInTiming, 'Less than 1 s after scheduled start');
    expect(close.checkOutTiming, '1 s before scheduled end');
    expect(
      WorkReportFormat.time(
        DateTime.utc(2026, 11, 20, 13, 35, 12),
        scheduled: true,
      ),
      '20 Nov 2026, 9:35:12 PM MYT',
    );
  });

  test('signed factual offsets and summary use the same recorded duration', () {
    final data = report(
      checkInOffset: const Duration(minutes: 10),
      checkOutOffset: const Duration(minutes: -5),
    );
    expect(data.summary.checkInOffset, const Duration(minutes: 10));
    expect(data.summary.checkOutOffset, const Duration(minutes: -5));
    expect(
      data.summary.recordedDuration,
      const Duration(hours: 2, minutes: 45),
    );
    expect(data.summary.filesSubmitted, 2);
    expect(data.summary.completion, WorkAssignmentStatus.completed);
    expect(data.summary.verification, WorkVerificationStatus.verified);
    expect(data.summary.verifiedAt, data.markedCompleteAtVerification);
  });

  test('only supported employment values become report labels', () {
    for (final entry in {
      'full_time': 'Full-time',
      'part_time': 'Part-time',
      'contract': 'Contract',
      'internship': 'Internship',
      'temporary': 'Temporary',
      'gig': null,
    }.entries) {
      expect(report(type: entry.key).employmentTypeLabel, entry.value);
    }
    expect(report().employmentTypeLabel, isNull);
  });

  test('descriptions are copied, deduplicated and immutable', () {
    final descriptions = [
      'Delivered stock',
      ' Delivered stock ',
      ' ',
      'Updated inventory',
    ];
    final data = report(descriptions: descriptions);
    descriptions.clear();
    expect(data.submittedDescriptions, [
      'Delivered stock',
      'Updated inventory',
    ]);
    expect(
      () => data.submittedDescriptions.add('extra'),
      throwsUnsupportedError,
    );
  });
}
