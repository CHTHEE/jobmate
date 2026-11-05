import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/mobile_back_action.dart';
import 'work_attendance_models.dart';
import 'work_evidence_qa_page.dart' show supervisedWorkEvidenceQaAssignment;
import 'work_evidence_repository.dart';

abstract class WorkEvidenceQaReviewSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<void> verify(String assignmentId);
  Future<void> requestMore(String assignmentId, String reason);
}

class SupabaseWorkEvidenceQaReviewSource implements WorkEvidenceQaReviewSource {
  SupabaseWorkEvidenceQaReviewSource(this.client);
  final SupabaseClient client;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((e) => e.session?.user.id);
  Future<void> _call(
    String function,
    String assignmentId, [
    String? reason,
  ]) async {
    final actor = userId;
    if (actor == null) throw const AuthException('Authentication required');
    if (workUuid(assignmentId) != supervisedWorkEvidenceQaAssignment) {
      throw const FormatException('QA scope required');
    }
    final result = await client
        .rpc(
          function,
          params: {
            'p_assignment_id': supervisedWorkEvidenceQaAssignment,
            'p_reason': ?reason,
          },
        )
        .retry(enabled: false, requestTimeout: const Duration(seconds: 30));
    if (userId != actor) throw const AuthException('Account changed');
    if (result != null && result != '') {
      throw const FormatException('Unconfirmed review response');
    }
  }

  @override
  Future<void> verify(String assignmentId) =>
      _call('verify_work_assignment', assignmentId);
  @override
  Future<void> requestMore(String assignmentId, String reason) {
    final normalized = reason.trim();
    if (normalized.runes.isEmpty || normalized.runes.length > 1000) {
      throw const FormatException('A reason of 1–1000 characters is required');
    }
    return _call('request_more_work_evidence', assignmentId, normalized);
  }
}

/// Shared running-app protection; not durable or coordinated across devices.
/// Tests inject a fresh session. Never clear it to retry an uncertain request.
class WorkEvidenceQaReviewSession {
  final _used = <(String, String, String)>{};
  static final runningApp = WorkEvidenceQaReviewSession();
}

bool canReviewWorkEvidenceQa(WorkEvidenceRepository viewer) =>
    viewer.employer &&
    viewer.companyId != null &&
    !viewer.loading &&
    viewer.error == null &&
    viewer.attendance.source.userId != null &&
    viewer.assignmentId == supervisedWorkEvidenceQaAssignment &&
    viewer.assignment is CompanyWorkAssignment &&
    viewer.assignment!.assignmentId == supervisedWorkEvidenceQaAssignment &&
    viewer.assignment!.assignmentStatus ==
        WorkAssignmentStatus.awaitingVerification &&
    viewer.assignment!.verificationStatus ==
        WorkVerificationStatus.pendingReview &&
    viewer.evidence.isNotEmpty;

/// Dedicated modal: parent list rebuilds during fresh reads cannot dispose an
/// in-flight operation. No mock component is converted into a live transport.
class WorkEvidenceQaReviewDialog extends StatefulWidget {
  const WorkEvidenceQaReviewDialog({
    super.key,
    required this.viewer,
    required this.source,
    this.session,
    this.workerName,
  });
  final WorkEvidenceRepository viewer;
  final WorkEvidenceQaReviewSource source;
  final WorkEvidenceQaReviewSession? session;
  final String? workerName;
  @override
  State<WorkEvidenceQaReviewDialog> createState() =>
      _WorkEvidenceQaReviewDialogState();
}

class _WorkEvidenceQaReviewDialogState
    extends State<WorkEvidenceQaReviewDialog> {
  final _reason = TextEditingController();
  late final _actor = widget.viewer.attendance.source.userId;
  late final _company = widget.viewer.companyId;
  late final _session =
      widget.session ?? WorkEvidenceQaReviewSession.runningApp;
  late final _key = (
    _actor ?? '',
    _company ?? '',
    supervisedWorkEvidenceQaAssignment,
  );
  late final StreamSubscription<String?> _subscription;
  bool _busy = false, _invalid = false, _leaving = false, _closing = false;
  String? _message;
  bool get _used => _session._used.contains(_key);
  bool get _current =>
      mounted &&
      !_invalid &&
      _actor != null &&
      _company != null &&
      widget.source.userId == _actor &&
      widget.viewer.attendance.source.userId == _actor &&
      widget.viewer.companyId == _company &&
      widget.viewer.employer &&
      widget.viewer.assignmentId == supervisedWorkEvidenceQaAssignment;
  bool get _verifyEligible {
    if (!canReviewWorkEvidenceQa(widget.viewer)) return false;
    final row = widget.viewer.assignment!;
    final latest = widget.viewer.evidence
        .map((e) => e.submissionRound)
        .reduce((a, b) => a > b ? a : b);
    final count = widget.viewer.evidence
        .where((e) => e.submissionRound == latest)
        .length;
    return row.checkInAt != null &&
        row.checkOutAt != null &&
        !row.checkOutAt!.isBefore(row.checkInAt!) &&
        count >= 1 &&
        count <= 5;
  }

  List<(String, int, String, String, String)> _snapshot() {
    final rows = widget.viewer.evidence.toList()
      ..sort((a, b) => a.evidenceId.compareTo(b.evidenceId));
    return rows
        .map(
          (e) => (
            e.evidenceId,
            e.submissionRound,
            e.description,
            e.storagePath,
            e.submittedBy,
          ),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    widget.viewer.addListener(_observe);
    _subscription = widget.source.accountChanges.listen((actor) {
      if (actor != _actor) _invalid = true;
      _observe();
    });
  }

  void _observe() {
    if (!mounted) return;
    if (!_current) _invalid = true;
    setState(() {});
  }

  Future<void> _close() async {
    if (_busy || _closing) return;
    _closing = true;
    final leave = await confirmDiscardChanges(
      context,
      !_used && _reason.text.isNotEmpty,
    );
    _closing = false;
    if (!mounted || !leave) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _act({required bool verify}) async {
    final reason = _reason.text.trim();
    if (!_current ||
        _busy ||
        _used ||
        !canReviewWorkEvidenceQa(widget.viewer) ||
        (verify && !_verifyEligible) ||
        (!verify && (reason.isEmpty || reason.runes.length > 1000))) {
      return;
    }
    final before = widget.viewer.assignment as CompanyWorkAssignment;
    final evidence = _snapshot();
    setState(() => _busy = true);
    var confirmed = false;
    var dispatched = false;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(
            verify
                ? 'Confirm real verification?'
                : 'Confirm real evidence request?',
          ),
          content: SingleChildScrollView(
            child: Text(
              '${before.jobTitle}\n${widget.workerName ?? 'Assigned worker'}\n\n${verify ? 'Confirm that you have reviewed the evidence and want to mark this work as verified.' : 'Ask the worker to provide more evidence:\n$reason'}\n\nQA test only. Use one tab/device. If the result is unclear, stop and ask for help. Do not try again.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm review'),
            ),
          ],
        ),
      );
      if (accepted != true || !_current) return;
      // Reserve synchronously, before fresh reads, across dialog lifetimes.
      if (!_session._used.add(_key)) return;
      setState(
        () => _message = 'Checking current company authorization and evidence…',
      );
      await widget.viewer.load().timeout(const Duration(seconds: 20));
      final after = widget.viewer.assignment;
      if (!_current ||
          !canReviewWorkEvidenceQa(widget.viewer) ||
          (verify && !_verifyEligible) ||
          after is! CompanyWorkAssignment ||
          after.applicationId != before.applicationId ||
          after.jobId != before.jobId ||
          after.workerId != before.workerId ||
          !listEquals(evidence, _snapshot())) {
        if (mounted) {
          setState(
            () => _message = 'Your access or the work details changed. No review was sent. Further actions are blocked; ask for help before continuing.',
          );
        }
        return;
      }
      setState(() => _message = 'Sending real QA review once…');
      dispatched = true;
      if (verify) {
        await widget.source
            .verify(supervisedWorkEvidenceQaAssignment)
            .timeout(const Duration(seconds: 35));
      } else {
        await widget.source
            .requestMore(supervisedWorkEvidenceQaAssignment, reason)
            .timeout(const Duration(seconds: 35));
      }
      confirmed = true;
      if (!_current) return;
      await widget.viewer.load().timeout(const Duration(seconds: 20));
      if (_current) {
        setState(
          () => _message = widget.viewer.error == null
              ? (verify &&
                        widget.viewer.assignment?.verificationStatus ==
                            WorkVerificationStatus.verified
                    ? 'Work verified successfully!'
                    : !verify &&
                          widget.viewer.assignment?.verificationStatus ==
                              WorkVerificationStatus.moreEvidenceRequired
                    ? 'More evidence requested successfully.'
                    : 'Your review was recorded. Check the latest work status below.')
              : 'Your review was recorded, but the latest work details could not be loaded. Further actions are blocked; ask for help before continuing.',
        );
      }
    } catch (_) {
      if (!_current) return;
      setState(
        () => _message = confirmed
            ? 'Your review was recorded, but the latest work details could not be loaded. Further actions are blocked; ask for help before continuing.'
            : dispatched
            ? 'We could not confirm your review. Further actions are blocked. Do not try again or reload to retry; ask for help to check what happened.'
            : 'We could not check your access. No review was sent. Further actions are blocked; ask for help before continuing.',
      );
      // Only an authoritative READ follows failure. It cannot prove which
      // request produced a status or recover the request-more history/reason.
      if (dispatched && !confirmed) {
        try {
          await widget.viewer.load().timeout(const Duration(seconds: 20));
        } catch (_) {
          /* Remain blocked. */
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    widget.viewer.removeListener(_observe);
    unawaited(_subscription.cancel());
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eligible =
        _current && canReviewWorkEvidenceQa(widget.viewer) && !_busy && !_used;
    final status = !_current
        ? null
        : widget.viewer.assignment?.verificationStatus;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) _close();
      },
      child: AlertDialog(
        title: const Text('Work review (QA only)'),
        content: SizedBox(
          width: 520,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .6,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Verification history isn’t available here yet.'),
                  const SizedBox(height: 12),
                  const Text(
                    'QA test only. Use one browser tab/device. If the result is unclear, stop and ask for help. Do not try again or reload to retry: restarting loses this safety lock.',
                  ),
                  if (!_current)
                    const Text(
                      'Account or company context changed. Close this dialog.',
                    ),
                  if (_current)
                    Text(
                      'Authoritative verification status: ${switch (status) {
                        WorkVerificationStatus.pendingReview => 'pending_review',
                        WorkVerificationStatus.moreEvidenceRequired => 'more_evidence_required',
                        WorkVerificationStatus.notSubmitted => 'not_submitted',
                        WorkVerificationStatus.verified => 'verified',
                        WorkVerificationStatus.disputed => 'disputed',
                        null => 'checking/unavailable',
                      }}',
                    ),
                  if (_used)
                    const Text(
                      'Further QA review actions are blocked for this running session.',
                    ),
                  if (_message != null && _current)
                    Semantics(liveRegion: true, child: Text(_message!)),
                  if (_busy && _used)
                    const LinearProgressIndicator(
                      semanticsLabel: 'QA review in progress',
                    ),
                  const SizedBox(height: 16),
                  if (_current)
                    TextField(
                      controller: _reason,
                      enabled: eligible,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText:
                            'Reason for more evidence (1–1000 characters)',
                        errorText: _reason.text.trim().runes.length > 1000
                            ? 'Use at most 1,000 characters.'
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : _close,
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: eligible && _verifyEligible
                ? () => _act(verify: true)
                : null,
            child: const Text('Verify Work'),
          ),
          OutlinedButton(
            onPressed:
                eligible &&
                    _reason.text.trim().isNotEmpty &&
                    _reason.text.trim().runes.length <= 1000
                ? () => _act(verify: false)
                : null,
            child: const Text('Request More Evidence'),
          ),
        ],
      ),
    );
  }
}
