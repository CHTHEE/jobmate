import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/expandable_filter_bar.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../applications/module2_widgets.dart';
import 'work_attendance_models.dart';
import 'work_attendance_repository.dart';
import 'work_attendance_location_dialog.dart';
import 'work_status_presentation.dart';
import 'work_evidence_deadline.dart';
import 'engagement_closure_controls.dart';
import 'work_attendance_lifecycle.dart';
import 'work_shift_ui.dart';
import 'work_action_indicators.dart';

/// Worker attendance. The caller owns the repository and route access gate.
class WorkAttendancePage extends StatefulWidget {
  const WorkAttendancePage({
    super.key,
    required this.repository,
    this.captureLocation,
    this.closureGateway,
    this.history = false,
  });

  final WorkAttendanceRepository repository;

  /// Optional GPS provider for tests. Production uses device GPS.
  final Future<WorkAttendanceLocation> Function()? captureLocation;
  final EngagementClosureGateway? closureGateway;
  final bool history;

  @override
  State<WorkAttendancePage> createState() => _WorkAttendancePageState();
}

class _WorkAttendancePageState extends State<WorkAttendancePage> {
  String? _actor;
  bool _confirming = false;
  AttendanceHistoryFilter _historyFilter = AttendanceHistoryFilter.all;
  String _period = 'all';
  final Set<String> _expandedApplications = {};
  final _historySearch = TextEditingController();

  bool _applicationExpanded(String id) => _expandedApplications.contains(id);

  void _toggleApplication(String id) => setState(() {
    if (!_expandedApplications.add(id)) _expandedApplications.remove(id);
  });

  bool _matches(WorkerWorkAssignment row) {
    if (widget.history) {
      final query = _historySearch.text.trim().toLowerCase();
      return _historyFilter.matches(row) &&
          (row.jobTitle.toLowerCase().contains(query) ||
              row.companyName.toLowerCase().contains(query));
    }
    final state = AttendanceLifecycle.of(row);
    return switch (_period) {
      'upcoming' => state == AttendanceLifecycle.scheduled,
      'current' =>
        state == AttendanceLifecycle.ready ||
            state == AttendanceLifecycle.onShift,
      'expired' =>
        row.attendanceAsOf != null &&
            row.attendanceAsOf!.isAfter(row.scheduledEnd),
      _ => true,
    };
  }

  EngagementClosureGateway? get _closureGateway =>
      widget.closureGateway ??
      (widget.repository.source is SupabaseWorkAttendanceSource
          ? SupabaseEngagementClosureGateway(Supabase.instance.client)
          : null);

  Future<void> _clock(WorkerWorkAssignment row, bool checkingIn) async {
    final repository = widget.repository;
    if (_confirming || repository.acting) return;

    final generation = repository.sessionGeneration;
    setState(() => _confirming = true);

    try {
      if (!checkingIn) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => ListenableBuilder(
            listenable: repository,
            builder: (_, _) => AlertDialog(
              title: const Text('Confirm Check-Out?'),
              content: const Text(
                'Once you check out, you cannot check in again for this shift. Are you sure you want to continue?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(dialogContext).colorScheme.error,
                    foregroundColor: Theme.of(dialogContext)
                        .colorScheme
                        .onError,
                  ),
                  onPressed: repository.currentSession(generation)
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  child: const Text('Confirm Check-Out'),
                ),
              ],
            ),
          ),
        );
        if (!mounted ||
            confirmed != true ||
            !repository.currentSession(generation)) {
          return;
        }
      }
      final location = await showDialog<WorkAttendanceLocation>(
        context: context,
        barrierDismissible: false,
        builder: (context) => ListenableBuilder(
          listenable: repository,
          builder: (context, _) => WorkAttendanceLocationDialog(
            jobTitle: row.jobTitle,
            checkingIn: checkingIn,
            captureLocation: widget.captureLocation,
            canContinue: () =>
                identical(repository, widget.repository) &&
                repository.currentSession(generation),
          ),
        ),
      );

      if (!mounted ||
          location == null ||
          !identical(repository, widget.repository) ||
          !repository.currentSession(generation)) {
        return;
      }

      if (checkingIn) {
        await repository.checkIn(row.assignmentId, location: location);
      } else {
        await repository.checkOut(row.assignmentId, location: location);
      }
      if (mounted &&
          identical(repository, widget.repository) &&
          repository.currentSession(generation) &&
          repository.actionFailed) {
        final failure = repository.actionFailure;
        final outsideWindow =
            failure is PostgrestException &&
            failure.message == 'Check-in is outside the allowed shift window.';
        final denied =
            failure != null &&
            workAttendanceErrorKind(failure) == WorkAttendanceError.permission;
        final authentication =
            failure != null &&
            workAttendanceErrorKind(failure) ==
                WorkAttendanceError.authentication;
        final rejected =
            failure is PostgrestException &&
            ['P0001', '23514', '22023', '23505'].contains(failure.code);
        final title = outsideWindow
            ? 'Check-in unavailable'
            : authentication
            ? 'Sign in required'
            : denied
            ? 'Attendance access denied'
            : rejected
            ? checkingIn
                  ? 'Check-in not available'
                  : 'Check-out not available'
            : checkingIn
            ? 'Unable to confirm check-in'
            : 'Unable to confirm check-out';
        final message = outsideWindow
            ? 'Your shift is scheduled to start at ${_malaysiaTime(row.scheduledStart)}. '
                  'Check-in is only available during the permitted attendance window. '
                  'Check the schedule and try again when your shift becomes eligible.'
            : failure == null
            ? 'The attendance request was accepted, but the list could not refresh. Refresh and review the recorded state before taking another action.'
            : authentication || denied
            ? repository.actionMessage!
            : rejected
            ? 'The server did not accept this attendance action. Refresh and review the shift status and recorded attendance before trying again.'
            : 'The attendance action could not be confirmed. Review the recorded attendance and refresh before retrying. A lost response may still have recorded your attendance.';
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => ListenableBuilder(
            listenable: repository,
            builder: (_, _) {
              final current =
                  identical(repository, widget.repository) &&
                  repository.currentSession(generation);
              return AlertDialog(
                title: Text(current ? title : 'Account changed'),
                content: SingleChildScrollView(
                  child: Text(
                    current ? message : 'Close this dialog and refresh attendance for your current account.',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close'),
                  ),
                ],
              );
            },
          ),
        );
      } else if (mounted &&
          identical(repository, widget.repository) &&
          repository.currentSession(generation) &&
          !repository.actionFailed &&
          repository.actionMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              checkingIn
                  ? 'Checked in successfully!'
                  : 'Checked out successfully!',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _confirming = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _actor = widget.repository.source.userId;
    widget.repository.addListener(_accountChanged);
    widget.repository.loadWorkerAssignments();
  }

  void _accountChanged() {
    final actor = widget.repository.source.userId;
    if (actor == _actor) return;
    _actor = actor;
    _historyFilter = AttendanceHistoryFilter.all;
    _historySearch.clear();
    _period = 'all';
    _expandedApplications.clear();
    // The repository clears rows synchronously. Reload after its notification
    // finishes, avoiding nested ChangeNotifier notifications.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.repository.source.userId == actor) {
        widget.repository.loadWorkerAssignments();
      }
    });
  }

  @override
  void didUpdateWidget(covariant WorkAttendancePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.history != widget.history) {
      _expandedApplications.clear();
      _historySearch.clear();
    }
    if (!identical(oldWidget.repository, widget.repository)) {
      _expandedApplications.clear();
      _historySearch.clear();
      oldWidget.repository.removeListener(_accountChanged);
      _attach();
    }
  }

  Widget _upcomingShiftSummary(List<WorkerWorkAssignment> shifts) {
    final next = nextUpcomingShift(shifts.where(_matches));
    if (next != null) return UpcomingShiftPreview(shift: next);
    return Text(
      shifts.where(_matches).any((row) => row.attendanceAsOf == null)
          ? 'Upcoming shift timing unavailable.'
          : 'No upcoming shifts.',
    );
  }

  @override
  void dispose() {
    _historySearch.dispose();
    widget.repository.removeListener(_accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.repository,
    builder: (context, _) {
      final state = widget.repository.worker;
      final records = widget.history
          ? state.rows.where(isAttendanceHistoryRow).toList(growable: false)
          : state.rows;
      final matchingCount = records.where(_matches).length;
      return AppWorkspace(
        title: widget.history ? 'Attendance History' : 'My Work Shifts',
        path: widget.history
            ? AppRoutes.attendanceHistory
            : AppRoutes.workAttendance,
        role: 'job_seeker',
        navigationActionCounts: !state.loading && state.error == null
            ? {
                AppRoutes.workAttendance: state.rows
                    .where(workerShiftNeedsAction)
                    .length,
              }
            : const {},
        actions: [
          IconButton(
            tooltip: 'Refresh assignments',
            onPressed: state.loading || widget.repository.acting
                ? null
                : widget.repository.loadWorkerAssignments,
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: WorkspaceContent(
          maxWidth: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.history ? 'Attendance History' : 'My Work Shifts',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (widget.history) ...[
                const Text(
                  'Review past shifts, recorded attendance and employer verification.',
                ),
                const SizedBox(height: 4),
              ],
              const Text('All times are Malaysia time (MYT, UTC+08:00).'),
              const SizedBox(height: 12),
              if (!widget.history) ...[
                const _WorkerShiftAvailabilityBanner(),
                const SizedBox(height: 12),
              ],
              if (!state.loading && state.error == null)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => context.go(
                        widget.history
                            ? AppRoutes.workAttendance
                            : AppRoutes.attendanceHistory,
                      ),
                      icon: Icon(
                        widget.history
                            ? Icons.calendar_month_outlined
                            : Icons.history,
                      ),
                      label: Text(
                        widget.history
                            ? 'View assigned work'
                            : 'Attendance History',
                      ),
                    ),
                  ],
                ),
              if (widget.history &&
                  !state.loading &&
                  state.error == null &&
                  records.isNotEmpty)
                _AttendanceOverview(records: records),
              if (!state.loading &&
                  state.error == null &&
                  (!widget.history || records.isNotEmpty))
                ExpandableFilterBar(
                  search: widget.history
                      ? TextField(
                          controller: _historySearch,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Search job or company',
                            prefixIcon: const Icon(LucideIcons.search),
                            suffixIcon: _historySearch.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () =>
                                        setState(_historySearch.clear),
                                    icon: const Icon(LucideIcons.x),
                                  ),
                          ),
                        )
                      : null,
                  activeCount:
                      (widget.history
                          ? _historyFilter != AttendanceHistoryFilter.all
                          : _period != 'all')
                      ? 1
                      : 0,
                  onClear: () => setState(() {
                    _historyFilter = AttendanceHistoryFilter.all;
                    _historySearch.clear();
                    _period = 'all';
                  }),
                  filters: [
                    if (widget.history)
                      for (final filter in AttendanceHistoryFilter.values)
                        ChoiceChip(
                          label: Text(switch (filter) {
                            AttendanceHistoryFilter.all => 'All',
                            AttendanceHistoryFilter.recorded => 'Recorded',
                            AttendanceHistoryFilter.issues => 'Issues',
                          }),
                          selected: _historyFilter == filter,
                          onSelected: (_) =>
                              setState(() => _historyFilter = filter),
                        )
                    else
                      for (final entry in {
                        'all': 'All shifts',
                        'upcoming': 'Upcoming',
                        'current': 'Current',
                        'expired': 'Expired',
                      }.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: _period == entry.key,
                          onSelected: (_) =>
                              setState(() => _period = entry.key),
                        ),
                  ],
                ),
              const SizedBox(height: 8),
              if (widget.history &&
                  !state.loading &&
                  state.error == null &&
                  records.isNotEmpty)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Showing $matchingCount of ${records.length} loaded past shifts',
                  ),
                ),
              if (!state.loading &&
                  state.error == null &&
                  records.any((row) => row.attendanceAsOf == null))
                Text(
                  widget.history
                      ? 'Attendance timing is unavailable for some loaded records.'
                      : 'Server attendance timing is unavailable. Refresh after the lifecycle read contract is approved and installed. No device-time classifications are used.',
                ),
              const SizedBox(height: 8),
              if (!widget.history)
                const Text(
                  'Check in, then check out when work finishes. GPS can be retried or skipped; its capture status is retained.',
                ),
              const SizedBox(height: 8),
              if (widget.repository.actionMessage != null &&
                  widget.repository.actionFailed)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      widget.repository.actionMessage!,
                      style: widget.repository.actionFailed
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            )
                          : null,
                    ),
                  ),
                ),
              if (widget.repository.acting) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(
                  semanticsLabel: 'Recording attendance',
                ),
                const Text('Recording attendance and refreshing server state…'),
              ],
              const SizedBox(height: 24),
              if (state.loading)
                const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Loading assignments',
                  ),
                )
              else if (state.error != null)
                Semantics(
                  liveRegion: true,
                  child: ModuleState(
                    title: switch (state.errorKind) {
                      WorkAttendanceError.authentication => 'Sign in required',
                      WorkAttendanceError.permission =>
                        'Attendance access denied',
                      _ => 'Unable to load assignments',
                    },
                    message: state.error!,
                    action: widget.repository.loadWorkerAssignments,
                    actionLabel: 'Retry',
                  ),
                )
              else if (records.isEmpty)
                if (widget.history)
                  const ModuleState(
                    title: 'No past shifts',
                    message: 'Past shifts will appear here when available.',
                  )
                else
                  const ModuleState(
                    title: 'No work shifts scheduled yet',
                    message: 'Your shifts will appear here once an employer schedules them for you.',
                  )
              else ...[
                if (widget.history && matchingCount == 0)
                  ModuleState(
                    title: 'No matching attendance records',
                    message: 'Try another job or company name, or clear the filters.',
                    actionLabel: 'Clear search and filters',
                    action: () => setState(() {
                      _historySearch.clear();
                      _historyFilter = AttendanceHistoryFilter.all;
                    }),
                  )
                else if (matchingCount == 0)
                  Text(switch (_period) {
                    'upcoming' => 'No upcoming shifts',
                    'current' => 'No current shifts',
                    'expired' => 'No expired shifts',
                    _ => 'No shifts match this view. Choose All shifts to see every returned assignment.',
                  }),
                for (final shifts in _applicationGroups(
                  records,
                  prioritize: !widget.history,
                ))
                  if (shifts.any(_matches))
                    Card.outlined(
                      key: ValueKey(
                        'application-${shifts.first.applicationId}',
                      ),
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const WorkHeadingIcon(LucideIcons.briefcase),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        shifts.first.jobTitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      Text(
                                        shifts.first.companyName,
                                        style: const TextStyle(
                                          color: JobMateTheme.body,
                                        ),
                                      ),
                                      Text(
                                        shifts.every(_matches)
                                            ? '${shifts.length} ${shifts.length == 1 ? 'shift' : 'shifts'}'
                                            : '${shifts.where(_matches).length} matching of ${shifts.length} shifts',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                AttendanceStatusBadge(
                                  label:
                                      '${shifts.where((r) => r.verificationStatus == WorkVerificationStatus.verified).length} verified',
                                  tone:
                                      shifts.any(
                                        (row) =>
                                            row.verificationStatus ==
                                            WorkVerificationStatus.verified,
                                      )
                                      ? AttendanceTone.positive
                                      : AttendanceTone.neutral,
                                ),
                                AttendanceStatusBadge(
                                  label:
                                      '${shifts.where((r) => r.verificationStatus == WorkVerificationStatus.pendingReview).length} pending review',
                                  tone:
                                      shifts.any(
                                        (row) =>
                                            row.verificationStatus ==
                                            WorkVerificationStatus
                                                .pendingReview,
                                      )
                                      ? AttendanceTone.pending
                                      : AttendanceTone.neutral,
                                ),
                                if (shifts.every(
                                  (r) => r.attendanceAsOf != null,
                                ))
                                  AttendanceStatusBadge(
                                    label:
                                        '${shifts.where((r) => AttendanceLifecycle.of(r).isIssue).length} attendance issues',
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
                            if (!widget.history &&
                                !_applicationExpanded(
                                  shifts.first.applicationId,
                                ))
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _upcomingShiftSummary(shifts),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Semantics(
                                  expanded: _applicationExpanded(
                                    shifts.first.applicationId,
                                  ),
                                  child: TextButton.icon(
                                    onPressed: () => _toggleApplication(
                                      shifts.first.applicationId,
                                    ),
                                    icon: Icon(
                                      _applicationExpanded(
                                            shifts.first.applicationId,
                                          )
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                    ),
                                    label: Text(
                                      _applicationExpanded(
                                            shifts.first.applicationId,
                                          )
                                          ? 'Hide ${widget.history ? 'attendance records' : 'application shifts'}'
                                          : 'Show ${widget.history ? 'attendance records' : 'application shifts'}',
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (!widget.history && _closureGateway != null)
                              ExpansionTile(
                                key: PageStorageKey(
                                  'worker-closure-${shifts.first.applicationId}',
                                ),
                                tilePadding: EdgeInsets.zero,
                                childrenPadding: const EdgeInsets.only(
                                  top: 4,
                                  bottom: 12,
                                ),
                                shape: const Border(),
                                collapsedShape: const Border(),
                                expandedCrossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                title: Text(
                                  'Engagement status & closure',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                children: [
                                  EngagementClosureControls(
                                    key: ValueKey((
                                      'closure-request-${shifts.first.applicationId}',
                                      widget.repository.source.userId,
                                    )),
                                    applicationId: shifts.first.applicationId,
                                    worker: true,
                                    shiftSummary:
                                        '${shifts.length} shifts · ${shifts.where((r) => r.verificationStatus == WorkVerificationStatus.verified).length} verified · ${shifts.where((r) => r.resolution?.decision == 'confirmed_absent').length} confirmed absent · ${shifts.where((r) => r.assignmentStatus == WorkAssignmentStatus.cancelled).length} cancelled',
                                    gateway: _closureGateway,
                                  ),
                                ],
                              ),
                            if (!_applicationExpanded(
                                  shifts.first.applicationId,
                                ) &&
                                !widget.history &&
                                shifts.where(_matches).any(_workerActionable))
                              const Text(
                                'Shifts needing action remain visible below.',
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: ResponsiveGrid(
                                minItemWidth: 375,
                                maxColumns:
                                    widget.history &&
                                        shifts.where(_matches).length == 1
                                    ? 1
                                    : 3,
                                equalRowHeight: true,
                                reserveEmptyColumns: true,
                                children: [
                                  for (final assignment in shifts.where(
                                    _matches,
                                  ))
                                    if (_applicationExpanded(
                                          shifts.first.applicationId,
                                        ) ||
                                        (!widget.history &&
                                            _workerActionable(assignment)))
                                      if (widget.history)
                                        _HistoryAssignmentCard(assignment)
                                      else
                                        _AssignmentCard(
                                          assignment,
                                          key: ValueKey(
                                            'worker-shift-${assignment.assignmentId}',
                                          ),
                                          enabled:
                                              !_confirming &&
                                              !widget.repository.acting,
                                          onClock: (checkingIn) =>
                                              _clock(assignment, checkingIn),
                                        ),
                                ],
                              ),
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

// Keep groups in first-seen server order; sort copies, never repository rows.
List<List<WorkerWorkAssignment>> _applicationGroups(
  List<WorkerWorkAssignment> rows, {
  bool prioritize = false,
}) {
  final groups = <String, List<WorkerWorkAssignment>>{};
  for (final row in rows) {
    (groups[row.applicationId] ??= []).add(row);
  }
  for (final shifts in groups.values) {
    shifts.sort((a, b) {
      if (prioritize) {
        return compareShiftDisplayOrder(
          a,
          b,
          aNeedsAction: _workerActionable(a),
          bNeedsAction: _workerActionable(b),
        );
      }
      final start = a.scheduledStart.compareTo(b.scheduledStart);
      if (start != 0) return start;
      final end = a.scheduledEnd.compareTo(b.scheduledEnd);
      return end != 0 ? end : a.assignmentId.compareTo(b.assignmentId);
    });
  }
  final result = groups.values.toList();
  if (prioritize) {
    final order = {
      for (var i = 0; i < result.length; i++) result[i].first.applicationId: i,
    };
    result.sort((a, b) {
      final aa = a.any(_workerActionable), bb = b.any(_workerActionable);
      return aa != bb
          ? (aa ? -1 : 1)
          : order[a.first.applicationId]!.compareTo(
              order[b.first.applicationId]!,
            );
    });
  }
  return result;
}

bool _recoveryEnded(WorkerWorkAssignment row) =>
    row.resolution?.recoveryEnforced == true &&
    row.attendanceAsOf != null &&
    row.attendanceAsOf!.isAfter(row.resolution!.recoveryCutoff);

bool _showsClockAction(WorkerWorkAssignment row) =>
    row.resolution?.decision == null &&
    !_recoveryEnded(row) &&
    ((row.assignmentStatus == WorkAssignmentStatus.scheduled &&
            AttendanceLifecycle.of(row) != AttendanceLifecycle.missed &&
            row.checkInAt == null &&
            row.checkOutAt == null) ||
        (row.assignmentStatus == WorkAssignmentStatus.active &&
            row.checkInAt != null &&
            row.checkOutAt == null));

bool _clockActionAvailable(WorkerWorkAssignment row) =>
    row.assignmentStatus != WorkAssignmentStatus.scheduled ||
    !{
      AttendanceLifecycle.scheduled,
      AttendanceLifecycle.missed,
      AttendanceLifecycle.inconsistent,
    }.contains(AttendanceLifecycle.of(row));

bool _workerActionable(WorkerWorkAssignment row) =>
    (_showsClockAction(row) && _clockActionAvailable(row)) ||
    workerShiftNeedsAction(row);

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard(
    this.assignment, {
    super.key,
    required this.enabled,
    required this.onClock,
  });
  final WorkerWorkAssignment assignment;
  final bool enabled;
  final ValueChanged<bool> onClock;

  @override
  Widget build(BuildContext context) {
    final row = assignment;
    final stage = WorkStage.fromAssignment(row);
    final state = AttendanceLifecycle.of(row);
    final recoveryEnded = _recoveryEnded(row);
    final hasAttendance =
        row.effectiveCheckInAt != null || row.effectiveCheckOutAt != null;
    final showClock = _showsClockAction(row) && _clockActionAvailable(row);
    final evidencePrimary =
        row.assignmentStatus == WorkAssignmentStatus.awaitingVerification &&
        workerShiftNeedsAction(row);
    final detailsLabel =
        {
          AttendanceLifecycle.missed,
          AttendanceLifecycle.confirmedAbsent,
        }.contains(state)
        ? 'View Full Record'
        : state == AttendanceLifecycle.scheduled
        ? 'Shift details'
        : stage.evidenceAction(false);
    final onDetails = enabled
        ? () => context.push(
            '${AppRoutes.workAttendance}/${row.assignmentId}/evidence',
          )
        : null;
    return Card.outlined(
      key: ValueKey(row.assignmentId),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${shiftDateLabel(row.scheduledStart)} · ${shiftTimeRange(row.scheduledStart, row.scheduledEnd)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    AttendanceStatusBadge(
                      label: AttendanceLifecycle.of(row).label,
                      tone: attendanceTone(AttendanceLifecycle.of(row)),
                    ),
                    if (row.verificationStatus !=
                        WorkVerificationStatus.verified)
                      AttendanceStatusBadge(
                        tone: verificationTone(row.verificationStatus),
                        label:
                            'Verification: ${workVerificationStatusLabel(row.verificationStatus)}',
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Workplace: ${row.workplaceLocation}'),
                WorkplaceMapAction(uri: row.workplaceMapLink),
                const SizedBox(height: 8),
                if (row.verificationStatus ==
                    WorkVerificationStatus.moreEvidenceRequired)
                  const Text(
                    'Action required: read the employer feedback and resubmit evidence.',
                  ),
                if (row.verificationStatus ==
                    WorkVerificationStatus.pendingReview)
                  const Text('Your evidence is waiting for employer review.'),
                if (!hasAttendance || row.resolution?.decision != 'corrected')
                  Text(
                    state.guidanceFor(
                      employer: false,
                      recoveryEnforced:
                          row.resolution?.recoveryEnforced == true,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (hasAttendance) ...[
                  const SizedBox(height: 8),
                  ShiftAttendanceSummary(assignment: row, inShiftCard: true),
                ],
                if (row.verifiedAt != null)
                  Text('Verified at: ${_malaysiaTime(row.verifiedAt!)}'),
                if (row.effectiveCheckOutAt != null)
                  EvidenceDeadlineSummary(assignment: row),
                if (recoveryEnded &&
                    row.assignmentStatus == WorkAssignmentStatus.active)
                  const Text(
                    'The ordinary checkout recovery window has ended. Ask the employer to review and correct attendance.',
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showClock) ...[
                    FilledButton(
                      style: row.assignmentStatus == WorkAssignmentStatus.active
                          ? FilledButton.styleFrom(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .error,
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .onError,
                            )
                          : null,
                      onPressed: enabled
                          ? () => onClock(
                              row.assignmentStatus ==
                                  WorkAssignmentStatus.scheduled,
                            )
                          : null,
                      child: Text(
                        row.assignmentStatus == WorkAssignmentStatus.scheduled
                            ? 'Check in'
                            : 'Check out',
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (evidencePrimary)
                    FilledButton.icon(
                      onPressed: onDetails,
                      icon: const Icon(LucideIcons.fileCheck, size: 18),
                      label: Text(detailsLabel),
                    )
                  else
                    OutlinedButton(
                      onPressed: onDetails,
                      child: Text(detailsLabel),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceOverview extends StatelessWidget {
  const _AttendanceOverview({required this.records});

  final List<WorkerWorkAssignment> records;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Overview of loaded past shifts',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        ResponsiveGrid(
          minItemWidth: 128,
          maxColumns: 4,
          spacing: 8,
          equalRowHeight: true,
          children: [
            for (final (label, count, icon) in [
              ('Total past shifts', records.length, LucideIcons.calendar),
              (
                'Verified shifts',
                records
                    .where(
                      (r) =>
                          r.verificationStatus ==
                          WorkVerificationStatus.verified,
                    )
                    .length,
                LucideIcons.circleCheck,
              ),
              (
                'Awaiting verification',
                records
                    .where(
                      (r) =>
                          r.verificationStatus ==
                          WorkVerificationStatus.pendingReview,
                    )
                    .length,
                LucideIcons.clock,
              ),
              (
                'Attendance issues',
                records.any((r) => r.attendanceAsOf == null)
                    ? null
                    : records
                          .where((r) => AttendanceLifecycle.of(r).isIssue)
                          .length,
                LucideIcons.circleAlert,
              ),
            ])
              Card.outlined(
                key: ValueKey('attendance-overview-$label'),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, color: JobMateTheme.darkTeal, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              count?.toString() ?? 'Unavailable',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(label),
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

class _HistoryAssignmentCard extends StatelessWidget {
  const _HistoryAssignmentCard(this.row);
  final WorkerWorkAssignment row;
  @override
  Widget build(BuildContext context) {
    final state = AttendanceLifecycle.of(row);
    return Card.outlined(
      key: ValueKey(row.assignmentId),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ResponsiveGrid(
              minItemWidth: 365,
              maxColumns: 2,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const WorkHeadingIcon(LucideIcons.calendar),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shiftDateLabel(row.scheduledStart),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                'Scheduled: ${shiftTimeRange(row.scheduledStart, row.scheduledEnd)}',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AttendanceStatusBadge(
                        label: state.label,
                        tone: attendanceTone(state),
                      ),
                    ),
                    if (row.workplaceLocation.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Workplace: ${row.workplaceLocation}'),
                    ],
                    WorkplaceMapAction(uri: row.workplaceMapLink),
                    if (state != AttendanceLifecycle.confirmedAbsent) ...[
                      const SizedBox(height: 10),
                      WorkerVerificationOutcome(assignment: row),
                    ],
                    if (row.effectiveCheckOutAt != null &&
                        row.verificationStatus ==
                            WorkVerificationStatus.notSubmitted &&
                        state != AttendanceLifecycle.confirmedAbsent)
                      EvidenceDeadlineSummary(assignment: row),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ShiftAttendanceSummary(assignment: row, workerRecord: true),
                    if (hasDistinctAttendanceAudit(row)) ...[
                      const SizedBox(height: 12),
                      AttendanceRecordDetails(assignment: row),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: () => context.push(
                  '${AppRoutes.workAttendance}/${row.assignmentId}/evidence?from=history',
                ),
                icon: const Icon(LucideIcons.fileText, size: 18),
                label: const Text('Details'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Fixed MYT conversion intentionally does not use the browser/device timezone.
String _malaysiaTime(DateTime timestamp) {
  return '${shiftDateLabel(timestamp)} ${shiftTimeLabel(timestamp)} MYT';
}

class _WorkerShiftAvailabilityBanner extends StatelessWidget {
  const _WorkerShiftAvailabilityBanner();

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
                'Work shifts are for Part-Time and Temporary jobs',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                "If you're hired for a Part-Time or Temporary job, your employer can schedule shifts here. "
                'Your assigned shifts and attendance actions will appear below.',
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
