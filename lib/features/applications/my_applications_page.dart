import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/expandable_filter_bar.dart';
import '../../shared/widgets/responsive_layout.dart';
import 'my_application_presentation.dart';
import '../chat/chat_application_button.dart';
import 'module2_widgets.dart';
import 'my_applications_repository.dart';

class MyApplicationsPage extends StatefulWidget {
  const MyApplicationsPage({super.key, required this.repository});
  final MyApplicationsRepository repository;
  @override
  State<MyApplicationsPage> createState() => _MyApplicationsPageState();
}

class _MyApplicationsPageState extends State<MyApplicationsPage> {
  final search = TextEditingController();
  String tab = 'All', status = '', sort = 'Newest';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.repository.load();
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> navigate(String path) async {
    if (path == AppRoutes.home) {
      context.go(path);
      return;
    }
    await context.push<void>(path);
    if (mounted) await widget.repository.load();
  }

  void clear() => setState(() {
    search.clear();
    tab = 'All';
    status = '';
    sort = 'Newest';
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.repository,
    builder: (context, _) {
      final repo = widget.repository;
      final rows = repo.search(
        query: search.text,
        tab: tab,
        status: status,
        sort: sort,
      );
      return AppWorkspace(
        title: 'My Applications',
        path: AppRoutes.applications,
        role: 'job_seeker',
        onNavigate: navigate,
        actions: [
          IconButton(
            tooltip: 'Refresh applications',
            onPressed: repo.loading ? null : repo.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: WorkspaceContent(
          maxWidth: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'My Applications',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Track and manage your job applications in one place.',
              ),
              const SizedBox(height: 24),
              if (repo.loading || (!repo.loaded && repo.error == null))
                const Center(child: CircularProgressIndicator())
              else if (repo.error != null)
                ModuleState(
                  title: 'Unable to load applications',
                  message: repo.error!,
                  action: repo.load,
                  actionLabel: 'Retry',
                )
              else ...[
                _ApplicationCounts(
                  total: repo.applications.length,
                  completed: repo.applications
                      .where((a) => a.status.completed)
                      .length,
                ),
                const SizedBox(height: 16),
                ExpandableFilterBar(
                  search: TextField(
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Search job or company',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  activeCount: [
                    tab != 'All',
                    status.isNotEmpty,
                    sort != 'Newest',
                  ].where((value) => value).length,
                  onClear: clear,
                  filters: [
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
                    ModuleSelect(
                      label: 'Application status',
                      value: status,
                      options: {
                        '': 'All statuses',
                        for (final s in MyApplicationStatus.values)
                          s.name: s.label,
                      },
                      onChanged: (v) => setState(() => status = v),
                    ),
                    ModuleSelect(
                      label: 'Sort',
                      value: sort,
                      options: {'Newest': 'Newest', 'Oldest': 'Oldest'},
                      onChanged: (v) => setState(() => sort = v),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Your applications',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${rows.length} matching ${rows.length == 1 ? 'application' : 'applications'}',
                      style: const TextStyle(color: JobMateTheme.body),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (rows.isEmpty)
                  ModuleState(
                    title: repo.applications.isEmpty
                        ? 'No applications yet'
                        : 'No applications found',
                    message: repo.applications.isEmpty
                        ? 'Applications you submit will appear here.'
                        : 'Try another search or clear the filters.',
                    action: repo.applications.isEmpty
                        ? () => navigate(AppRoutes.browseJobs)
                        : clear,
                    actionLabel: repo.applications.isEmpty
                        ? 'Browse Jobs'
                        : 'Clear filters',
                  ),
                ResponsiveGrid(
                  minItemWidth: 345,
                  maxColumns: 3,
                  equalRowHeight: true,
                  reserveEmptyColumns: true,
                  children: [
                    for (final application in rows)
                      _ApplicationCard(
                        key: ValueKey(application.id),
                        application: application,
                        onApplication: () => navigate(
                          '${AppRoutes.applications}/${application.id}',
                        ),
                        onJob: () => navigate(
                          '${AppRoutes.browseJobs}/${application.jobId}',
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _ApplicationCounts extends StatelessWidget {
  const _ApplicationCounts({required this.total, required this.completed});

  final int total;
  final int completed;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final wide = box.maxWidth >= 565 * scale;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (label, value, icon) in [
            ('All', total, LucideIcons.files),
            ('Active', total - completed, LucideIcons.clock),
            ('Completed', completed, LucideIcons.circleCheck),
          ])
            SizedBox(
              width: wide ? (box.maxWidth - 16) / 3 : box.maxWidth,
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      ApplicationIconTile(icon),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label == 'All' ? 'All applications' : label,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$value',
                        key: ValueKey('application-count-$label'),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: JobMateTheme.darkTeal,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    super.key,
    required this.application,
    required this.onApplication,
    required this.onJob,
  });

  final MyJobApplication application;
  final VoidCallback onApplication;
  final VoidCallback onJob;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MyApplicationIdentity(
                  application: application,
                  titleStyle: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  applicationStatusDescription(application.status),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: JobMateTheme.body,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      LucideIcons.calendar,
                      size: 16,
                      color: JobMateTheme.body,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Applied ${applicationDate(application.appliedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: JobMateTheme.body,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(height: 20),
                FilledButton(
                  onPressed: onApplication,
                  child: const Text('View Application'),
                ),
                const SizedBox(height: 8),
                _secondaryActions(context),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _secondaryActions(BuildContext context) {
    final theme = Theme.of(context).outlinedButtonTheme;
    final job = OutlinedButton.icon(
      onPressed: onJob,
      icon: const Icon(LucideIcons.briefcase, size: 16),
      label: const Text('View Job'),
    );
    final message = ChatApplicationButton(
      key: ValueKey('chat:${application.id}'),
      applicationId: application.id,
      fullWidth: true,
      icon: LucideIcons.messageCircle,
    );
    return OutlinedButtonTheme(
      data: OutlinedButtonThemeData(
        style: (theme.style ?? const ButtonStyle()).copyWith(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          if (constraints.maxWidth < 300 * scale) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [job, const SizedBox(height: 8), message],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: job),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: message),
            ],
          );
        },
      ),
    );
  }
}
