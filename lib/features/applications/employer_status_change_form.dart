import 'package:flutter/material.dart';

import '../../shared/theme/jobmate_theme.dart';

import 'compensation_offer.dart' show CompensationOffer;
import 'employer_applicants_repository.dart';
import 'module2_widgets.dart';
import 'my_applications_repository.dart';

String employerTransitionLabel(MyApplicationStatus status) => switch (status) {
  MyApplicationStatus.shortlisted => 'Shortlist',
  MyApplicationStatus.interview => 'Move to Interview',
  MyApplicationStatus.offered => 'Make Offer',
  MyApplicationStatus.rejected => 'Reject',
  _ => status.label,
};

class EmployerStatusChangeForm extends StatefulWidget {
  const EmployerStatusChangeForm({
    super.key,
    required this.repository,
    required this.applicant,
    required this.next,
  });
  final EmployerApplicantsRepository repository;
  final JobApplicant applicant;
  final MyApplicationStatus next;
  @override
  State<EmployerStatusChangeForm> createState() =>
      _EmployerStatusChangeFormState();
}

class _EmployerStatusChangeFormState extends State<EmployerStatusChangeForm> {
  final note = TextEditingController();
  CompensationOffer? issuedOffer;
  late final String? actor;
  late final Object? company;
  bool busy = false, success = false, leaving = false, invalid = false;
  String? error;
  @override
  void initState() {
    super.initState();
    // Capture before a possible asynchronous account change.
    actor = widget.repository.source.userId;
    company = widget.repository.context!.access.company!['company_id'];
    widget.repository.addListener(changed);
  }

  void changed() {
    if (!mounted) return;
    final repo = widget.repository;
    if (!repo.active ||
        repo.source.userId != actor ||
        (repo.context != null &&
            repo.context!.access.company?['company_id'] != company)) {
      note.clear();
      setState(() {
        invalid = true;
        success = false;
        busy = false;
        error = 'Your account or job context changed. Close this form and reopen the job.';
      });
    } else {
      setState(() {});
    }
  }

  Future<void> confirm() async {
    if (busy || success || invalid) return;
    if (note.text.trim().runes.length > 2000) {
      setState(() => error = 'Keep the note within 2,000 characters.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final job = widget.repository.job;
      if (widget.next == MyApplicationStatus.offered) {
        if (job == null ||
            !canOfferForJob(
              job,
              versionedOffersEnabled:
                  widget.repository.compensationOffersEnabled,
              reissue: widget.applicant.status == MyApplicationStatus.offered,
            )) {
          throw StateError(
            'Offer issuance is unavailable. Refresh the Job terms.',
          );
        }
        if (isPaymentSupportedJob(job)) {
          issuedOffer = await widget.repository.issueCompensationOffer(
            widget.applicant,
            note.text,
            widget.repository.compensationOfferRequestId(widget.applicant.id),
          );
        } else {
          await widget.repository.updateStatus(
            widget.applicant,
            widget.next,
            note.text,
          );
        }
      } else {
        await widget.repository.updateStatus(
          widget.applicant,
          widget.next,
          note.text,
        );
      }
      if (!mounted || invalid) return;
      setState(() => success = true);
    } catch (failure) {
      if (mounted && !invalid) {
        setState(() => error = employerStatusError(failure));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool get transitionAvailable {
    final repo = widget.repository;
    final current = repo.applicants
        .where((a) => a.id == widget.applicant.id)
        .firstOrNull;
    final selectedJob = repo.job;
    return !repo.loading &&
        current?.status == widget.applicant.status &&
        (current?.employerNext.contains(widget.next) ?? false) &&
        (widget.next != MyApplicationStatus.offered ||
            selectedJob != null &&
                canOfferForJob(
                  selectedJob,
                  versionedOffersEnabled: repo.compensationOffersEnabled,
                  reissue: current?.status == MyApplicationStatus.offered,
                ));
  }

  Future<void> close() async {
    if (busy) return;
    if (!success && !invalid && note.text.trim().isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard status note?'),
          content: const Text('This note has not been submitted.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() => leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    widget.repository.removeListener(changed);
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop:
        leaving || (!busy && (success || invalid || note.text.trim().isEmpty)),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) close();
    },
    child: _RecruitmentDialogBody(
      onClose: busy ? null : close,
      rejected: widget.next == MyApplicationStatus.rejected,
      title: invalid
          ? 'Session changed'
          : success
          ? switch (widget.next) {
              MyApplicationStatus.shortlisted => 'Application shortlisted',
              MyApplicationStatus.interview => 'Interview stage updated',
              MyApplicationStatus.offered => 'Offer sent',
              MyApplicationStatus.rejected => 'Application rejected',
              _ => 'Application status updated',
            }
          : '${employerTransitionLabel(widget.next)} applicant?',
      actions: [
        TextButton(
          onPressed: busy ? null : close,
          child: Text(success || invalid ? 'Done' : 'Cancel'),
        ),
        if (!success && !invalid)
          FilledButton(
            style: widget.next == MyApplicationStatus.rejected
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            onPressed: busy || !transitionAvailable ? null : confirm,
            child: Text(
              busy
                  ? 'Updating…'
                  : 'Confirm ${employerTransitionLabel(widget.next)}',
            ),
          ),
      ],
      children: [
        if (!invalid) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: JobMateTheme.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.applicant.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (widget.repository.job?['title'] case final String title)
                  Text(
                    title,
                    style: const TextStyle(
                      color: JobMateTheme.body,
                      fontSize: 13,
                    ),
                  ),
                if (!success)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      MyApplicationStatusBadge(widget.applicant.status),
                      const Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: JobMateTheme.body,
                      ),
                      MyApplicationStatusBadge(widget.next),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (success)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.applicant.name.trim().isEmpty ? 'This applicant' : widget.applicant.name} ${switch (widget.next) {
                    MyApplicationStatus.shortlisted => 'has been shortlisted successfully. You can continue reviewing this application.',
                    MyApplicationStatus.interview => 'has been moved to the interview stage successfully.',
                    MyApplicationStatus.offered => 'has been sent a job offer successfully.',
                    MyApplicationStatus.rejected => 'has been marked as rejected.',
                    _ => 'has an updated application status.',
                  }}${widget.repository.error == null ? '' : ' The applicant list could not refresh. Close this form and refresh the list.'}',
                ),
                if (issuedOffer case final offer?) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Compensation Offer · Version ${offer.version}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(offer.salaryRange),
                  const Text(
                    'These terms are saved as an immutable Offer version.',
                  ),
                ],
              ],
            )
          else ...[
            Text(
              'Change ${widget.applicant.status.label} to ${widget.next.label}?',
            ),
            const SizedBox(height: 8),
            Text(switch (widget.next) {
              MyApplicationStatus.shortlisted =>
                'Add this applicant to the shortlist for further review.',
              MyApplicationStatus.interview => 'Move this application to the interview stage. This action does not schedule an interview.',
              MyApplicationStatus.offered => 'Send an offer for this job. Hiring requires the worker to accept it.',
              MyApplicationStatus.rejected => 'Mark this application as Rejected. Review the applicant and job before confirming.',
              _ => 'Review this status change before confirming.',
            }, style: const TextStyle(color: JobMateTheme.body, height: 1.4)),
            if (widget.next == MyApplicationStatus.offered) ...[
              const SizedBox(height: 12),
              const Text(
                'The worker must accept the offer before this application becomes Hired.',
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: note,
              enabled: !busy,
              maxLength: 2000,
              minLines: 3,
              maxLines: 7,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                alignLabelWithHint: true,
                helperText:
                    'Optional recruitment note. Maximum 2,000 characters.',
                helperMaxLines: 3,
                errorMaxLines: 4,
                errorText: error == 'Keep the note within 2,000 characters.'
                    ? error
                    : null,
              ),
            ),
            if (busy) const LinearProgressIndicator(),
          ],
        ],
        if (error != null && error != 'Keep the note within 2,000 characters.')
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}

/// Keeps the existing modal and bottom-sheet routes and PopScope behavior.
class _RecruitmentDialogBody extends StatelessWidget {
  const _RecruitmentDialogBody({
    required this.title,
    required this.children,
    required this.actions,
    required this.onClose,
    required this.rejected,
  });
  final String title;
  final List<Widget> children, actions;
  final VoidCallback? onClose;
  final bool rejected;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  rejected
                      ? Icons.person_off_outlined
                      : Icons.assignment_ind_outlined,
                  size: 22,
                  color: rejected
                      ? Theme.of(context).colorScheme.error
                      : JobMateTheme.darkTeal,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Close recruitment dialog',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            const Divider(height: 20),
            ...children,
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 10,
              children: actions,
            ),
          ],
        ),
      ),
    ),
  );
}
