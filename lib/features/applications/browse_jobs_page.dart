import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../jobs/job_display.dart';
import 'module2_repository.dart';
import 'module2_widgets.dart';
import 'browse_job_card.dart';
import 'published_company_logo.dart';

class BrowseJobsPage extends StatefulWidget {
  const BrowseJobsPage({super.key, this.repository});
  final Module2Repository? repository;
  @override
  State<BrowseJobsPage> createState() => _BrowseJobsPageState();
}

class _BrowseJobsPageState extends State<BrowseJobsPage> {
  late final repo = (widget.repository ?? Module2Repository.session).browse;
  final search = TextEditingController();
  final location = TextEditingController();
  String type = '', arrangement = '', sort = 'Newest';
  bool savedOnly = false;
  bool filtersExpanded = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) repo.load();
    });
  }

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
        actions: [
          IconButton(
            tooltip: 'Refresh jobs',
            onPressed: repo.loading ? null : repo.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: WorkspaceContent(
          maxWidth: 880,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeading(
                title: 'Find your next opportunity',
                description: 'Explore published jobs and find your next role.',
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Search title, company or keywords',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        setState(() => filtersExpanded = !filtersExpanded),
                    icon: Icon(
                      filtersExpanded ? Icons.expand_less : Icons.tune,
                    ),
                    label: const Text('Filters'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (filtersExpanded)
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
                    ResponsiveFilter(
                      child: TextField(
                        controller: location,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Location',
                        ),
                      ),
                    ),
                  ],
                ),
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: const Text('Saved this session'),
                    selected: savedOnly,
                    onSelected: (v) => setState(() => savedOnly = v),
                  ),
                  if (type.isNotEmpty)
                    InputChip(
                      label: Text(jobLabel(type)),
                      onDeleted: () => setState(() => type = ''),
                    ),
                  if (arrangement.isNotEmpty)
                    InputChip(
                      label: Text(jobLabel(arrangement)),
                      onDeleted: () => setState(() => arrangement = ''),
                    ),
                  if (location.text.isNotEmpty)
                    InputChip(
                      label: Text(location.text),
                      onDeleted: () => setState(location.clear),
                    ),
                  if (search.text.isNotEmpty ||
                      location.text.isNotEmpty ||
                      type.isNotEmpty ||
                      arrangement.isNotEmpty ||
                      savedOnly ||
                      sort != 'Newest')
                    TextButton(
                      onPressed: clear,
                      child: const Text('Clear filters'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (repo.loading || (!repo.loaded && repo.error == null))
                const Center(child: CircularProgressIndicator())
              else if (repo.error != null)
                ModuleState(
                  title: 'Unable to load jobs',
                  message: repo.error!,
                  action: repo.load,
                  actionLabel: 'Retry',
                )
              else
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    Text('${jobs.length} results'),
                    Semantics(
                      label: 'Sort jobs',
                      child: DropdownButton<String>(
                        value: sort,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final value in ['Newest', 'Title', 'Deadline'])
                            DropdownMenuItem(value: value, child: Text(value)),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => sort = value);
                        },
                        hint: const Text('Sort'),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              if (repo.loaded && jobs.isEmpty)
                ModuleState(
                  title: repo.jobs.isEmpty
                      ? 'No published jobs yet'
                      : 'No matching jobs',
                  message: repo.jobs.isEmpty
                      ? 'Check back later or refresh for new opportunities.'
                      : 'Try another keyword or clear your filters.',
                  action: repo.jobs.isEmpty ? repo.load : clear,
                  actionLabel: repo.jobs.isEmpty ? 'Refresh' : 'Clear filters',
                ),
              for (final job in jobs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: BrowseJobCard(
                    job: job,
                    logo: PublishedCompanyLogo(
                      job: job,
                      repository: repo,
                      size: 32,
                    ),
                    saved: repo.saved(job.id),
                    onSave: () => repo.toggleSave(job.id),
                    onDetails: () =>
                        context.push('${AppRoutes.browseJobs}/${job.id}'),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
