import 'work_attendance_models.dart';
import 'work_attendance_lifecycle.dart';

/// Display-only counts for the loaded authorized snapshot, never permissions.
bool workerShiftNeedsAction(WorkAssignment row) {
  if ({
        WorkAssignmentStatus.completed,
        WorkAssignmentStatus.cancelled,
        WorkAssignmentStatus.disputed,
      }.contains(row.assignmentStatus) ||
      {
        WorkVerificationStatus.verified,
        WorkVerificationStatus.pendingReview,
        WorkVerificationStatus.disputed,
      }.contains(row.verificationStatus) ||
      row.resolution?.decision == 'confirmed_absent') {
    return false;
  }
  if (row.assignmentStatus == WorkAssignmentStatus.awaitingVerification &&
      row.effectiveCheckInAt != null &&
      row.effectiveCheckOutAt != null &&
      !row.effectiveCheckOutAt!.isBefore(row.effectiveCheckInAt!) &&
      {
        WorkVerificationStatus.notSubmitted,
        WorkVerificationStatus.moreEvidenceRequired,
      }.contains(row.verificationStatus)) {
    return true;
  }
  if (row.resolution?.decision != null) return false;
  if (row.resolution?.recoveryEnforced == true &&
      row.attendanceAsOf != null &&
      row.attendanceAsOf!.isAfter(row.resolution!.recoveryCutoff)) {
    return false;
  }
  return {
    AttendanceLifecycle.ready,
    AttendanceLifecycle.onShift,
    AttendanceLifecycle.overdue,
  }.contains(AttendanceLifecycle.of(row));
}

bool employerShiftNeedsAction(WorkAssignment row) {
  if ({
        WorkAssignmentStatus.completed,
        WorkAssignmentStatus.cancelled,
      }.contains(row.assignmentStatus) ||
      row.verificationStatus == WorkVerificationStatus.verified ||
      row.resolution?.decision == 'confirmed_absent') {
    return false;
  }
  return row.resolution?.canReview == true ||
      (row.assignmentStatus == WorkAssignmentStatus.awaitingVerification &&
          row.verificationStatus == WorkVerificationStatus.pendingReview);
}
