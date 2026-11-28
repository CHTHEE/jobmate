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
import '../applications/module2_repository.dart' show BrowseJob;
import '../jobs/job_display.dart';
import '../jobs/employer_job_card.dart' show postingStatusLabel;
import '../jobs/job_form_result.dart';
import '../jobs/job_form_route.dart';
import '../jobs/job_postings_repository.dart';
import '../jobs/job_preview.dart';
import '../work_attendance/work_action_indicators.dart';
import '../work_attendance/work_attendance_lifecycle.dart';
import '../work_attendance/work_attendance_models.dart';
import '../work_attendance/work_attendance_repository.dart';
import '../work_attendance/work_shift_ui.dart';

/// The dashboard owns the work reader and uses the same company resolution as
/// the destination pages linked from its action cards.
class EmployerDashboardData {
  EmployerDashboardData({
    required this.loadAccess,
    required this.listPostings,
    required this.work,
  });

  factory EmployerDashboardData.forClient(
    SupabaseClient client, {
    required String companyContext,
  }) {
    final postings = JobPostingsRepository(
      client,
      companyContext: companyContext,
    );
    return EmployerDashboardData(
      loadAccess: () => postings.loadAccess(includeLogo: false),
      listPostings: postings.list,
      work: WorkAttendanceRepository(SupabaseWorkAttendanceSource(client)),
    );
  }

  final Future<JobAccess> Function() loadAccess;
  final Future<List<Map<String, dynamic>>> Function(String) listPostings;
  final WorkAttendanceRepository work;
}

class EmployerDashboard extends StatefulWidget {
  const EmployerDashboard({
    super.key,
    required this.profile,
    required this.email,
    required this.company,
    required this.companyError,
    required this.memberRole,
    required this.onProfile,
    required this.onCompany,
    required this.onVerification,
    this.onRefresh,
    this.client,
    this.createData,
    this.initialPostings,
    this.initialPostingError,
    this.now,
  });

  final Map<String, dynamic> profile;
  final String email, memberRole;
  final Map<String, dynamic>? company;
  final String? companyError;
  final VoidCallback onProfile, onCompany, onVerification;
  final VoidCallback? onRefresh;
  final SupabaseClient? client;
  final EmployerDashboardData Function()? createData;
  final List<Map<String, dynamic>>? initialPostings;
  final String? initialPostingError;
  final DateTime Function()? now;

  @override
  State<EmployerDashboard> createState() => _EmployerDashboardState();
}

class _EmployerDashboardState extends State<EmployerDashboard> {
  late final EmployerDashboardData? _data;
  late final String? _actor;
  StreamSubscription<String?>? _accounts;
  bool _accountChanged = false;
  int _scope = 0;
  int _postingRequest = 0;
  JobAccess? _access;
  bool _checking = false, _loadingPostings = false;
  bool _postJobOpen = false;
  String? _accessError, _postingError;
  List<Map<String, dynamic>>? _postings;

  String? get _companyId => widget.company?['company_id'] as String?;
  bool get _current =>
      mounted &&
      !_accountChanged &&
      (_data == null || (_actor != null && _data.work.source.userId == _actor));
  bool get _mayCheck =>
      widget.companyError == null &&
      _companyId?.trim().isNotEmpty == true &&
      widget.profile['status'] == 'active' &&
      widget.company?['verification_status'] == 'verified' &&
      const ['owner', 'employer'].contains(widget.memberRole);
  bool get _authorized =>
      _current &&
      _mayCheck &&
      _access?.allowed == true &&
      _access?.company?['company_id'] == _companyId;

  @override
  void initState() {
    super.initState();
    final client = widget.client;
    final companyId = _companyId;
    _data =
        widget.createData?.call() ??
        (client == null || companyId == null || companyId.trim().isEmpty
            ? null
            : EmployerDashboardData.forClient(
                client,
                companyContext: companyId,
              ));
    _actor = _data?.work.source.userId;
    _accounts = _data?.work.source.accountChanges.listen((actor) {
      if (mounted && actor != _actor && !_accountChanged) {
        setState(() {
          _accountChanged = true;
          _clearScope();
        });
      }
    });
    _clearScope();
    unawaited(_authorize());
  }

  @override
  void didUpdateWidget(covariant EmployerDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.company?['company_id'] != _companyId ||
        oldWidget.company?['verification_status'] !=
            widget.company?['verification_status'] ||
        oldWidget.memberRole != widget.memberRole ||
        oldWidget.profile['status'] != widget.profile['status'] ||
        oldWidget.companyError != widget.companyError) {
      _clearScope();
      unawaited(_authorize());
    }
  }

  void _clearScope() {
    _scope++;
    _access = null;
    _checking = _loadingPostings = false;
    _accessError = null;
    _postings = _data == null ? widget.initialPostings : null;
    _postingError = _data == null ? widget.initialPostingError : null;
  }

  @override
  void dispose() {
    unawaited(_accounts?.cancel());
    _data?.work.dispose();
    super.dispose();
  }

  Future<void> _authorize() async {
    final data = _data;
    if (!_current || !_mayCheck || _checking || data == null) return;
    final scope = _scope;
    setState(() {
      _checking = true;
      _accessError = null;
    });
    try {
      final access = await data.loadAccess();
      if (!_current || _scope != scope) return;
      if (!access.allowed) {
        setState(() => _accessError = access.message);
        return;
      }
      if (access.company?['company_id'] != _companyId) {
        setState(
          () => _accessError = 'The hiring company changed. Check for updates before continuing.',
        );
        return;
      }
      setState(() => _access = access);
      unawaited(_loadPostings());
      _loadWork(replace: true);
    } catch (_) {
      if (_current && _scope == scope) {
        setState(() => _accessError = 'Company access could not be verified.');
      }
    } finally {
      if (_current && _scope == scope) setState(() => _checking = false);
    }
  }

  Future<void> _loadPostings({bool replace = false}) async {
    if (!_authorized || (_loadingPostings && !replace)) return;
    final company = _companyId!;
    final scope = _scope;
    final request = ++_postingRequest;
    bool current() =>
        _authorized && _scope == scope && _postingRequest == request;
    setState(() {
      _loadingPostings = true;
      _postings = null;
      _postingError = null;
    });
    try {
      final rows = await _data!.listPostings(company);
      if (!current()) return;
      if (rows.any(
        (row) => row['company_id'] != null && row['company_id'] != company,
      )) {
        throw StateError('Posting company mismatch');
      }
      setState(() => _postings = rows);
    } catch (_) {
      if (current()) {
        setState(() => _postingError = 'Company postings could not be loaded.');
      }
    } finally {
      if (current()) setState(() => _loadingPostings = false);
    }
  }

  void _loadWork({bool replace = false}) {
    if (!_authorized) return;
    final work = _data!.work;
    if (!replace &&
        work.company.loading &&
        work.company.scopeId == _companyId) {
      return;
    }
    unawaited(work.loadCompanyAssignments(_companyId!));
  }

  Future<void> _open(String route) async {
    if (!_authorized) return;
    if (route == AppRoutes.createJob) {
      await _postJob();
      return;
    }
    final scope = _scope;
    await context.push<void>(route);
    if (!_authorized || scope != _scope) return;
    if (route == AppRoutes.jobPostings) {
      unawaited(_loadPostings());
    } else if (route == AppRoutes.workVerification) {
      _loadWork();
    }
  }

  Future<void> _postJob() async {
    if (!_authorized || _postJobOpen) return;
    _postJobOpen = true;
    final scope = _scope;
    try {
      final result = await openJobFormDialog(context, AppRoutes.createJob);
      if (_authorized &&
          scope == _scope &&
          result?.change == JobFormChange.created) {
        unawaited(_loadPostings(replace: true));
      }
    } finally {
      _postJobOpen = false;
    }
  }

  String get _companyName =>
      (_access?.company?['company_name'] as String? ??
              widget.company?['company_name'] as String? ??
              '')
          .trim();

  String? get _companyNotice {
    if (widget.companyError != null) return widget.companyError;
    if (widget.company == null) {
      return 'Set up and verify your company profile to manage hiring.';
    }
    return switch (widget.company?['verification_status']) {
      'pending' => 'Your company is awaiting verification. Changes remain locked during review.',
      'rejected' =>
        widget.memberRole == 'owner'
            ? 'Review the company verification feedback before resubmitting.'
            : 'The company owner can review verification feedback and resubmit.',
      'verified' =>
        !_mayCheck
            ? 'Hiring requires an active employer account and an authorized company membership.'
            : _accessError,
      _ => 'Complete company verification before managing jobs.',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) {
      return const Text('Sign in again to view your hiring dashboard.');
    }
    final name = (widget.profile['name'] as String? ?? '').trim();
    final title = _authorized && _companyName.isNotEmpty
        ? _companyName
        : (name.isEmpty ? 'Your hiring dashboard' : name);
    final notice = _companyNotice;
    return ResponsiveContent(
      maxWidth: 1200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Welcome back,'),
          PageHeading(
            title: title,
            description: "Here's an overview of your hiring activity.",
            fontSize: 24,
            actions: [
              if (widget.onRefresh != null)
                IconButton(
                  tooltip: 'Check for updates',
                  onPressed: widget.onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              if (_authorized)
                FilledButton.icon(
                  onPressed: () => _open(AppRoutes.createJob),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Post Job'),
                ),
            ],
          ),
          if (notice != null) ...[
            _DashboardCard(
              child: _EmployerState(
                message: notice,
                retry: _accessError != null && _mayCheck ? _authorize : null,
              ),
            ),
            const SizedBox(height: 16),
          ],
          _postingStats(context),
          if (_authorized) ...[
            const SizedBox(height: 20),
            _sectionHeading(context, 'Quick Actions'),
            _quickActions(context),
          ],
          const SizedBox(height: 20),
          _sectionHeading(
            context,
            'Active Job Posts',
            action: _authorized ? 'View all' : null,
            onPressed: () => _open(AppRoutes.jobPostings),
          ),
          _activePosts(context),
          if (_authorized) ...[
            const SizedBox(height: 20),
            ListenableBuilder(
              listenable: _data!.work,
              builder: (context, _) => _authorized
                  ? _workSections(context)
                  : const SizedBox.shrink(),
            ),
          ],
          const SizedBox(height: 20),
          ResponsiveGrid(
            minItemWidth: 350,
            maxColumns: 2,
            spacing: 20,
            equalRowHeight: true,
            children: [_companyCard(context), _accountCard(context)],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(
    BuildContext context,
    String title, {
    String? action,
    VoidCallback? onPressed,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (action != null)
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
    ),
  );

  Widget _postingStats(BuildContext context) {
    final rows = _postings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeading(context, 'Job posting statistics'),
        if (rows != null) ...[
          Text(
            'Counts reflect available company postings.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        ResponsiveGrid(
          minItemWidth: 160,
          maxColumns: 4,
          children: [
            for (final (status, title, icon, color) in [
              ('', 'Total Jobs', Icons.work_outline, JobMateTheme.darkTeal),
              (
                'published',
                'Published',
                Icons.public_outlined,
                Colors.blue.shade800,
              ),
              (
                'draft',
                'Draft',
                Icons.edit_note_outlined,
                Colors.brown.shade700,
              ),
              ('closed', 'Closed', Icons.task_alt, Colors.blueGrey.shade800),
            ])
              _DashboardCard(
                child: _Metric(
                  value: rows == null
                      ? '—'
                      : '${status.isEmpty ? rows.length : rows.where((row) => row['status'] == status).length}',
                  label: title,
                  icon: icon,
                  color: color,
                ),
              ),
          ],
        ),
        if (rows == null) _postingState(),
      ],
    );
  }

  Widget _postingState() {
    final pending = _checking || _loadingPostings;
    return _EmployerState(
      message: _checking
          ? 'Verifying company access...'
          : _loadingPostings
          ? 'Loading company postings...'
          : _postingError ?? 'Posting data is unavailable.',
      loading: pending,
      retry: !pending && _postingError != null && _authorized
          ? _loadPostings
          : null,
    );
  }

  Widget _quickActions(BuildContext context) => ResponsiveGrid(
    minItemWidth: 218,
    maxColumns: 3,
    children: [
      for (final (label, icon, route) in [
        ('Post New Job', Icons.add_circle_outline, AppRoutes.createJob),
        (
          'Review Applicants',
          Icons.assignment_ind_outlined,
          AppRoutes.applicants,
        ),
        ('Manage Workers', Icons.groups_outlined, AppRoutes.workers),
      ])
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: TextButton(
            onPressed: () => _open(route),
            style: TextButton.styleFrom(padding: const EdgeInsets.all(14)),
            child: Row(
              children: [
                _TileIcon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _activePosts(BuildContext context) {
    final rows = _postings;
    if (rows == null) {
      return const _DashboardCard(
        child: Text(
          'Open postings will appear here when posting data is available.',
        ),
      );
    }
    final now = widget.now?.call() ?? DateTime.now();
    final open =
        rows
            .where(
              (row) =>
                  row['status'] == 'published' &&
                  BrowseJob(row, company: _companyName).unavailable(now) ==
                      null,
            )
            .toList()
          ..sort((a, b) {
            final first = DateTime.tryParse('${a['published_at']}');
            final second = DateTime.tryParse('${b['published_at']}');
            final byDate = first == null
                ? (second == null ? 0 : 1)
                : second == null
                ? -1
                : second.compareTo(first);
            return byDate == 0
                ? '${a['job_id']}'.compareTo('${b['job_id']}')
                : byDate;
          });
    if (open.isEmpty) {
      return const _DashboardCard(
        child: Text('No loaded postings are open for applications.'),
      );
    }
    return ResponsiveGrid(
      minItemWidth: 336,
      maxColumns: 3,
      spacing: 16,
      equalRowHeight: true,
      children: [for (final row in open.take(3)) _postingCard(context, row)],
    );
  }

  Widget _postingCard(BuildContext context, Map<String, dynamic> row) {
    final job = BrowseJob(row, company: _companyName);
    final date = marketplaceDate(row['published_at']);
    final location = job.text('location');
    final arrangement = job.text('work_arrangement');
    return _DashboardCard(
      footer: !_authorized
          ? null
          : Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () {
                  if (!_authorized) return;
                  showDialog<void>(
                    context: context,
                    builder: (_) => JobPreview(job: row, company: _companyName),
                  );
                },
                label: const Text('View Job'),
                icon: const Icon(Icons.chevron_right, size: 18),
                iconAlignment: IconAlignment.end,
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(
                      job.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_companyName.isNotEmpty)
                      _Detail(Icons.business_outlined, _companyName),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: Align(
                  alignment: AlignmentDirectional.topEnd,
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: JobMateTheme.teal100,
                    side: BorderSide.none,
                    label: Text(postingStatusLabel('published')),
                  ),
                ),
              ),
            ],
          ),
          if (job.text('employment_type').isNotEmpty)
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(jobLabel(job.text('employment_type'))),
            ),
          if (location.isNotEmpty || arrangement.isNotEmpty)
            _Detail(
              Icons.place_outlined,
              location.isEmpty ? jobLabel(arrangement) : location,
            ),
          Text(
            marketplaceSalary(job),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (date != 'Not set')
            _Detail(Icons.schedule_outlined, 'Posted $date'),
        ],
      ),
    );
  }

  Widget _workSections(BuildContext context) {
    final state = _data!.work.company;
    final rows = state.rows;
    final loaded =
        state.scopeId == _companyId && !state.loading && state.error == null;
    final upcoming = loaded ? nextUpcomingShift(rows) : null;
    final timingComplete =
        loaded && rows.every((row) => row.attendanceAsOf != null);
    final activeWorkers = timingComplete
        ? rows
              .where(
                (row) =>
                    isUpcomingShift(row) ||
                    AttendanceLifecycle.of(row) == AttendanceLifecycle.onShift,
              )
              .map((row) => row.workerId)
              .toSet()
              .length
        : null;
    final completed = rows
        .where(
          (row) =>
              row.assignmentStatus == WorkAssignmentStatus.completed &&
              row.verificationStatus == WorkVerificationStatus.verified,
        )
        .length;
    return ResponsiveGrid(
      minItemWidth: 350,
      maxColumns: 2,
      spacing: 20,
      equalRowHeight: true,
      children: [
        _DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHeading(
                context,
                'Work Management',
                action: 'Manage Work',
                onPressed: () => _open(AppRoutes.workVerification),
              ),
              !loaded
                  ? _EmployerState(
                      message: state.loading
                          ? 'Loading company shifts...'
                          : state.error ?? 'Company shifts are unavailable.',
                      loading: state.loading,
                      retry: state.error == null ? null : _loadWork,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [
                        _Metric(
                          value:
                              '${rows.where(employerShiftNeedsAction).length}',
                          label: 'Shifts needing action',
                          icon: Icons.fact_check_outlined,
                        ),
                        const Divider(height: 1),
                        if (upcoming != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Next upcoming shift',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                upcoming.jobTitle,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              _Detail(
                                Icons.calendar_today_outlined,
                                shiftDateLabel(upcoming.scheduledStart),
                              ),
                              _Detail(
                                Icons.schedule_outlined,
                                shiftTimeRange(
                                  upcoming.scheduledStart,
                                  upcoming.scheduledEnd,
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            timingComplete
                                ? 'No upcoming shifts in loaded assignments.'
                                : 'Upcoming shift timing is unavailable.',
                          ),
                        Text(
                          'Based on loaded company assignments.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
            ],
          ),
        ),
        if (loaded)
          _DashboardCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionHeading(
                  context,
                  'Worker Overview',
                  action: 'View all',
                  onPressed: () => _open(AppRoutes.workers),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    _Metric(
                      value: activeWorkers?.toString() ?? '—',
                      label: 'Workers with upcoming or in-progress shifts',
                      icon: Icons.groups_outlined,
                    ),
                    if (activeWorkers == null)
                      const Text(
                        'Server timing is unavailable for some shifts.',
                      ),
                    const Divider(height: 1),
                    _Metric(
                      value: '$completed',
                      label: 'Verified completed shifts',
                      icon: Icons.check_circle_outline,
                    ),
                    Text(
                      'Based on loaded company assignments.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _companyCard(BuildContext context) => WorkspaceCard(
    title: widget.companyError != null
        ? 'Company unavailable'
        : 'Company Overview',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        if (widget.company != null && widget.companyError == null) ...[
          Row(
            children: [
              _companyAvatar(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _companyName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              WorkspaceStatus(
                widget.company?['verification_status'] as String? ?? '',
              ),
              Chip(
                label: Text('Membership: ${workspaceLabel(widget.memberRole)}'),
              ),
            ],
          ),
          if ((widget.company?['industry'] as String? ?? '').isNotEmpty)
            _Detail(Icons.work_outline, widget.company!['industry'] as String),
          if ((widget.company?['location'] as String? ?? '').isNotEmpty)
            _Detail(
              Icons.place_outlined,
              widget.company!['location'] as String,
            ),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: widget.onCompany,
            child: Text(
              widget.company == null && widget.companyError == null
                  ? 'Set up company'
                  : 'View company profile',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _companyAvatar() {
    const fallback = SizedBox.square(
      dimension: 44,
      child: Center(child: _TileIcon(Icons.business_outlined)),
    );
    final logo = _authorized ? _access?.logo : null;
    if (logo == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.memory(
        logo,
        width: 44,
        height: 44,
        fit: BoxFit.contain,
        semanticLabel: '$_companyName logo',
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  Widget _accountCard(BuildContext context) {
    final name = (widget.profile['name'] as String? ?? '').trim();
    final photo = (widget.profile['profile_image_url'] as String? ?? '').trim();
    final completed = [
      name,
      widget.email.trim(),
      (widget.profile['phone_num'] as String? ?? '').trim(),
      photo,
    ].where((value) => value.isNotEmpty).length;
    const fallback = _TileIcon(Icons.person_outline);
    return WorkspaceCard(
      title: 'Your Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            children: [
              if (photo.isEmpty)
                fallback
              else
                ClipOval(
                  child: Image.network(
                    photo,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => fallback,
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name.isEmpty ? 'Your account' : name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              const Chip(label: Text('Employer')),
              WorkspaceStatus(widget.profile['status'] as String? ?? ''),
            ],
          ),
          Text(
            completed == 4
                ? 'Profile complete · 100%'
                : 'Profile completion: ${completed * 25}%',
          ),
          LinearProgressIndicator(
            value: completed / 4,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Personal verification'),
              WorkspaceStatus(
                widget.profile['verification_status'] as String? ?? '',
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: widget.onProfile,
                child: const Text('View personal profile'),
              ),
              TextButton(
                onPressed: widget.onVerification,
                child: const Text('Verification documents'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child, this.footer});

  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: footer == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [child, footer!],
            ),
    ),
  );
}

class _TileIcon extends StatelessWidget {
  const _TileIcon(this.icon, {this.color = JobMateTheme.darkTeal});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Icon(icon, color: color, size: 20),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    this.color = JobMateTheme.darkTeal,
  });
  final String label, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _TileIcon(icon, color: color),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(color: color),
            ),
            Text(label),
          ],
        ),
      ),
    ],
  );
}

class _Detail extends StatelessWidget {
  const _Detail(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: JobMateTheme.body),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
    ],
  );
}

class _EmployerState extends StatelessWidget {
  const _EmployerState({
    required this.message,
    this.loading = false,
    this.retry,
  });
  final String message;
  final bool loading;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (loading)
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      Semantics(liveRegion: true, child: Text(message)),
      if (retry != null)
        TextButton(onPressed: retry, child: const Text('Retry')),
    ],
  );
}
