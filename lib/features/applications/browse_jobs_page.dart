import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../jobs/job_display.dart';
import 'module2_repository.dart';
import 'module2_widgets.dart';
import 'job_details_page.dart';

class BrowseJobsPage extends StatefulWidget {
  const BrowseJobsPage({super.key, this.repository});
  final Module2Repository? repository;
  @override
  State<BrowseJobsPage> createState() => _BrowseJobsPageState();
}

class _BrowseJobsPageState extends State<BrowseJobsPage> {
  late final repo = widget.repository ?? Module2Repository.session;
  final search = TextEditingController();
  final location = TextEditingController();
  String type = '', arrangement = '', sort = 'Newest';
  bool savedOnly = false;
  @override
  void dispose() {
    search.dispose();
    location.dispose();
    super.dispose();
  }

  void clear() => setState(() {
    search.clear();
    location.clear();
    type = '';
    arrangement = '';
    savedOnly = false;
    sort = 'Newest';
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final jobs = repo.searchJobs(
        query: search.text,
        location: location.text,
        type: type,
        arrangement: arrangement,
        sort: sort,
        savedOnly: savedOnly,
      );
      return AppWorkspace(
        title: 'Browse Jobs',
        path: AppRoutes.browseJobs,
        role: 'job_seeker',
        child: WorkspaceContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DemoNotice(),
              const PageHeading(
                title: 'Find your next opportunity',
                description: 'Explore the demo catalogue. Real job browsing is awaiting a verified public read contract.',
              ),
              TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Search title, company or keywords',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  ModuleSelect(
                    label: 'Employment type',
                    value: type,
                    options: {
                      '': 'All types',
                      for (final v in [
                        'full_time',
                        'part_time',
                        'contract',
                        'internship',
                        'temporary',
                      ])
                        v: jobLabel(v),
                    },
                    onChanged: (v) => setState(() => type = v),
                  ),
                  ModuleSelect(
                    label: 'Work arrangement',
                    value: arrangement,
                    options: {
                      '': 'All arrangements',
                      for (final v in ['on_site', 'hybrid', 'remote'])
                        v: jobLabel(v),
                    },
                    onChanged: (v) => setState(() => arrangement = v),
                  ),
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width < 600
                        ? MediaQuery.sizeOf(context).width - 32
                        : 220,
                    child: TextField(
                      controller: location,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Location'),
                    ),
                  ),
                  ModuleSelect(
                    label: 'Sort',
                    value: sort,
                    options: {
                      for (final v in ['Newest', 'Title', 'Deadline']) v: v,
                    },
                    onChanged: (v) => setState(() => sort = v),
                  ),
                ],
              ),
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: const Text('Saved in demo'),
                    selected: savedOnly,
                    onSelected: (v) => setState(() => savedOnly = v),
                  ),
                  TextButton(
                    onPressed: clear,
                    child: const Text('Clear filters'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('${jobs.length} demo results'),
              const SizedBox(height: 16),
              if (jobs.isEmpty)
                ModuleState(
                  title: 'No matching jobs',
                  message: 'Try another keyword or clear your filters.',
                  action: clear,
                  actionLabel: 'Clear filters',
                ),
              for (final job in jobs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: WorkspaceCard(
                    title: job.title,
                    leading: CircleAvatar(
                      radius: 20,
                      child: Text(
                        job.company.replaceFirst('Demo ', '').substring(0, 1),
                      ),
                    ),
                    subtitle: job.company,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        JobFacts(job),
                        const SizedBox(height: 12),
                        Text(
                          job.text('role_overview'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (job.unavailable() case final String reason)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(reason),
                          ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton(
                              onPressed: () => context.push(
                                '${AppRoutes.browseJobs}/${job.id}',
                              ),
                              child: const Text('View Details'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => repo.toggleSave(job.id),
                              icon: Icon(
                                repo.saved(job.id)
                                    ? Icons.bookmark
                                    : Icons.bookmark_border,
                              ),
                              label: Text(
                                repo.saved(job.id)
                                    ? 'Unsave (demo)'
                                    : 'Save (demo)',
                              ),
                            ),
                            if (repo.applied(job.id))
                              const Chip(label: Text('Applied in demo')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
