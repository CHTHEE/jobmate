import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../jobs/job_display.dart';
import 'module2_widgets.dart';
import 'my_applications_repository.dart';

class MyApplicationDetailsPage extends StatefulWidget {
  const MyApplicationDetailsPage({
    super.key,
    required this.applicationId,
    required this.source,
  });
  final String applicationId;
  final MyApplicationsSource source;
  @override
  State<MyApplicationDetailsPage> createState() =>
      _MyApplicationDetailsPageState();
}

class _MyApplicationDetailsPageState extends State<MyApplicationDetailsPage> {
  late MyApplicationDetailsRepository repo;
  bool confirming = false;

  Future<void> respond(
    MyJobApplication application,
    ApplicationResponseAction action,
  ) async {
    if (confirming || repo.responding) return;
    final current = repo;
    final version = current.sessionVersion;
    setState(() => confirming = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: current,
        builder: (context, _) {
          final available =
              current.currentSession(version) &&
              current.application?.id == application.id &&
              current.application?.status == application.status &&
              !current.loading;
          return AlertDialog(
            title: Text(available ? '${action.label}?' : 'Application changed'),
            content: Text(
              !available
                  ? 'Close this dialog and refresh your application.'
                  : switch (action) {
                      ApplicationResponseAction.acceptOffer => 'Accepting this offer changes your application status to Hired.',
                      ApplicationResponseAction.declineOffer => 'Declining this offer changes your application status to Declined.',
                      ApplicationResponseAction.withdraw => 'Withdrawal is final and cannot be undone through the current workflow.',
                    },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: available
                    ? () => Navigator.pop(context, true)
                    : null,
                child: Text('Confirm ${action.label}'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
    setState(() => confirming = false);
    if (confirmed != true ||
        !identical(repo, current) ||
        !current.currentSession(version)) {
      return;
    }
    try {
      await current.respond(application, action.wireName);
    } on StateError {
      if (mounted &&
          identical(repo, current) &&
          current.currentSession(version)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This action is unavailable. Refresh the application.',
            ),
          ),
        );
      }
    }
  }

  void initialize() {
    repo = MyApplicationDetailsRepository(widget.source, widget.applicationId);
    final current = repo;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(repo, current)) current.load();
    });
  }

  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void didUpdateWidget(covariant MyApplicationDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.applicationId != widget.applicationId ||
        oldWidget.source != widget.source) {
      repo.dispose();
      initialize();
    }
  }

  @override
  void dispose() {
    repo.dispose();
    super.dispose();
  }

  Future<void> navigate(String path) async {
    if (path == AppRoutes.home) {
      context.go(path);
      return;
    }
    await context.push<void>(path);
    if (mounted) await repo.load();
  }

  String statusLabel(MyApplicationStatus status) => status.label;
  String dateTime(BuildContext context, DateTime value) {
    final local = value.toLocal();
    return '${jobDate(local)} • ${TimeOfDay.fromDateTime(local).format(context)}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final application = repo.application;
      return AppWorkspace(
        title: 'Application Details',
        path: AppRoutes.applications,
        role: 'job_seeker',
        onNavigate: navigate,
        navigationLocked: repo.responding,
        leading: kIsWeb
            ? null
            : BackButton(
                onPressed: repo.responding
                    ? null
                    : () => moduleBack(context, AppRoutes.applications),
              ),
        actions: [
          IconButton(
            tooltip: 'Refresh application',
            onPressed: repo.loading || repo.historyLoading || repo.responding
                ? null
                : repo.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: WorkspaceContent(
          maxWidth: 448,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: repo.responding
                      ? null
                      : () => moduleBack(context, AppRoutes.applications),
                  icon: kIsWeb ? null : const Icon(Icons.arrow_back),
                  label: const Text('Back to Applications'),
                ),
              ),
              if (repo.responseError != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    repo.responseError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (repo.loading)
                const Center(child: CircularProgressIndicator())
              else if (repo.error != null)
                ModuleState(
                  title: 'Unable to load application',
                  message: repo.error!,
                  action: repo.load,
                  actionLabel: 'Retry',
                )
              else if (application == null)
                const ModuleState(
                  title: 'Application unavailable',
                  message: 'This application is unavailable or does not belong to your account.',
                )
              else ...[
                WorkspaceCard(
                  title: application.jobTitle,
                  subtitle: application.companyName,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SelectableText('Application ID: ${application.id}'),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: MyApplicationStatusBadge(
                          application.status,
                          label: statusLabel(application.status),
                        ),
                      ),
                      Text(
                        'Applied: ${dateTime(context, application.appliedAt)}',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        application.resumeId != null
                            ? 'Resume attached'
                            : 'No resume attached',
                      ),
                      if (application.coverNote?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Cover note',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(application.coverNote!),
                      ],
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: repo.responding
                              ? null
                              : () => navigate(
                                  '${AppRoutes.browseJobs}/${application.jobId}',
                                ),
                          child: const Text('View Job'),
                        ),
                      ),
                      if (repo.responding) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                        const Text('Updating application…'),
                      ],
                      if (ApplicationResponseAction.values.any(
                        (a) => a.allowed(application.status),
                      )) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final action
                                in ApplicationResponseAction.values.where(
                                  (a) => a.allowed(application.status),
                                ))
                              OutlinedButton(
                                onPressed: repo.responding || confirming
                                    ? null
                                    : () => respond(application, action),
                                child: Text(action.label),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                WorkspaceCard(
                  title: 'Application timeline',
                  child: repo.historyLoading
                      ? const Column(
                          children: [
                            LinearProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Loading status history…'),
                          ],
                        )
                      : repo.historyError != null
                      ? ModuleState(
                          title: 'Unable to load status history',
                          message: repo.historyError!,
                          action: repo.loadHistory,
                          actionLabel: 'Retry history',
                        )
                      : repo.events.isEmpty
                      ? const Text('No status history available.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final event in repo.events)
                              ListTile(
                                key: ValueKey(event.id),
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.check_circle_outline),
                                title: Text(statusLabel(event.newStatus)),
                                subtitle: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(dateTime(context, event.changedAt)),
                                    if (event.changedByName
                                            ?.trim()
                                            .isNotEmpty ==
                                        true)
                                      Text(event.changedByName!),
                                    if (event.note?.trim().isNotEmpty == true)
                                      Text(event.note!),
                                  ],
                                ),
                              ),
                          ],
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
