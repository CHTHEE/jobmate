import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../applications/module2_widgets.dart';
import '../jobs/job_postings_repository.dart';
import 'work_attendance_models.dart';
import 'work_status_presentation.dart';
import 'work_attendance_repository.dart';
import 'work_attendance_gps.dart';
import 'work_assignment_creation_dialog.dart';
import 'work_assignment_creation_repository.dart';
import 'work_assignment_people.dart';
import 'work_evidence_deadline.dart';
import 'engagement_closure_controls.dart';

/// The caller supplies the selected company and owns the repository.
/// Access is checked against existing employer membership/verification rules;
/// the assignment RPC remains the authoritative backend authorization boundary.
class WorkVerificationPage extends StatefulWidget {
  const WorkVerificationPage({
    super.key,
    required this.repository,
    required this.companyId,
    this.loadAccess,
    this.createAssignmentRepository,
    this.loadWorkerName,
    this.gpsSource,
    this.closureGateway,
  });
  final WorkAttendanceRepository repository;
  final String companyId;
  final Future<JobAccess> Function()? loadAccess;

  /// Optional fake/alternate factory; this page owns and disposes its result.
  final WorkAssignmentCreationRepository Function()? createAssignmentRepository;
  final WorkAssignmentNameLoader? loadWorkerName;
  final WorkAttendanceGpsSource? gpsSource;
  final EngagementClosureGateway? closureGateway;

  @override
  State<WorkVerificationPage> createState() => _WorkVerificationPageState();
}

class _WorkVerificationPageState extends State<WorkVerificationPage> {
  String? _actor, _authorizedActor, _company;
  final _search = TextEditingController();
  final Set<String> _expandedShiftIds = {};
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
    return (_jobFilter.isEmpty || row.jobId == _jobFilter) &&
        (_shiftFilter.isEmpty || row.assignmentStatus.name == _shiftFilter) &&
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
    widget.repository.addListener(_accountChanged);
    _load();
  }

  void _accountChanged() {
    final actor = widget.repository.source.userId;
    if (actor == _actor) return;
    _actor = actor;
    _expandedShiftIds.clear();
    _clearFilters();
    _workerNames.clear();
    _workerNameReads.clear();
    _people = null;
    ++_request;
    _authorizedActor = null;
    _company = null;
    _checking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.repository.source.userId == actor) _load();
    });
  }

  Future<void> _load() async {
    final request = ++_request;
    final repository = widget.repository;
    final actor = repository.source.userId;
    bool current() =>
        mounted &&
        request == _request &&
        identical(repository, widget.repository) &&
        actor == repository.source.userId;
    setState(() {
      _checking = true;
      _authorizedActor = null;
      _company = null;
      _error = null;
      _errorKind = null;
      _closureStates.clear();
      _workerNames.clear();
      _workerNameReads.clear();
      ++_closureRefreshToken;
    });
    try {
      final company = workUuid(widget.companyId);
      if (actor == null) throw const AuthException('Authentication required');
      final access =
          await (widget.loadAccess?.call() ??
              JobPostingsRepository(Supabase.instance.client).loadAccess());
      if (!current()) return;
      if (!access.allowed ||
          workUuid(access.company?['company_id']) != company) {
        setState(() {
          _checking = false;
          _errorKind = WorkAttendanceError.permission;
          _error = access.allowed
              ? 'Your account is not authorized for the selected company.'
              : access.message ?? 'Employer company access is denied.';
        });
        return;
      }
      setState(() {
        _checking = false;
        _authorizedActor = actor;
        _company = company;
      });
      await repository.loadCompanyAssignments(company);
    } catch (failure) {
      if (!current()) return;
      final kind = workAttendanceErrorKind(failure);
      setState(() {
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
      widget.repository.addListener(_accountChanged);
    }
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.companyId != widget.companyId ||
        oldWidget.loadAccess != widget.loadAccess) {
      if (!identical(oldWidget.repository, widget.repository) ||
          oldWidget.companyId != widget.companyId) {
        _expandedShiftIds.clear();
      }
      _clearFilters();
      _people = null;
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
      final state = widget.repository.company;
      final authorized =
          _authorizedActor != null &&
          _authorizedActor == widget.repository.source.userId &&
          _company == state.scopeId;
      final loading = _checking || (authorized && state.loading);
      final error = _error ?? (authorized ? state.error : null);
      final kind = _errorKind ?? (authorized ? state.errorKind : null);
      return AppWorkspace(
        title: 'Work Assignments & Verification',
        path: AppRoutes.workVerification,
        role: 'employer',
        actions: [
          IconButton(
            tooltip: 'Refresh company assignments',
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: WorkspaceContent(
          maxWidth: 1100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Work Assignments & Verification',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Manage company shifts, attendance and work evidence.',
              ),
              const SizedBox(height: 4),
              const Text('All times are Malaysia time (MYT, UTC+08:00).'),
              const SizedBox(height: 12),
              if (authorized && !loading && error == null) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _dialogOpen ? null : () => _createAssignment(),
                    icon: const Icon(Icons.add),
                    label: const Text('Create Assignment'),
                  ),
                ),
              ],
              if (_closureGateway != null)
                CompanyEngagementClosureRequests(
                  key: ValueKey(widget.repository.source.userId),
                  gateway: _closureGateway,
                  onClosed: (applicationId) => context.go(
                    '${AppRoutes.employerSoftSkillEvaluations}/$applicationId/rate',
                  ),
                ),
              if (authorized &&
                  !loading &&
                  error == null &&
                  state.rows.isNotEmpty) ...[
                const SizedBox(height: 20),
                _AssignmentOverview(rows: state.rows),
                const SizedBox(height: 16),
                TextField(
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
                const SizedBox(height: 12),
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
                        initialValue: options.containsKey(value) ? value : '',
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
                          if (value != null) setState(() => onChanged(value));
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
                        }, (v) => _shiftFilter = v),
                        filter('Verification status', _verificationFilter, {
                          '': 'All verification states',
                          for (final status in WorkVerificationStatus.values)
                            status.name: _verificationLabel(status),
                        }, (v) => _verificationFilter = v),
                        TextButton.icon(
                          onPressed: () => setState(_clearFilters),
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          label: const Text('Clear filters'),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Showing ${state.rows.where(_matches).length} of ${state.rows.length} loaded shifts',
                  ),
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
              if (loading)
                const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Loading company assignments',
                  ),
                )
              else if (error != null)
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
              else if (!authorized || state.rows.isEmpty)
                const ModuleState(
                  title: 'No company work assignments',
                  message: 'There are no work assignments to display for this company.',
                )
              else
                for (final shifts in _applicationGroups(state.rows))
                  Builder(
                    builder: (context) {
                      final applicationId = shifts.first.applicationId;
                      final closureState = _closureStates[applicationId];
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
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLow,
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
                                ),
                                Text(
                                  '${shifts.length} ${shifts.length == 1 ? 'shift' : 'shifts'}',
                                ),
                                const SizedBox(height: 8),
                                if (_closureGateway != null)
                                  EngagementClosureControls(
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
                                if (_closureGateway == null)
                                  const Text(
                                    'Unable to check engagement status. Retry before scheduling a shift.',
                                  ),
                                if (closed)
                                  const Text(
                                    'This job engagement has been closed. New shifts cannot be scheduled.',
                                  ),
                                const SizedBox(height: 8),
                                Align(
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
                                const SizedBox(height: 8),
                                for (final row in shifts)
                                  ExcludeFocus(
                                    excluding: !_matches(row),
                                    child: Offstage(
                                      offstage: !_matches(row),
                                      child: _CompanyAssignmentCard(
                                        row,
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
    shifts.sort((a, b) {
      final start = a.scheduledStart.compareTo(b.scheduledStart);
      if (start != 0) return start;
      final end = a.scheduledEnd.compareTo(b.scheduledEnd);
      return end != 0 ? end : a.assignmentId.compareTo(b.assignmentId);
    });
  }
  return groups.values.toList();
}

class _CompanyAssignmentCard extends StatelessWidget {
  const _CompanyAssignmentCard(
    this.row, {
    this.viewGps,
    required this.expanded,
    required this.onToggleDetails,
  });
  final bool expanded;
  final VoidCallback onToggleDetails;
  final CompanyWorkAssignment row;
  final VoidCallback? viewGps;

  @override
  Widget build(BuildContext context) => Card.outlined(
    key: ValueKey(row.assignmentId),
    color: Theme.of(context).colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _AssignmentTag(label: WorkStage.fromAssignment(row).label),
              _AssignmentTag(
                label:
                    'Verification: ${_verificationLabel(row.verificationStatus)}',
              ),
            ],
          ),
          Text(
            WorkStage.fromAssignment(row).heading(true),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Text(
            _shiftSummary(row),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (row.workplaceLocation.trim().isNotEmpty)
            Text('Workplace: ${row.workplaceLocation}'),
          WorkCheckInTiming(assignment: row),
          Semantics(
            expanded: expanded,
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onToggleDetails,
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                label: Text(
                  expanded ? 'Hide shift details' : 'Show shift details',
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(WorkStage.fromAssignment(row).detail(true)),
                  EvidenceDeadlineSummary(assignment: row),
                  const SizedBox(height: 8),
                  Text('Scheduled start: ${_malaysiaTime(row.scheduledStart)}'),
                  Text('Scheduled end: ${_malaysiaTime(row.scheduledEnd)}'),
                  if (row.checkInAt != null)
                    Text('Checked in: ${_malaysiaTime(row.checkInAt!)}'),
                  if (row.checkOutAt != null)
                    Text('Checked out: ${_malaysiaTime(row.checkOutAt!)}'),
                  if (row.verifiedAt != null)
                    Text('Verified at: ${_malaysiaTime(row.verifiedAt!)}'),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: viewGps,
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('View attendance GPS'),
              ),
              FilledButton.icon(
                onPressed: () => context.push(
                  '${AppRoutes.workVerification}/${row.assignmentId}/evidence',
                ),
                icon: const Icon(Icons.description_outlined),
                label: Text(WorkStage.fromAssignment(row).evidenceAction(true)),
              ),
            ],
          ),
        ],
      ),
    ),
  );
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
  const _AssignmentOverview({required this.rows});
  final List<CompanyWorkAssignment> rows;

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
          final width = constraints.maxWidth < 600
              ? constraints.maxWidth
              : (constraints.maxWidth - 24) / 3;
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
          ];
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final metric in metrics)
                SizedBox(
                  width: width,
                  child: Container(
                    key: ValueKey('overview-${metric.$1}'),
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
                          metric.$3,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${metric.$2}',
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
            ],
          );
        },
      ),
    ],
  );
}

class _AssignmentTag extends StatelessWidget {
  const _AssignmentTag({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSecondaryContainer),
    ),
  );
}

String _shiftSummary(CompanyWorkAssignment row) {
  final start = row.scheduledStart.toUtc().add(const Duration(hours: 8));
  final end = row.scheduledEnd.toUtc().add(const Duration(hours: 8));
  String two(int n) => n.toString().padLeft(2, '0');
  String date(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';
  String time(DateTime d) =>
      '${d.hour % 12 == 0 ? 12 : d.hour % 12}:${two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
  final sameDate =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  return '${date(start)} | ${time(start)} - ${sameDate ? '' : '${date(end)} '}${time(end)} MYT';
}
