import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jobs/job_postings_repository.dart';
import 'work_attendance_models.dart';
import 'work_attendance_repository.dart';

/// Resolves assignment ownership before reading evidence. This controller has no
/// file-opening or mutation API. Give each viewer its own attendance repository;
/// the caller retains ownership of that injected repository.
class WorkEvidenceRepository extends ChangeNotifier {
  WorkEvidenceRepository.worker(this.attendance, {required this.assignmentId})
    : companyId = null,
      loadCompanyAccess = null {
    _attach();
  }
  WorkEvidenceRepository.employer(
    this.attendance, {
    required this.assignmentId,
    required String this.companyId,
    this.loadCompanyAccess,
  }) {
    _attach();
  }

  final WorkAttendanceRepository attendance;
  final String assignmentId;
  final String? companyId;
  final Future<JobAccess> Function()? loadCompanyAccess;
  bool get employer => companyId != null;
  String? _actor;
  int _request = 0;
  bool _disposed = false;
  bool _loading = true;
  String? _error;
  WorkAttendanceError? _errorKind;
  WorkAssignment? _assignment;
  List<WorkEvidence> _rows = const [];

  bool get _visible => !_disposed && _actor == attendance.source.userId;
  bool get loading => _visible && _loading;
  String? get error => _visible ? _error : null;
  WorkAttendanceError? get errorKind => _visible ? _errorKind : null;
  WorkAssignment? get assignment => _visible ? _assignment : null;
  List<WorkEvidence> get evidence => _visible ? _rows : const [];

  /// UX state from a freshly authorized assignment, never file authorization.
  bool get awaitingFirstSubmission =>
      _visible &&
      !_loading &&
      _error == null &&
      employer &&
      _assignment?.verificationStatus == WorkVerificationStatus.notSubmitted;

  void _attach() {
    _actor = attendance.source.userId;
    attendance.addListener(_accountChanged);
  }

  void _accountChanged() {
    final actor = attendance.source.userId;
    if (_disposed || actor == _actor) return;
    _actor = actor;
    ++_request;
    _assignment = null;
    _rows = const [];
    _loading = false;
    _error = actor == null
        ? 'Sign in to view work evidence.'
        : 'Your account changed. Refresh to check evidence access.';
    _errorKind = actor == null ? WorkAttendanceError.authentication : null;
    notifyListeners();
    // Never silently carry the prior account's selected assignment/company
    // forward. An explicit refresh re-resolves all access for the new account.
  }

  Future<void> load() async {
    if (_disposed) return;
    _actor = attendance.source.userId;
    final actor = _actor, request = ++_request;
    bool current() =>
        !_disposed && request == _request && actor == attendance.source.userId;
    _loading = true;
    _assignment = null;
    _rows = const [];
    _error = null;
    _errorKind = null;
    notifyListeners();
    try {
      if (actor == null) throw const AuthException('Authentication required');
      final id = workUuid(assignmentId);
      WorkAssignment? selected;
      if (employer) {
        final company = workUuid(companyId);
        final access =
            await (loadCompanyAccess?.call() ??
                JobPostingsRepository(Supabase.instance.client).loadAccess());
        if (!current()) return;
        if (!access.allowed ||
            workUuid(access.company?['company_id']) != company) {
          throw const _EvidenceFailure(
            WorkAttendanceError.permission,
            'You are not authorized to view evidence for this company.',
          );
        }
        await attendance.loadCompanyAssignments(company);
        if (!current()) return;
        final state = attendance.company;
        _checkRead(state);
        if (state.scopeId != company) {
          throw const FormatException('Company context changed');
        }
        selected = state.rows
            .where((row) => row.assignmentId == id)
            .firstOrNull;
      } else {
        await attendance.loadWorkerAssignments();
        if (!current()) return;
        final state = attendance.worker;
        _checkRead(state);
        selected = state.rows
            .where((row) => row.assignmentId == id)
            .firstOrNull;
      }
      if (selected == null) {
        throw const _EvidenceFailure(
          WorkAttendanceError.permission,
          'This assignment is unavailable or you do not have access.',
        );
      }
      if (employer &&
          selected.verificationStatus == WorkVerificationStatus.notSubmitted) {
        // Employers cannot call list_work_evidence before formal submission.
        // Assignment access was independently established above; this normal
        // empty state grants no access to evidence metadata or private files.
        _assignment = selected;
        return;
      }
      // The UUID alone is never proof of access. The metadata RPC independently
      // enforces can_view_work_evidence, including formal employer submission.
      await attendance.loadEvidence(id);
      if (!current()) return;
      final state = attendance.evidence;
      _checkRead(state);
      if (state.scopeId != id) {
        throw const FormatException('Assignment context changed');
      }
      _assignment = selected;
      _rows = List.unmodifiable(state.rows);
    } catch (failure) {
      if (!current()) return;
      final kind = failure is _EvidenceFailure
          ? failure.kind
          : workAttendanceErrorKind(failure);
      _errorKind = kind;
      _error = failure is _EvidenceFailure
          ? failure.message
          : switch (kind) {
              WorkAttendanceError.authentication =>
                'Your session has expired. Sign in again.',
              WorkAttendanceError.permission =>
                'Work evidence access is denied.',
              WorkAttendanceError.invalidData =>
                'Unable to read work evidence. Refresh and retry.',
              WorkAttendanceError.connection => 'Unable to load work evidence. Check your connection and retry.',
            };
    } finally {
      if (current()) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void _checkRead<T>(WorkAttendanceReadState<T> state) {
    if (state.error != null) {
      throw _EvidenceFailure(
        state.errorKind ?? WorkAttendanceError.connection,
        state.error!,
      );
    }
    if (state.loading) throw const FormatException('Read context changed');
  }

  @override
  void dispose() {
    _disposed = true;
    ++_request;
    attendance.removeListener(_accountChanged);
    _assignment = null;
    _rows = const [];
    super.dispose();
  }
}

class _EvidenceFailure implements Exception {
  const _EvidenceFailure(this.kind, this.message);
  final WorkAttendanceError kind;
  final String message;
}
