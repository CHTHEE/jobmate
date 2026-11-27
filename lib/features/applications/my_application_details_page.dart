import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../chat/chat_application_button.dart';
import 'compensation_offer.dart';
import 'module2_widgets.dart';
import 'my_application_presentation.dart';
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
              (action != ApplicationResponseAction.acceptOffer ||
                  current.canAcceptOffer) &&
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
                        if (action == ApplicationResponseAction.acceptOffer &&
                            p03CompensationOffersEnabled &&
                            current.compensationOffer != null) ...[
                          Text(
                            'Offer version ${current.compensationOffer!.version}: ${current.compensationOffer!.salaryRange}',
                          ),
                          const SizedBox(height: 8),
                        ],
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
            : IconButton(
                tooltip: 'Back to Applications',
                icon: const BackButtonIcon(),
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
          centered: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (kIsWeb)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: repo.responding
                        ? null
                        : () => moduleBack(context, AppRoutes.applications),
                    icon: const Icon(LucideIcons.arrowLeft, size: 18),
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
    final timeline = _timeline(context);
    final decisions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (p03CompensationOffersEnabled &&
            (application.status == MyApplicationStatus.offered ||
                application.status == MyApplicationStatus.hired) &&
            (repo.offerLoading || repo.compensationOffer != null)) ...[
          _compensationOfferCard(context),
          const SizedBox(height: 16),
        ],
        _actions(context, application),
      ],
    );
    return Column(
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
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            if (constraints.maxWidth >= 696 * scale) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: timeline),
                  const SizedBox(width: 16),
                  Expanded(child: decisions),
                ],
              );
            }
            final offered = application.status == MyApplicationStatus.offered;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                offered ? decisions : timeline,
                const SizedBox(height: 16),
                offered ? timeline : decisions,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _summaryCard(BuildContext context, MyJobApplication application) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MyApplicationIdentity(
              application: application,
              titleStyle: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            _statusPanel(context, application.status),
            const SizedBox(height: 16),
            Text('Application information', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ResponsiveGrid(
              maxColumns: 2,
              children: [
                _metadata(
                  context,
                  'Applied on',
                  applicationDateTime(context, application.appliedAt),
                ),
                _metadata(
                  context,
                  'Resume',
                  application.resumeId != null
                      ? 'Resume attached'
                      : 'No resume attached',
                ),
              ],
            ),
            if (application.coverNote?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 16),
              Text('Cover note', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(application.coverNote!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, MyJobApplication application) {
    final hired = application.status == MyApplicationStatus.hired;
    final viewJob = OutlinedButton.icon(
      onPressed: repo.responding
          ? null
          : () => navigate('${AppRoutes.browseJobs}/${application.jobId}'),
      icon: const Icon(LucideIcons.briefcase, size: 18),
      label: const Text('View Job'),
    );
    final message = ChatApplicationButton(
      key: ValueKey('chat:${application.id}'),
      applicationId: application.id,
      enabled: !repo.responding && !confirming,
      fullWidth: hired,
      filled: hired,
      icon: LucideIcons.messageCircle,
    );
    final offerNotice = _offerNotice(application.status);

    final actions = ApplicationResponseAction.values.where(
      (action) => action.allowed(application.status),
    );
    VoidCallback? onResponse(ApplicationResponseAction action) =>
        repo.responding ||
            confirming ||
            action == ApplicationResponseAction.acceptOffer &&
                !repo.canAcceptOffer
        ? null
        : () => respond(application, action);

    return WorkspaceCard(
      title: 'Application actions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (repo.responding) ...[
            const LinearProgressIndicator(),
            const Text('Updating application…'),
          ],
          if (offerNotice != null) ...[
            Text(offerNotice),
            const SizedBox(height: 12),
          ],
          if (actions.any(
            (action) => action != ApplicationResponseAction.withdraw,
          )) ...[
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
            const SizedBox(height: 12),
          ],
          if (hired) ...[
            message,
            const SizedBox(height: 8),
            viewJob,
            const SizedBox(height: 12),
            Text(
              'Ending a hired arrangement is currently unavailable.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                viewJob,
                message,
                if (actions.contains(ApplicationResponseAction.withdraw))
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: onResponse(ApplicationResponseAction.withdraw),
                    child: Text(ApplicationResponseAction.withdraw.label),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _statusPanel(BuildContext context, MyApplicationStatus status) {
    final (icon, color) = switch (status) {
      MyApplicationStatus.submitted => (LucideIcons.send, Colors.blue.shade800),
      MyApplicationStatus.shortlisted => (
        LucideIcons.bookmark,
        Colors.amber.shade900,
      ),
      MyApplicationStatus.interview => (
        LucideIcons.calendar,
        JobMateTheme.darkTeal,
      ),
      MyApplicationStatus.offered => (
        LucideIcons.mail,
        Colors.deepPurple.shade700,
      ),
      MyApplicationStatus.hired => (
        LucideIcons.circleCheck,
        Colors.green.shade800,
      ),
      MyApplicationStatus.rejected || MyApplicationStatus.declined => (
        LucideIcons.circleX,
        Colors.red.shade800,
      ),
      MyApplicationStatus.withdrawn => (LucideIcons.info, JobMateTheme.body),
    };
    final hired = status == MyApplicationStatus.hired;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(JobMateTheme.controlRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hired) ...[
                    Text(
                      "You've been hired!",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    hired
                        ? 'Manage any assigned shifts and attendance records in My Work. Withdrawal and offer decline are no longer available.'
                        : status.lifecycleExplanation ??
                              applicationStatusDescription(status),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metadata(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: JobMateTheme.body),
      ),
      const SizedBox(height: 4),
      Text(value),
    ],
  );

  String? _offerNotice(MyApplicationStatus status) {
    if (status != MyApplicationStatus.offered &&
        status != MyApplicationStatus.hired) {
      return null;
    }
    if (!p03CompensationOffersEnabled) {
      if (status != MyApplicationStatus.offered) return null;
      if (repo.offerLoading) return 'Checking Offer availability…';
      if (repo.offerError case final error?) return error;
      return repo.compensationOffer == null
          ? null
          : 'Versioned Offer acceptance is currently unavailable.';
    }
    if (repo.offerLoading) return null;
    if (repo.offerError case final error?) return error;
    if (repo.compensationOffer != null) return null;
    return 'This legacy offer has no recorded compensation terms for Payment Handling.';
  }

  Widget _compensationOfferCard(BuildContext context) {
    final offer = repo.compensationOffer;
    return WorkspaceCard(
      title: 'Compensation offer',
      leading: const ApplicationIconTile(LucideIcons.wallet),
      child: offer == null
          ? const LinearProgressIndicator(
              semanticsLabel: 'Loading compensation offer',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: JobMateTheme.teal50,
                    borderRadius: BorderRadius.circular(
                      JobMateTheme.controlRadius,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          applicationOfferAmount(offer),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: JobMateTheme.teal800,
                              ),
                        ),
                        Text(applicationOfferPeriod(offer.salaryPeriod)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _metadata(context, 'Offer version', 'Version ${offer.version}'),
                const SizedBox(height: 8),
                _metadata(
                  context,
                  'Issued on',
                  applicationDateTime(context, offer.issuedAt),
                ),
                if (repo.source is! ExactVersionCompensationOfferSource) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Acceptance is unavailable while the separate hiring-membership workflow is active.',
                  ),
                ],
              ],
            ),
    );
  }

  Widget _timeline(BuildContext context) {
    final events = repo.events;
    return WorkspaceCard(
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
          : events.isEmpty
          ? const Text('No status history available.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, event) in events.indexed)
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
                              Icon(
                                Icons.circle,
                                size: 12,
                                color: index == events.length - 1
                                    ? JobMateTheme.darkTeal
                                    : JobMateTheme.border,
                              ),
                              if (index < events.length - 1)
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
                              bottom: index < events.length - 1 ? 12 : 0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.newStatus.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (index == events.length - 1)
                                  Text(
                                    'Latest',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: JobMateTheme.darkTeal,
                                        ),
                                  ),
                                Text(
                                  applicationDateTime(context, event.changedAt),
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
}
