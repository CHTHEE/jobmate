import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../jobs/job_display.dart';
import 'module2_repository.dart';
import 'module2_widgets.dart';

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
  final search = TextEditingController();
  String tab = 'All', jobId = '', status = '', sort = 'Newest';
  bool showDemo = false;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final base = repo.searchApplications(
        mineOnly: !widget.employer,
        jobId: jobId,
      );
      final rows = repo.searchApplications(
        mineOnly: !widget.employer,
        query: search.text,
        jobId: jobId,
        stage: ApplicationStage.fromLabel(status),
        tab: tab,
        sort: sort,
      );
      return AppWorkspace(
        title: widget.employer ? 'Employer Applications' : 'My Applications',
        path: widget.employer ? AppRoutes.applicants : AppRoutes.applications,
        role: widget.employer ? 'employer' : 'job_seeker',
        child: WorkspaceContent(
          maxWidth: widget.employer ? 768 : 672,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.postingId != null && !showDemo) ...[
                ModuleState(
                  title: 'Live applications are not connected',
                  message: 'No applicant source is connected for this real posting. No actual applicant count can be shown. The sample pipeline is a separate fictional environment.',
                  action: () => setState(() => showDemo = true),
                  actionLabel: 'Explore separate demo pipeline',
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => moduleBack(context, AppRoutes.jobPostings),
                  child: const Text('Back to My Job Postings'),
                ),
              ] else ...[
                const DemoNotice(),
                Text(
                  widget.employer
                      ? 'Manage the demo pipeline'
                      : 'Track your demo applications',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.employer
                      ? 'Sample candidates only • no actual applicants or hiring decisions.'
                      : 'The demo candidate is fictional and is not your signed-in profile.',
                ),
                const SizedBox(height: 24),
                if (widget.employer)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ModuleSelect(
                      label: 'Demo posting',
                      value: jobId,
                      options: {
                        '': 'All demo postings',
                        for (final j in repo.jobs) j.id: j.title,
                      },
                      onChanged: (v) => setState(() => jobId = v),
                    ),
                  ),
                StatGrid(
                  children: [
                    for (final item in <(String, int)>[
                      ('All', base.length),
                      ('Active', base.where((a) => !a.stage.completed).length),
                      (
                        'Completed',
                        base.where((a) => a.stage.completed).length,
                      ),
                    ])
                      StatTile(
                        label: item.$1,
                        value: '${item.$2}',
                        icon: item.$1 == 'All'
                            ? Icons.description_outlined
                            : item.$1 == 'Active'
                            ? Icons.schedule
                            : Icons.task_alt,
                        note: 'Demo applications',
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (widget.employer)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in ApplicationStage.values)
                        Chip(
                          label: Text(
                            '${s.label}: ${base.where((a) => a.stage == s).length}',
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final v in ['All', 'Active', 'Completed'])
                      ChoiceChip(
                        label: Text(v),
                        selected: tab == v,
                        onSelected: (_) => setState(() => tab = v),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: widget.employer
                        ? 'Search candidate, job or skills'
                        : 'Search job or company',
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 16,
                  children: [
                    ModuleSelect(
                      label: 'Application status',
                      value: status,
                      options: {
                        '': 'All statuses',
                        for (final s in ApplicationStage.values)
                          s.label: s.label,
                      },
                      onChanged: (v) => setState(() => status = v),
                    ),
                    ModuleSelect(
                      label: 'Sort',
                      value: sort,
                      options: {
                        for (final v in [
                          'Newest',
                          'Oldest',
                          if (widget.employer) 'Name',
                        ])
                          v: v,
                      },
                      onChanged: (v) => setState(() => sort = v),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        search.clear();
                        status = '';
                        tab = 'All';
                        jobId = '';
                        sort = 'Newest';
                      }),
                      child: const Text('Clear filters'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  '${rows.length} matching demo applications • summaries include all statuses for the selected posting',
                ),
                const SizedBox(height: 16),
                if (rows.isEmpty)
                  const ModuleState(
                    title: 'No applications found',
                    message: 'Try changing the filters. New demo applications appear here after applying to an available demo job.',
                  ),
                for (final a in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: WorkspaceCard(
                      leading: CircleAvatar(
                        radius: 20,
                        child: Icon(
                          widget.employer
                              ? Icons.person_outline
                              : Icons.work_outline,
                          size: 20,
                        ),
                      ),
                      title: widget.employer
                          ? a.candidate
                          : repo.job(a.jobId)!.title,
                      subtitle: widget.employer
                          ? repo.job(a.jobId)!.title
                          : repo.job(a.jobId)!.company,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: StageBadge(a.stage),
                          ),
                          Text('Applied: ${jobDate(a.date)}'),
                          if (widget.employer) ...[
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final skill in a.skills)
                                  Chip(label: Text(skill)),
                              ],
                            ),
                            Text(
                              a.resume
                                  ? 'Sample resume marked available (no file connected)'
                                  : 'Resume not provided',
                            ),
                            Text(
                              a.note.isEmpty ? 'No cover note' : a.note,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton(
                              onPressed: () => context.push(
                                '${widget.employer ? AppRoutes.applicants : AppRoutes.applications}/${a.id}',
                              ),
                              child: Text(
                                widget.employer
                                    ? 'View Applicant'
                                    : 'View Application',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ApplicationActions(
                            application: a,
                            repository: repo,
                            employer: widget.employer,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
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
    final repo = repository ?? Module2Repository.session;
    final path = employer ? AppRoutes.applicants : AppRoutes.applications;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final a = repo.application(applicationId);
        final j = a == null ? null : repo.job(a.jobId);
        return AppWorkspace(
          title: employer ? 'Applicant Details' : 'Application Details',
          leading: kIsWeb
              ? null
              : BackButton(onPressed: () => moduleBack(context, path)),
          path: path,
          role: employer ? 'employer' : 'job_seeker',
          child: WorkspaceContent(
            maxWidth: employer ? 512 : 448,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => moduleBack(context, path),
                    icon: kIsWeb ? null : const Icon(Icons.arrow_back),
                    label: const Text('Back to Applications'),
                  ),
                ),
                const DemoNotice(),
                if (a == null || j == null || (!employer && !a.mine))
                  const ModuleState(
                    title: 'Application unavailable',
                    message: 'This application does not exist in your demo session. Refresh resets demo changes.',
                  )
                else ...[
                  WorkspaceCard(
                    title: employer ? a.candidate : j.title,
                    subtitle: j.company,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (employer) Text(j.title),
                        Text(
                          'Demo ID: ${a.id}',
                          style: const TextStyle(
                            fontFamily: 'DM Mono',
                            fontSize: 11,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: StageBadge(a.stage),
                        ),
                        if (employer)
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final skill in a.skills)
                                Chip(label: Text(skill)),
                            ],
                          ),
                        const Text(
                          'Fictional profile • no trust score or verification is asserted.',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          a.resume
                              ? 'Sample resume marked available. No real resume file is connected.'
                              : 'Resume missing. No file was shared.',
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Cover note',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(a.note.isEmpty ? 'Not provided' : a.note),
                        if (employer && a.internalNote.isNotEmpty) ...[
                          const Divider(),
                          const Text(
                            'Internal demo rejection note (employer view only)',
                          ),
                          Text(a.internalNote),
                        ],
                        const SizedBox(height: 20),
                        ApplicationActions(
                          application: a,
                          repository: repo,
                          employer: employer,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  WorkspaceCard(
                    title: 'Application timeline',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final event in a.timeline)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.check_circle_outline),
                            title: Text(event.$1.label),
                            subtitle: Text(
                              '${jobDate(event.$2)} • ${TimeOfDay.fromDateTime(event.$2).format(context)} • demo only',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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
