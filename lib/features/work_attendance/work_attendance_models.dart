import 'package:flutter/foundation.dart';

enum WorkAssignmentStatus {
  scheduled,
  active,
  awaitingVerification,
  completed,
  cancelled,
  disputed;

  static WorkAssignmentStatus parse(Object? value) => switch (value) {
    'scheduled' => scheduled,
    'active' => active,
    'awaiting_verification' => awaitingVerification,
    'completed' => completed,
    'cancelled' => cancelled,
    'disputed' => disputed,
    _ => throw const FormatException('Invalid assignment status.'),
  };
}

enum WorkVerificationStatus {
  notSubmitted,
  pendingReview,
  moreEvidenceRequired,
  verified,
  disputed;

  static WorkVerificationStatus parse(Object? value) => switch (value) {
    'not_submitted' => notSubmitted,
    'pending_review' => pendingReview,
    'more_evidence_required' => moreEvidenceRequired,
    'verified' => verified,
    'disputed' => disputed,
    _ => throw const FormatException('Invalid verification status.'),
  };
}

/// Derived from server timestamps; never from the device clock.
enum WorkAttendanceState { notStarted, checkedIn, checkedOut }

String workUuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value)) {
    throw const FormatException('Invalid UUID.');
  }
  return value.toLowerCase();
}

String _text(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String) throw FormatException('Invalid $key.');
  return value;
}

DateTime _time(Map<String, dynamic> row, String key) {
  final value = _text(row, key);
  // timestamptz must carry a zone; do not interpret missing zones as local time.
  if (!RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(value)) {
    throw FormatException('Missing timezone for $key.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Invalid $key.');
  return parsed.toUtc();
}

DateTime? _nullableTime(Map<String, dynamic> row, String key) =>
    row[key] == null ? null : _time(row, key);

@immutable
sealed class WorkAssignment {
  WorkAssignment.fromJson(Map<String, dynamic> row)
    : assignmentId = workUuid(row['assignment_id']),
      applicationId = workUuid(row['application_id']),
      jobId = workUuid(row['job_id']),
      jobTitle = _text(row, 'job_title'),
      scheduledStart = _time(row, 'scheduled_start'),
      scheduledEnd = _time(row, 'scheduled_end'),
      workplaceLocation = _text(row, 'workplace_location'),
      assignmentStatus = WorkAssignmentStatus.parse(row['assignment_status']),
      verificationStatus = WorkVerificationStatus.parse(
        row['verification_status'],
      ),
      checkInAt = _nullableTime(row, 'check_in_at'),
      checkOutAt = _nullableTime(row, 'check_out_at'),
      verifiedAt = _nullableTime(row, 'verified_at');

  final String assignmentId, applicationId, jobId, jobTitle, workplaceLocation;
  final DateTime scheduledStart, scheduledEnd;
  final DateTime? checkInAt, checkOutAt, verifiedAt;
  final WorkAssignmentStatus assignmentStatus;
  final WorkVerificationStatus verificationStatus;
  WorkAttendanceState get attendanceState => checkOutAt != null
      ? WorkAttendanceState.checkedOut
      : checkInAt != null
      ? WorkAttendanceState.checkedIn
      : WorkAttendanceState.notStarted;
}

/// Exactly the worker RPC projection, including company identity.
@immutable
final class WorkerWorkAssignment extends WorkAssignment {
  WorkerWorkAssignment.fromJson(super.row)
    : companyId = workUuid(row['company_id']),
      companyName = _text(row, 'company_name'),
      super.fromJson();
  final String companyId, companyName;
}

/// Company identity is supplied to the RPC, not returned in this projection.
@immutable
final class CompanyWorkAssignment extends WorkAssignment {
  CompanyWorkAssignment.fromJson(super.row)
    : workerId = workUuid(row['worker_id']),
      super.fromJson();
  final String workerId;
}

/// Assignment identity is supplied to list_work_evidence, not returned.
@immutable
final class WorkEvidence {
  WorkEvidence.fromJson(Map<String, dynamic> row)
    : evidenceId = workUuid(row['evidence_id']),
      submissionRound = _round(row['submission_round']),
      description = _text(row, 'description'),
      storagePath = _text(row, 'storage_path'),
      fileName = _text(row, 'file_name'),
      mimeType = _text(row, 'mime_type'),
      submittedBy = workUuid(row['submitted_by']),
      submittedAt = _time(row, 'submitted_at');
  final String evidenceId,
      description,
      storagePath,
      fileName,
      mimeType,
      submittedBy;
  final int submissionRound;
  final DateTime submittedAt;

  static int _round(Object? value) {
    if (value is! int || value < 1) {
      throw const FormatException('Invalid submission round.');
    }
    return value;
  }
}
