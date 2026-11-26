import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/expandable_filter_bar.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../../shared/theme/jobmate_theme.dart';
import 'job_postings_repository.dart';
import 'job_form_result.dart';
import 'job_form_route.dart';
import 'employer_job_card.dart';
import '../company/company_logo.dart';
import '../applications/applicant_unseen_controller.dart';

class JobPostingsPage extends StatefulWidget {
  const JobPostingsPage({
    super.key,
    this.repository,
    this.applicantUnseen,
    this.initialStatus = 'all',
  });
  final JobPostingsRepository? repository;
  final ApplicantUnseenController? applicantUnseen;
  final String initialStatus;
  @override
  State<JobPostingsPage> createState() => _JobPostingsPageState();
}

class _JobPostingsPageState extends State<JobPostingsPage> {
  late final repo =
      widget.repository ?? JobPostingsRepository(Supabase.instance.client);
  ApplicantUnseenController? get _applicantUnseen =>
      widget.applicantUnseen ??
      (widget.repository == null
          ? ApplicantUnseenController.session(repo.client)
          : null);
  JobAccess? access;
  List<Map<String, dynamic>> jobs = [];
  String filter = 'all';
  String query = '';
  String? error;
  bool loading = true, refreshing = false, busy = false;
  bool get actionsLocked => busy || refreshing;
  @override
  void initState() {
    super.initState();
    filter =
        ['all', 'draft', 'published', 'closed'].contains(widget.initialStatus)
        ? widget.initialStatus
        : 'all';
    load();
  }

  Future<void> load() async {
    if (refreshing) return;
    final accountId = repo.client.auth.currentUser?.id;
    setState(() {
      refreshing = true;
      loading = access == null;
      error = null;
    });
    try {
      final result = await repo.loadAccess();
      if (!mounted || repo.client.auth.currentUser?.id != accountId) return;
      if (mounted && widget.repository == null) {
        _applicantUnseen?.enterWorkspace(
          accountId: accountId,
          companyId: result.allowed
              ? result.company!['company_id'] as String?
              : null,
        );
      }
      final records = result.allowed
          ? await repo.list(result.company!['company_id'].toString())
          : <Map<String, dynamic>>[];
      if (mounted && repo.client.auth.currentUser?.id == accountId) {
        setState(() {
          access = result;
          jobs = List.of(records);
        });
      }
    } catch (e) {
      if (mounted && repo.client.auth.currentUser?.id == accountId) {
        setState(() {
          error = jobError(e);
          access = null;
          jobs = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          refreshing = false;
          if (repo.client.auth.currentUser?.id != accountId) {
            jobs = [];
            access = null;
          }
        });
      }
    }
  }

  bool _sameSession(String? actor) =>
      repo.signedIn && repo.client.auth.currentUser?.id == actor;

  Future<void> openJobForm(String path) async {
    final actor = repo.client.auth.currentUser?.id;
    final result = await openJobFormDialog(context, path);
    if (!mounted || result == null || !_sameSession(actor)) return;
    _applySavedJob(result);
  }

  void _applySavedJob(JobFormResult result) {
    final job = result.job;
    final index = jobs.indexWhere((row) => row['job_id'] == job['job_id']);
    setState(() {
      if (index >= 0) {
        jobs[index] = job;
      } else if (result.change == JobFormChange.created) {
        jobs.insert(0, job);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final unseen = _applicantUnseen;
    if (unseen == null) return _buildPostings(context, null);
    return ListenableBuilder(
      listenable: unseen,
      builder: (context, child) => _buildPostings(context, unseen),
    );
  }

  Widget _buildPostings(
    BuildContext context,
    ApplicantUnseenController? unseen,
  ) {
    final counts = {
      'all': jobs.length,
      for (final status in ['published', 'draft', 'closed'])
        status: jobs.where((job) => job['status'] == status).length,
    };
    final visible = jobs
        .where(
          (job) =>
              (filter == 'all' || job['status'] == filter) &&
              '${job['title'] ?? ''} ${job['department'] ?? ''} ${job['location'] ?? ''}'
                  .toLowerCase()
                  .contains(query.trim().toLowerCase()),
        )
        .toList();
    return AppWorkspace(
      title: 'My Job Postings',
      path: AppRoutes.jobPostings,
      role: 'employer',
      applicantUnseen: unseen,
      navigationLocked: busy,
      child: loading
          ? const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading job postings',
              ),
            )
          : WorkspaceContent(
              maxWidth: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageHeading(
                    title: 'My Job Postings',
                    description: 'Manage job opportunities for your company.',
                    actions: [
                      OutlinedButton(
                        onPressed: actionsLocked ? null : load,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(
                            0,
                            ResponsiveLayout.actionHeight,
                          ),
                        ),
                        child: const Text('Check for updates'),
                      ),
                      FilledButton.icon(
                        onPressed: access?.allowed == true && !actionsLocked
                            ? () => openJobForm(AppRoutes.createJob)
                            : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(
                            0,
                            ResponsiveLayout.actionHeight,
                          ),
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Post Job'),
                      ),
                    ],
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: WorkspaceCard(
                        title: 'Unable to complete this request',
                        leading: const Icon(
                          Icons.error_outline,
                          color: JobMateTheme.error,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              error!,
                              style: const TextStyle(color: JobMateTheme.error),
                            ),
                            TextButton(
                              onPressed: actionsLocked ? null : load,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (access != null && !access!.allowed)
                    WorkspaceCard(
                      title: 'Job creation unavailable',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(access!.message!),
                          TextButton(
                            onPressed: actionsLocked
                                ? null
                                : () async {
                                    await context.push<void>(AppRoutes.company);
                                    if (mounted) await load();
                                  },
                            child: const Text('Company profile'),
                          ),
                        ],
                      ),
                    ),
                  if (access?.allowed == true) ...[
                    CompanyIdentity(
                      name: access!.company!['company_name'] as String,
                      logo: access!.logo,
                    ),
                    const SizedBox(height: 16),
                    PostingSummary(counts),
                    const SizedBox(height: 16),
                    ExpandableFilterBar(
                      activeCount: filter == 'all' ? 0 : 1,
                      onClear: busy
                          ? null
                          : () => setState(() => filter = 'all'),
                      search: TextField(
                        onChanged: (value) => setState(() => query = value),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search job title, department or location',
                          labelText: 'Search your postings',
                        ),
                      ),
                      filters: [
                        for (final value in [
                          'all',
                          'published',
                          'draft',
                          'closed',
                        ])
                          ChoiceChip(
                            label: Text(
                              '${postingStatusLabel(value)} (${counts[value]})',
                            ),
                            selected: filter == value,
                            onSelected: busy
                                ? null
                                : (_) => setState(() => filter = value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (visible.isEmpty && error == null)
                      WorkspaceCard(
                        title: jobs.isEmpty
                            ? 'No job postings yet'
                            : query.trim().isNotEmpty
                            ? 'No matching jobs'
                            : 'No ${filter == 'all' ? '' : '$filter '}jobs',
                        leading: const Icon(
                          Icons.work_outline,
                          color: JobMateTheme.darkTeal,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              jobs.isEmpty
                                  ? 'Post a job to start your first draft.'
                                  : query.trim().isNotEmpty
                                  ? 'Try a different search or status.'
                                  : 'Your $filter jobs will appear here.',
                            ),
                            if (jobs.isEmpty)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => openJobForm(AppRoutes.createJob),
                                child: const Text('Post your first job'),
                              ),
                          ],
                        ),
                      ),
                    ResponsiveGrid(
                      minItemWidth: 385,
                      equalRowHeight: true,
                      children: [
                        for (final job in visible)
                          EmployerJobCard(
                            key: ValueKey('employer-job-${job['job_id']}'),
                            job: job,
                            unseenApplicantCount:
                                unseen?.countFor(job['job_id'].toString()) ?? 0,
                            busy: actionsLocked,
                            onEdit: () => openJobForm(
                              '${AppRoutes.jobPostings}/${job['job_id']}/edit',
                            ),
                            onApplicants: () => context.push<void>(
                              Uri(
                                path: AppRoutes.applicants,
                                queryParameters: {
                                  'posting': job['job_id'].toString(),
                                },
                              ).toString(),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (busy || refreshing) const LinearProgressIndicator(),
                ],
              ),
            ),
    );
  }
}
