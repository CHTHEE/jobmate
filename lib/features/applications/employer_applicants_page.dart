import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../jobs/job_display.dart';
import '../jobs/job_preview.dart';
import '../chat/chat_application_button.dart';
import 'employer_applicants_repository.dart';
import 'employer_applicant_profile.dart';
import 'module2_widgets.dart';
import 'my_applications_repository.dart';
import 'employer_status_change_form.dart';
import 'employer_resume_button.dart';

class EmployerApplicantsPage extends StatefulWidget {
  const EmployerApplicantsPage({super.key, required this.source, this.jobId});
  final EmployerApplicantsSource source;
  final String? jobId;
  @override
  State<EmployerApplicantsPage> createState() => _EmployerApplicantsPageState();
}

class _EmployerApplicantsPageState extends State<EmployerApplicantsPage> {
  late EmployerApplicantsRepository repo;
  final search = TextEditingController();
  String tab = 'All', status = '', sort = 'Newest';
  void initialize() {
    repo = EmployerApplicantsRepository(widget.source, widget.jobId);
    final current = repo;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(current, repo)) current.load();
    });
  }

  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void didUpdateWidget(covariant EmployerApplicantsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobId != widget.jobId || oldWidget.source != widget.source) {
      repo.dispose();
      search.clear();
      tab = 'All';
      status = '';
      sort = 'Newest';
      initialize();
    }
  }

  @override
  void dispose() {
    repo.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> navigate(String path) async {
    if (path == AppRoutes.home) {
      context.go(path);
      return;
    }
    await context.push<void>(path);
    if (mounted) await repo.load();
  }

  String statusLabel(MyApplicationStatus s) => s.label;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final job = repo.job, company = repo.context?.access.company;
      final rows = repo.search(
        query: search.text,
        tab: tab,
        status: status,
        sort: sort,
      );
      return AppWorkspace(
        title: 'Employer Applications',
        path: AppRoutes.applicants,
        role: 'employer',
        onNavigate: navigate,
        navigationLocked: repo.updating,
        actions: [
          IconButton(
            tooltip: 'Refresh applicants',
            onPressed: repo.loading || repo.updating ? null : repo.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: WorkspaceContent(
          maxWidth: 768,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton(
                onPressed: () => moduleBack(context, AppRoutes.jobPostings),
                child: const Text('Back to My Job Postings'),
              ),
              const PageHeading(
                title: 'View Applicants',
                description: 'Review applications for your job postings.',
              ),
              if (repo.loading)
                const Center(child: CircularProgressIndicator())
              else if (repo.error != null)
                ModuleState(
                  title: 'Unable to load applicants',
                  message: repo.error!,
                  action: repo.load,
                  actionLabel: 'Retry',
                )
              else ...[
                ModuleSelect(
                  label: 'Job posting',
                  value: job == null ? '' : widget.jobId!,
                  options: {
                    '': 'Select a job',
                    for (final post
                        in repo.context?.jobs ?? <Map<String, dynamic>>[])
                      post['job_id'] as String:
                          '${post['title']} (${jobLabel('${post['status']}')})',
                  },
                  onChanged: (id) => context.go(
                    Uri(
                      path: AppRoutes.applicants,
                      queryParameters: id.isEmpty ? null : {'posting': id},
                    ).toString(),
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.jobId == null)
                  const ModuleState(
                    title: 'Select a job to view applicants',
                    message: 'Choose a posting above or open View Applicants from My Job Postings.',
                  )
                else if (job == null)
                  const ModuleState(
                    title: 'Job unavailable',
                    message: 'This job is unavailable or you no longer have company access.',
                  )
                else ...[
                  WorkspaceCard(
                    title: job['title'] as String,
                    subtitle: company?['company_name'] as String?,
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        WorkspaceStatus(job['status'] as String),
                        OutlinedButton(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => JobPreview(
                              job: job,
                              company: company!['company_name'] as String,
                              logo: repo.context!.access.logo,
                            ),
                          ),
                          child: const Text('View Job'),
                        ),
                        if (['draft', 'published'].contains(job['status']))
                          OutlinedButton(
                            onPressed: () => navigate(
                              '${AppRoutes.jobPostings}/${widget.jobId}/edit',
                            ),
                            child: const Text('Edit Job'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  StatGrid(
                    children: [
                      for (final value in <(String, int)>[
                        ('All', repo.applicants.length),
                        (
                          'Active',
                          repo.applicants
                              .where((a) => !a.status.completed)
                              .length,
                        ),
                        (
                          'Completed',
                          repo.applicants
                              .where((a) => a.status.completed)
                              .length,
                        ),
                      ])
                        StatTile(
                          label: value.$1,
                          value: '${value.$2}',
                          icon: Icons.people_outline,
                          note: 'This job',
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in MyApplicationStatus.values)
                        Chip(
                          label: Text(
                            '${statusLabel(s)}: ${repo.applicants.where((a) => a.status == s).length}',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final value in ['All', 'Active', 'Completed'])
                        ChoiceChip(
                          label: Text(value),
                          selected: tab == value,
                          onSelected: (_) => setState(() => tab = value),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Search applicant name',
                      prefixIcon: Icon(Icons.search),
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
                          for (final s in MyApplicationStatus.values)
                            s.name: statusLabel(s),
                        },
                        onChanged: (v) => setState(() => status = v),
                      ),
                      ModuleSelect(
                        label: 'Sort',
                        value: sort,
                        options: {
                          for (final v in ['Newest', 'Oldest', 'Name']) v: v,
                        },
                        onChanged: (v) => setState(() => sort = v),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          search.clear();
                          status = '';
                          tab = 'All';
                          sort = 'Newest';
                        }),
                        child: const Text('Clear filters'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('${rows.length} matching applications'),
                  const SizedBox(height: 16),
                  if (rows.isEmpty)
                    ModuleState(
                      title: repo.applicants.isEmpty
                          ? 'No applicants yet'
                          : 'No matching applicants',
                      message: repo.applicants.isEmpty
                          ? 'Applications for this job will appear here.'
                          : 'Try changing the filters.',
                    ),
                  for (final applicant in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: WorkspaceCard(
                        key: ValueKey(applicant.id),
                        leading: const CircleAvatar(
                          radius: 20,
                          child: Icon(Icons.person_outline, size: 20),
                        ),
                        title: applicant.name,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: MyApplicationStatusBadge(
                                applicant.status,
                                label: statusLabel(applicant.status),
                              ),
                            ),
                            if (applicant.status.lifecycleExplanation
                                case final explanation?) ...[
                              Text(explanation),
                              const SizedBox(height: 12),
                            ],
                            Text(
                              'Applied: ${jobDate(applicant.appliedAt.toLocal())} • ${TimeOfDay.fromDateTime(applicant.appliedAt.toLocal()).format(context)}',
                            ),
                            Text(
                              applicant.resumeId != null
                                  ? 'Resume attached'
                                  : 'No resume attached',
                            ),
                            if (applicant.resumeId != null)
                              EmployerResumeButton(
                                key: ValueKey(
                                  'resume:${applicant.id}:${applicant.resumeId}',
                                ),
                                repository: repo,
                                applicant: applicant,
                              ),
                            ApplicantProfileButton(applicationId: applicant.id),
                            if (applicant.coverNote?.trim().isNotEmpty ==
                                true) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Cover note',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(applicant.coverNote!),
                            ],
                            const SizedBox(height: 12),
                            SelectableText('Application ID: ${applicant.id}'),
                            ChatApplicationButton(
                              key: ValueKey('chat:${applicant.id}'),
                              applicationId: applicant.id,
                              employer: true,
                              enabled: !repo.updating,
                            ),
                            if (applicant.employerNext.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final next in applicant.employerNext)
                                    OutlinedButton(
                                      onPressed: repo.updating
                                          ? null
                                          : () => moduleModal<void>(
                                              context,
                                              EmployerStatusChangeForm(
                                                repository: repo,
                                                applicant: applicant,
                                                next: next,
                                              ),
                                            ),
                                      child: Text(
                                        employerTransitionLabel(next),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      );
    },
  );
}
