import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/expandable_filter_bar.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../applications/module2_widgets.dart';
import '../jobs/job_postings_repository.dart';
import 'work_attendance_models.dart';
import 'work_status_presentation.dart';
import 'work_verification_loading.dart';
import 'work_attendance_repository.dart';
import 'work_attendance_gps.dart';
import 'work_assignment_creation_dialog.dart';
import 'work_assignment_creation_repository.dart';
import 'work_assignment_people.dart';
import 'work_evidence_deadline.dart';
import 'engagement_closure_controls.dart';
import 'work_attendance_lifecycle.dart';
import 'work_attendance_resolution.dart';
import 'work_attendance_resolution_dialog.dart';
import 'work_shift_ui.dart';
import 'work_action_indicators.dart';

/// The caller supplies the selected company and owns the repository.
/// Access is checked against existing employer membership/verification rules;
/// the assignment RPC remains the authoritative backend authorization boundary.
class WorkVerificationPage extends StatefulWidget {
  const WorkVerificationPage({
    super.key,
    required this.repository,
    required this.companyId,
    this.loadAccess,
    this.initialAccess,
    this.createAssignmentRepository,
    this.loadWorkerName,
    this.gpsSource,
    this.closureGateway,
    this.resolutionSource,
    this.jobId,
    this.overview = false,
  });
  final WorkAttendanceRepository repository;
  final String companyId;
  final Future<JobAccess> Function()? loadAccess;
  final JobAccess? initialAccess;

  /// Optional fake/alternate factory; this page owns and disposes its result.
  final WorkAssignmentCreationRepository Function()? createAssignmentRepository;
  final WorkAssignmentNameLoader? loadWorkerName;
  final WorkAttendanceGpsSource? gpsSource;
  final EngagementClosureGateway? closureGateway;
  final WorkAttendanceResolutionSource? resolutionSource;
  final String? jobId;
  final bool overview;

  @override
  State<WorkVerificationPage> createState() => _WorkVerificationPageState();
}

class _WorkVerificationPageState extends State<WorkVerificationPage> {
  String? _actor, _authorizedActor, _company;
  late int _session;
  final _search = TextEditingController();
  final Set<String> _expandedShiftIds = {};
  final Set<String> _expandedApplicationIds = {};
  String _jobFilter = '', _shiftFilter = '', _verificationFilter = '';
  final Map<String, String> _workerNames = {};
  final Map<String, Future<String?>> _workerNameReads = {};
  WorkAssignmentPeopleRepository? _people;

  void _clearFilters() {
    _search.clear();
    _jobFilter = _shiftFilter = _verificationFilter = '';
  }

  Future<String?> _workerName(CompanyWorkAssignment row, String company) =>
      _workerNameReads.putIfAbsent(row.applicationId, () async {
        final request = _request;
        final actor = widget.repository.source.userId;
        final loader =
            widget.loadWorkerName ??
            (widget.repository.source is SupabaseWorkAttendanceSource
                ? (_people ??= WorkAssignmentPeopleRepository(
                    SupabaseWorkAssignmentCreationSource(
                      (widget.repository.source as SupabaseWorkAttendanceSource)
                          .client,
                    ),
                  )).workerName
                : null);
        String? name;
        try {
          name = await loader?.call(row, company);
        } catch (_) {
          name = null;
        }
        if (mounted &&
            request == _request &&
            actor == widget.repository.source.userId &&
            company == widget.companyId &&
            name != null) {
          setState(() => _workerNames[row.applicationId] = name!);
        }
        return name;
      });

  bool _matches(CompanyWorkAssignment row) {
    final query = _search.text.trim().toLowerCase();
    return (widget.jobId == null || row.jobId == widget.jobId) &&
        (_jobFilter.isEmpty || row.jobId == _jobFilter) &&
        matchesAttendanceShiftFilter(row, _shiftFilter) &&
        (_verificationFilter.isEmpty ||
            row.verificationStatus.name == _verificationFilter) &&
        (query.isEmpty ||
            row.jobTitle.toLowerCase().contains(query) ||
            (_workerNames[row.applicationId]?.toLowerCase().contains(query) ??
                false));
  }

  int _request = 0;
  bool _checking = true;
  String? _error;
  WorkAttendanceError? _errorKind;
  WorkAssignmentCreationRepository? _creation;
  bool _dialogOpen = false;
  int _closureRefreshToken = 0;
  final Map<String, EngagementClosureStatusSnapshot> _closureStates = {};
  EngagementClosureGateway? _defaultClosureGateway;
  WorkAttendanceReadState<CompanyWorkAssignment>? _presented;
  AsyncSnapshot<List<Map<String, dynamic>>>? _inbox;
  JobAccess? _initialAccess;

  EngagementClosureGateway? get _closureGateway {
    if (widget.closureGateway != null) return widget.closureGateway;
    if (widget.repository.source is SupabaseWorkAttendanceSource) {
      return _defaultClosureGateway ??= SupabaseEngagementClosureGateway(
        Supabase.instance.client,
      );
    }
    return null;
  }

  Future<void> _viewGps(CompanyWorkAssignment assignment) async {
    if (_dialogOpen ||
        _authorizedActor == null ||
        _authorizedActor != widget.repository.source.userId ||
        _company != widget.companyId) {
      return;
    }
    final source =
        widget.gpsSource ??
        (widget.repository.source is SupabaseWorkAttendanceSource
            ? SupabaseWorkAttendanceGpsSource(
                (widget.repository.source as SupabaseWorkAttendanceSource)
                    .client,
              )
            : null);
    if (source == null || source.userId != _authorizedActor) return;
    final repository = WorkAttendanceGpsRepository(
      source,
      widget.companyId,
      assignment.assignmentId,
    );
    setState(() => _dialogOpen = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => WorkAttendanceGpsDialog(repository: repository),
      );
    } finally {
      repository.dispose();
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  Future<void> _reviewAttendance(CompanyWorkAssignment row) async {
    final attendance = widget.repository.source;
    final source =
        widget.resolutionSource ??
        (attendance is SupabaseWorkAttendanceSource
            ? SupabaseWorkAttendanceResolutionSource(attendance.client)
            : null);
    if (_dialogOpen ||
        row.resolution?.canReview != true ||
        source == null ||
        source.userId != _authorizedActor ||
        _company != widget.companyId) {
      return;
    }
    final actor = _authorizedActor;
    setState(() => _dialogOpen = true);
    try {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => WorkAttendanceResolutionDialog(
          assignment: row,
          source: source,
          workerName: _workerNames[row.applicationId],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _dialogOpen = false);
        if (widget.repository.source.userId == actor) await _load();
      }
    }
  }

  Future<void> _createAssignment({String? applicationId}) async {
    final status = applicationId == null ? null : _closureStates[applicationId];
    if (_dialogOpen ||
        _authorizedActor == null ||
        _authorizedActor != widget.repository.source.userId ||
        _company != widget.companyId ||
        (applicationId != null &&
            (status == null ||
                status.loading ||
                status.error != null ||
                status.isClosed)) ||
        _closureGateway == null) {
      return;
    }
    final actor = widget.repository.source.userId;
    final company = widget.companyId;
    _creation ??=
        widget.createAssignmentRepository?.call() ??
        WorkAssignmentCreationRepository(
          SupabaseWorkAssignmentCreationSource(Supabase.instance.client),
        );
    setState(() => _dialogOpen = true);
    final assignmentId = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkAssignmentCreationDialog(
        repository: _creation!,
        companyId: company,
        closureGateway: _closureGateway!,
        applicationId: applicationId,
      ),
    );
    if (!mounted) return;
    setState(() {
      _dialogOpen = false;
      ++_closureRefreshToken;
    });
    if (assignmentId != null &&
        actor == widget.repository.source.userId &&
        company == widget.companyId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Assignment confirmed. Refreshing company assignments.',
          ),
        ),
      );
      await _load();
    }
  }

  @override
  void initState() {
    super.initState();
    _actor = widget.repository.source.userId;
    _session = widget.repository.sessionGeneration;
    _initialAccess = widget.initialAccess;
    widget.repository.addListener(_accountChanged);
    _load();
  }

  void _accountChanged() {
    final actor = widget.repository.source.userId;
    final session = widget.repository.sessionGeneration;
    if (actor == _actor && session == _session) return;
    _actor = actor;
    _session = session;
    _expandedShiftIds.clear();
    _expandedApplicationIds.clear();
    _clearFilters();
    _workerNames.clear();
    _workerNameReads.clear();
    _people = null;
    _clearPresentation();
    final request = ++_request;
    _authorizedActor = null;
    _company = null;
    _checking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          request == _request &&
          widget.repository.source.userId == actor &&
          widget.repository.sessionGeneration == session) {
        _load();
      }
    });
  }

  void _clearPresentation() {
    _presented = null;
    _inbox = null;
    _initialAccess = null;
    _defaultClosureGateway = null;
  }

  Future<void> _load() async {
    final request = ++_request;
    final repository = widget.repository;
    final actor = repository.source.userId;
    final session = repository.sessionGeneration;
    final initialAccess = _initialAccess;
    _initialAccess = null;
    bool current() =>
        mounted &&
        request == _request &&
        identical(repository, widget.repository) &&
        session == repository.sessionGeneration &&
        actor == repository.source.userId;
    setState(() {
      _checking = true;
      _error = null;
      _errorKind = null;
    });
    try {
      final company = workUuid(widget.companyId);
      if (actor == null) throw const AuthException('Authentication required');
      final access =
          initialAccess ??
          await (widget.loadAccess?.call() ??
              JobPostingsRepository(Supabase.instance.client).loadAccess());
      if (!current()) return;
      if (!access.allowed ||
          workUuid(access.company?['company_id']) != company) {
        setState(() {
          _clearPresentation();
          _checking = false;
          _errorKind = WorkAttendanceError.permission;
          _error = access.allowed
              ? 'Your account is not authorized for the selected company.'
              : access.message ?? 'Employer company access is denied.';
        });
        return;
      }
      final gateway = widget.overview && widget.jobId == null
          ? null
          : _closureGateway;
      final assignments = repository.loadCompanyAssignments(company);
      final inbox = gateway == null
          ? null
          : Future.sync(gateway.companyRequests)
                .then<AsyncSnapshot<List<Map<String, dynamic>>>>(
                  (rows) => AsyncSnapshot.withData(ConnectionState.done, rows),
                  onError: (Object error, StackTrace stack) =>
                      AsyncSnapshot<List<Map<String, dynamic>>>.withError(
                        ConnectionState.done,
                        error,
                        stack,
                      ),
                );
      await assignments;
      if (!current()) return;
      final state = repository.company;
      final requests = state.error == null ? await inbox : null;
      if (!current()) return;
      setState(() {
        _closureStates.clear();
        _workerNames.clear();
        _workerNameReads.clear();
        ++_closureRefreshToken;
        _checking = false;
        _authorizedActor = actor;
        _company = company;
        _presented = state;
        _inbox = requests;
      });
    } catch (failure) {
      if (!current()) return;
      final kind = workAttendanceErrorKind(failure);
      setState(() {
        _clearPresentation();
        _checking = false;
        _errorKind = kind;
        _error = switch (kind) {
          WorkAttendanceError.authentication =>
            'Sign in again to view company assignments.',
          WorkAttendanceError.permission => 'Company access is denied.',
          WorkAttendanceError.invalidData =>
            'A valid authorized company ID is required.',
          WorkAttendanceError.connection =>
            'Unable to check company access. Check your connection and retry.',
        };
      });
    }
  }

  @override
  void didUpdateWidget(covariant WorkVerificationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      oldWidget.repository.removeListener(_accountChanged);
      _actor = widget.repository.source.userId;
      _session = widget.repository.sessionGeneration;
      widget.repository.addListener(_accountChanged);
    }
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.companyId != widget.companyId ||
        oldWidget.loadAccess != widget.loadAccess ||
        oldWidget.jobId != widget.jobId ||
        oldWidget.overview != widget.overview ||
        oldWidget.closureGateway != widget.closureGateway) {
      if (!identical(oldWidget.repository, widget.repository) ||
          oldWidget.companyId != widget.companyId) {
        _expandedShiftIds.clear();
        _expandedApplicationIds.clear();
      }
      _clearFilters();
      _people = null;
      _clearPresentation();
      _load();
    }
  }

  @override
  void dispose() {
    ++_request;
    _search.dispose();
    _creation?.dispose();
    widget.repository.removeListener(_accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.repository,
    builder: (context, _) {
      final state =
          _presented ?? const WorkAttendanceReadState<CompanyWorkAssignment>();
      final authorized =
          _authorizedActor != null &&
          _authorizedActor == widget.repository.source.userId &&
          _company == state.scopeId;
      final loading = _checking && (!authorized || state.error != null);
      final refreshing = _checking && !loading;
      final error = _error ?? (authorized ? state.error : null);
      final kind = _errorKind ?? (authorized ? state.errorKind : null);
      if (loading) {
        return const AppWorkspace(
          title: 'Work Management',
          path: AppRoutes.workVerification,
          role: 'employer',
          child: WorkVerificationLoading(),
        );
      }
      if (widget.overview && widget.jobId == null) {
        return _buildJobOverview(
          context,
          state,
          authorized: authorized,
          refreshing: refreshing,
          error: error,
          kind: kind,
        );
      }
      final selectedRows = widget.jobId == null
          ? state.rows
          : state.rows
                .where((row) => row.jobId == widget.jobId)
                .toList(growable: false);
      final selectedTitle = widget.jobId == null
          ? 'Work Assignments & Verification'
          : selectedRows.isEmpty
          ? 'Selected Job'
          : selectedRows.first.jobTitle;
      return AppWorkspace(
        title: 'Work Management',
        path: AppRoutes.workVerification,
        role: 'employer',
        navigationActionCounts: authorized && error == null
            ? {
                AppRoutes.workVerification: state.rows
                    .where(employerShiftNeedsAction)
                    .length,
              }
            : const {},
        actions: [
          IconButton(
            tooltip: 'Refresh company assignments',
            onPressed: refreshing ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: _VerificationContent(
          refreshing: refreshing,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeading(
                title: selectedTitle,
                description: 'Manage this job’s workers, shifts, attendance and verification.',
                actions: [
                  if (authorized && error == null)
                    FilledButton.icon(
                      onPressed: _dialogOpen ? null : () => _createAssignment(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Create Assignment'),
                    ),
                ],
              ),
              if (widget.jobId != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go(AppRoutes.workVerification),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Back to Work Management'),
                  ),
                ),
              const SizedBox(height: 4),
              const Text('All times are Malaysia time (MYT, UTC+08:00).'),
              const SizedBox(height: 12),
              const _ShiftEligibilityBanner(),
              if (_inbox != null)
                CompanyEngagementClosureRequests(
                  key: ValueKey(widget.repository.source.userId),
                  gateway: _closureGateway,
                  initialRequests: _inbox,
                  onClosed: (applicationId) => context.go(
                    '${AppRoutes.employerSoftSkillEvaluations}/$applicationId/rate',
                  ),
                ),
              if (authorized && error == null && state.rows.isNotEmpty) ...[
                const SizedBox(height: 20),
                _AssignmentOverview(
                  rows: state.rows,
                  onIssues: () =>
                      setState(() => _shiftFilter = 'attendanceIssues'),
                ),
                const SizedBox(height: 16),
                ExpandableFilterBar(
                  search: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Search job title or worker name',
                      helperText: 'Worker names are searchable when available.',
                      helperMaxLines: 2,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () => setState(_search.clear),
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  activeCount: [
                    _jobFilter,
                    _shiftFilter,
                    _verificationFilter,
                  ].where((value) => value.isNotEmpty).length,
                  onClear: () => setState(_clearFilters),
                  filters: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final jobs = {
                          for (final row in state.rows) row.jobId: row.jobTitle,
                        };
                        final width = constraints.maxWidth < 600
                            ? constraints.maxWidth
                            : 240.0;
                        Widget filter(
                          String label,
                          String value,
                          Map<String, String> options,
                          ValueChanged<String> onChanged,
                        ) => SizedBox(
                          width: width,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('$label:$value'),
                            initialValue: options.containsKey(value)
                                ? value
                                : '',
                            isExpanded: true,
                            decoration: InputDecoration(labelText: label),
                            items: options.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(
                                      e.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => onChanged(value));
                              }
                            },
                          ),
                        );
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            if (jobs.length > 1 || _jobFilter.isNotEmpty)
                              filter('Job', _jobFilter, {
                                '': 'All jobs',
                                ...jobs,
                                if (_jobFilter.isNotEmpty &&
                                    !jobs.containsKey(_jobFilter))
                                  _jobFilter:
                                      'Previously selected job (unavailable)',
                              }, (v) => _jobFilter = v),
                            filter('Shift status', _shiftFilter, {
                              '': 'All shift statuses',
                              for (final status in WorkAssignmentStatus.values)
                                status.name: _shiftStatusLabel(status),
                              'attendanceIssues': 'Attendance Issues',
                              for (final status in AttendanceLifecycle.values)
                                'attendance:${status.name}': status.label,
                            }, (v) => _shiftFilter = v),
                            filter('Verification status', _verificationFilter, {
                              '': 'All verification states',
                              for (final status
                                  in WorkVerificationStatus.values)
                                status.name: _verificationLabel(status),
                            }, (v) => _verificationFilter = v),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Showing ${state.rows.where(_matches).length} of ${state.rows.length} loaded shifts',
                  ),
                ),
                Text(
                  '${_applicationGroups(state.rows.where(_matches).toList()).length} matching hired application groups',
                ),
                if (state.rows.any((row) => row.attendanceAsOf == null))
                  const Text(
                    'Attendance issue totals unavailable until server attendance timing can be loaded. Refresh after the read contract is approved and installed.',
                  ),
                if (!state.rows.any(_matches))
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No shifts match your search or filters. Clear filters to see all loaded assignments.',
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              if (error != null)
                Semantics(
                  liveRegion: true,
                  child: ModuleState(
                    title: switch (kind) {
                      WorkAttendanceError.authentication => 'Sign in required',
                      WorkAttendanceError.permission => 'Company access denied',
                      _ => 'Unable to load assignments',
                    },
                    message: error,
                    action: _load,
                    actionLabel: 'Retry',
                  ),
                )
              else if (!authorized || selectedRows.isEmpty)
                ModuleState(
                  title: widget.jobId == null
                      ? 'No company work assignments'
                      : 'Job work unavailable',
                  message: widget.jobId == null
                      ? 'Jobs with work assignments will appear here.'
                      : 'This job has no accessible work assignments, or it is no longer available.',
                )
              else
                for (final shifts in _applicationGroups(selectedRows))
                  Builder(
                    builder: (context) {
                      final applicationId = shifts.first.applicationId;
                      final applicationExpanded = _expandedApplicationIds
                          .contains(applicationId);
                      final nextShift = applicationExpanded
                          ? null
                          : nextUpcomingShift(shifts.where(_matches));
                      final closureState = _closureStates[applicationId];
                      final engagement = closureState?.status;
                      final closed = closureState?.isClosed == true;
                      final statusUnavailable =
                          closureState == null ||
                          closureState.loading ||
                          closureState.error != null;
                      return ExcludeFocus(
                        excluding: !shifts.any(_matches),
                        child: Offstage(
                          offstage: !shifts.any(_matches),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              key: ValueKey('application-$applicationId'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Semantics(
                                  header: true,
                                  child: Text(
                                    shifts.first.jobTitle,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                ),
                                WorkAssignmentWorkerName(
                                  key: ValueKey((
                                    shifts.first.applicationId,
                                    widget.companyId,
                                  )),
                                  assignment: shifts.first,
                                  companyId: widget.companyId,
                                  loader: _workerName,
                                  profileHeader: true,
                                ),
                                if (!shifts.every(_matches))
                                  Text(
                                    '${shifts.where(_matches).length} matching of ${shifts.length} shifts',
                                  ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    AttendanceStatusBadge(
                                      label:
                                          '${shifts.length} total ${shifts.length == 1 ? 'shift' : 'shifts'}',
                                    ),
                                    AttendanceStatusBadge(
                                      label:
                                          '${shifts.where((r) => r.verificationStatus == WorkVerificationStatus.verified).length} verified',
                                      tone:
                                          shifts.any(
                                            (r) =>
                                                r.verificationStatus ==
                                                WorkVerificationStatus.verified,
                                          )
                                          ? AttendanceTone.positive
                                          : AttendanceTone.neutral,
                                    ),
                                    AttendanceStatusBadge(
                                      label:
                                          '${shifts.where((r) => r.verificationStatus == WorkVerificationStatus.pendingReview).length} awaiting review',
                                      tone:
                                          shifts.any(
                                            (r) =>
                                                r.verificationStatus ==
                                                WorkVerificationStatus
                                                    .pendingReview,
                                          )
                                          ? AttendanceTone.pending
                                          : AttendanceTone.neutral,
                                    ),
                                    AttendanceStatusBadge(
                                      label:
                                          shifts.any(
                                            (r) => r.attendanceAsOf == null,
                                          )
                                          ? 'Issues unavailable'
                                          : '${shifts.where((r) => AttendanceLifecycle.of(r).isIssue).length} unresolved issues',
                                      tone:
                                          shifts.any(
                                            (row) =>
                                                AttendanceLifecycle.of(row)
                                                    .isIssue,
                                          )
                                          ? AttendanceTone.issue
                                          : AttendanceTone.neutral,
                                    ),
                                  ],
                                ),
                                if (nextShift != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 10,
                                      bottom: 14,
                                    ),
                                    child: UpcomingShiftPreview(
                                      shift: nextShift,
                                    ),
                                  ),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final toggle = Semantics(
                                      expanded: applicationExpanded,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton.icon(
                                          onPressed: () => setState(() {
                                            if (!_expandedApplicationIds.add(
                                              applicationId,
                                            )) {
                                              _expandedApplicationIds.remove(
                                                applicationId,
                                              );
                                            }
                                          }),
                                          icon: Icon(
                                            applicationExpanded
                                                ? Icons.expand_less
                                                : Icons.expand_more,
                                          ),
                                          label: Text(
                                            applicationExpanded
                                                ? 'Hide application shifts'
                                                : 'Show application shifts',
                                          ),
                                        ),
                                      ),
                                    );
                                    final addShift = Align(
                                      alignment: Alignment.centerLeft,
                                      child: OutlinedButton.icon(
                                        onPressed:
                                            _dialogOpen ||
                                                statusUnavailable ||
                                                closed ||
                                                _closureGateway == null
                                            ? null
                                            : () => _createAssignment(
                                                applicationId: applicationId,
                                              ),
                                        icon: const Icon(Icons.add),
                                        label: const Text('Add shift'),
                                      ),
                                    );
                                    return constraints.maxWidth >= 520
                                        ? Row(
                                            children: [
                                              Expanded(child: toggle),
                                              const SizedBox(width: 12),
                                              addShift,
                                            ],
                                          )
                                        : Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [toggle, addShift],
                                          );
                                  },
                                ),
                                const SizedBox(height: 8),
                                if (_closureGateway != null)
                                  Visibility(
                                    visible: applicationExpanded,
                                    maintainState: true,
                                    child: EngagementClosureControls(
                                      key: ValueKey((
                                        'closure-${shifts.first.applicationId}',
                                        widget.repository.source.userId,
                                      )),
                                      applicationId: applicationId,
                                      worker: false,
                                      gateway: _closureGateway,
                                      refreshToken: _closureRefreshToken,
                                      onStatusChanged: (snapshot) {
                                        if (!mounted) return;
                                        setState(() {
                                          _closureStates[applicationId] =
                                              snapshot;
                                        });
                                      },
                                      onClosed: () => context.go(
                                        '${AppRoutes.employerSoftSkillEvaluations}/$applicationId/rate',
                                      ),
                                    ),
                                  ),
                                if (!applicationExpanded &&
                                    engagement != null) ...[
                                  Text(
                                    'Engagement: ${switch (engagement['closure_status']) {
                                      'closed' => 'Closed',
                                      'closure_requested' => 'Closure requested',
                                      _ => 'Open',
                                    }}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                  if ((engagement['closure_status'] == 'open' ||
                                          engagement['closure_status'] ==
                                              'ineligible') &&
                                      engagement['eligible'] == false)
                                    Text(
                                      engagement['eligibility_reason'] ==
                                              unresolvedEngagementShiftsReason
                                          ? 'Closure available once all shifts are resolved.'
                                          : 'Closure is not yet available.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                ],
                                if (_closureGateway == null)
                                  const Text(
                                    'Unable to check engagement status. Retry before scheduling a shift.',
                                  ),
                                if (closed)
                                  const Text(
                                    'This job engagement has been closed. New shifts cannot be scheduled.',
                                  ),
                                if (closureState?.error != null)
                                  Text(
                                    'Unable to check engagement status. Retry before scheduling a shift.',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                if (applicationExpanded)
                                  const SizedBox(height: 8),
                                for (final row in shifts)
                                  ExcludeFocus(
                                    excluding:
                                        !_matches(row) || !applicationExpanded,
                                    child: Offstage(
                                      offstage:
                                          !_matches(row) ||
                                          !applicationExpanded,
                                      child: _CompanyAssignmentCard(
                                        row,
                                        reviewAttendance:
                                            !_dialogOpen &&
                                                row.resolution?.canReview ==
                                                    true &&
                                                (widget.resolutionSource !=
                                                        null ||
                                                    widget.repository.source
                                                        is SupabaseWorkAttendanceSource)
                                            ? () => _reviewAttendance(row)
                                            : null,
                                        expanded: _expandedShiftIds.contains(
                                          row.assignmentId,
                                        ),
                                        onToggleDetails: () => setState(() {
                                          if (!_expandedShiftIds.add(
                                            row.assignmentId,
                                          )) {
                                            _expandedShiftIds.remove(
                                              row.assignmentId,
                                            );
                                          }
                                        }),
                                        viewGps:
                                            _dialogOpen ||
                                                (widget.gpsSource == null &&
                                                    widget.repository.source
                                                        is! SupabaseWorkAttendanceSource)
                                            ? null
                                            : () => _viewGps(row),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
            ],
          ),
        ),
      );
    },
  );

  Widget _buildJobOverview(
    BuildContext context,
    WorkAttendanceReadState<CompanyWorkAssignment> state, {
    required bool authorized,
    required bool refreshing,
    required String? error,
    required WorkAttendanceError? kind,
  }) {
    final query = _search.text.trim().toLowerCase();
    final groups = _jobGroups(state.rows)
        .where((rows) {
          if (query.isNotEmpty &&
              !rows.first.jobTitle.toLowerCase().contains(query) &&
              !rows.any(
                (row) => row.workplaceLocation.toLowerCase().contains(query),
              )) {
            return false;
          }
          return switch (_verificationFilter) {
            'pending' => rows.any(
              (row) =>
                  row.verificationStatus ==
                  WorkVerificationStatus.pendingReview,
            ),
            'issues' => rows.any((row) => AttendanceLifecycle.of(row).isIssue),
            _ => true,
          };
        })
        .toList(growable: false);
    return AppWorkspace(
      title: 'Work Management',
      path: AppRoutes.workVerification,
      role: 'employer',
      navigationActionCounts: authorized && error == null
          ? {
              AppRoutes.workVerification: state.rows
                  .where(employerShiftNeedsAction)
                  .length,
            }
          : const {},
      actions: [
        IconButton(
          tooltip: 'Refresh company assignments',
          onPressed: refreshing ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: _VerificationContent(
        refreshing: refreshing,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeading(
              title: 'Work Management',
              description: 'Choose a job to manage its workers, shifts, attendance and verification.',
              actions: [
                if (authorized && error == null)
                  FilledButton.icon(
                    onPressed: _dialogOpen ? null : () => _createAssignment(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Create Assignment'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('All times are Malaysia time (MYT, UTC+08:00).'),
            const SizedBox(height: 12),
            const _ShiftEligibilityBanner(),
            if (authorized && error == null && state.rows.isNotEmpty) ...[
              const SizedBox(height: 20),
              ExpandableFilterBar(
                search: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Search job title or workplace',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () => setState(_search.clear),
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
                activeCount: _verificationFilter.isEmpty ? 0 : 1,
                onClear: () => setState(() => _verificationFilter = ''),
                filters: [
                  DropdownButtonFormField<String>(
                    key: ValueKey('overview-status:$_verificationFilter'),
                    initialValue: _verificationFilter,
                    decoration: const InputDecoration(labelText: 'Work status'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('All jobs')),
                      DropdownMenuItem(
                        value: 'pending',
                        child: Text('Pending verification'),
                      ),
                      DropdownMenuItem(
                        value: 'issues',
                        child: Text('Attendance issues'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _verificationFilter = value ?? ''),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  'Showing ${groups.length} of ${_jobGroups(state.rows).length} jobs',
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (error != null)
              ModuleState(
                title: switch (kind) {
                  WorkAttendanceError.authentication => 'Sign in required',
                  WorkAttendanceError.permission => 'Company access denied',
                  _ => 'Unable to load work management',
                },
                message: error,
                action: _load,
                actionLabel: 'Retry',
              )
            else if (!authorized || state.rows.isEmpty)
              const ModuleState(
                title: 'No company work assignments',
                message: 'Jobs with work assignments will appear here.',
              )
            else if (groups.isEmpty)
              const ModuleState(
                title: 'No matching jobs',
                message:
                    'Clear the search or filter to see all work assignments.',
              )
            else
              ResponsiveGrid(
                minItemWidth: 360,
                maxColumns: 3,
                equalRowHeight: true,
                children: [for (final rows in groups) _jobOverviewCard(rows)],
              ),
          ],
        ),
      ),
    );
  }

  Widget _jobOverviewCard(List<CompanyWorkAssignment> rows) {
    final first = rows.first;
    final workers = rows.map((row) => row.applicationId).toSet().length;
    final pending = rows
        .where(
          (row) =>
              row.verificationStatus == WorkVerificationStatus.pendingReview,
        )
        .length;
    final issuesAvailable = rows.every((row) => row.attendanceAsOf != null);
    final issues = rows
        .where((row) => AttendanceLifecycle.of(row).isIssue)
        .length;
    final locations = rows
        .map((row) => row.workplaceLocation.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  first.jobTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  locations.isEmpty
                      ? 'Workplace not available'
                      : locations.length == 1
                      ? locations.single
                      : '${locations.length} workplaces',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AttendanceStatusBadge(
                      label: '$workers ${workers == 1 ? 'worker' : 'workers'}',
                    ),
                    AttendanceStatusBadge(
                      label:
                          '${rows.length} ${rows.length == 1 ? 'shift' : 'shifts'}',
                    ),
                    AttendanceStatusBadge(
                      label: '$pending pending review',
                      tone: pending > 0
                          ? AttendanceTone.pending
                          : AttendanceTone.neutral,
                    ),
                    AttendanceStatusBadge(
                      label: issuesAvailable
                          ? '$issues attendance issues'
                          : 'Issues unavailable',
                      tone: issues > 0
                          ? AttendanceTone.issue
                          : AttendanceTone.neutral,
                    ),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: FilledButton.icon(
                key: ValueKey('manage-work-${first.jobId}'),
                onPressed: () => context.push(
                  Uri(
                    path: AppRoutes.workVerification,
                    queryParameters: {'job': first.jobId},
                  ).toString(),
                ),
                icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                label: const Text('Manage Work Assignments'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationContent extends StatelessWidget {
  const _VerificationContent({required this.refreshing, required this.child});

  final bool refreshing;
  final Widget child;

  @override
  Widget build(BuildContext context) => WorkspaceContent(
    centered: true,
    maxWidth: 1440,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (refreshing)
          const LinearProgressIndicator(
            semanticsLabel: 'Refreshing work verification',
          ),
        ExcludeFocus(
          excluding: refreshing,
          child: IgnorePointer(ignoring: refreshing, child: child),
        ),
      ],
    ),
  );
}

class _ShiftEligibilityBanner extends StatelessWidget {
  const _ShiftEligibilityBanner();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: JobMateTheme.teal50,
      border: Border.all(color: JobMateTheme.teal100),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 20, color: JobMateTheme.teal),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Shift assignments are for Part-Time and Temporary jobs',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Create shifts for hired workers under these employment types. '
                'Other job types are not eligible for new shift assignments.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: JobMateTheme.body),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// Preserve first-seen group order without mutating the repository's projection.
List<List<CompanyWorkAssignment>> _applicationGroups(
  List<CompanyWorkAssignment> rows,
) {
  final groups = <String, List<CompanyWorkAssignment>>{};
  for (final row in rows) {
    (groups[row.applicationId] ??= []).add(row);
  }
  for (final shifts in groups.values) {
    shifts.sort(
      (a, b) => compareShiftDisplayOrder(
        a,
        b,
        aNeedsAction: employerShiftNeedsAction(a),
        bNeedsAction: employerShiftNeedsAction(b),
      ),
    );
  }
  return groups.values.toList();
}

// Preserve first-seen job order and group only by authoritative job identity.
// Duplicate titles must never merge unrelated postings.
List<List<CompanyWorkAssignment>> _jobGroups(List<CompanyWorkAssignment> rows) {
  final groups = <String, List<CompanyWorkAssignment>>{};
  for (final row in rows) {
    groups.putIfAbsent(row.jobId, () => <CompanyWorkAssignment>[]).add(row);
  }
  return groups.values.toList(growable: false);
}

class _CompanyAssignmentCard extends StatelessWidget {
  const _CompanyAssignmentCard(
    this.row, {
    this.viewGps,
    this.reviewAttendance,
    required this.expanded,
    required this.onToggleDetails,
  });
  final bool expanded;
  final VoidCallback onToggleDetails;
  final CompanyWorkAssignment row;
  final VoidCallback? viewGps, reviewAttendance;

  @override
  Widget build(BuildContext context) {
    final state = AttendanceLifecycle.of(row);
    final stage = WorkStage.fromAssignment(row);
    final futureWithoutRecords =
        state == AttendanceLifecycle.scheduled &&
        row.checkInAt == null &&
        row.checkOutAt == null &&
        row.resolution?.decision == null &&
        row.verificationStatus == WorkVerificationStatus.notSubmitted;
    final showDetails = expanded && !futureWithoutRecords;
    final corrected = row.resolution?.decision == 'corrected';
    final timing = workCheckInTimingLabel(
      row.scheduledStart,
      row.effectiveCheckInAt,
    );
    final evidenceLabel = workVerificationStatusLabel(row.verificationStatus);
    final fullRecordOnly =
        {
          AttendanceLifecycle.missed,
          AttendanceLifecycle.confirmedAbsent,
        }.contains(state) &&
        row.verificationStatus == WorkVerificationStatus.notSubmitted;
    final hasDeviceRecords =
        row.checkInAt != null ||
        row.checkOutAt != null ||
        row.resolution?.originalCheckInLocationStatus != null ||
        row.resolution?.originalCheckOutLocationStatus != null;
    final evidencePrimary =
        reviewAttendance == null &&
        state != AttendanceLifecycle.missed &&
        state != AttendanceLifecycle.confirmedAbsent;
    void evidence() => context.push(
      '${AppRoutes.workVerification}/${row.assignmentId}/evidence',
    );
    final detailsLabel = futureWithoutRecords
        ? 'Shift details'
        : fullRecordOnly
        ? 'View Full Record'
        : stage.evidenceAction(true);
    Widget evidenceAction({bool primary = false}) => primary
        ? FilledButton.icon(
            onPressed: evidence,
            icon: const Icon(Icons.description_outlined),
            label: Text(detailsLabel),
          )
        : OutlinedButton.icon(
            style:
                row.verificationStatus == WorkVerificationStatus.pendingReview
                ? OutlinedButton.styleFrom(
                    backgroundColor: attendanceToneColors(
                      context,
                      AttendanceTone.pending,
                    ).$1,
                    foregroundColor: attendanceToneColors(
                      context,
                      AttendanceTone.pending,
                    ).$2,
                  )
                : null,
            onPressed: evidence,
            icon: const Icon(Icons.description_outlined),
            label: Text(detailsLabel),
          );
    final guidance =
        state == AttendanceLifecycle.unavailable ||
            row.verificationStatus == WorkVerificationStatus.pendingReview ||
            row.verificationStatus ==
                WorkVerificationStatus.moreEvidenceRequired
        ? stage.heading(true)
        : state.guidanceFor(
            employer: true,
            recoveryEnforced: row.resolution?.recoveryEnforced == true,
          );
    String time(DateTime? value) => value == null
        ? 'Not recorded'
        : '${shiftDateLabel(value)}\n${shiftTimeLabel(value)} MYT';
    final details = <Widget>[
      ShiftDetailPanel(
        title: 'Scheduled shift',
        icon: Icons.calendar_today_outlined,
        children: [
          Text(
            '${shiftDateLabel(row.scheduledStart)}\n${shiftTimeRange(row.scheduledStart, row.scheduledEnd)}',
          ),
        ],
      ),
      ShiftDetailPanel(
        title: 'Effective check-in',
        icon: Icons.login,
        children: [
          Text(
            '${corrected ? 'Corrected: ' : ''}${time(row.effectiveCheckInAt)}',
          ),
        ],
      ),
      ShiftDetailPanel(
        title: 'Effective checkout',
        icon: Icons.logout,
        children: [
          Text(
            '${corrected ? 'Corrected: ' : ''}${time(row.effectiveCheckOutAt)}',
          ),
        ],
      ),
    ];
    return Card.outlined(
      key: ValueKey(row.assignmentId),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.calendar_month_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${shiftDateLabel(row.scheduledStart)}\n${shiftTimeRange(row.scheduledStart, row.scheduledEnd)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (!futureWithoutRecords)
                  Semantics(
                    expanded: expanded,
                    child: IconButton(
                      tooltip: expanded
                          ? 'Hide shift details'
                          : 'Show shift details',
                      onPressed: onToggleDetails,
                      icon: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                AttendanceStatusBadge(
                  label: state == AttendanceLifecycle.unavailable
                      ? stage.label
                      : state.label,
                  tone: attendanceTone(state),
                ),
                if (row.verificationStatus != WorkVerificationStatus.verified)
                  AttendanceStatusBadge(
                    label: 'Verification: $evidenceLabel',
                    tone:
                        row.verificationStatus ==
                            WorkVerificationStatus.verified
                        ? AttendanceTone.positive
                        : {
                            WorkVerificationStatus.pendingReview,
                            WorkVerificationStatus.moreEvidenceRequired,
                          }.contains(row.verificationStatus)
                        ? AttendanceTone.pending
                        : AttendanceTone.neutral,
                  ),
                if (timing != null)
                  Tooltip(
                    message:
                        '${corrected ? 'Corrected check-in timing' : 'Check-in timing'}: $timing (15-minute grace period)',
                    child: AttendanceStatusBadge(
                      label: corrected ? 'Corrected · $timing' : timing,
                      tone: timing == 'Late'
                          ? AttendanceTone.pending
                          : AttendanceTone.positive,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: state.isIssue,
              child: Container(
                padding: state.isIssue
                    ? const EdgeInsets.all(8)
                    : EdgeInsets.zero,
                decoration: state.isIssue
                    ? BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer
                            .withValues(alpha: .35),
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state.isIssue) ...[
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        guidance,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!showDetails && row.workplaceLocation.trim().isNotEmpty)
              Text('Workplace: ${row.workplaceLocation}'),
            if (!showDetails) WorkplaceMapAction(uri: row.workplaceMapLink),
            if (showDetails) ...[
              const SizedBox(height: 12),
              _ShiftResponsiveGrid(columns: 3, children: details),
              const SizedBox(height: 12),
              _ShiftResponsiveGrid(
                columns: 3,
                children: [
                  ShiftDetailPanel(
                    title: 'Workplace & GPS',
                    icon: Icons.location_on_outlined,
                    children: [
                      Text('Workplace: ${row.workplaceLocation}'),
                      WorkplaceMapAction(uri: row.workplaceMapLink),
                      const SizedBox(height: 6),
                      Text(
                        row.checkInAt == null && row.checkOutAt == null
                            ? 'No device attendance recorded.'
                            : 'View original recorded GPS and location permission details separately.',
                      ),
                      if (row.resolution?.originalCheckInLocationStatus != null)
                        Text(
                          'Check-in location: ${row.resolution!.originalCheckInLocationStatus}',
                        ),
                      if (row.resolution?.originalCheckOutLocationStatus !=
                          null)
                        Text(
                          'Checkout location: ${row.resolution!.originalCheckOutLocationStatus}',
                        ),
                      if (hasDeviceRecords)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: viewGps,
                            icon: const Icon(Icons.location_on_outlined),
                            label: const Text('View attendance GPS'),
                          ),
                        ),
                    ],
                  ),
                  ShiftDetailPanel(
                    title: 'Work Evidence',
                    icon: Icons.folder_outlined,
                    children: [
                      Text('Status: $evidenceLabel'),
                      const SizedBox(height: 6),
                      Text(
                        row.verificationStatus ==
                                WorkVerificationStatus.notSubmitted
                            ? 'No evidence has been submitted for this shift.'
                            : 'Files, descriptions and review actions are available in the authorized evidence view.',
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: evidenceAction(primary: evidencePrimary),
                      ),
                      EvidenceDeadlineSummary(assignment: row),
                    ],
                  ),
                  ShiftDetailPanel(
                    title: 'Verification & settlement',
                    icon: Icons.fact_check_outlined,
                    children: [
                      Text('Work verification: $evidenceLabel'),
                      const SizedBox(height: 6),
                      const Text(
                        'Work verification does not by itself approve payable work. Payment eligibility is calculated separately from accepted compensation, resolved attendance, verified shifts and Engagement Closure.',
                      ),
                      if (state.isIssue)
                        const Text(
                          'Settlement remains blocked while this attendance issue is unresolved.',
                        ),
                    ],
                  ),
                ],
              ),
              if (row.effectiveCheckInAt != null &&
                  row.effectiveCheckOutAt != null)
                Text(
                  '${corrected ? "Corrected" : "Recorded"} duration: ${row.effectiveCheckOutAt!.difference(row.effectiveCheckInAt!).inHours}h ${row.effectiveCheckOutAt!.difference(row.effectiveCheckInAt!).inMinutes.remainder(60)}m (not approved payable time)',
                ),
              if (corrected)
                const Text(
                  'Employer-corrected effective times; original device records are in the audit below. Work verification is separate.',
                ),
              AttendanceRecordDetails(assignment: row),
              if (row.verifiedAt != null)
                Text('Verified at: ${_malaysiaTime(row.verifiedAt!)}'),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (reviewAttendance != null)
                  FilledButton.icon(
                    onPressed: reviewAttendance,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Review Attendance'),
                  ),
                if (!showDetails) ...[
                  if (hasDeviceRecords)
                    OutlinedButton.icon(
                      onPressed: viewGps,
                      icon: const Icon(Icons.location_on_outlined),
                      label: const Text('View attendance GPS'),
                    ),
                  evidenceAction(primary: evidencePrimary),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftResponsiveGrid extends StatelessWidget {
  const _ShiftResponsiveGrid({required this.columns, required this.children});
  final int columns;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      ShiftEqualHeightGrid(columns: columns, children: children);
}

String _malaysiaTime(DateTime timestamp) {
  final time = timestamp.toUtc().add(const Duration(hours: 8));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.day)}/${two(time.month)}/${time.year} ${two(time.hour)}:${two(time.minute)} MYT';
}

String _shiftStatusLabel(WorkAssignmentStatus status) => switch (status) {
  WorkAssignmentStatus.scheduled => 'Scheduled',
  WorkAssignmentStatus.active => 'Active',
  WorkAssignmentStatus.awaitingVerification => 'Awaiting verification',
  WorkAssignmentStatus.completed => 'Completed',
  WorkAssignmentStatus.cancelled => 'Cancelled',
  WorkAssignmentStatus.disputed => 'Disputed',
};

String _verificationLabel(WorkVerificationStatus status) => switch (status) {
  WorkVerificationStatus.notSubmitted => 'Not submitted',
  WorkVerificationStatus.pendingReview => 'Pending review',
  WorkVerificationStatus.moreEvidenceRequired => 'More evidence required',
  WorkVerificationStatus.verified => 'Verified',
  WorkVerificationStatus.disputed => 'Disputed',
};

class _AssignmentOverview extends StatelessWidget {
  const _AssignmentOverview({required this.rows, required this.onIssues});
  final List<CompanyWorkAssignment> rows;
  final VoidCallback onIssues;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Overview of loaded authorized records',
        style: Theme.of(context).textTheme.labelMedium,
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 950
              ? 4
              : constraints.maxWidth >= 600
              ? 2
              : 1;
          final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
          final metrics = [
            ('Total shifts', rows.length, Icons.calendar_month_outlined),
            (
              'Awaiting verification',
              rows
                  .where(
                    (r) =>
                        r.verificationStatus ==
                        WorkVerificationStatus.pendingReview,
                  )
                  .length,
              Icons.rate_review_outlined,
            ),
            (
              'Verified',
              rows
                  .where(
                    (r) =>
                        r.verificationStatus == WorkVerificationStatus.verified,
                  )
                  .length,
              Icons.verified_outlined,
            ),
            (
              'Attendance issues',
              rows.any((row) => row.attendanceAsOf == null)
                  ? null
                  : rows
                        .where((row) => AttendanceLifecycle.of(row).isIssue)
                        .length,
              Icons.report_outlined,
            ),
          ];
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final metric in metrics)
                SizedBox(
                  width: width,
                  child: InkWell(
                    onTap: metric.$1 == 'Attendance issues' && metric.$2 != null
                        ? onIssues
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      key: ValueKey('overview-${metric.$1}'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            metric.$3,
                            color: metric.$1 == 'Attendance issues'
                                ? Theme.of(context).colorScheme.error
                                : metric.$1 == 'Verified'
                                ? Theme.of(context).colorScheme.primary
                                : metric.$1 == 'Awaiting verification'
                                ? attendanceToneColors(
                                    context,
                                    AttendanceTone.pending,
                                  ).$2
                                : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  metric.$2?.toString() ?? '\u2014',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                                Text(metric.$1),
                              ],
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
      ),
    ],
  );
}
