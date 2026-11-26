import 'package:flutter/foundation.dart';

import '../jobs/job_display.dart';
import 'work_attendance_models.dart';

enum ReportAttendanceSource { original, corrected }

enum ReportLocationStatus { granted, denied, unavailable, notRecorded }

/// Location metadata refers only to the original attendance event.
typedef ReportAttendanceLocation = ({
  ReportLocationStatus? status,
  DateTime? originalEventAt,
});

/// An on-demand report containing only approved display data.
@immutable
class WorkCompletionReportData {
  WorkCompletionReportData({
    required this.generatedAt,
    required this.jobTitle,
    required this.companyName,
    this.workerName,
    String? employmentType,
    required this.workplaceLocation,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.checkInAt,
    required this.checkOutAt,
    required this.attendanceSource,
    required this.checkInLocation,
    required this.checkOutLocation,
    required this.verifiedRound,
    required this.submittedFileCount,
    required Iterable<String> submittedDescriptions,
    required this.verifiedAt,
  }) : employmentTypeLabel = jobEmploymentTypes.contains(employmentType)
           ? jobLabel(employmentType!)
           : null,
       submittedDescriptions = List.unmodifiable(
         submittedDescriptions
             .map((text) => text.trim())
             .where((text) => text.isNotEmpty)
             .toSet(),
       );

  final DateTime generatedAt, scheduledStart, scheduledEnd;
  final DateTime checkInAt, checkOutAt, verifiedAt;
  final String jobTitle, companyName, workplaceLocation;
  final String? workerName, employmentTypeLabel;
  final ReportAttendanceSource attendanceSource;
  final ReportAttendanceLocation checkInLocation, checkOutLocation;
  final int verifiedRound, submittedFileCount;
  final List<String> submittedDescriptions;

  WorkAssignmentStatus get assignmentStatus => WorkAssignmentStatus.completed;
  WorkVerificationStatus get verificationStatus =>
      WorkVerificationStatus.verified;
  Duration get scheduledDuration => scheduledEnd.difference(scheduledStart);
  Duration get recordedAttendanceDuration => checkOutAt.difference(checkInAt);
  Duration get checkInOffset => checkInAt.difference(scheduledStart);
  Duration get checkOutOffset => checkOutAt.difference(scheduledEnd);
  DateTime get markedCompleteAtVerification => verifiedAt;
  String get verifiedBy => 'Employer';
  String get evidenceSubmissionStatus => 'Submitted';
  String get attendanceStatus => switch (attendanceSource) {
    ReportAttendanceSource.original => 'Attendance recorded',
    ReportAttendanceSource.corrected => 'Employer-corrected attendance',
  };

  /// Factual offsets are signed and independent of the punctuality grace rule.
  ({
    String attendance,
    Duration recordedDuration,
    Duration checkInOffset,
    Duration checkOutOffset,
    WorkAssignmentStatus completion,
    int filesSubmitted,
    WorkVerificationStatus verification,
    DateTime verifiedAt,
  })
  get summary => (
    attendance: attendanceStatus,
    recordedDuration: recordedAttendanceDuration,
    checkInOffset: checkInOffset,
    checkOutOffset: checkOutOffset,
    completion: assignmentStatus,
    filesSubmitted: submittedFileCount,
    verification: verificationStatus,
    verifiedAt: verifiedAt,
  );
}
