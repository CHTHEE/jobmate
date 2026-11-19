import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_page.dart';
import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../applications/browse_job_card.dart';
import '../applications/job_discovery_place_search.dart';
import '../applications/module2_repository.dart';
import '../applications/module2_widgets.dart';
import '../applications/published_company_logo.dart';
import '../jobs/job_display.dart';
import 'nearby_job_results.dart';
import 'nearby_jobs_map.dart';

List<GoRoute> nearbyJobsRoutes({
  NearbyJobsListPage page = const NearbyJobsListPage(),
}) => [
  GoRoute(
    path: AppRoutes.nearbyJobs,
    pageBuilder: (_, state) => appPage(state, page),
  ),
  GoRoute(
    path: '${AppRoutes.nearbyJobs}/:jobId',
    redirect: (_, _) => AppRoutes.nearbyJobs,
  ),
];

class NearbyJobsListPage extends StatelessWidget {
  const NearbyJobsListPage({
    super.key,
    this.repository,
    this.searchPlaces = searchJobDiscoveryPlaces,
    this.checkAccess,
    this.mapBuilder,
  });

  final PublishedJobsRepository? repository;
  final DiscoveryPlaceSearch searchPlaces;
  final Future<bool> Function()? checkAccess;
  final NearbyMapBuilder? mapBuilder;

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? Module2Repository.session.browse;
    return StreamBuilder<String?>(
      stream: repo.source.accountChanges,
      builder: (context, _) => Module2Gate(
        key: ValueKey(repo.source.userId),
        role: 'job_seeker',
        checkAccess: checkAccess,
        child: _NearbyJobsList(
          repository: repo,
          searchPlaces: searchPlaces,
          mapBuilder: mapBuilder,
        ),
      ),
    );
  }
}

class _NearbyJobsList extends StatefulWidget {
  const _NearbyJobsList({
    required this.repository,
    required this.searchPlaces,
    required this.mapBuilder,
  });

  final PublishedJobsRepository repository;
  final DiscoveryPlaceSearch searchPlaces;
  final NearbyMapBuilder? mapBuilder;

  @override
  State<_NearbyJobsList> createState() => _NearbyJobsListState();
}

class _NearbyJobsListState extends State<_NearbyJobsList> {
  static const radii = [5, 10, 20];
  int _radius = 5;
  String _employmentType = '';
  DiscoveryPlace? _place;
  bool _showMap = false;
  String? _selectedJobId;

  PublishedJobsRepository get _repo => widget.repository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_repo.loaded && !_repo.loading) _repo.load();
    });
  }

  Future<void> _selectPlace() async {
    final source = _repo.source;
    final actor = source.userId;
    final search = widget.searchPlaces;
    final place = await showDialog<DiscoveryPlace>(
      context: context,
      builder: (_) => StreamBuilder<String?>(
        stream: source.accountChanges,
        builder: (context, _) => source.userId == actor
            ? DiscoveryPlaceDialog(search: search)
            : AlertDialog(
                title: const Text('Account changed'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
      ),
    );
    if (!mounted || source.userId != actor || place == null) return;
    setState(() => _place = place);
  }

  Widget _card(NearbyJobResult result) => Padding(
    padding: const EdgeInsets.only(bottom: JobMateTheme.space12),
    child: BrowseJobCard(
      key: ValueKey(result.job.id),
      job: result.job,
      distanceKm: result.distanceKm,
      logo: PublishedCompanyLogo(job: result.job, repository: _repo, size: 32),
      saved: _repo.saved(result.job.id),
      onSave: () => _repo.toggleSave(result.job.id),
      onDetails: () => context.push(
        '${AppRoutes.browseJobs}/${Uri.encodeComponent(result.job.id)}',
      ),
    ),
  );

  Widget _map(DiscoveryPlace place, List<NearbyJobResult> results) {
    void select(String id) => setState(() => _selectedJobId = id);
    void showList() => setState(() => _showMap = false);
    final builder = widget.mapBuilder;
    return builder == null
        ? NearbyJobsMap(
            origin: place.coordinates,
            radiusKm: _radius,
            results: results,
            onJobSelected: select,
            onShowList: showList,
          )
        : builder(
            context,
            place.coordinates,
            _radius,
            results,
            select,
            showList,
          );
  }

  Widget _searchPanel(DiscoveryPlace? place) => Container(
    padding: const EdgeInsets.all(JobMateTheme.space16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(JobMateTheme.dialogRadius),
      border: Border.all(color: JobMateTheme.divider),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 520;
        final theme = Theme.of(context);
        final action = OutlinedButton.icon(
          onPressed: _selectPlace,
          icon: Icon(
            place == null
                ? Icons.place_outlined
                : Icons.edit_location_alt_outlined,
          ),
          label: Text(place == null ? 'Choose a location' : 'Change location'),
        );
        if (place == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Search location', style: theme.textTheme.labelLarge),
              const SizedBox(height: JobMateTheme.space8),
              action,
            ],
          );
        }

        final address = place.address.trim();
        final location = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.location_on_outlined,
              color: JobMateTheme.darkTeal,
            ),
            const SizedBox(width: JobMateTheme.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(place.name, style: theme.textTheme.titleMedium),
                  if (address.isNotEmpty && address != place.name.trim())
                    Text(address, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        );
        final radiusFilter = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Search radius', style: theme.textTheme.labelLarge),
            const SizedBox(height: JobMateTheme.space4),
            Wrap(
              spacing: JobMateTheme.space8,
              runSpacing: JobMateTheme.space4,
              children: [
                for (final radius in radii)
                  ChoiceChip(
                    label: Text('$radius km'),
                    selected: _radius == radius,
                    selectedColor: JobMateTheme.teal100,
                    onSelected: (_) => setState(() => _radius = radius),
                  ),
              ],
            ),
          ],
        );
        final employmentFilter = ModuleSelect(
          label: 'Employment type',
          value: _employmentType,
          options: {
            '': 'All types',
            for (final value in [
              'full_time',
              'part_time',
              'contract',
              'internship',
              'temporary',
            ])
              value: jobLabel(value),
          },
          onChanged: (value) => setState(() => _employmentType = value),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Search location', style: theme.textTheme.labelLarge),
            const SizedBox(height: JobMateTheme.space8),
            if (stacked) ...[
              location,
              const SizedBox(height: JobMateTheme.space8),
              action,
            ] else
              Row(
                children: [
                  Expanded(child: location),
                  const SizedBox(width: JobMateTheme.space16),
                  action,
                ],
              ),
            const Divider(height: JobMateTheme.space24),
            if (stacked) ...[
              radiusFilter,
              const SizedBox(height: JobMateTheme.space12),
              employmentFilter,
            ] else
              Row(
                children: [
                  Expanded(child: radiusFilter),
                  const SizedBox(width: JobMateTheme.space16),
                  SizedBox(width: 220, child: employmentFilter),
                ],
              ),
          ],
        );
      },
    ),
  );

  Widget _resultsHeader(DiscoveryPlace place, int count) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final summary = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count nearby ${count == 1 ? 'job' : 'jobs'}',
            style: theme.textTheme.titleMedium,
          ),
          Text(
            'Within $_radius km of ${place.name}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
      final toggle = SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('List')),
          ButtonSegment(value: true, label: Text('Map')),
        ],
        selected: {_showMap},
        onSelectionChanged: (selection) =>
            setState(() => _showMap = selection.single),
      );
      if (constraints.maxWidth < 480) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            summary,
            const SizedBox(height: JobMateTheme.space8),
            toggle,
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: summary),
          const SizedBox(width: JobMateTheme.space16),
          toggle,
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _repo,
    builder: (context, _) {
      final place = _place;
      final results = place != null && _repo.catalogueComplete
          ? nearbyJobResults(
              _repo.jobs,
              origin: place.coordinates,
              radiusKm: _radius,
              employmentType: _employmentType,
            )
          : const <NearbyJobResult>[];
      final selected = results
          .where((r) => r.job.id == _selectedJobId)
          .firstOrNull;
      final overlapping = selected == null
          ? const <NearbyJobResult>[]
          : results
                .where((r) => r.job.workplace == selected.job.workplace)
                .toList();

      return AppWorkspace(
        title: 'Nearby Jobs',
        path: AppRoutes.nearbyJobs,
        role: 'job_seeker',
        child: WorkspaceContent(
          maxWidth: 880,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeading(
                title: 'Nearby Jobs',
                description: 'Find jobs near a place you choose in Malaysia.',
              ),
              _searchPanel(place),
              const SizedBox(height: JobMateTheme.space16),
              if (_repo.loading || (!_repo.loaded && _repo.error == null))
                const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Loading published jobs',
                  ),
                )
              else if (_repo.error case final error?)
                ModuleState(
                  title: 'Unable to load jobs',
                  message: error,
                  action: _repo.load,
                  actionLabel: 'Retry',
                )
              else if (_repo.loaded && !_repo.catalogueComplete)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ModuleState(
                      title: 'Nearby results unavailable',
                      message: 'The full published jobs catalogue could not be verified.',
                      action: _repo.load,
                      actionLabel: 'Retry',
                    ),
                    Align(
                      child: TextButton(
                        onPressed: () => context.go(AppRoutes.browseJobs),
                        child: const Text('Browse Jobs'),
                      ),
                    ),
                  ],
                )
              else if (place == null)
                const ModuleState(
                  title: 'No location selected',
                  message: 'Choose a place to see nearby workplaces.',
                )
              else if (_repo.catalogueComplete) ...[
                _resultsHeader(place, results.length),
                const SizedBox(height: JobMateTheme.space12),
                if (_showMap) ...[
                  _map(place, results),
                  if (overlapping.length > 1) ...[
                    const SizedBox(height: JobMateTheme.space12),
                    Text(
                      'Jobs at this marker',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: JobMateTheme.space4),
                    Wrap(
                      spacing: JobMateTheme.space8,
                      runSpacing: JobMateTheme.space4,
                      children: [
                        for (final result in overlapping)
                          ChoiceChip(
                            key: ValueKey('nearby-marker-job-${result.job.id}'),
                            label: Text(
                              '${result.job.title} · ${result.job.company}',
                            ),
                            selected: result.job.id == _selectedJobId,
                            onSelected: (_) =>
                                setState(() => _selectedJobId = result.job.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: JobMateTheme.space8),
                  ],
                  if (selected != null) _card(selected),
                ],
                if (results.isEmpty)
                  const ModuleState(
                    title: 'No nearby jobs',
                    message: 'Try a larger radius or another location or employment type.',
                  ),
                if (!_showMap)
                  for (final result in results) _card(result),
              ],
            ],
          ),
        ),
      );
    },
  );
}
