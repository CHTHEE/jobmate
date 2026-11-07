import 'dart:async';

import 'package:flutter/material.dart';

import 'work_attendance_models.dart';

enum EvidenceDeadlineState {
  notStarted,
  unavailable,
  notYetDue,
  dueSoon,
  overdue,
  submitted,
  moreEvidenceRequired,
  verified,
  notApplicable,
}

/// Advisory presentation only. Never used by submission/verification eligibility.
class EvidenceDeadline {
  const EvidenceDeadline(this.state, {this.dueAt});
  final EvidenceDeadlineState state;
  final DateTime? dueAt;

  static EvidenceDeadline fromAssignment(
    WorkAssignment row, {
    required DateTime now,
    WorkAssignmentStatus? assignmentStatus,
    WorkVerificationStatus? verificationStatus,
  }) {
    final assignment = assignmentStatus ?? row.assignmentStatus;
    final verification = verificationStatus ?? row.verificationStatus;
    if (assignment == WorkAssignmentStatus.cancelled ||
        assignment == WorkAssignmentStatus.disputed ||
        verification == WorkVerificationStatus.disputed) {
      return const EvidenceDeadline(EvidenceDeadlineState.notApplicable);
    }
    final checkout = row.checkOutAt;
    final validAttendance =
        checkout != null &&
        row.checkInAt != null &&
        !checkout.isBefore(row.checkInAt!);
    final due = validAttendance
        ? checkout.toUtc().add(const Duration(hours: 24))
        : null;
    // Returned lifecycle state takes priority over elapsed time, including when
    // historic attendance is incomplete. Never label submitted work overdue.
    final outcome = switch (verification) {
      WorkVerificationStatus.verified => EvidenceDeadlineState.verified,
      WorkVerificationStatus.pendingReview => EvidenceDeadlineState.submitted,
      WorkVerificationStatus.moreEvidenceRequired =>
        EvidenceDeadlineState.moreEvidenceRequired,
      _ => null,
    };
    if (outcome != null) return EvidenceDeadline(outcome, dueAt: due);
    if (assignment == WorkAssignmentStatus.completed) {
      return EvidenceDeadline(EvidenceDeadlineState.notApplicable, dueAt: due);
    }
    if (checkout == null &&
        (assignment == WorkAssignmentStatus.scheduled ||
            assignment == WorkAssignmentStatus.active)) {
      return const EvidenceDeadline(EvidenceDeadlineState.notStarted);
    }
    if (due == null ||
        assignment != WorkAssignmentStatus.awaitingVerification ||
        now.toUtc().isBefore(checkout!)) {
      return EvidenceDeadline(EvidenceDeadlineState.unavailable, dueAt: due);
    }
    if (!now.toUtc().isBefore(due)) {
      return EvidenceDeadline(EvidenceDeadlineState.overdue, dueAt: due);
    }
    if (due.difference(now.toUtc()) <= const Duration(hours: 4)) {
      return EvidenceDeadline(EvidenceDeadlineState.dueSoon, dueAt: due);
    }
    return EvidenceDeadline(EvidenceDeadlineState.notYetDue, dueAt: due);
  }

  String get label => switch (state) {
    EvidenceDeadlineState.notStarted => 'Evidence timing: After checkout',
    EvidenceDeadlineState.unavailable => 'Evidence timing: Unavailable',
    EvidenceDeadlineState.notYetDue => 'Evidence: Not yet due',
    EvidenceDeadlineState.dueSoon => 'Evidence: Due soon',
    EvidenceDeadlineState.overdue => 'Evidence: Overdue',
    EvidenceDeadlineState.submitted => 'Evidence: Submitted',
    EvidenceDeadlineState.moreEvidenceRequired =>
      'Evidence: More Evidence Required',
    EvidenceDeadlineState.verified => 'Evidence: Verified',
    EvidenceDeadlineState.notApplicable => 'Evidence timing: Not assessed',
  };
}

/// Updates relative timing on an open page and after resume, without RPCs/writes.
class EvidenceDeadlineSummary extends StatefulWidget {
  const EvidenceDeadlineSummary({
    super.key,
    required this.assignment,
    this.clock,
    this.assignmentStatus,
    this.verificationStatus,
  });
  final WorkAssignment assignment;
  final DateTime Function()? clock;
  // Optional fresher server workflow projection; never local optimistic state.
  final WorkAssignmentStatus? assignmentStatus;
  final WorkVerificationStatus? verificationStatus;

  @override
  State<EvidenceDeadlineSummary> createState() =>
      _EvidenceDeadlineSummaryState();
}

class _EvidenceDeadlineSummaryState extends State<EvidenceDeadlineSummary>
    with WidgetsBindingObserver {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timing = EvidenceDeadline.fromAssignment(
      widget.assignment,
      now: (widget.clock ?? DateTime.now)(),
      assignmentStatus: widget.assignmentStatus,
      verificationStatus: widget.verificationStatus,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(timing.label, style: Theme.of(context).textTheme.titleSmall),
          if (timing.dueAt != null)
            Text(
              'Suggested initial evidence due: ${_malaysiaTime(timing.dueAt!)}',
            ),
          Text(switch (timing.state) {
            EvidenceDeadlineState.notStarted => 'The 24-hour target starts from recorded checkout, not scheduled shift end.',
            EvidenceDeadlineState.unavailable => 'Check the recorded attendance and device clock, then refresh. No deadline is enforced here.',
            EvidenceDeadlineState.moreEvidenceRequired => 'Follow the employer feedback and resubmit. No new resubmission deadline has been set.',
            EvidenceDeadlineState.submitted =>
              'Submitted evidence is awaiting employer review.',
            EvidenceDeadlineState.verified =>
              'Evidence has been verified; no submission is due.',
            EvidenceDeadlineState.notApplicable =>
              'See the recorded shift and verification status.',
            _ => 'Advisory timing uses this device clock. Overdue does not mean failed and does not block submission; server eligibility still applies.',
          }),
        ],
      ),
    );
  }
}

String _malaysiaTime(DateTime timestamp) {
  final time = timestamp.toUtc().add(const Duration(hours: 8));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.day)}/${two(time.month)}/${time.year} ${two(time.hour)}:${two(time.minute)} MYT';
}
