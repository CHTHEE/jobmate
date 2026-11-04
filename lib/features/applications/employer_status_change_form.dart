import 'package:flutter/material.dart';

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
      await widget.repository.updateStatus(
        widget.applicant,
        widget.next,
        note.text,
      );
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
    return !repo.loading &&
        current?.status == widget.applicant.status &&
        (current?.employerNext.contains(widget.next) ?? false);
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
    child: ModalBody(
      title: invalid
          ? 'Session changed'
          : success
          ? 'Application status updated'
          : '${employerTransitionLabel(widget.next)} applicant?',
      actions: [
        TextButton(
          onPressed: busy ? null : close,
          child: Text(success || invalid ? 'Done' : 'Cancel'),
        ),
        if (!success && !invalid)
          FilledButton(
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
          Text(widget.applicant.name),
          const SizedBox(height: 12),
          if (success)
            Text(
              widget.repository.error == null
                  ? 'The server confirmed the change. The applicant list has been refreshed.'
                  : 'The server confirmed the change, but the list could not refresh. Close this form and retry loading applicants.',
            )
          else ...[
            Text(
              'Change ${widget.applicant.status.label} to ${widget.next.label}?',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: note,
              enabled: !busy,
              maxLength: 2000,
              minLines: 3,
              maxLines: 7,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                alignLabelWithHint: true,
              ),
            ),
            if (busy) const LinearProgressIndicator(),
          ],
        ],
        if (error != null)
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
