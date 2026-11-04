import 'package:flutter/material.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import 'module2_repository.dart';
import 'module2_widgets.dart';
import 'my_applications_page.dart';
import 'my_application_details_page.dart';
import 'employer_applicants_page.dart';

class ApplicationsPage extends StatefulWidget {
  const ApplicationsPage({
    super.key,
    this.employer = false,
    this.postingId,
    this.repository,
  });
  final bool employer;
  final String? postingId;
  final Module2Repository? repository;
  @override
  State<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends State<ApplicationsPage> {
  late final repo = widget.repository ?? Module2Repository.session;
  late final employerSource = repo.createEmployerApplicantsSource();
  @override
  Widget build(BuildContext context) => widget.employer
      ? EmployerApplicantsPage(source: employerSource, jobId: widget.postingId)
      : MyApplicationsPage(repository: repo.myApplications);
}

class ApplicationDetailsPage extends StatelessWidget {
  const ApplicationDetailsPage({
    super.key,
    required this.applicationId,
    this.employer = false,
    this.repository,
  });
  final String applicationId;
  final bool employer;
  final Module2Repository? repository;
  @override
  Widget build(BuildContext context) {
    if (!employer) {
      return MyApplicationDetailsPage(
        applicationId: applicationId,
        source: (repository ?? Module2Repository.session).myApplications.source,
      );
    }
    return AppWorkspace(
      title: 'Applicant Details',
      path: AppRoutes.applicants,
      role: 'employer',
      child: WorkspaceContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextButton(
              onPressed: () => moduleBack(context, AppRoutes.applicants),
              child: const Text('Back to Applicants'),
            ),
            const ModuleState(
              title: 'Applicant details are not available yet',
              message: 'Open View Applicants from My Job Postings to review applications.',
            ),
          ],
        ),
      ),
    );
  }
}

class ApplicationActions extends StatelessWidget {
  const ApplicationActions({
    super.key,
    required this.application,
    required this.repository,
    required this.employer,
  });
  final DemoApplication application;
  final Module2Repository repository;
  final bool employer;
  @override
  Widget build(BuildContext context) {
    final a = application;
    final actions = employer
        ? <(String, ApplicationStage, bool)>[
            for (final s in [
              ApplicationStage.shortlisted,
              ApplicationStage.interview,
              ApplicationStage.offered,
              ApplicationStage.hired,
              ApplicationStage.rejected,
            ])
              (
                switch (s) {
                  ApplicationStage.shortlisted => 'Shortlist',
                  ApplicationStage.interview => 'Move to Interview',
                  ApplicationStage.offered => 'Make Offer',
                  ApplicationStage.hired => 'Hire',
                  _ => 'Reject',
                },
                s,
                a.stage.employerNext.contains(s),
              ),
          ]
        : <(String, ApplicationStage, bool)>[
            if (a.stage == ApplicationStage.offered) ...[
              ('Accept demo offer', ApplicationStage.hired, true),
              ('Decline demo offer', ApplicationStage.withdrawn, true),
            ] else
              ('Withdraw', ApplicationStage.withdrawn, a.stage.canWithdraw),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final action in actions)
              Tooltip(
                message: action.$3
                    ? 'Session demo change only'
                    : 'Unavailable from ${a.stage.label}',
                child: OutlinedButton(
                  onPressed: action.$3
                      ? () => moduleModal<void>(
                          context,
                          TransitionForm(
                            application: a,
                            repository: repository,
                            employer: employer,
                            next: action.$2,
                            label: action.$1,
                          ),
                        )
                      : null,
                  child: Text(action.$1),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          employer
              ? 'Actions follow the demo pipeline; completed applications cannot advance.'
              : 'Offer acceptance records Hired in the demo only; no assignment is created.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class TransitionForm extends StatefulWidget {
  const TransitionForm({
    super.key,
    required this.application,
    required this.repository,
    required this.employer,
    required this.next,
    required this.label,
  });
  final DemoApplication application;
  final Module2Repository repository;
  final bool employer;
  final ApplicationStage next;
  final String label;
  @override
  State<TransitionForm> createState() => _TransitionFormState();
}

class _TransitionFormState extends State<TransitionForm> {
  late final draftKey = '${widget.next.name}:${widget.application.id}';
  late final note = TextEditingController(
    text: widget.repository.noteDraft(draftKey),
  );
  String? error;
  bool leaving = false;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> close() async {
    if (note.text.trim().isNotEmpty) {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard internal note?'),
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
      if (result != true || !mounted) return;
    }
    finish();
  }

  void finish() {
    if (leaving) return;
    widget.repository.clearNoteDraft(draftKey);
    setState(() => leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving || note.text.trim().isEmpty,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) close();
    },
    child: ModalBody(
      title: '${widget.label}?',
      actions: [
        TextButton(onPressed: close, child: const Text('Cancel')),
        FilledButton(
          style:
              [
                ApplicationStage.rejected,
                ApplicationStage.withdrawn,
              ].contains(widget.next)
              ? FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                )
              : null,
          onPressed: () {
            if (leaving) return;
            try {
              widget.repository.transition(
                widget.application.id,
                widget.next,
                employer: widget.employer,
                note: note.text,
              );
              finish();
            } on StateError catch (e) {
              setState(() => error = e.message.toString());
            }
          },
          child: const Text('Confirm demo change'),
        ),
      ],
      children: [
        const Text(
          'DEMO ONLY • This changes local sample data. No applicant, employer or server is notified.',
        ),
        const SizedBox(height: 16),
        Text('${widget.application.candidate} → ${widget.next.label}'),
        if (widget.next == ApplicationStage.withdrawn)
          const Text(
            'Withdrawal ends this demo application and cannot be undone in this session.',
          ),
        if (widget.employer && widget.next == ApplicationStage.rejected) ...[
          const SizedBox(height: 16),
          TextField(
            controller: note,
            onChanged: (value) {
              widget.repository.keepNoteDraft(draftKey, value);
              setState(() {});
            },
            maxLength: 1000,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Internal note (optional)',
              helperText: 'Visible only in the employer demo view.',
            ),
          ),
        ],
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}
