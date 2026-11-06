import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../applications/module2_widgets.dart';
import 'work_attendance_models.dart';
import 'work_attendance_repository.dart';
import 'work_attendance_location_dialog.dart';
import 'work_status_presentation.dart';

/// Worker attendance. The caller owns the repository and route access gate.
class WorkAttendancePage extends StatefulWidget {
  const WorkAttendancePage({
    super.key,
    required this.repository,
    this.captureLocation,
  });

  final WorkAttendanceRepository repository;

  /// Optional GPS provider for tests. Production uses device GPS.
  final Future<WorkAttendanceLocation> Function()? captureLocation;

  @override
  State<WorkAttendancePage> createState() => _WorkAttendancePageState();
}

class _WorkAttendancePageState extends State<WorkAttendancePage> {
  String? _actor;
  bool _confirming = false;

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
    if (!identical(oldWidget.repository, widget.repository)) {
      oldWidget.repository.removeListener(_accountChanged);
      _attach();
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.repository,
    builder: (context, _) {
      final state = widget.repository.worker;
      return AppWorkspace(
        title: 'Work Attendance',
        path: AppRoutes.workAttendance,
        role: 'job_seeker',
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
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'My work assignments',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('All times are Malaysia time (MYT, UTC+08:00).'),
              const SizedBox(height: 8),
              const Text(
                'JobMate requests your current device location when you check in or check out. '
                'If GPS is denied or unavailable, you can retry or continue without location. '
                'Your attendance record will indicate whether location was captured.',
              ),
              const SizedBox(height: 8),
              const Text(
                'You can check in once and check out once. Check out only after checking in. After checking out, you cannot check in again for this assignment.',
              ),
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
              else if (state.rows.isEmpty)
                const ModuleState(
                  title: 'No work assignments',
                  message:
                      'There are no scheduled work assignments to display.',
                )
              else
                for (final assignment in state.rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _AssignmentCard(
                      assignment,
                      enabled: !_confirming && !widget.repository.acting,
                      onClock: (checkingIn) => _clock(assignment, checkingIn),
                    ),
                  ),
            ],
          ),
        ),
      );
    },
  );
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard(
    this.assignment, {
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
    return Card.outlined(
      key: ValueKey(row.assignmentId),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(row.jobTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(row.companyName),
            const SizedBox(height: 12),
            WorkStatusBanner(stage: stage, employer: false),
            const SizedBox(height: 16),
            Text('Scheduled start: ${_malaysiaTime(row.scheduledStart)}'),
            Text('Scheduled end: ${_malaysiaTime(row.scheduledEnd)}'),
            const SizedBox(height: 12),
            _AttendanceDetails(row),
            if (row.verifiedAt != null)
              Text('Verified at: ${_malaysiaTime(row.verifiedAt!)}'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: enabled
                  ? () => context.push(
                      '${AppRoutes.workAttendance}/${row.assignmentId}/evidence',
                    )
                  : null,
              child: Text(stage.evidenceAction(false)),
            ),
            if ((row.assignmentStatus == WorkAssignmentStatus.scheduled &&
                    row.checkInAt == null &&
                    row.checkOutAt == null) ||
                (row.assignmentStatus == WorkAssignmentStatus.active &&
                    row.checkInAt != null &&
                    row.checkOutAt == null)) ...[
              const SizedBox(height: 16),
              // Use only server-returned status, never the device clock.
              FilledButton(
                style: row.assignmentStatus == WorkAssignmentStatus.active
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      )
                    : null,
                onPressed: enabled
                    ? () => onClock(
                        row.assignmentStatus == WorkAssignmentStatus.scheduled,
                      )
                    : null,
                child: Text(
                  row.assignmentStatus == WorkAssignmentStatus.scheduled
                      ? 'Check in'
                      : 'Check out',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Uses only the worker RPC projection; never infers a GPS outcome.
class _AttendanceDetails extends StatelessWidget {
  const _AttendanceDetails(this.row);
  final WorkerWorkAssignment row;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Attendance details',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        _detail(Icons.place_outlined, 'Workplace: ${row.workplaceLocation}'),
        _detail(
          Icons.login_outlined,
          row.checkInAt == null
              ? 'Check-in not recorded'
              : 'Checked in: ${_malaysiaTime(row.checkInAt!)}',
        ),
        _detail(
          Icons.logout_outlined,
          row.checkOutAt == null
              ? 'Check-out not recorded'
              : 'Checked out: ${_malaysiaTime(row.checkOutAt!)}',
        ),
        const Divider(),
        _detail(
          Icons.location_on_outlined,
          'GPS status: Not included in shift summary',
        ),
        Text(
          'Location is requested separately at check-in and check-out. Capture may be granted, denied or unavailable.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );

  Widget _detail(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

// Fixed MYT conversion intentionally does not use the browser/device timezone.
String _malaysiaTime(DateTime timestamp) {
  final time = timestamp.toUtc().add(const Duration(hours: 8));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.day)}/${two(time.month)}/${time.year} ${two(time.hour)}:${two(time.minute)} MYT';
}
