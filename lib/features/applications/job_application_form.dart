import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/navigation/app_routes.dart';
import '../profile/resume_repository.dart';
import 'job_application_repository.dart';
import 'module2_repository.dart';
import 'module2_widgets.dart';

class JobApplicationForm extends StatefulWidget {
  const JobApplicationForm({
    super.key,
    required this.job,
    required this.repository,
    required this.gateway,
  });
  final BrowseJob job;
  final Module2Repository repository;
  final JobApplicationGateway gateway;
  @override
  State<JobApplicationForm> createState() => _JobApplicationFormState();
}

class _JobApplicationFormState extends State<JobApplicationForm> {
  late final draftKey =
      'application:${widget.gateway.actorId}:${widget.job.id}';
  late final note = TextEditingController(
    text: widget.repository.noteDraft(draftKey),
  );
  late final StreamSubscription<String?> subscription;
  List<ResumeFile> resumes = [];
  String? selectedResume, applicationId, error, resumeError;
  bool loading = true, busy = false, leaving = false, invalidSession = false;
  bool get dirty => note.text.trim().isNotEmpty || selectedResume != null;

  @override
  void initState() {
    super.initState();
    subscription = widget.gateway.accountChanges.listen((_) => checkSession());
    loadResumes();
  }

  bool checkSession() {
    if (!mounted || invalidSession) return false;
    try {
      widget.gateway.checkSession();
      return true;
    } catch (_) {
      widget.repository.clearNoteDraft(draftKey);
      note.clear();
      setState(() {
        invalidSession = true;
        selectedResume = null;
        resumes = [];
        applicationId = null;
        busy = false;
        loading = false;
        error = 'Your account changed. Close this form and reopen it after signing in.';
      });
      return false;
    }
  }

  Future<void> loadResumes() async {
    if (!checkSession()) return;
    setState(() {
      loading = true;
      resumeError = null;
    });
    try {
      final files = await widget.gateway.listResumes();
      if (!checkSession()) return;
      setState(() => resumes = files);
    } catch (failure) {
      if (checkSession()) {
        setState(() => resumeError = jobApplicationError(failure));
      }
    } finally {
      if (mounted && !invalidSession) setState(() => loading = false);
    }
  }

  Future<void> submit() async {
    if (busy ||
        loading ||
        applicationId != null ||
        resumeError != null ||
        !checkSession()) {
      return;
    }
    if (note.text.length > 1000) {
      setState(() => error = 'Keep the cover note within 1,000 characters.');
      return;
    }
    if (selectedResume != null && !resumes.any((r) => r.id == selectedResume)) {
      setState(() => error = 'Choose an available resume.');
      return;
    }
    final unavailable = widget.job.unavailable();
    if (unavailable != null) {
      setState(() => error = unavailable);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final id = await widget.gateway.submit(
        widget.job.id,
        resumeId: selectedResume,
        coverNote: note.text,
      );
      if (!checkSession()) return;
      widget.repository.clearNoteDraft(draftKey);
      setState(() => applicationId = id);
    } catch (failure) {
      if (checkSession()) setState(() => error = jobApplicationError(failure));
    } finally {
      if (mounted && !invalidSession) setState(() => busy = false);
    }
  }

  void finish({String? route, bool keepDraft = false}) {
    if (!keepDraft) widget.repository.clearNoteDraft(draftKey);
    setState(() => leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(route);
    });
  }

  Future<void> close() async {
    if (busy) return;
    if (applicationId == null && dirty && !invalidSession) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard application draft?'),
          content: const Text(
            'Your cover note and resume selection have not been submitted.',
          ),
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
      if (discard != true || !mounted || busy) return;
    }
    finish();
  }

  @override
  void dispose() {
    subscription.cancel();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop:
        leaving ||
        (!busy && (applicationId != null || !dirty || invalidSession)),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) close();
    },
    child: ModalBody(
      title: invalidSession
          ? 'Session changed'
          : applicationId != null
          ? 'Application submitted'
          : 'Apply to ${widget.job.title}',
      actions: [
        TextButton(
          onPressed: busy ? null : close,
          child: Text(
            applicationId != null || invalidSession ? 'Done' : 'Cancel',
          ),
        ),
        if (applicationId != null)
          FilledButton(
            onPressed: () => finish(route: AppRoutes.applications),
            child: const Text('My Applications'),
          )
        else if (!invalidSession)
          FilledButton(
            onPressed: busy || loading || resumeError != null ? null : submit,
            child: Text(busy ? 'Submitting…' : 'Submit application'),
          ),
      ],
      children: [
        if (!invalidSession) Text(widget.job.company),
        const SizedBox(height: 16),
        if (applicationId != null) ...[
          const Text('Your application has been saved.'),
          SelectableText('Application ID: $applicationId'),
        ] else if (!invalidSession) ...[
          if (loading)
            const LinearProgressIndicator()
          else if (resumeError != null) ...[
            Text('Unable to load resumes: $resumeError'),
            TextButton(
              onPressed: loadResumes,
              child: const Text('Retry resumes'),
            ),
          ] else if (resumes.isEmpty) ...[
            const Text(
              'No uploaded resumes yet. You may apply without one or upload a PDF in My Resume.',
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => finish(
                      route: AppRoutes.documentSubmission,
                      keepDraft: true,
                    ),
              child: const Text('Visit My Resume'),
            ),
          ] else
            DropdownButtonFormField<String>(
              initialValue: selectedResume ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Resume (optional)'),
              items: [
                const DropdownMenuItem(value: '', child: Text('No resume')),
                for (final resume in resumes)
                  DropdownMenuItem(
                    value: resume.id,
                    child: Text(resume.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (value) => setState(
                      () => selectedResume = value == '' ? null : value,
                    ),
            ),
          const SizedBox(height: 20),
          TextField(
            controller: note,
            enabled: !busy,
            maxLength: 1000,
            minLines: 4,
            maxLines: 8,
            onChanged: (value) {
              if (!checkSession()) return;
              widget.repository.keepNoteDraft(draftKey, value);
              setState(() {});
            },
            decoration: const InputDecoration(
              labelText: 'Cover note (optional)',
              alignLabelWithHint: true,
            ),
          ),
          if (busy) const LinearProgressIndicator(),
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
