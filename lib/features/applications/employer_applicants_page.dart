import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/theme/jobmate_theme.dart';
import 'employer_applicant_card.dart';
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

  void clear() => setState(() {
    search.clear();
    status = '';
    tab = 'All';
    sort = 'Newest';
  });

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
      final counts = {
        'All': repo.applicants.length,
        'Active': repo.applicants
            .where((applicant) => !applicant.status.completed)
            .length,
        'Completed': repo.applicants
            .where((applicant) => applicant.status.completed)
            .length,
      };
      return AppWorkspace(
        title: 'View Applicants',
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
          maxWidth: 880,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => moduleBack(context, AppRoutes.jobPostings),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back to My Job Postings'),
                ),
              ),
              const PageHeading(
                title: 'View Applicants',
                description: 'Review applications for your job postings.',
              ),
              if (repo.loading)
                const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Loading applicants',
                  ),
                )
              else if (repo.error != null)
                ModuleState(
                  title: 'Unable to load applicants',
                  message: repo.error!,
                  action: repo.load,
                  actionLabel: 'Retry',
                )
              else ...[
                DropdownButtonFormField<String>(
                  key: ValueKey('applicant-job-${widget.jobId}'),
                  initialValue: job == null ? '' : widget.jobId!,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Job posting'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Select a job'),
                    ),
                    for (final post
                        in repo.context?.jobs ?? <Map<String, dynamic>>[])
                      DropdownMenuItem(
                        value: post['job_id'] as String,
                        child: Text(
                          '${post['title']} (${workspaceLabel(post['status'] as String)})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) {
                      context.go(
                        Uri(
                          path: AppRoutes.applicants,
                          queryParameters: id.isEmpty ? null : {'posting': id},
                        ).toString(),
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
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
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: JobMateTheme.divider),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          job['title'] as String,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (company?['company_name'] != null)
                          Text(
                            company!['company_name'] as String,
                            style: const TextStyle(color: JobMateTheme.body),
                          ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            WorkspaceStatus(job['status'] as String),
                            TextButton.icon(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => JobPreview(
                                  job: job,
                                  company: company!['company_name'] as String,
                                  logo: repo.context!.access.logo,
                                ),
                              ),
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 17,
                              ),
                              label: const Text('View Job'),
                            ),
                            if (['draft', 'published'].contains(job['status']))
                              TextButton.icon(
                                onPressed: () => navigate(
                                  '${AppRoutes.jobPostings}/${widget.jobId}/edit',
                                ),
                                icon: const Icon(Icons.edit_outlined, size: 17),
                                label: const Text('Edit Job'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  ApplicantSummaryFilters(
                    counts: counts,
                    selected: tab,
                    onSelected: (value) => setState(() => tab = value),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, box) {
                      final searchField = TextField(
                        controller: search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Search applicant name',
                          prefixIcon: Icon(Icons.search),
                        ),
                      );
                      final sortField = ModuleSelect(
                        label: 'Sort',
                        value: sort,
                        options: {
                          for (final value in ['Newest', 'Oldest', 'Name'])
                            value: value,
                        },
                        onChanged: (value) => setState(() => sort = value),
                      );
                      if (box.maxWidth <
                          520 *
                              MediaQuery.textScalerOf(context).scale(14) /
                              14) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            searchField,
                            const SizedBox(height: 10),
                            sortField,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: searchField),
                          const SizedBox(width: 12),
                          SizedBox(width: 180, child: sortField),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ModuleSelect(
                        label: 'Application status',
                        value: status,
                        options: {
                          '': 'All statuses',
                          for (final state in MyApplicationStatus.values)
                            state.name:
                                '${state.label}: ${repo.applicants.where((applicant) => applicant.status == state).length}',
                        },
                        onChanged: (value) => setState(() => status = value),
                      ),
                      TextButton(
                        onPressed: clear,
                        child: const Text('Clear filters'),
                      ),
                      Text(
                        '${rows.length} matching ${rows.length == 1 ? 'application' : 'applications'}',
                        style: const TextStyle(color: JobMateTheme.body),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
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
                      padding: const EdgeInsets.only(bottom: 14),
                      child: EmployerApplicantCard(
                        key: ValueKey(applicant.id),
                        applicant: applicant,
                        jobTitle: job['title'] as String,
                        updating: repo.updating,
                        profileAction: ApplicantProfileButton(
                          applicationId: applicant.id,
                          applicant: applicant,
                          jobTitle: job['title'] as String,
                          applicantsRepository: repo,
                        ),
                        resumeAction: applicant.resumeId == null
                            ? null
                            : EmployerResumeButton(
                                key: ValueKey(
                                  'resume:${applicant.id}:${applicant.resumeId}',
                                ),
                                repository: repo,
                                applicant: applicant,
                              ),
                        messageAction: ChatApplicationButton(
                          key: ValueKey('chat:${applicant.id}'),
                          applicationId: applicant.id,
                          employer: true,
                          enabled: !repo.updating,
                        ),
                        onTransition: (next) => moduleModal<void>(
                          context,
                          EmployerStatusChangeForm(
                            repository: repo,
                            applicant: applicant,
                            next: next,
                          ),
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
