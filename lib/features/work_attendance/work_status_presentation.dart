import 'package:flutter/material.dart';

import 'work_attendance_models.dart';

/// Informational only: compare saved server instants, never the device clock.
/// This does not change assignment status, eligibility, review or payment.
String? workCheckInTimingLabel(DateTime scheduledStart, DateTime? checkInAt) {
  if (checkInAt == null) return null;
  return checkInAt.isAfter(scheduledStart.add(const Duration(minutes: 15)))
      ? 'Late'
      : 'On Time';
}

/// Shared text presentation for worker and authorized employer assignment views.
class WorkCheckInTiming extends StatelessWidget {
  const WorkCheckInTiming({super.key, required this.assignment});
  final WorkAssignment assignment;

  @override
  Widget build(BuildContext context) {
    final label = workCheckInTimingLabel(
      assignment.scheduledStart,
      assignment.checkInAt,
    );
    return label == null
        ? const SizedBox.shrink()
        : Text('Check-in timing: $label (15-minute grace period)');
  }
}

/// Presentation only. Never grants attendance or verification eligibility.
enum WorkStage {
  scheduled,
  checkedIn,
  awaitingEvidence,
  pendingReview,
  moreEvidence,
  verified,
  completed,
  cancelled,
  disputed;

  static WorkStage fromAssignment(WorkAssignment row) => fromStatuses(
    row.assignmentStatus,
    row.verificationStatus,
    checkedOut: row.checkOutAt != null,
    checkedIn: row.checkInAt != null,
  );

  static WorkStage fromStatuses(
    WorkAssignmentStatus assignment,
    WorkVerificationStatus verification, {
    bool checkedOut = false,
    bool checkedIn = false,
  }) {
    if (assignment == WorkAssignmentStatus.cancelled) return cancelled;
    if (assignment == WorkAssignmentStatus.disputed ||
        verification == WorkVerificationStatus.disputed) {
      return disputed;
    }
    if (verification == WorkVerificationStatus.verified) return verified;
    if (assignment == WorkAssignmentStatus.completed) return completed;
    if (verification == WorkVerificationStatus.moreEvidenceRequired) {
      return moreEvidence;
    }
    if (verification == WorkVerificationStatus.pendingReview) {
      return pendingReview;
    }
    if (checkedOut || assignment == WorkAssignmentStatus.awaitingVerification) {
      return awaitingEvidence;
    }
    if (checkedIn || assignment == WorkAssignmentStatus.active) {
      return WorkStage.checkedIn;
    }
    return scheduled;
  }

  String get label => switch (this) {
    scheduled => 'Scheduled',
    WorkStage.checkedIn => 'Checked In',
    awaitingEvidence => 'Awaiting Evidence',
    pendingReview => 'Pending Review',
    moreEvidence => 'More Evidence Required',
    verified => 'Completed / Verified',
    completed => 'Completed',
    cancelled => 'Cancelled',
    disputed => 'Disputed',
  };

  IconData get icon => switch (this) {
    scheduled => Icons.calendar_month_outlined,
    WorkStage.checkedIn => Icons.timer_outlined,
    awaitingEvidence => Icons.upload_file_outlined,
    pendingReview => Icons.rate_review_outlined,
    moreEvidence => Icons.feedback_outlined,
    verified || completed => Icons.verified_outlined,
    cancelled => Icons.cancel_outlined,
    disputed => Icons.report_outlined,
  };

  String heading(bool employer) => switch (this) {
    scheduled => employer ? 'Shift scheduled' : 'Your next shift',
    WorkStage.checkedIn =>
      employer ? 'Worker checked in' : 'Your shift is in progress',
    awaitingEvidence =>
      employer
          ? 'Waiting for worker evidence'
          : 'Your shift is complete — add evidence',
    pendingReview =>
      employer
          ? 'Action needed: review evidence'
          : 'Your evidence is awaiting review',
    moreEvidence =>
      employer
          ? 'Waiting for updated evidence'
          : 'Action needed: update your evidence',
    verified => 'Work verified successfully',
    completed => 'Work completed',
    cancelled => 'This shift was cancelled',
    disputed => 'This work needs attention',
  };

  String detail(bool employer) => switch (this) {
    scheduled =>
      'Check-in availability is validated by the server for this shift.',
    WorkStage.checkedIn =>
      employer
          ? 'Attendance has started. GPS details are available below.'
          : 'Check out when your work is finished, then submit evidence.',
    awaitingEvidence =>
      employer ? 'The worker can now submit their work description and files.' : 'Submit your work description and private PDF or images for employer review.',
    pendingReview =>
      employer
          ? 'Open the latest files, then verify work or request additional evidence.'
          : 'Your employer will review the latest submitted files.',
    moreEvidence =>
      employer
          ? 'Your feedback has been sent to the worker.'
          : 'Read the employer’s feedback and submit updated files.',
    verified => 'The employer has approved this work. Evidence and verification history remain available.',
    completed => 'Open the work details to see the recorded outcome.',
    cancelled => 'Recorded details remain available for reference.',
    disputed => 'Review the recorded details and contact support if needed.',
  };

  String evidenceAction(bool employer) => switch (this) {
    awaitingEvidence => employer ? 'View Evidence' : 'Submit Evidence',
    pendingReview => employer ? 'Review Evidence' : 'View submitted evidence',
    moreEvidence =>
      employer ? 'View feedback & evidence' : 'Review Feedback & Resubmit',
    verified || completed => 'View Verification Details',
    _ => 'View Evidence',
  };
}

class WorkStatusBanner extends StatelessWidget {
  const WorkStatusBanner({
    super.key,
    required this.stage,
    required this.employer,
  });
  final WorkStage stage;
  final bool employer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urgent =
        stage == WorkStage.moreEvidence ||
        (employer && stage == WorkStage.pendingReview);
    final (background, foreground) = switch (stage) {
      WorkStage.cancelled ||
      WorkStage.disputed => (scheme.errorContainer, scheme.onErrorContainer),
      WorkStage.verified || WorkStage.completed => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _ when urgent => (scheme.primaryContainer, scheme.onPrimaryContainer),
      WorkStage.checkedIn => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      _ => (scheme.surfaceContainerHighest, scheme.onSurface),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: urgent ? Border.all(color: scheme.primary, width: 2) : null,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(stage.icon, color: foreground),
                Text(
                  stage.label,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              stage.heading(employer),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: foreground),
            ),
            const SizedBox(height: 4),
            Text(stage.detail(employer)),
          ],
        ),
      ),
    );
  }
}
