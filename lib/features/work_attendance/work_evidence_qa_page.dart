import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_models.dart';
import 'work_evidence_draft_controller.dart';
import 'work_evidence_draft_page.dart';
import 'work_evidence_draft_upload_controller.dart';
import 'work_evidence_repository.dart';
import 'work_evidence_submission_repository.dart';
import 'work_evidence_upload_repository.dart';

const supervisedWorkEvidenceQaAssignment =
    '49f417e6-9645-4433-a1fd-76a99d6c0815';

bool canUseSupervisedWorkEvidenceQa(WorkEvidenceRepository viewer) {
  final assignment = viewer.assignment;
  return !viewer.employer &&
      !viewer.loading &&
      viewer.error == null &&
      viewer.attendance.source.userId != null &&
      viewer.assignmentId == supervisedWorkEvidenceQaAssignment &&
      assignment is WorkerWorkAssignment &&
      assignment.assignmentId == supervisedWorkEvidenceQaAssignment &&
      assignment.assignmentStatus ==
          WorkAssignmentStatus.awaitingVerification &&
      assignment.verificationStatus == WorkVerificationStatus.notSubmitted &&
      assignment.checkInAt != null &&
      assignment.checkOutAt != null &&
      !assignment.checkOutAt!.isBefore(assignment.checkInAt!);
}

/// Operational app-lifetime gate only. Refresh/restart loses this protection.
/// Each test injects a fresh session; production shares it across page lifetimes.
class WorkEvidenceQaSession {
  final _workers = <String, _QaAttempt>{};
  static final runningApp = WorkEvidenceQaSession();
}

class _QaAttempt {
  bool uploadStarted = false,
      submitStarted = false,
      blocked = false,
      finished = false;
}

/// Dedicated dependencies, owned/disposed by the QA page. No eager live calls.
class WorkEvidenceQaDependencies {
  WorkEvidenceQaDependencies({
    required WorkEvidenceDraftController draft,
    required this.uploads,
    required this.submissions,
    WorkEvidenceQaSession? session,
  }) : coordinator = WorkEvidenceDraftUploadController(
         draft: draft,
         uploads: uploads,
       ),
       session = session ?? WorkEvidenceQaSession.runningApp;
  factory WorkEvidenceQaDependencies.supabase(
    WorkEvidenceDraftController draft,
  ) {
    final client = Supabase.instance.client;
    final uploads = WorkEvidenceUploadRepository(
      SupabaseWorkEvidenceUploadSource(client),
      assignmentId: supervisedWorkEvidenceQaAssignment,
    );
    return WorkEvidenceQaDependencies(
      draft: draft,
      uploads: uploads,
      submissions: WorkEvidenceSubmissionRepository(
        SupabaseWorkEvidenceSubmissionSource(client),
        uploads: uploads,
      ),
    );
  }
  final WorkEvidenceUploadRepository uploads;
  final WorkEvidenceSubmissionRepository submissions;
  final WorkEvidenceDraftUploadController coordinator;
  final WorkEvidenceQaSession session;
  bool _disposed = false;
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    coordinator.dispose();
    submissions.dispose();
    uploads.dispose();
  }
}

class WorkEvidenceQaPage extends StatefulWidget {
  const WorkEvidenceQaPage({
    super.key,
    required this.viewer,
    required this.draft,
    required this.dependencies,
    this.onClose,
  });
  final WorkEvidenceRepository viewer;
  final WorkEvidenceDraftController draft;
  final WorkEvidenceQaDependencies dependencies;
  final VoidCallback? onClose;
  @override
  State<WorkEvidenceQaPage> createState() => _WorkEvidenceQaPageState();
}

class _WorkEvidenceQaPageState extends State<WorkEvidenceQaPage> {
  late final _actor = widget.draft.session.userId;
  late final _entry = widget.dependencies.session._workers.putIfAbsent(
    _actor ?? '',
    _QaAttempt.new,
  );
  bool _armed = false, _busy = false, _confirming = false, _invalid = false;
  String _message =
      'Select and validate files, then explicitly confirm each real action.';
  WorkEvidenceQaDependencies get deps => widget.dependencies;
  bool get _current =>
      mounted &&
      !_invalid &&
      _actor != null &&
      widget.draft.session.userId == _actor &&
      widget.draft.assignmentId == supervisedWorkEvidenceQaAssignment &&
      widget.viewer.assignmentId == supervisedWorkEvidenceQaAssignment &&
      !widget.viewer.employer &&
      widget.viewer.attendance.source.userId == _actor &&
      deps.uploads.source.userId == _actor &&
      deps.submissions.source.userId == _actor;

  @override
  void initState() {
    super.initState();
    widget.draft.addListener(_observe);
    deps.coordinator.addListener(_observe);
    widget.viewer.addListener(_observe);
    if (_entry.uploadStarted && !_entry.finished) _entry.blocked = true;
  }

  void _observe() {
    if (!mounted) return;
    if (!_current) {
      _invalid = true;
      if (_entry.uploadStarted) _entry.blocked = true;
    } else if (_entry.uploadStarted &&
        !_busy &&
        deps.coordinator.state.phase ==
            WorkEvidenceDraftUploadPhase.invalidated) {
      _entry.blocked = true;
      _message = 'Draft changed after upload. Stop and investigate; uploaded objects were not removed.';
    }
    setState(() {});
  }

  void _block(String message) {
    _entry.blocked = true;
    if (mounted) setState(() => _message = message);
  }

  Future<bool> _confirm(String title, String message) async {
    setState(() => _confirming = true);
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm real action'),
          ),
        ],
      ),
    );
    if (mounted) setState(() => _confirming = false);
    return accepted == true && _current;
  }

  Future<bool> _freshEligibility() async {
    await widget.viewer.load().timeout(const Duration(seconds: 20));
    return _current && canUseSupervisedWorkEvidenceQa(widget.viewer);
  }

  Future<void> _upload() async {
    if (!_current ||
        !_armed ||
        _busy ||
        _confirming ||
        _entry.uploadStarted ||
        !widget.draft.ready) {
      return;
    }
    if (!await _confirm(
      'Upload real QA evidence?',
      'Upload ${widget.draft.files.length} validated files to private Supabase Storage for the approved QA assignment? Files will not be overwritten or deleted. This does not submit evidence.',
    )) {
      return;
    }
    if (_entry.uploadStarted || !_armed || !widget.draft.ready) return;
    _entry.uploadStarted = true;
    setState(() {
      _busy = true;
      _message = 'Checking eligibility and uploading real QA files…';
    });
    try {
      if (!await _freshEligibility()) {
        _block(
          'Eligibility or account could not be confirmed. Stop and investigate.',
        );
        return;
      }
      final state = await deps.coordinator.start().timeout(
        const Duration(seconds: 45),
      );
      if (!_current) return;
      if (state.phase != WorkEvidenceDraftUploadPhase.confirmed ||
          state.receipt == null) {
        _block(
          'Upload did not fully confirm. Some objects may exist. No retry is allowed in this QA session; manual investigation is required.',
        );
      } else {
        setState(
          () => _message =
              'Real upload batch confirmed. Evidence has not been submitted.',
        );
      }
    } catch (_) {
      // Stop further file-loop requests, without claiming an in-flight upload
      // was rolled back. The existing repository owns its pending byte snapshot.
      deps.uploads.changeAssignment('');
      _block(
        'Upload outcome is uncertain. Objects may already exist. Stop; manual investigation is required.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final receipt = deps.coordinator.state.receipt;
    if (!_current ||
        !_armed ||
        _busy ||
        _confirming ||
        _entry.blocked ||
        _entry.submitStarted ||
        receipt == null) {
      return;
    }
    if (!await _confirm(
      'Submit real QA evidence once?',
      'Submit the confirmed ${receipt.uploadedPaths.length}-file batch and this description?\n\n${widget.draft.description}\n\nThis calls the deployed non-idempotent RPC once. Do not refresh or restart during uncertainty.',
    )) {
      return;
    }
    if (_entry.submitStarted || _entry.blocked || !_current) return;
    _entry.submitStarted = true;
    setState(() {
      _busy = true;
      _message = 'Checking eligibility and submitting QA evidence once…';
    });
    try {
      if (!await _freshEligibility()) {
        _block(
          'Fresh eligibility could not be confirmed. No submission was sent. Stop and investigate.',
        );
        return;
      }
      final result = await deps.submissions.submit(
        draft: widget.draft,
        receipt: receipt,
      );
      if (!_current || !deps.submissions.isCurrent(result)) {
        _block(
          'Account or draft changed. Outcome must be investigated; no further QA submission is allowed.',
        );
        return;
      }
      if (!result.requiresRefresh) {
        _block(
          'Submission did not confirm. This QA session is permanently blocked; manual investigation is required.',
        );
        if (result.requiresReconciliation) {
          final read = await deps.submissions
              .reconcile(assignmentId: supervisedWorkEvidenceQaAssignment)
              .timeout(const Duration(seconds: 20));
          if (_current &&
              deps.submissions.isReconciliationCurrent(read) &&
              read.status == WorkEvidenceReconciliationStatus.committed) {
            _entry.finished = true;
            setState(
              () => _message =
                  'Fresh evidence confirms submission round ${read.submissionRound}. QA remains closed to further writes.',
            );
            await widget.viewer.load().timeout(const Duration(seconds: 20));
          }
        }
        return;
      }
      _entry.finished = true;
      setState(
        () => _message =
            'Submission confirmed: round ${result.submissionRound}. Refreshing authoritative evidence…',
      );
      await widget.viewer.load().timeout(const Duration(seconds: 20));
      if (_current) {
        setState(
          () => _message = widget.viewer.error == null
              ? 'Submission confirmed: round ${result.submissionRound}. Authoritative assignment and evidence refreshed. QA session complete.'
              : 'Submission confirmed: round ${result.submissionRound}, but refresh failed. Do not submit again; investigate using read-only refresh.',
        );
      }
    } catch (_) {
      _block(
        _entry.finished
            ? 'Submission was confirmed, but refresh did not finish. Do not submit again; manual read-only investigation is required.'
            : 'Submission outcome is uncertain. Stop; no retry is allowed. Manual investigation is required.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    widget.draft.removeListener(_observe);
    deps.coordinator.removeListener(_observe);
    widget.viewer.removeListener(_observe);
    if (_entry.uploadStarted && !_entry.finished) _entry.blocked = true;
    deps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = !_current || _entry.blocked;
    final locked =
        _entry.uploadStarted ||
        _entry.finished ||
        blocked ||
        _busy ||
        _confirming;
    return WorkEvidenceDraftPage(
      controller: widget.draft,
      onClose: widget.onClose,
      supervisedQaBusy: _busy || _confirming,
      supervisedQaLocked: locked,
      supervisedQaControls: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'SUPERVISED QA — REAL BACKEND',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Approved QA assignment only. Use one browser tab/device. Browser refresh/restart loses client-side locks. If any outcome is uncertain, STOP and obtain manual investigation. Do not reopen, re-upload or resubmit to retry. This is not restart-safe idempotency.',
          ),
          if (!_current)
            const Text('Account or assignment changed. Close this QA form.'),
          if (_entry.blocked)
            const Text(
              'QA session blocked. Manual investigation is required; no more writes are allowed.',
            ),
          if (_entry.finished)
            const Text(
              'QA session already completed. No further writes are allowed.',
            ),
          if (_current) Semantics(liveRegion: true, child: Text(_message)),
          if (_current && _entry.uploadStarted)
            Text(
              'Confirmed real files: ${deps.coordinator.state.confirmedPaths.length} of ${widget.draft.files.length}.',
            ),
          if (_busy)
            const LinearProgressIndicator(
              semanticsLabel: 'Real QA action in progress',
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'I am supervising this one QA attempt and understand the restart warning.',
            ),
            value: _armed,
            onChanged: blocked || _busy || _confirming || _entry.uploadStarted
                ? null
                : (v) => setState(() => _armed = v ?? false),
          ),
          FilledButton(
            onPressed:
                !blocked &&
                    !_entry.finished &&
                    !_entry.uploadStarted &&
                    _armed &&
                    widget.draft.ready &&
                    !_busy &&
                    !_confirming
                ? _upload
                : null,
            child: const Text('Upload real QA evidence'),
          ),
          FilledButton(
            onPressed:
                !blocked &&
                    !_entry.finished &&
                    !_entry.submitStarted &&
                    deps.coordinator.state.receipt != null &&
                    _armed &&
                    !_busy &&
                    !_confirming
                ? _submit
                : null,
            child: const Text('Submit QA evidence once'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
