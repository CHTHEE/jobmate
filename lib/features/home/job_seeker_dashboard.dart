import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../applications/job_marketplace_format.dart';
import '../applications/module2_repository.dart';
import '../applications/module2_widgets.dart';
import '../applications/my_applications_repository.dart';
import '../jobs/job_display.dart';
import '../phase4/reputation_gateway.dart';
import '../profile/job_seeker_profile_sections.dart';
import '../recommendations/job_matching.dart';
import '../work_attendance/work_attendance_lifecycle.dart';
import '../work_attendance/work_attendance_repository.dart';
import '../work_attendance/work_shift_ui.dart';

/// The dashboard owns these read repositories for the lifetime of one account.
class JobSeekerDashboardData {
  JobSeekerDashboardData({
    required this.applications,
    required this.jobs,
    required this.work,
    required this.loadProfile,
    required this.loadReputation,
  });

  factory JobSeekerDashboardData.forClient(SupabaseClient client) =>
      JobSeekerDashboardData(
        applications: MyApplicationsRepository(
          SupabaseMyApplicationsSource(client),
          verifyCompleteness: true,
        ),
        jobs: PublishedJobsRepository(
          SupabasePublishedJobsSource(client),
          requirePublished: true,
        ),
        work: WorkAttendanceRepository(SupabaseWorkAttendanceSource(client)),
        loadProfile: (id) =>
            SupabaseJobSeekerProfileRepository(client)
                .load(id, matchingOnly: true),
        loadReputation: SupabaseReputationGateway(client).workerSummary,
      );

  final MyApplicationsRepository applications;
  final PublishedJobsRepository jobs;
  final WorkAttendanceRepository work;
  final Future<JobSeekerProfileData> Function(String) loadProfile;
  final Future<Map<String, dynamic>> Function() loadReputation;

  void dispose() {
    applications.dispose();
    jobs.dispose();
    work.dispose();
  }
}

class JobSeekerDashboard extends StatefulWidget {
  const JobSeekerDashboard({
    super.key,
    required this.name,
    required this.email,
    required this.phone,
    required this.photo,
    required this.onProfile,
    this.client,
    this.createData,
    this.now,
  });

  final String name, email, phone, photo;
  final VoidCallback onProfile;
  final SupabaseClient? client;
  final JobSeekerDashboardData Function()? createData;
  final DateTime Function()? now;

  @override
  State<JobSeekerDashboard> createState() => _JobSeekerDashboardState();
}

class _JobSeekerDashboardState extends State<JobSeekerDashboard> {
  JobSeekerDashboardData? _data;
  late final String? _actor;
  StreamSubscription<String?>? _accounts;
  bool _sessionChanged = false;
  bool _loadingProfile = false, _loadingReputation = false;
  JobSeekerProfileData? _profile;
  Map<String, dynamic>? _reputation;

  @override
  void initState() {
    super.initState();
    final client = widget.client;
    final data = _data =
        widget.createData?.call() ??
        (client == null ? null : JobSeekerDashboardData.forClient(client));
    _actor = data?.applications.source.userId;
    if (data == null || _actor == null) return;
    _accounts = data.applications.source.accountChanges.listen((actor) {
      if (!mounted || actor == _actor || _sessionChanged) return;
      setState(() {
        _sessionChanged = true;
        _profile = null;
        _reputation = null;
      });
    });
    _loadApplications();
    _loadRecommendations();
    _loadWork();
    _loadReputation();
  }

  bool get _current =>
      mounted &&
      !_sessionChanged &&
      _actor != null &&
      _data?.applications.source.userId == _actor;

  void _loadApplications() {
    if (_current) unawaited(_data!.applications.load());
  }

  Future<void> _loadRecommendations() async {
    if (!_current || _loadingProfile) return;
    final data = _data!;
    setState(() => _loadingProfile = true);
    unawaited(data.jobs.load());
    JobSeekerProfileData? profile;
    try {
      profile = await data.loadProfile(_actor!);
    } catch (_) {
      // A missing profile response leaves the recommendation preview unavailable.
    }
    if (!_current) return;
    setState(() {
      _profile = profile;
      _loadingProfile = false;
    });
  }

  void _loadWork() {
    if (_current && !_data!.work.worker.loading) {
      unawaited(_data!.work.loadWorkerAssignments());
    }
  }

  Future<void> _loadReputation() async {
    if (!_current || _loadingReputation) return;
    setState(() => _loadingReputation = true);
    Map<String, dynamic>? reputation;
    try {
      reputation = await _data!.loadReputation();
    } catch (_) {
      // Keep the existing reputation destination available.
    }
    if (!_current) return;
    setState(() {
      _reputation = reputation;
      _loadingReputation = false;
    });
  }

  @override
  void dispose() {
    unawaited(_accounts?.cancel());
    _data?.dispose();
    super.dispose();
  }

  Future<void> _open(String path, {VoidCallback? onReturn}) async {
    await context.push<void>(path);
    if (_current) onReturn?.call();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data != null && !_current) {
      return const Text(
        'Sign in with an active Job Seeker account to view your dashboard.',
      );
    }
    return ResponsiveContent(
      maxWidth: 1200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.name.trim().isNotEmpty) const Text('Welcome back,'),
          PageHeading(
            title: widget.name.trim().isEmpty
                ? 'Welcome back'
                : widget.name.trim(),
            description: 'Your next opportunity starts here.',
            fontSize: 24,
          ),
          _profileCompletion(context),
          if (data != null)
            ListenableBuilder(
              listenable: Listenable.merge([
                data.applications,
                data.jobs,
                data.work,
              ]),
              builder: (context, _) =>
                  _current ? _sections(context, data) : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  Widget _profileCompletion(BuildContext context) {
    final checks = [
      ('Add your name', widget.name),
      ('Email on account', widget.email),
      ('Add a phone number', widget.phone),
      ('Add a profile photo', widget.photo),
    ];
    final completed = checks
        .where((check) => check.$2.trim().isNotEmpty)
        .length;
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Complete your profile',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${completed * 25}%',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: JobMateTheme.darkTeal),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: completed / checks.length,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: JobMateTheme.divider,
          ),
          const SizedBox(height: 10),
          ResponsiveGrid(
            minItemWidth: 235,
            maxColumns: 2,
            spacing: 6,
            children: [
              for (final (label, value) in checks)
                Row(
                  children: [
                    Icon(
                      value.trim().isEmpty
                          ? Icons.radio_button_unchecked
                          : Icons.check_circle_outline,
                      size: 18,
                      color: value.trim().isEmpty
                          ? JobMateTheme.body
                          : JobMateTheme.darkTeal,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: JobMateTheme.body,
                          decoration: value.trim().isEmpty
                              ? null
                              : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onProfile,
              label: const Text('Edit profile'),
              icon: const Icon(Icons.chevron_right, size: 18),
              iconAlignment: IconAlignment.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sections(BuildContext context, JobSeekerDashboardData data) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 24),
      _applicationStats(context, data.applications),
      const SizedBox(height: 24),
      _recommendationBanner(context),
      const SizedBox(height: 24),
      _heading(
        context,
        'Recommended for You',
        'See all',
        () => _open(AppRoutes.recommendations, onReturn: _loadApplications),
      ),
      _recommendations(context, data),
      const SizedBox(height: 24),
      _heading(
        context,
        'Recent Applications',
        'View all',
        () => _open(AppRoutes.applications, onReturn: _loadApplications),
      ),
      _recentApplications(context, data.applications),
      const SizedBox(height: 24),
      ResponsiveGrid(
        minItemWidth: 360,
        maxColumns: 2,
        spacing: 20,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading(
                context,
                'My Work',
                'View all',
                () => _open(AppRoutes.workAttendance, onReturn: _loadWork),
              ),
              _work(context, data.work),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading(
                context,
                'My Reputation',
                'View details',
                () => _open(
                  AppRoutes.profileReputation,
                  onReturn: _loadReputation,
                ),
              ),
              _reputationCard(context),
            ],
          ),
        ],
      ),
    ],
  );

  Widget _heading(
    BuildContext context,
    String title,
    String action,
    VoidCallback onPressed,
  ) => Row(
    children: [
      Expanded(
        flex: 3,
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      const SizedBox(width: 8),
      Flexible(
        flex: 2,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: onPressed,
            child: Text(action, textAlign: TextAlign.end),
          ),
        ),
      ),
    ],
  );

  Widget _recommendationBanner(BuildContext context) {
    final action = OutlinedButton.icon(
      onPressed: () =>
          _open(AppRoutes.recommendations, onReturn: _loadApplications),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: JobMateTheme.teal100),
      ),
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.chevron_right, size: 18),
      label: const Text('View all matches'),
    );
    final message = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Discover jobs matched to you',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 4),
        const Text(
          'Explore opportunities based on your skills, experience and preferences.',
          style: TextStyle(color: JobMateTheme.teal100),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JobMateTheme.darkTeal,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inline =
              constraints.maxWidth >=
              640 * (MediaQuery.textScalerOf(context).scale(14) / 14);
          final headline = Row(
            crossAxisAlignment: inline
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              const _DashboardIcon(
                Icons.auto_awesome_outlined,
                background: Color(0xFF115E59),
                color: JobMateTheme.teal100,
              ),
              const SizedBox(width: 12),
              Expanded(child: message),
              if (inline) ...[const SizedBox(width: 16), action],
            ],
          );
          return inline
              ? headline
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [headline, const SizedBox(height: 8), action],
                );
        },
      ),
    );
  }

  Widget _applicationStats(
    BuildContext context,
    MyApplicationsRepository applications,
  ) {
    if (!applications.loaded) {
      return WorkspaceCard(
        title: 'Application statistics',
        child: _applicationState(applications),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          applications.complete
              ? 'Current application statuses'
              : 'Current statuses from loaded applications',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ResponsiveGrid(
          minItemWidth: 145,
          maxColumns: 3,
          children: [
            for (final (status, tone, icon) in [
              (
                MyApplicationStatus.submitted,
                Colors.blue.shade800,
                Icons.description_outlined,
              ),
              (
                MyApplicationStatus.shortlisted,
                Colors.purple.shade700,
                Icons.bookmark_added_outlined,
              ),
              (
                MyApplicationStatus.interview,
                Colors.green.shade800,
                Icons.event_available_outlined,
              ),
            ])
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    tone.withValues(alpha: .08),
                    Theme.of(context).colorScheme.surface,
                  ),
                  border: Border.all(color: tone.withValues(alpha: .20)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(icon, size: 21, color: tone),
                    const SizedBox(height: 4),
                    Text(
                      '${applications.applications.where((row) => row.status == status).length}',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: tone, fontWeight: FontWeight.w700),
                    ),
                    Text(status.label, textAlign: TextAlign.center),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _applicationState(MyApplicationsRepository applications) =>
      _DashboardReadState(
        message: applications.loading
            ? 'Loading your applications...'
            : applications.error ?? 'Applications are unavailable.',
        loading: applications.loading,
        onRetry: applications.loading ? null : _loadApplications,
      );

  Widget _recommendations(BuildContext context, JobSeekerDashboardData data) {
    final applications = data.applications;
    final jobs = data.jobs;
    if (applications.loading || jobs.loading || _loadingProfile) {
      return const _DashboardCard(
        child: _DashboardReadState(
          message: 'Finding matching jobs...',
          loading: true,
        ),
      );
    }
    if (!applications.complete || !jobs.loaded || _profile == null) {
      return _DashboardCard(
        child: _DashboardReadState(
          message: !applications.complete
              ? 'Recommendations are unavailable because your application history could not be verified.'
              : 'Recommendations could not be loaded.',
          onRetry: !applications.complete
              ? _loadApplications
              : _loadRecommendations,
        ),
      );
    }
    final matches = filterMatches(
      matchJobs(
        jobs.jobs,
        _profile!,
        appliedJobIds: applications.applications
            .map((row) => row.jobId)
            .toSet(),
        now: widget.now?.call() ?? DateTime.now(),
      ),
    ).take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!jobs.catalogueComplete)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Only part of the published job catalogue could be verified.',
            ),
          ),
        if (matches.isEmpty)
          _DashboardCard(
            child: Text(
              jobs.catalogueComplete
                  ? 'No eligible matches right now.'
                  : 'No eligible matches in the jobs loaded.',
            ),
          )
        else
          ResponsiveGrid(
            minItemWidth: 336,
            maxColumns: 3,
            children: [for (final match in matches) _jobCard(context, match)],
          ),
      ],
    );
  }

  Widget _jobCard(BuildContext context, JobMatch match) {
    final job = match.job;
    final published = marketplaceDate(job.text('published_at'));
    final location = job.text('location');
    final arrangement = job.text('work_arrangement');
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    _DashboardMetadata(Icons.business_outlined, job.company),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(flex: 2, child: _MatchBadge(score: match.score)),
            ],
          ),
          const SizedBox(height: 8),
          if (job.text('employment_type').isNotEmpty)
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(jobLabel(job.text('employment_type'))),
            ),
          if (location.isNotEmpty || arrangement.isNotEmpty)
            _DashboardMetadata(
              Icons.place_outlined,
              location.isNotEmpty ? location : jobLabel(arrangement),
            ),
          const SizedBox(height: 6),
          Text(
            marketplaceSalary(job),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (published != 'Not set')
            _DashboardMetadata(Icons.schedule_outlined, 'Posted $published'),
          const Divider(height: 14),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () => _open(
                '${AppRoutes.browseJobs}/${Uri.encodeComponent(job.id)}',
                onReturn: _loadApplications,
              ),
              label: const Text('View Job'),
              icon: const Icon(Icons.chevron_right, size: 18),
              iconAlignment: IconAlignment.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentApplications(
    BuildContext context,
    MyApplicationsRepository applications,
  ) {
    if (!applications.loaded) {
      return _DashboardCard(child: _applicationState(applications));
    }
    final recent = applications.search().take(3).toList();
    if (recent.isEmpty) {
      return _DashboardCard(
        child: _DashboardReadState(
          message: applications.complete
              ? 'You have no applications yet.'
              : 'No applications in the available results.',
          onRetry: () =>
              _open(AppRoutes.browseJobs, onReturn: _loadApplications),
          action: 'Browse Jobs',
        ),
      );
    }
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < recent.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _RecentApplicationRow(
              application: recent[i],
              onTap: () => _open(
                '${AppRoutes.applications}/${Uri.encodeComponent(recent[i].id)}',
                onReturn: _loadApplications,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _work(BuildContext context, WorkAttendanceRepository work) {
    final state = work.worker;
    final shift =
        nextUpcomingShift(state.rows) ??
        state.rows
            .where(
              (row) =>
                  AttendanceLifecycle.of(row) == AttendanceLifecycle.onShift,
            )
            .firstOrNull;
    return _DashboardCard(
      child: state.loading || state.error != null
          ? _DashboardReadState(
              message: state.loading ? 'Loading your shifts...' : state.error!,
              loading: state.loading,
              onRetry: state.loading ? null : _loadWork,
            )
          : shift == null
          ? Text(
              state.rows.isNotEmpty &&
                      state.rows.every((row) => row.attendanceAsOf == null)
                  ? 'Upcoming shift timing is unavailable. Open My Work for your assignments.'
                  : 'No upcoming shifts.',
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _DashboardIcon(Icons.event_available_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isUpcomingShift(shift))
                        Text(
                          'Next upcoming shift',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      Text(
                        shift.jobTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      _DashboardMetadata(
                        Icons.calendar_today_outlined,
                        shiftDateLabel(shift.scheduledStart),
                      ),
                      _DashboardMetadata(
                        Icons.schedule_outlined,
                        shiftTimeRange(
                          shift.scheduledStart,
                          shift.scheduledEnd,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AttendanceStatusBadge(
                        label: AttendanceLifecycle.of(shift).label,
                        tone: AttendanceTone.information,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _reputationCard(BuildContext context) {
    final row = _reputation;
    if (_loadingReputation || row == null) {
      return _DashboardCard(
        child: _DashboardReadState(
          message: _loadingReputation
              ? 'Loading your reputation...'
              : 'Reputation summary is unavailable.',
          loading: _loadingReputation,
          onRetry: _loadingReputation ? null : _loadReputation,
        ),
      );
    }
    final average = row['core_average'] as num?;
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (average == null)
                      for (var i = 0; i < 5; i++)
                        const Icon(
                          Icons.star_border,
                          size: 17,
                          color: JobMateTheme.body,
                        )
                    else
                      const Icon(
                        Icons.star_rounded,
                        color: JobMateTheme.darkTeal,
                      ),
                  ],
                ),
              ),
              Text(
                average == null
                    ? 'No ratings yet'
                    : '${average.toStringAsFixed(2)} / 5 Core average',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${row['rated_application_count']} Core-rated applications · ${row['published_application_count']} released evaluations',
          ),
          const Divider(height: 22),
          Row(
            children: [
              const _DashboardIcon(Icons.check_circle_outline),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${row['verified_completed_shift_count']}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: JobMateTheme.darkTeal,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(text: ' verified completed shifts'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardIcon extends StatelessWidget {
  const _DashboardIcon(
    this.icon, {
    this.background = JobMateTheme.teal100,
    this.color = JobMateTheme.darkTeal,
  });

  final IconData icon;
  final Color background, color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Icon(icon, color: color, size: 20),
    ),
  );
}

class _DashboardMetadata extends StatelessWidget {
  const _DashboardMetadata(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: JobMateTheme.body),
      const SizedBox(width: 6),
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
    ],
  );
}

class _MatchBadge extends StatelessWidget {
  const _MatchBadge({required this.score});

  final int? score;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: score == null ? JobMateTheme.background : JobMateTheme.teal100,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (score != null)
          Text(
            '$score%',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: JobMateTheme.darkTeal,
              fontWeight: FontWeight.w700,
            ),
          ),
        Text(
          score == null ? 'Limited evidence' : 'Est. match',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    ),
  );
}

class _RecentApplicationRow extends StatelessWidget {
  const _RecentApplicationRow({required this.application, required this.onTap});

  final MyJobApplication application;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inline =
          constraints.maxWidth >=
          480 * (MediaQuery.textScalerOf(context).scale(14) / 14);
      final status = Column(
        crossAxisAlignment: inline
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          MyApplicationStatusBadge(application.status),
          Text(
            marketplaceDate(application.appliedAt.toLocal()),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const _DashboardIcon(
                Icons.business_outlined,
                background: JobMateTheme.background,
                color: JobMateTheme.body,
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      application.jobTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      application.companyName,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (!inline) ...[const SizedBox(height: 4), status],
                  ],
                ),
              ),
              if (inline) ...[
                const SizedBox(width: 12),
                Flexible(
                  flex: 2,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: status,
                  ),
                ),
              ],
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      );
    },
  );
}

class _DashboardReadState extends StatelessWidget {
  const _DashboardReadState({
    required this.message,
    this.loading = false,
    this.onRetry,
    this.action = 'Retry',
  });

  final String message, action;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 10,
    runSpacing: 6,
    children: [
      if (loading)
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      Semantics(liveRegion: true, child: Text(message)),
      if (onRetry != null) TextButton(onPressed: onRetry, child: Text(action)),
    ],
  );
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(JobMateTheme.space16),
      child: child,
    ),
  );
}
