import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/app_workspace.dart';
import '../jobs/job_display.dart';
import '../chat/chat_application_button.dart';
import 'module2_widgets.dart';
import 'my_applications_repository.dart';
import 'hiring_membership_panel.dart';
import 'hiring_membership_status.dart';

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
    if (confirming ||
        repo.responding ||
        repo.loading ||
        !action.allowed(application.status)) {
      return;
    }
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
              action.allowed(application.status) &&
              !current.responding &&
              !current.loading;
          return AlertDialog(
            title: Text(available ? '${action.label}?' : 'Application changed'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: !available
                    ? [
                        const Text(
                          'Close this dialog and refresh your application.',
                        ),
                      ]
                    : [
                        Text(application.jobTitle),
                        Text(application.companyName),
                        const SizedBox(height: 12),
                        Text(action.confirmationMessage),
                      ],
              ),
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
          maxWidth: 1040,
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
              else
                _details(context, application),
            ],
          ),
        ),
      );
    },
  );

  Widget _details(BuildContext context, MyJobApplication application) {
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summaryCard(context, application),
        if (application.status == MyApplicationStatus.hired &&
            widget.source is HiringMembershipStatusSource) ...[
          const SizedBox(height: 16),
          HiringMembershipPanel(
            key: ValueKey(
              '${repo.sessionVersion}:${repo.applicationReadVersion}:${application.id}',
            ),
            source: widget.source as HiringMembershipStatusSource,
            applicationId: application.id,
          ),
        ],
      ],
    );
    final timeline = _timeline(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 760 * scale.clamp(1.0, 1.25)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [summary, const SizedBox(height: 16), timeline],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: summary),
            const SizedBox(width: 24),
            Expanded(flex: 2, child: timeline),
          ],
        );
      },
    );
  }

  Widget _summaryCard(BuildContext context, MyJobApplication application) {
    final theme = Theme.of(context);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          application.jobTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          application.companyName,
          style: theme.textTheme.bodyMedium?.copyWith(color: JobMateTheme.body),
        ),
      ],
    );
    final badge = MyApplicationStatusBadge(
      application.status,
      label: statusLabel(application.status),
    );
    final actions = ApplicationResponseAction.values.where(
      (action) => action.allowed(application.status),
    );
    VoidCallback? onResponse(ApplicationResponseAction action) =>
        repo.responding || confirming
        ? null
        : () => respond(application, action);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                if (constraints.maxWidth < 360 * scale) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 8), badge],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 16),
                    badge,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _metadata(
                  Icons.event_outlined,
                  'Applied: ${dateTime(context, application.appliedAt)}',
                ),
                _metadata(
                  Icons.description_outlined,
                  application.resumeId != null
                      ? 'Resume attached'
                      : 'No resume attached',
                ),
              ],
            ),
            if (application.status.lifecycleExplanation
                case final explanation?) ...[
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: JobMateTheme.teal50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(explanation),
                ),
              ),
            ],
            if (application.coverNote?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 16),
              Text('Cover note', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(application.coverNote!),
            ],
            if (repo.responding) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const Text('Updating application…'),
            ],
            if (actions.any(
              (action) => action != ApplicationResponseAction.withdraw,
            )) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in actions)
                    if (action == ApplicationResponseAction.acceptOffer)
                      FilledButton(
                        onPressed: onResponse(action),
                        child: Text(action.label),
                      )
                    else if (action == ApplicationResponseAction.declineOffer)
                      OutlinedButton(
                        onPressed: onResponse(action),
                        child: Text(action.label),
                      ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: repo.responding
                      ? null
                      : () => navigate(
                          '${AppRoutes.browseJobs}/${application.jobId}',
                        ),
                  icon: const Icon(Icons.work_outline),
                  label: const Text('View Job'),
                ),
                ChatApplicationButton(
                  key: ValueKey('chat:${application.id}'),
                  applicationId: application.id,
                  enabled: !repo.responding && !confirming,
                ),
                if (actions.contains(ApplicationResponseAction.withdraw))
                  TextButton(
                    onPressed: onResponse(ApplicationResponseAction.withdraw),
                    child: Text(ApplicationResponseAction.withdraw.label),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metadata(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: JobMateTheme.body),
      const SizedBox(width: 8),
      Flexible(
        child: Text(label, style: const TextStyle(color: JobMateTheme.body)),
      ),
    ],
  );

  Widget _timeline(BuildContext context) => WorkspaceCard(
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
              for (final (index, event) in repo.events.indexed)
                IntrinsicHeight(
                  key: ValueKey(event.id),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 16,
                        child: Column(
                          children: [
                            const SizedBox(height: 4),
                            const Icon(
                              Icons.circle,
                              size: 12,
                              color: JobMateTheme.darkTeal,
                            ),
                            if (index < repo.events.length - 1)
                              const Expanded(
                                child: VerticalDivider(
                                  width: 16,
                                  thickness: 1,
                                  color: JobMateTheme.divider,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: index < repo.events.length - 1 ? 12 : 0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                statusLabel(event.newStatus),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                dateTime(context, event.changedAt),
                                style: const TextStyle(
                                  color: JobMateTheme.body,
                                ),
                              ),
                              if (event.changedByName?.trim().isNotEmpty ==
                                  true)
                                Text(event.changedByName!),
                              if (event.note?.trim().isNotEmpty == true)
                                Text(event.note!),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
  );
}
