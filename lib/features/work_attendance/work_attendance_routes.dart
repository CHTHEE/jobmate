import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_page.dart';
import '../../shared/navigation/app_routes.dart';
import '../applications/module2_widgets.dart';
import 'work_attendance_pages.dart';
import 'work_attendance_repository.dart';
import 'work_evidence_pages.dart';
import 'work_evidence_repository.dart';

/// The application auth redirect handles guests; Module2Gate verifies active role.
/// Optional dependencies allow route tests without initializing live Supabase.
GoRoute workAttendanceRoute({
  WorkAttendanceSource? source,
  Future<bool> Function()? checkAccess,
  bool evidence = false,
  bool history = false,
}) => GoRoute(
  path: evidence
      ? AppRoutes.workAttendanceEvidence
      : history
      ? AppRoutes.attendanceHistory
      : AppRoutes.workAttendance,
  pageBuilder: (_, state) => appPage(
    state,
    _WorkAttendanceAccess(
      source: source,
      checkAccess: checkAccess,
      assignmentId: evidence ? state.pathParameters['assignmentId'] : null,
      history: history,
      returnToHistory:
          evidence && state.uri.queryParameters['from'] == 'history',
    ),
  ),
);

class _WorkAttendanceAccess extends StatefulWidget {
  const _WorkAttendanceAccess({
    this.source,
    this.checkAccess,
    this.assignmentId,
    this.history = false,
    this.returnToHistory = false,
  });
  final String? assignmentId;
  final bool history;
  final bool returnToHistory;
  final WorkAttendanceSource? source;
  final Future<bool> Function()? checkAccess;
  @override
  State<_WorkAttendanceAccess> createState() => _WorkAttendanceAccessState();
}

class _WorkAttendanceAccessState extends State<_WorkAttendanceAccess> {
  late final source =
      widget.source ?? SupabaseWorkAttendanceSource(Supabase.instance.client);
  late final StreamSubscription<String?> subscription;

  @override
  void initState() {
    super.initState();
    subscription = source.accountChanges.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Module2Gate(
    // Module2Gate caches its access Future. Recreate it on account changes so
    // the old account's granted access cannot authorize the new account.
    key: ValueKey(source.userId),
    role: 'job_seeker',
    checkAccess: source.userId == null ? () async => false : widget.checkAccess,
    child: _OwnedWorkerList(
      key: ValueKey(widget.assignmentId),
      source: source,
      assignmentId: widget.assignmentId,
      history: widget.history,
      returnToHistory: widget.returnToHistory,
    ),
  );
}

class _OwnedWorkerList extends StatefulWidget {
  const _OwnedWorkerList({
    super.key,
    required this.source,
    this.assignmentId,
    this.history = false,
    this.returnToHistory = false,
  });
  final bool history;
  final bool returnToHistory;
  final String? assignmentId;
  final WorkAttendanceSource source;
  @override
  State<_OwnedWorkerList> createState() => _OwnedWorkerListState();
}

class _OwnedWorkerListState extends State<_OwnedWorkerList> {
  late final repository = WorkAttendanceRepository(widget.source);
  late final evidence = widget.assignmentId == null
      ? null
      : WorkEvidenceRepository.worker(
          repository,
          assignmentId: widget.assignmentId!,
        );
  @override
  void dispose() {
    evidence?.dispose();
    repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => evidence == null
      ? WorkAttendancePage(repository: repository, history: widget.history)
      : WorkEvidencePage(
          repository: evidence!,
          returnToHistory: widget.returnToHistory,
        );
}
