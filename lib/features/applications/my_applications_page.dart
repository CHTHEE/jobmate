import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/app_workspace.dart';
import '../jobs/job_display.dart';
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
          maxWidth: 880,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Track your applications',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text('Review the status of your job applications.'),
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
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                        const SizedBox(height: 16),
                        TextField(
                          controller: search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Search job or company',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 16,
                          children: [
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
                            TextButton(
                              onPressed: clear,
                              child: const Text('Clear filters'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
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
                        : 'Try changing the filters.',
                    action: repo.applications.isEmpty
                        ? () => navigate(AppRoutes.browseJobs)
                        : clear,
                    actionLabel: repo.applications.isEmpty
                        ? 'Browse Jobs'
                        : 'Clear filters',
                  ),
                for (final application in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _ApplicationCard(
                      key: ValueKey(application.id),
                      application: application,
                      onApplication: () => navigate(
                        '${AppRoutes.applications}/${application.id}',
                      ),
                      onJob: () => navigate(
                        '${AppRoutes.browseJobs}/${application.jobId}',
                      ),
                    ),
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
      final wide = box.maxWidth >= 480 * scale;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (label, value, icon) in [
            ('All', total, Icons.description_outlined),
            ('Active', total - completed, Icons.schedule),
            ('Completed', completed, Icons.task_alt),
          ])
            SizedBox(
              width: wide ? (box.maxWidth - 16) / 3 : box.maxWidth,
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(icon, color: JobMateTheme.darkTeal, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(label)),
                      const SizedBox(width: 4),
                      Text(
                        '$value',
                        key: ValueKey('application-count-$label'),
                        style: Theme.of(context).textTheme.headlineSmall
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
    final (
      statusIcon,
      statusColor,
      statusDescription,
    ) = switch (application.status) {
      MyApplicationStatus.submitted => (
        Icons.send_outlined,
        Colors.blue.shade800,
        'Application submitted.',
      ),
      MyApplicationStatus.shortlisted => (
        Icons.bookmark_outline,
        Colors.amber.shade900,
        'The employer shortlisted your application.',
      ),
      MyApplicationStatus.interview => (
        Icons.event_available_outlined,
        Colors.deepPurple.shade700,
        'Your application reached the interview stage.',
      ),
      MyApplicationStatus.offered => (
        Icons.mail_outline,
        Colors.deepPurple.shade700,
        'Open the application to review your offer.',
      ),
      MyApplicationStatus.hired => (
        Icons.check_circle_outline,
        Colors.green.shade800,
        'The employer marked this application as hired.',
      ),
      MyApplicationStatus.rejected => (
        Icons.info_outline,
        Colors.blueGrey.shade700,
        'The employer did not move this application forward.',
      ),
      MyApplicationStatus.declined => (
        Icons.info_outline,
        Colors.blueGrey.shade700,
        'You declined the offer.',
      ),
      MyApplicationStatus.withdrawn => (
        Icons.info_outline,
        Colors.blueGrey.shade700,
        'You withdrew this application.',
      ),
    };
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          radius: 18,
          backgroundColor: JobMateTheme.teal50,
          foregroundColor: JobMateTheme.darkTeal,
          child: Icon(Icons.work_outline, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(application.jobTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                application.companyName,
                style: const TextStyle(color: JobMateTheme.body),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(statusIcon, size: 15, color: statusColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      statusDescription,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: JobMateTheme.body,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    final badge = MyApplicationStatusBadge(application.status);
    const actionPadding = WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );
    final footerTheme = theme.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: (theme.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
          padding: actionPadding,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
            .copyWith(padding: actionPadding),
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    final scale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    if (box.maxWidth < 340 * scale) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [identity, const SizedBox(height: 8), badge],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: identity),
                        const SizedBox(width: 12),
                        badge,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            decoration: const BoxDecoration(
              color: JobMateTheme.background,
              border: Border(top: BorderSide(color: JobMateTheme.divider)),
            ),
            child: Theme(
              data: footerTheme,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 14,
                        color: JobMateTheme.body,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Applied: ${jobDate(application.appliedAt)}',
                          style: const TextStyle(color: JobMateTheme.body),
                        ),
                      ),
                    ],
                  ),
                  FilledButton(
                    onPressed: onApplication,
                    child: const Text('View Application'),
                  ),
                  OutlinedButton(
                    onPressed: onJob,
                    child: const Text('View Job'),
                  ),
                  ChatApplicationButton(
                    key: ValueKey('chat:${application.id}'),
                    applicationId: application.id,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
