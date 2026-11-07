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
  });
  final WorkAttendanceRepository repository;
  final String companyId;
  final Future<JobAccess> Function()? loadAccess;

  /// Optional fake/alternate factory; this page owns and disposes its result.
  final WorkAssignmentCreationRepository Function()? createAssignmentRepository;
  final WorkAssignmentNameLoader? loadWorkerName;
  final WorkAttendanceGpsSource? gpsSource;

  @override
  State<WorkVerificationPage> createState() => _WorkVerificationPageState();
}

class _WorkVerificationPageState extends State<WorkVerificationPage> {
  String? _actor, _authorizedActor, _company;
  int _request = 0;
  bool _checking = true;
  String? _error;
  WorkAttendanceError? _errorKind;
  WorkAssignmentCreationRepository? _creation;
  bool _dialogOpen = false;

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
    if (_dialogOpen ||
        _authorizedActor == null ||
        _authorizedActor != widget.repository.source.userId ||
        _company != widget.companyId) {
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
        applicationId: applicationId,
      ),
    );
    if (!mounted) return;
    setState(() => _dialogOpen = false);
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
      _load();
    }
  }

  @override
  void dispose() {
    ++_request;
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
        title: 'Company Work Assignments',
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
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Company work assignments',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('All times are Malaysia time (MYT, UTC+08:00).'),
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      key: ValueKey(
                        'application-${shifts.first.applicationId}',
                      ),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            shifts.first.jobTitle,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        WorkAssignmentWorkerName(
                          key: ValueKey((
                            shifts.first.applicationId,
                            widget.companyId,
                          )),
                          assignment: shifts.first,
                          companyId: widget.companyId,
                          loader:
                              widget.loadWorkerName ??
                              (widget.repository.source
                                      is SupabaseWorkAttendanceSource
                                  ? WorkAssignmentPeopleRepository(
                                      SupabaseWorkAssignmentCreationSource(
                                        Supabase.instance.client,
                                      ),
                                    ).workerName
                                  : null),
                        ),
                        Text(
                          '${shifts.length} ${shifts.length == 1 ? 'shift' : 'shifts'}',
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _dialogOpen
                                ? null
                                : () => _createAssignment(
                                    applicationId: shifts.first.applicationId,
                                  ),
                            icon: const Icon(Icons.add),
                            label: const Text('Add shift'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final row in shifts)
                          _CompanyAssignmentCard(
                            row,
                            viewGps:
                                _dialogOpen ||
                                    (widget.gpsSource == null &&
                                        widget.repository.source
                                            is! SupabaseWorkAttendanceSource)
                                ? null
                                : () => _viewGps(row),
                          ),
                      ],
                    ),
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
  const _CompanyAssignmentCard(this.row, {this.viewGps});
  final CompanyWorkAssignment row;
  final VoidCallback? viewGps;

  @override
  Widget build(BuildContext context) => Card.outlined(
    key: ValueKey(row.assignmentId),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkStatusBanner(
            stage: WorkStage.fromAssignment(row),
            employer: true,
          ),
          const SizedBox(height: 12),
          Text('Scheduled start: ${_malaysiaTime(row.scheduledStart)}'),
          Text('Scheduled end: ${_malaysiaTime(row.scheduledEnd)}'),
          Text('Workplace: ${row.workplaceLocation}'),
          const SizedBox(height: 12),
          if (row.checkInAt != null)
            Text('Checked in: ${_malaysiaTime(row.checkInAt!)}'),
          if (row.checkOutAt != null)
            Text('Checked out: ${_malaysiaTime(row.checkOutAt!)}'),
          if (row.verifiedAt != null)
            Text('Verified at: ${_malaysiaTime(row.verifiedAt!)}'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: viewGps,
            icon: const Icon(Icons.location_on_outlined),
            label: const Text('View attendance GPS'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => context.push(
              '${AppRoutes.workVerification}/${row.assignmentId}/evidence',
            ),
            child: Text(WorkStage.fromAssignment(row).evidenceAction(true)),
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
