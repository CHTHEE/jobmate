import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
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
          maxWidth: 672,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Track your applications',
                style: Theme.of(context).textTheme.headlineMedium,
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
                StatGrid(
                  children: [
                    for (final item in <(String, int)>[
                      ('All', repo.applications.length),
                      (
                        'Active',
                        repo.applications
                            .where((a) => !a.status.completed)
                            .length,
                      ),
                      (
                        'Completed',
                        repo.applications
                            .where((a) => a.status.completed)
                            .length,
                      ),
                    ])
                      StatTile(
                        label: item.$1,
                        value: '${item.$2}',
                        icon: item.$1 == 'All'
                            ? Icons.description_outlined
                            : item.$1 == 'Active'
                            ? Icons.schedule
                            : Icons.task_alt,
                        note: 'Your applications',
                      ),
                  ],
                ),
                const SizedBox(height: 20),
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
                const SizedBox(height: 20),
                Text('${rows.length} matching applications'),
                const SizedBox(height: 16),
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
                    child: WorkspaceCard(
                      key: ValueKey(application.id),
                      leading: const CircleAvatar(
                        radius: 20,
                        child: Icon(Icons.work_outline, size: 20),
                      ),
                      title: application.jobTitle,
                      subtitle: application.companyName,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: MyApplicationStatusBadge(application.status),
                          ),
                          Text('Applied: ${jobDate(application.appliedAt)}'),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              OutlinedButton(
                                onPressed: () => navigate(
                                  '${AppRoutes.applications}/${application.id}',
                                ),
                                child: const Text('View Application'),
                              ),
                              OutlinedButton(
                                onPressed: () => navigate(
                                  '${AppRoutes.browseJobs}/${application.jobId}',
                                ),
                                child: const Text('View Job'),
                              ),
                              ChatApplicationButton(
                                key: ValueKey('chat:${application.id}'),
                                applicationId: application.id,
                              ),
                            ],
                          ),
                        ],
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
