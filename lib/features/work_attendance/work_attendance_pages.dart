import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../applications/module2_widgets.dart';
import 'work_attendance_models.dart';
import 'work_attendance_repository.dart';

/// Worker attendance. The caller owns the repository and route access gate.
class WorkAttendancePage extends StatefulWidget {
  const WorkAttendancePage({super.key, required this.repository});
  final WorkAttendanceRepository repository;

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: repository,
        builder: (context, _) => !repository.currentSession(generation)
            ? AlertDialog(
                title: const Text('Account changed'),
                content: const Text(
                  'Close this confirmation and reopen attendance for your current account.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Close'),
                  ),
                ],
              )
            : AlertDialog(
                title: Text(
                  checkingIn ? 'Confirm check-in' : 'Confirm check-out',
                ),
                content: SingleChildScrollView(
                  child: Text(
                    '${row.jobTitle}\n\nDevice location is not collected. This action is recorded without GPS. '
                    'The server sets the timestamp and decides attendance eligibility. '
                    '${checkingIn ? 'You can check in once, from 60 minutes before the scheduled start until the scheduled end.' : 'You can check out once after checking in. There is no minimum work duration. After checking out, you cannot check in again for this assignment.'}',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(
                      checkingIn ? 'Confirm check-in' : 'Confirm check-out',
                    ),
                  ),
                ],
              ),
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (confirmed != true ||
        !identical(repository, widget.repository) ||
        !repository.currentSession(generation)) {
      return;
    }
    if (checkingIn) {
      await repository.checkIn(row.assignmentId);
    } else {
      await repository.checkOut(row.assignmentId);
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
                'Device location is not collected. Attendance is recorded without GPS.',
              ),
              const SizedBox(height: 8),
              const Text(
                'You can check in once and check out once. Check out only after checking in. After checking out, you cannot check in again for this assignment.',
              ),
              if (widget.repository.actionMessage != null)
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
            const SizedBox(height: 16),
            Text('Scheduled start: ${_malaysiaTime(row.scheduledStart)}'),
            Text('Scheduled end: ${_malaysiaTime(row.scheduledEnd)}'),
            const SizedBox(height: 12),
            Text(
              'Assignment status: ${_assignmentLabel(row.assignmentStatus)}',
            ),
            Text(
              'Verification status: ${_verificationLabel(row.verificationStatus)}',
            ),
            if (row.checkInAt != null) ...[
              const SizedBox(height: 12),
              Text('Checked in: ${_malaysiaTime(row.checkInAt!)}'),
            ],
            if (row.checkOutAt != null)
              Text('Checked out: ${_malaysiaTime(row.checkOutAt!)}'),
            if (row.verifiedAt != null)
              Text('Verified at: ${_malaysiaTime(row.verifiedAt!)}'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: enabled
                  ? () => context.push(
                      '${AppRoutes.workAttendance}/${row.assignmentId}/evidence',
                    )
                  : null,
              child: const Text('View Evidence'),
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

// Fixed MYT conversion intentionally does not use the browser/device timezone.
String _malaysiaTime(DateTime timestamp) {
  final time = timestamp.toUtc().add(const Duration(hours: 8));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.day)}/${two(time.month)}/${time.year} ${two(time.hour)}:${two(time.minute)} MYT';
}

String _assignmentLabel(WorkAssignmentStatus status) => switch (status) {
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
