import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/expandable_filter_bar.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../jobs/job_display.dart';
import 'module2_repository.dart';
import 'module2_widgets.dart';
import 'browse_job_card.dart';
import 'published_company_logo.dart';

GoRoute legacyJobSearchRoute() => GoRoute(
  path: AppRoutes.search,
  redirect: (_, state) => AppRoutes.browseJobsLocation(
    state.uri.queryParameters[AppRoutes.jobKeywordParameter],
  ),
);

class BrowseJobsPage extends StatefulWidget {
  const BrowseJobsPage({
    super.key,
    this.repository,
    this.initialKeyword = '',
    this.keywordRequest,
  });
  final Module2Repository? repository;
  final String initialKeyword;
  final Object? keywordRequest;
  @override
  State<BrowseJobsPage> createState() => _BrowseJobsPageState();
}

class _BrowseJobsPageState extends State<BrowseJobsPage> {
  late final repo = (widget.repository ?? Module2Repository.session).browse;
  late final search = TextEditingController(text: widget.initialKeyword.trim());
  final location = TextEditingController();
  String type = '', arrangement = '', sort = 'Newest';
  bool savedOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) repo.load();
    });
  }

  @override
  void didUpdateWidget(BrowseJobsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A fresh panel submission can reapply the same URL keyword after a local edit.
    if (widget.initialKeyword != oldWidget.initialKeyword ||
        !identical(widget.keywordRequest, oldWidget.keywordRequest)) {
      search.text = widget.initialKeyword.trim();
    }
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
      final hasFilters =
          search.text.isNotEmpty ||
          location.text.isNotEmpty ||
          type.isNotEmpty ||
          arrangement.isNotEmpty ||
          savedOnly ||
          sort != 'Newest';
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
          maxWidth: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeading(
                title: 'Find your next opportunity',
                description: 'Explore published jobs and find your next role.',
              ),
              ExpandableFilterBar(
                search: TextField(
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search title, company or keywords',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                activeCount: [
                  type.isNotEmpty,
                  arrangement.isNotEmpty,
                  location.text.isNotEmpty,
                  savedOnly,
                ].where((active) => active).length,
                filters: [
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
                        labelText: 'City or state',
                        hintText: 'City or state',
                      ),
                    ),
                  ),
                  ResponsiveFilter(
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Bookmarked jobs only'),
                      value: savedOnly,
                      onChanged: (value) =>
                          setState(() => savedOnly = value ?? false),
                    ),
                  ),
                ],
              ),
              if (hasFilters) ...[
                const SizedBox(height: JobMateTheme.space8),
                Wrap(
                  spacing: JobMateTheme.space12,
                  runSpacing: JobMateTheme.space4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
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
                    TextButton(
                      onPressed: clear,
                      child: const Text('Clear filters'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: JobMateTheme.space8),
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
                  title: !hasFilters
                      ? 'No jobs accepting applications'
                      : 'No matching jobs',
                  message: !hasFilters
                      ? 'Check back later or refresh for new opportunities.'
                      : 'Try another keyword or clear your filters.',
                  action: !hasFilters ? repo.load : clear,
                  actionLabel: !hasFilters ? 'Refresh' : 'Clear filters',
                ),
              ResponsiveGrid(
                equalRowHeight: true,
                minItemWidth: 360,
                children: [
                  for (final job in jobs)
                    BrowseJobCard(
                      job: job,
                      availabilityAsOf: repo.availabilityAsOf,
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
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
