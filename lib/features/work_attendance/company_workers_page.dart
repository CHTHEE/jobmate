import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../applications/module2_widgets.dart';
import 'company_workers_repository.dart';
import 'work_assignment_creation_repository.dart';

class CompanyWorkersPage extends StatefulWidget {
  const CompanyWorkersPage({super.key, this.repository});

  /// The page owns only its default repository; injected repositories stay owned
  /// by their caller, matching the existing Module 4 page conventions.
  final CompanyWorkersRepository? repository;

  @override
  State<CompanyWorkersPage> createState() => _CompanyWorkersPageState();
}

class _CompanyWorkersPageState extends State<CompanyWorkersPage> {
  late CompanyWorkersRepository _repository;
  final _search = TextEditingController();
  final _countInfo = GlobalKey<TooltipState>();
  String _job = '';
  String? _actor;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _repository =
        widget.repository ??
        CompanyWorkersRepository(
          SupabaseWorkAssignmentCreationSource(Supabase.instance.client),
        );
    _actor = _repository.source.userId;
    _repository.addListener(_accountChanged);
    _repository.load();
  }

  void _accountChanged() {
    if (_actor != _repository.source.userId) {
      _actor = _repository.source.userId;
      _search.clear();
      _job = '';
    }
  }

  @override
  void didUpdateWidget(covariant CompanyWorkersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _repository.removeListener(_accountChanged);
      if (oldWidget.repository == null) _repository.dispose();
      _search.clear();
      _job = '';
      _attach();
    }
  }

  @override
  void dispose() {
    _repository.removeListener(_accountChanged);
    if (widget.repository == null) _repository.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _repository,
    builder: (context, _) {
      final workers = _repository.workers;
      final jobs = {for (final worker in workers) ...worker.jobs};
      final query = _search.text.trim().toLowerCase();
      final visible = workers
          .where(
            (worker) =>
                (_job.isEmpty || worker.jobs.containsKey(_job)) &&
                (query.isEmpty ||
                    worker.name.toLowerCase().contains(query) ||
                    worker.jobs.values.any(
                      (title) => title.toLowerCase().contains(query),
                    )),
          )
          .toList();
      return AppWorkspace(
        title: 'Company Workers',
        role: 'employer',
        path: AppRoutes.workers,
        actions: [
          IconButton(
            tooltip: 'Refresh company workers',
            onPressed: _repository.loading ? null : _repository.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: WorkspaceContent(
          maxWidth: 1100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Company Workers',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('Your hired team, their jobs and verified work.'),
              const SizedBox(height: 16),
              if (_repository.loading)
                const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Loading company workers',
                  ),
                )
              else if (_repository.error != null)
                Semantics(
                  liveRegion: true,
                  child: ModuleState(
                    title: 'Company workers unavailable',
                    message: _repository.error!,
                    action: _repository.load,
                    actionLabel: 'Retry',
                  ),
                )
              else ...[
                if (_repository.companyName != null) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.business_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _repository.companyName!,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                _WorkersOverview(
                  workers: workers,
                  countsAvailable: _repository.countsAvailable,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Tooltip(
                    key: _countInfo,
                    message: 'Counts cover all returned shifts for listed hired applications, including cancelled shifts. Verified shifts use the saved verification state. Totals do not change with filters. A dash means complete shift counts are unavailable.',
                    child: TextButton.icon(
                      onPressed: () =>
                          _countInfo.currentState?.ensureTooltipVisible(),
                      icon: const Icon(Icons.info_outline, size: 16),
                      label: const Text('About shift counts'),
                    ),
                  ),
                ),
                if (!_repository.countsAvailable && workers.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Shift counts unavailable. Refresh to try again.',
                    ),
                  ),
                const SizedBox(height: 12),
                if (workers.isEmpty)
                  const _WorkersEmptyState(
                    title: 'No hired workers yet',
                    message: 'Workers will appear here once they are hired through your company jobs.',
                  )
                else ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final search = TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Search workers or jobs',
                          prefixIcon: Icon(Icons.search),
                        ),
                      );
                      final showJob = jobs.length > 1 || _job.isNotEmpty;
                      final job = DropdownButtonFormField<String>(
                        key: ValueKey(_job),
                        initialValue: _job,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Job'),
                        items:
                            {
                                  '': 'All hired jobs',
                                  ...jobs,
                                  if (_job.isNotEmpty &&
                                      !jobs.containsKey(_job))
                                    _job:
                                        'Previously selected job (unavailable)',
                                }.entries
                                .map(
                                  (entry) => DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(
                                      entry.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _job = value);
                        },
                      );
                      if (constraints.maxWidth >= 650) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 2, child: search),
                            if (showJob) ...[
                              const SizedBox(width: 12),
                              Expanded(child: job),
                            ],
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          search,
                          if (showJob) ...[const SizedBox(height: 12), job],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Showing ${visible.length} of ${workers.length} hired workers',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _search.clear();
                          _job = '';
                        }),
                        icon: const Icon(
                          Icons.filter_alt_off_outlined,
                          size: 18,
                        ),
                        label: const Text('Clear filters'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (visible.isEmpty)
                    const _WorkersEmptyState(
                      title: 'No matching workers',
                      message:
                          'Try another worker name or job, or clear filters.',
                    ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1000
                          ? 3
                          : constraints.maxWidth >= 650
                          ? 2
                          : 1;
                      final width =
                          (constraints.maxWidth - 16 * (columns - 1)) / columns;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final worker in visible)
                            SizedBox(
                              width: width,
                              child: _WorkerProfileCard(
                                key: ValueKey(worker.id),
                                worker: worker,
                                onViewAssignments: () =>
                                    context.go(AppRoutes.workVerification),
                              ),
                            ),
                        ],
                      );
                    },
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

class _WorkersOverview extends StatelessWidget {
  const _WorkersOverview({
    required this.workers,
    required this.countsAvailable,
  });
  final List<CompanyWorker> workers;
  final bool countsAvailable;

  @override
  Widget build(BuildContext context) {
    final reliable =
        countsAvailable &&
        workers.every(
          (w) => w.assignedShifts != null && w.verifiedShifts != null,
        );
    final stats = [
      ('Hired Workers', '${workers.length}', Icons.groups_outlined),
      (
        'Total Assigned Shifts',
        reliable
            ? '${workers.fold<int>(0, (n, w) => n + w.assignedShifts!)}'
            : '\u2014',
        Icons.calendar_month_outlined,
      ),
      (
        'Verified Shifts',
        reliable
            ? '${workers.fold<int>(0, (n, w) => n + w.verifiedShifts!)}'
            : '\u2014',
        Icons.verified_outlined,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 600
            ? constraints.maxWidth
            : (constraints.maxWidth - 24) / 3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final stat in stats)
              SizedBox(
                width: width,
                child: Container(
                  key: ValueKey('summary-${stat.$1}'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        stat.$3,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              label: stat.$2 == '\u2014'
                                  ? '${stat.$1}: unavailable'
                                  : '${stat.$1}: ${stat.$2}',
                              excludeSemantics: true,
                              child: Text(
                                stat.$2,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                            ),
                            Text(stat.$1),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WorkerProfileCard extends StatefulWidget {
  const _WorkerProfileCard({
    super.key,
    required this.worker,
    required this.onViewAssignments,
  });
  final CompanyWorker worker;
  final VoidCallback onViewAssignments;
  @override
  State<_WorkerProfileCard> createState() => _WorkerProfileCardState();
}

class _WorkerProfileCardState extends State<_WorkerProfileCard> {
  bool _allJobs = false;
  @override
  Widget build(BuildContext context) {
    final worker = widget.worker;
    final colors = Theme.of(context).colorScheme;
    final initials = worker.name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((part) => part.characters.first)
        .join()
        .toUpperCase();
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    foregroundColor: colors.onPrimaryContainer,
                    child: Text(initials),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        worker.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Hired',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.primary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${worker.jobs.length} hired ${worker.jobs.length == 1 ? 'job' : 'jobs'}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final job in worker.jobs.values.take(
                  _allJobs ? worker.jobs.length : 2,
                ))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      job,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            if (worker.jobs.length > 2)
              Semantics(
                expanded: _allJobs,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _allJobs = !_allJobs),
                    child: Text(
                      _allJobs
                          ? 'Show fewer jobs'
                          : '+${worker.jobs.length - 2} more',
                    ),
                  ),
                ),
              ),
            if (worker.assignedShifts != null &&
                worker.verifiedShifts != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    _WorkerStat(
                      label: 'Assigned Shifts',
                      count: worker.assignedShifts!,
                    ),
                    _WorkerStat(
                      label: 'Verified Shifts',
                      count: worker.verifiedShifts!,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: widget.onViewAssignments,
              icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
              label: const Text('View Work Assignments'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerStat extends StatelessWidget {
  const _WorkerStat({required this.label, required this.count});
  final String label;
  final int count;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $count',
    excludeSemantics: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$count', style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

class _WorkersEmptyState extends StatelessWidget {
  const _WorkersEmptyState({required this.title, required this.message});
  final String title, message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        Icon(
          Icons.people_outline,
          size: 36,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}
