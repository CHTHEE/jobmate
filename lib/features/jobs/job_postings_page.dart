import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import 'job_postings_repository.dart';
import 'job_preview.dart';
import 'job_display.dart';
import 'job_validation.dart';
import '../company/company_logo.dart';

class JobPostingsPage extends StatefulWidget {
  const JobPostingsPage({
    super.key,
    this.repository,
    this.initialStatus = 'draft',
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
  String filter = 'draft';
  String? error;
  bool loading = true, busy = false;
  @override
  void initState() {
    super.initState();
    filter = ['draft', 'published', 'closed'].contains(widget.initialStatus)
        ? widget.initialStatus
        : 'draft';
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
  Widget build(BuildContext context) => AppWorkspace(
    title: 'My Job Postings',
    path: AppRoutes.jobPostings,
    role: 'employer',
    navigationLocked: busy,
    child: loading
        ? const Center(child: CircularProgressIndicator())
        : WorkspaceContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: access?.allowed == true && !busy
                          ? () => open(AppRoutes.createJob)
                          : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Create Job'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (access != null && !access!.allowed)
                  WorkspaceCard(
                    title: 'Job creation unavailable',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                  Text(
                    access!.company!['company_name'] as String,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final value in ['draft', 'published', 'closed'])
                        ChoiceChip(
                          label: Text(
                            '${workspaceLabel(value)} (${jobs.where((j) => j['status'] == value).length})',
                          ),
                          selected: filter == value,
                          onSelected: busy
                              ? null
                              : (_) => setState(() => filter = value),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (!jobs.any((j) => j['status'] == filter))
                    WorkspaceCard(
                      title: 'No $filter jobs',
                      child: Text(
                        filter == 'draft'
                            ? 'Create a job to save your first draft.'
                            : 'Your $filter jobs will appear here.',
                      ),
                    ),
                  for (final job in jobs.where((j) => j['status'] == filter))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: WorkspaceCard(
                        title: job['title'] as String? ?? 'Untitled job',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CompanyIdentity(
                              name: access!.company!['company_name'] as String,
                              logo: access!.logo,
                            ),
                            const SizedBox(height: 12),
                            WorkspaceStatus(job['status'] as String),
                            Wrap(
                              spacing: 24,
                              runSpacing: 8,
                              children: [
                                for (final key in [
                                  'department',
                                  'employment_type',
                                  'work_arrangement',
                                  'location',
                                ])
                                  if ('${job[key] ?? ''}'.isNotEmpty)
                                    Text(
                                      '${jobLabel(key)}: ${jobLabel('${job[key]}')}',
                                    ),
                                if (job['salary_visible'] == true)
                                  Text('Salary: ${jobSalary(job)}'),
                                Text(
                                  'Vacancies: ${job['vacancies'] ?? 'Not set'}',
                                ),
                                if (job['application_deadline'] != null)
                                  Text(
                                    'Application deadline: ${jobDate(job['application_deadline'])}',
                                  ),
                                if (job['published_at'] != null)
                                  Text(
                                    'Published: ${jobDate(job['published_at'])}',
                                  )
                                else if (job['created_at'] != null)
                                  Text(
                                    'Created: ${jobDate(job['created_at'])}',
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => context.push<void>(
                                          Uri(
                                            path: AppRoutes.applicants,
                                            queryParameters: {
                                              'posting': job['job_id']
                                                  .toString(),
                                            },
                                          ).toString(),
                                        ),
                                  icon: const Icon(Icons.people_outline),
                                  label: const Text('Applications (preview)'),
                                ),
                                OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => showDialog<void>(
                                          context: context,
                                          builder: (_) => JobPreview(
                                            logo: access!.logo,
                                            job: job,
                                            company:
                                                access!.company!['company_name']
                                                    as String,
                                          ),
                                        ),
                                  child: const Text('Preview'),
                                ),
                                if (job['status'] == 'draft' ||
                                    job['status'] == 'published')
                                  FilledButton(
                                    onPressed: busy
                                        ? null
                                        : () => open(
                                            '${AppRoutes.jobPostings}/${job['job_id']}/edit',
                                          ),
                                    child: Text(
                                      job['status'] == 'draft'
                                          ? 'Edit Draft'
                                          : 'Edit',
                                    ),
                                  ),
                                if (job['status'] == 'draft')
                                  OutlinedButton(
                                    onPressed: busy ? null : () => publish(job),
                                    child: const Text('Publish'),
                                  ),
                                if (job['status'] == 'published')
                                  OutlinedButton(
                                    onPressed: busy ? null : () => close(job),
                                    child: const Text('Close Job'),
                                  ),
                              ],
                            ),
                          ],
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
