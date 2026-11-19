import 'package:flutter/foundation.dart';

import '../jobs/workplace_coordinates.dart';

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
      workplacePin = workplaceCoordinates(
        row['workplace_latitude'],
        row['workplace_longitude'],
      ),
      assignmentStatus = WorkAssignmentStatus.parse(row['assignment_status']),
      verificationStatus = WorkVerificationStatus.parse(
        row['verification_status'],
      ),
      checkInAt = _nullableTime(row, 'check_in_at'),
      checkOutAt = _nullableTime(row, 'check_out_at'),
      attendanceAsOf = _nullableTime(row, 'attendance_as_of'),
      resolution = row['attendance_resolution'] == null
          ? null
          : WorkAttendanceResolution.fromJson(
              row['attendance_resolution'],
              workUuid(row['assignment_id']),
            ),
      verifiedAt = _nullableTime(row, 'verified_at');

  final String assignmentId, applicationId, jobId, jobTitle, workplaceLocation;
  final WorkplaceCoordinates? workplacePin;

  Uri? get workplaceMapLink {
    final pin = workplacePin;
    if (pin == null) return null;
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${pin.latitude},${pin.longitude}',
    });
  }

  final DateTime scheduledStart, scheduledEnd;
  final DateTime? checkInAt, checkOutAt, verifiedAt;

  /// Server statement time from the additive lifecycle read contract. Never
  /// substitute the device clock when the contract is not deployed.
  final DateTime? attendanceAsOf;
  final WorkAttendanceResolution? resolution;
  DateTime? get effectiveCheckInAt => resolution?.decision == 'corrected'
      ? resolution!.correctedCheckInAt
      : checkInAt;
  DateTime? get effectiveCheckOutAt => resolution?.decision == 'corrected'
      ? resolution!.correctedCheckOutAt
      : checkOutAt;
  final WorkAssignmentStatus assignmentStatus;
  final WorkVerificationStatus verificationStatus;
  WorkAttendanceState get attendanceState => checkOutAt != null
      ? WorkAttendanceState.checkedOut
      : checkInAt != null
      ? WorkAttendanceState.checkedIn
      : WorkAttendanceState.notStarted;
}

/// Optional Batch 2 metadata. Absent on the deployed Batch 1 read contract.
@immutable
class WorkAttendanceResolution {
  WorkAttendanceResolution.fromJson(Object? raw, String assignmentId) {
    if (raw is! Map) {
      throw const FormatException('Invalid attendance resolution.');
    }
    final row = Map<String, dynamic>.from(raw);
    if (row['contract_version'] != 2 ||
        workUuid(row['assignment_id']) != assignmentId ||
        row['version'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(row['version'] as String) ||
        row['can_confirm_absence'] is! bool ||
        row['can_correct'] is! bool ||
        row['checkout_recovery_enforced'] is! bool) {
      throw const FormatException('Invalid resolution scope or contract.');
    }
    version = row['version'] as String;
    canConfirmAbsence = row['can_confirm_absence'] as bool;
    canCorrect = row['can_correct'] as bool;
    recoveryEnforced = row['checkout_recovery_enforced'] as bool;
    recoveryCutoff = _time(row, 'recovery_cutoff');
    final location = row['original_location'];
    originalCheckInLocationStatus = location is Map
        ? location['check_in_status'] as String?
        : null;
    originalCheckOutLocationStatus = location is Map
        ? location['check_out_status'] as String?
        : null;
    if ([originalCheckInLocationStatus, originalCheckOutLocationStatus].any(
      (s) => s != null && !{'granted', 'denied', 'unavailable'}.contains(s),
    )) {
      throw const FormatException('Invalid original GPS status.');
    }
    final value = row['resolution'];
    if (value != null) {
      if (value is! Map) {
        throw const FormatException('Invalid resolution audit.');
      }
      final audit = Map<String, dynamic>.from(value);
      requestId = workUuid(audit['request_id']);
      actorId = workUuid(audit['resolved_by']);
      decision = _text(audit, 'decision');
      reason = _text(audit, 'reason');
      resolvedAt = _time(audit, 'resolved_at');
      correctedCheckInAt = _nullableTime(audit, 'corrected_check_in_at');
      correctedCheckOutAt = _nullableTime(audit, 'corrected_check_out_at');
      if (!{'confirmed_absent', 'corrected'}.contains(decision) ||
          reason!.trim().isEmpty ||
          (decision == 'corrected' &&
              (correctedCheckInAt == null ||
                  correctedCheckOutAt == null ||
                  correctedCheckOutAt!.isBefore(correctedCheckInAt!) ||
                  correctedCheckOutAt!.isAfter(resolvedAt!))) ||
          (decision == 'confirmed_absent' &&
              (correctedCheckInAt != null || correctedCheckOutAt != null))) {
        throw const FormatException('Invalid resolution decision.');
      }
    } else {
      requestId = actorId = decision = reason = null;
      resolvedAt = correctedCheckInAt = correctedCheckOutAt = null;
    }
  }
  late final String version;
  late final bool canConfirmAbsence, canCorrect, recoveryEnforced;
  late final DateTime recoveryCutoff;
  late final String? originalCheckInLocationStatus,
      originalCheckOutLocationStatus;
  late final String? requestId, actorId, decision, reason;
  late final DateTime? resolvedAt, correctedCheckInAt, correctedCheckOutAt;
  bool get canReview => decision == null && (canConfirmAbsence || canCorrect);
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

/// Location captured for one attendance check-in or check-out action.
///
/// Attendance is still allowed when location permission is denied or
/// the device cannot provide coordinates.
class WorkAttendanceLocation {
  const WorkAttendanceLocation._({
    required this.status,
    this.latitude,
    this.longitude,
  });

  final String status;
  final double? latitude;
  final double? longitude;

  factory WorkAttendanceLocation.granted({
    required double latitude,
    required double longitude,
  }) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw ArgumentError('Invalid attendance coordinates.');
    }

    return WorkAttendanceLocation._(
      status: 'granted',
      latitude: latitude,
      longitude: longitude,
    );
  }

  const WorkAttendanceLocation.denied() : this._(status: 'denied');

  const WorkAttendanceLocation.unavailable() : this._(status: 'unavailable');
}
