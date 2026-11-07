import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../shared/widgets/mobile_back_action.dart';
import 'work_attendance_models.dart';
import 'work_evidence_draft_controller.dart';
import 'work_evidence_draft_page.dart';
import 'work_evidence_repository.dart';
import 'work_evidence_upload_repository.dart';
import 'work_evidence_workflow.dart';
import 'work_evidence_deadline.dart';
import 'work_status_presentation.dart';

class WorkEvidenceWorkflowPanel extends StatefulWidget {
  const WorkEvidenceWorkflowPanel({
    super.key,
    required this.viewer,
    required this.source,
    this.pickFiles,
    this.createUploads,
    this.ledger,
  });
  final WorkEvidenceRepository viewer;
  final WorkEvidenceWorkflowSource source;
  final Future<List<XFile>> Function()? pickFiles;
  final WorkEvidenceUploadRepository Function(WorkEvidenceDraftController)?
  createUploads;
  final WorkEvidenceWorkflowLedger? ledger;
  @override
  State<WorkEvidenceWorkflowPanel> createState() =>
      _WorkEvidenceWorkflowPanelState();
}

class _WorkEvidenceWorkflowPanelState extends State<WorkEvidenceWorkflowPanel> {
  late final controller = WorkEvidenceWorkflowController(
    widget.source,
    assignmentId: widget.viewer.assignmentId,
    employer: widget.viewer.employer,
    ledger: widget.ledger,
  );
  WorkEvidenceDraftController? _draft;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    controller.load();
  }

  @override
  void dispose() {
    controller.dispose();
    final draft = _draft;
    if (draft != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => draft.changeAssignment(''),
      );
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_opening ||
        controller.snapshot?.canSubmit != true ||
        controller.newWriteBlocked) {
      return;
    }
    setState(() => _opening = true);
    final draft = WorkEvidenceDraftController(
      session: _Session(widget.source),
      assignmentId: widget.viewer.assignmentId,
      pickFiles: widget.pickFiles,
    );
    _draft = draft;
    final completed = ValueNotifier(false);
    final initialRound = controller.snapshot!.round;
    final additional = initialRound > 0;
    final uploads =
        widget.createUploads?.call(draft) ??
        WorkEvidenceUploadRepository(
          SupabaseWorkEvidenceUploadSource(
            (widget.source as SupabaseWorkEvidenceWorkflowSource).client,
          ),
          assignmentId: widget.viewer.assignmentId,
        );
    try {
      final route = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          child: SizedBox(
            width: 640,
            height: MediaQuery.sizeOf(context).height * .9,
            child: ListenableBuilder(
              listenable: Listenable.merge([controller, draft, completed]),
              builder: (context, _) => WorkEvidenceDraftPage(
                controller: draft,
                workflowLocked:
                    controller.newWriteBlocked ||
                    controller.snapshot?.canSubmit != true ||
                    controller.snapshot?.round != initialRound,
                workflowBusy: controller.busy,
                workflowCompleted: completed.value,
                workflowControls: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!controller.current)
                      const Text('Your account changed. Close this form.'),
                    if (controller.message != null &&
                        ![
                          'Evidence submitted.',
                          'Review recorded.',
                        ].contains(controller.message))
                      Text(controller.message!),
                    if (controller.busy) const LinearProgressIndicator(),
                    FilledButton(
                      onPressed:
                          !controller.current ||
                              controller.newWriteBlocked ||
                              controller.snapshot?.canSubmit != true ||
                              controller.snapshot?.round != initialRound ||
                              !draft.ready
                          ? null
                          : () async {
                              final confirmed = await _confirm(
                                context,
                                'Submit evidence?',
                                'Upload ${draft.files.length} private file(s) and submit this work description for employer review?',
                                controller: controller,
                              );
                              if (confirmed && controller.current) {
                                final recorded = await controller.submit(
                                  draft,
                                  uploads,
                                );
                                if (recorded && mounted && controller.current) {
                                  completed.value = true;
                                }
                              }
                            },
                      child: const Text('Submit Evidence'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await Navigator.of(context).push(route);
      // Keep draft notifiers alive until the reverse transition unmounts it.
      await route.completed;
    } finally {
      final recorded = completed.value;
      completed.dispose();
      uploads.dispose();
      draft.dispose();
      _draft = null;
      if (mounted) {
        setState(() => _opening = false);
        await widget.viewer.load();
        if (mounted && recorded && controller.current) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                additional
                    ? 'Additional evidence submitted successfully'
                    : 'Evidence submitted successfully',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _review() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final decision = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ReviewDialog(controller: controller),
      );
      if (mounted && decision != null && controller.current) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decision == 'verified'
                  ? 'Work verified successfully!'
                  : 'More evidence requested successfully',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        await widget.viewer.load();
      }
    }
  }

  Future<void> _resume() async {
    final original = widget.viewer.employer
        ? controller.snapshot?.review
        : controller.snapshot?.pendingAttempt;
    if (original == null) return;
    if (await _confirm(
      context,
      'Complete reserved action?',
      widget.viewer.employer
          ? '${_action(original['decision'] as String)} for round ${original['submission_round']}.${original['reason'] == null ? '' : '\n${original['reason']}'}'
          : 'Submit reserved round ${original['target_round']} with ${(original['storage_paths'] as List).length} previously uploaded file(s).\n${original['description']}',
      controller: controller,
    )) {
      final latest = widget.viewer.employer
          ? controller.snapshot?.review
          : controller.snapshot?.pendingAttempt;
      if (latest?['request_id'] != original['request_id']) return;
      await controller.resume();
      if (mounted) await widget.viewer.load();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.snapshot;
      final request = widget.viewer.employer
          ? state?.review
          : state?.pendingAttempt;
      final resume =
          request?['state'] == 'prepared' &&
          request?[widget.viewer.employer ? 'actor_id' : 'worker_id'] ==
              widget.source.userId;
      return Card.outlined(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state != null)
                WorkStatusBanner(
                  stage: WorkStage.fromStatuses(
                    state.assignmentStatus,
                    state.verificationStatus,
                    checkedOut: state.attendanceComplete,
                  ),
                  employer: widget.viewer.employer,
                )
              else
                Text(
                  'Evidence and verification',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              if (state != null && widget.viewer.assignment != null)
                EvidenceDeadlineSummary(
                  assignment: widget.viewer.assignment!,
                  assignmentStatus: state.assignmentStatus,
                  verificationStatus: state.verificationStatus,
                ),
              if (controller.loading) const LinearProgressIndicator(),
              if (controller.message != null &&
                  ![
                    'Evidence submitted.',
                    'Review recorded.',
                  ].contains(controller.message))
                Text(controller.message!),
              if (state != null) ...[
                if (controller.newWriteBlocked &&
                    !controller.busy &&
                    request == null &&
                    (widget.viewer.employer
                        ? state.canReview
                        : state.canSubmit))
                  const Text(
                    'An earlier action is unresolved. Refresh to check its status. Do not submit a replacement; contact support if it remains unresolved.',
                  ),
                const SizedBox(height: 12),
                Text('Latest submission round: ${state.round}'),
                if (state.verificationStatus.name == 'verified') ...[
                  Text(
                    'Employer approval recorded - Approved submission round: ${state.round}',
                  ),
                  if (state.history
                          .where((e) => e.action == 'verified')
                          .lastOrNull
                      case final event?)
                    Text('Verified at: ${_time(event.at)}'),
                ],
                if (state.verificationStatus.name == 'moreEvidenceRequired')
                  if (state.history
                          .where((e) => e.action == 'more_evidence_requested')
                          .lastOrNull
                      case final feedback?)
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Employer feedback',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            feedback.note ??
                                'Review the requested changes below.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                if (state.verificationStatus.name == 'moreEvidenceRequired')
                  const Text(
                    'More evidence requested. Read the employer’s reason below and submit updated evidence.',
                  ),
                if (!widget.viewer.employer &&
                    state.canSubmit &&
                    state.pendingAttempt == null)
                  FilledButton(
                    onPressed: _opening || controller.newWriteBlocked
                        ? null
                        : _submit,
                    child: Text(
                      state.round == 0
                          ? 'Submit work evidence'
                          : 'Resubmit work evidence',
                    ),
                  ),
                if (widget.viewer.employer &&
                    state.canReview &&
                    state.review == null)
                  FilledButton(
                    onPressed: _opening || controller.newWriteBlocked
                        ? null
                        : _review,
                    child: const Text('Review submitted evidence'),
                  ),
                if (request?['state'] == 'blocked')
                  const Text(
                    'This reserved submission was blocked. Contact support; a replacement attempt is not allowed.',
                  ),
                if (request?['state'] == 'prepared')
                  Text(
                    resume
                        ? 'A confirmed action is reserved. Check status or complete that same action.'
                        : 'Another employer has reserved this review.',
                  ),
                if (resume)
                  Text(
                    widget.viewer.employer
                        ? '${_action(request!['decision'] as String)}${request['reason'] == null ? '' : ': ${request['reason']}'}'
                        : 'Reserved description: ${request!['description']}',
                  ),
                if (resume)
                  OutlinedButton(
                    onPressed: controller.busy || _opening ? null : _resume,
                    child: const Text('Complete reserved action'),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Verification history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (state.history.isEmpty)
                  const Text('No verification events recorded yet.'),
                for (final event in state.history.reversed.take(3))
                  _HistoryTile(
                    event: event,
                    showNote:
                        !(state.verificationStatus ==
                                WorkVerificationStatus.moreEvidenceRequired &&
                            event.action == 'more_evidence_requested' &&
                            event.round == state.round),
                  ),
                if (state.history.length > 3)
                  ExpansionTile(
                    title: Text(
                      'Earlier history (${state.history.length - 3})',
                    ),
                    children: [
                      for (final event in state.history.reversed.skip(3))
                        _HistoryTile(
                          event: event,
                          showNote:
                              !(state.verificationStatus ==
                                      WorkVerificationStatus
                                          .moreEvidenceRequired &&
                                  event.action == 'more_evidence_requested' &&
                                  event.round == state.round),
                        ),
                    ],
                  ),
              ],
              TextButton(
                onPressed: controller.loading || controller.busy
                    ? null
                    : controller.load,
                child: const Text('Refresh verification status'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Session implements EvidenceDraftSession {
  _Session(this.source);
  final WorkEvidenceWorkflowSource source;
  @override
  String? get userId => source.userId;
  @override
  Stream<String?> get accountChanges => source.accountChanges;
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message, {
  required WorkEvidenceWorkflowController controller,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => StreamBuilder<String?>(
        stream: controller.source.accountChanges,
        initialData: controller.source.userId,
        builder: (context, _) => AlertDialog(
          title: Text(title),
          content: Text(
            controller.current
                ? message
                : 'Your account changed. Cancel and reopen this action.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: controller.current
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    ) ==
    true;

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.controller});
  final WorkEvidenceWorkflowController controller;
  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final reason = TextEditingController();
  late final round = widget.controller.snapshot?.round;
  bool confirming = false, started = false, leaving = false;
  String? error;
  late final StreamSubscription<String?> _account;
  @override
  void initState() {
    super.initState();
    _account = widget.controller.source.accountChanges.listen((_) {
      if (mounted && !widget.controller.current) {
        reason.clear();
        setState(() => error = null);
      }
    });
  }

  @override
  void dispose() {
    _account.cancel();
    reason.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (confirming || widget.controller.busy) return;
    if (!await confirmDiscardChanges(context, reason.text.isNotEmpty)) return;
    if (!mounted) return;
    setState(() => leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _decide(bool verify) async {
    if (confirming || started || widget.controller.busy) return;
    if (!verify &&
        (reason.text.trim().isEmpty ||
            reason.text.trim().runes.length > 1000)) {
      setState(() => error = 'Enter a reason of 1–1,000 characters.');
      return;
    }
    setState(() => confirming = true);
    final yes = await _confirm(
      context,
      verify ? 'Verify work?' : 'Request more evidence?',
      verify
          ? 'Confirm you reviewed the files for submission round $round and approve this work.'
          : reason.text.trim(),
      controller: widget.controller,
    );
    if (!mounted) return;
    setState(() => confirming = false);
    if (!yes ||
        !widget.controller.current ||
        widget.controller.snapshot?.round != round) {
      return;
    }
    setState(() => started = true);
    final recorded = await widget.controller.review(
      verify ? 'verified' : 'more_evidence_requested',
      verify ? null : reason.text,
    );
    if (!mounted || !recorded || !widget.controller.current) return;
    reason.clear();
    setState(() => leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.pop(context, verify ? 'verified' : 'more_evidence_requested');
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final enabled =
          c.current &&
          !c.busy &&
          !confirming &&
          !started &&
          c.snapshot?.round == round &&
          c.snapshot?.canReview == true;
      return PopScope(
        canPop: leaving,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: AlertDialog(
          title: Text('Review submission round $round'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Open and review the latest submitted PDF/files before making a decision.',
                  ),
                  TextField(
                    controller: reason,
                    enabled: enabled,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: 'Reason for requesting more evidence',
                      errorText: error,
                    ),
                  ),
                  if (c.message != null) Text(c.message!),
                  if (c.busy) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: c.busy || confirming ? null : _close,
              child: const Text('Close'),
            ),
            OutlinedButton(
              onPressed: enabled ? () => _decide(false) : null,
              child: const Text('Request more evidence'),
            ),
            FilledButton(
              onPressed: enabled ? () => _decide(true) : null,
              child: const Text('Verify work'),
            ),
          ],
        ),
      );
    },
  );
}

String _action(String value) => switch (value) {
  'evidence_submitted' => 'Evidence submitted',
  'evidence_resubmitted' => 'Evidence resubmitted',
  'more_evidence_requested' => 'More evidence requested',
  'verified' => 'Work verified',
  _ => 'Work disputed',
};
String _time(DateTime value) {
  final t = value.toUtc().add(const Duration(hours: 8));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)} MYT';
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.event, this.showNote = true});
  final bool showNote;
  final WorkEvidenceHistoryEvent event;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          event.action == 'verified'
              ? Icons.verified_outlined
              : event.action == 'more_evidence_requested'
              ? Icons.feedback_outlined
              : Icons.upload_file_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _action(event.action),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                '${event.round == null ? 'Earlier event' : 'Round ${event.round}'} - ${_time(event.at)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (showNote && event.note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(event.note!),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
