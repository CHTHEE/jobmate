import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/theme/jobmate_theme.dart';
import 'job_postings_repository.dart';
import 'job_preview.dart';
import 'employer_job_card.dart';
import 'job_validation.dart';
import '../company/company_logo.dart';

class JobPostingsPage extends StatefulWidget {
  const JobPostingsPage({
    super.key,
    this.repository,
    this.initialStatus = 'all',
  });
  final JobPostingsRepository? repository;
  final String initialStatus;
  @override
  State<JobPostingsPage> createState() => _JobPostingsPageState();
}

class _JobPostingsPageState extends State<JobPostingsPage> {
  late final repo =
      widget.repository ?? JobPostingsRepository(Supabase.instance.client);
  JobAccess? access;
  List<Map<String, dynamic>> jobs = [];
  String filter = 'all';
  String query = '';
  String? error;
  bool loading = true, busy = false;
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
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await repo.loadAccess();
      final records = result.allowed
          ? await repo.list(result.company!['company_id'].toString())
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          access = result;
          jobs = records;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = jobError(e);
          access = null;
          jobs = [];
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> close(Map<String, dynamic> job) async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close this job?'),
        content: const Text('Closed jobs cannot be edited or reopened.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close Job'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repo.close(job['job_id'].toString());
      await load();
    } catch (e) {
      if (mounted) setState(() => error = jobError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> publish(Map<String, dynamic> job) async {
    if (busy) return;
    final validation = jobPublishError(job);
    if (validation != null) {
      setState(
        () => error = '$validation Use Edit Draft to complete this job.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repo.save({'status': 'published'}, jobId: job['job_id'].toString());
      if (!mounted) return;
      setState(() => filter = 'published');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job published successfully')),
      );
      await load();
    } catch (e) {
      if (mounted) setState(() => error = jobError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(String path) async {
    final result = await context.push<String>(path, extra: 'job-list');
    if (!mounted) return;
    if (['draft', 'published', 'closed'].contains(result)) {
      setState(() => filter = result!);
    }
    await load();
  }

  @override
  Widget build(BuildContext context) {
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
      navigationLocked: busy,
      child: loading
          ? const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading job postings',
              ),
            )
          : WorkspaceContent(
              maxWidth: 880,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageHeading(
                    title: 'My Job Postings',
                    description: 'Manage job opportunities for your company.',
                    actions: [
                      OutlinedButton(
                        onPressed: busy ? null : load,
                        child: const Text('Check for updates'),
                      ),
                      FilledButton.icon(
                        onPressed: access?.allowed == true && !busy
                            ? () => open(AppRoutes.createJob)
                            : null,
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
                              onPressed: busy ? null : load,
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
                            onPressed: () => open(AppRoutes.company),
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
                    TextField(
                      onChanged: (value) => setState(() => query = value),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search job title, department or location',
                        labelText: 'Search your postings',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
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
                                    : () => open(AppRoutes.createJob),
                                child: const Text('Post your first job'),
                              ),
                          ],
                        ),
                      ),
                    for (final job in visible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: EmployerJobCard(
                          key: ValueKey('employer-job-${job['job_id']}'),
                          job: job,
                          busy: busy,
                          onEdit: () => open(
                            '${AppRoutes.jobPostings}/${job['job_id']}/edit',
                          ),
                          onPreview: () => showDialog<void>(
                            context: context,
                            builder: (_) => JobPreview(
                              logo: access!.logo,
                              job: job,
                              company:
                                  access!.company!['company_name'] as String,
                            ),
                          ),
                          onPublish: () => publish(job),
                          onClose: () => close(job),
                          onApplicants: () => context.push<void>(
                            Uri(
                              path: AppRoutes.applicants,
                              queryParameters: {
                                'posting': job['job_id'].toString(),
                              },
                            ).toString(),
                          ),
                        ),
                      ),
                  ],
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
            ),
    );
  }
}
