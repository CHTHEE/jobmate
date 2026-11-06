import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_models.dart';

abstract class WorkAttendanceSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<List<Map<String, dynamic>>> listMyAssignments();
  Future<List<Map<String, dynamic>>> listCompanyAssignments(String companyId);
  Future<List<Map<String, dynamic>>> listEvidence(String assignmentId);
  Future<DateTime> checkIn(
    String assignmentId, {
    WorkAttendanceLocation location =
        const WorkAttendanceLocation.unavailable(),
  });

  Future<DateTime> checkOut(
    String assignmentId, {
    WorkAttendanceLocation location =
        const WorkAttendanceLocation.unavailable(),
  });
}

/// Authorization and attendance timestamps remain enforced by deployed RPCs.
class SupabaseWorkAttendanceSource implements WorkAttendanceSource {
  SupabaseWorkAttendanceSource(this.client);
  final SupabaseClient client;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);

  Future<List<Map<String, dynamic>>> _read(
    String name, {
    Map<String, dynamic>? params,
  }) async {
    final actor = userId;
    if (actor == null) throw const AuthException('Authentication required');
    final result = await client.rpc(name, params: params);
    if (userId != actor) throw const AuthException('Account changed');
    if (result is! List || result.any((row) => row is! Map)) {
      throw const FormatException('Invalid attendance response.');
    }
    return result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> listMyAssignments() =>
      _read('list_my_work_assignments');

  @override
  Future<List<Map<String, dynamic>>> listCompanyAssignments(String companyId) =>
      _read(
        'list_company_work_assignments',
        params: {'p_company_id': workUuid(companyId)},
      );

  @override
  Future<List<Map<String, dynamic>>> listEvidence(String assignmentId) => _read(
    'list_work_evidence',
    params: {'p_assignment_id': workUuid(assignmentId)},
  );

  Future<DateTime> _clock(
    String rpc,
    String assignmentId, {
    WorkAttendanceLocation location =
        const WorkAttendanceLocation.unavailable(),
  }) async {
    final actor = userId;
    if (actor == null) throw const AuthException('Authentication required');
    final result = await client.rpc(
      rpc,
      params: {
        'p_assignment_id': workUuid(assignmentId),
        'p_location_status': location.status,
        'p_latitude': location.latitude,
        'p_longitude': location.longitude,
      },
    );
    if (userId != actor) throw const AuthException('Account changed');
    if (result is! String ||
        !RegExp(
          r'(Z|[+-]\d{2}:?\d{2})$',
          caseSensitive: false,
        ).hasMatch(result)) {
      throw const FormatException('Invalid attendance timestamp.');
    }
    final timestamp = DateTime.tryParse(result);
    if (timestamp == null) {
      throw const FormatException('Invalid attendance timestamp.');
    }
    return timestamp.toUtc();
  }

  @override
  Future<DateTime> checkIn(
    String assignmentId, {
    WorkAttendanceLocation location =
        const WorkAttendanceLocation.unavailable(),
  }) => _clock(
    'check_in_work_assignment',
    assignmentId,
    location: location,
  );

  @override
  Future<DateTime> checkOut(
    String assignmentId, {
    WorkAttendanceLocation location =
        const WorkAttendanceLocation.unavailable(),
  }) => _clock(
    'check_out_work_assignment',
    assignmentId,
    location: location,
  );
}

enum WorkAttendanceError { authentication, permission, connection, invalidData }

@immutable
class WorkAttendanceReadState<T> {
  const WorkAttendanceReadState({
    this.rows = const [],
    this.loading = false,
    this.error,
    this.errorKind,
    this.scopeId,
  });
  final List<T> rows;
  final bool loading;
  final String? error;
  final WorkAttendanceError? errorKind;

  /// Caller-selected company/assignment UUID; never inferred from another row.
  final String? scopeId;
}

class WorkAttendanceRepository extends ChangeNotifier {
  WorkAttendanceRepository(this.source) : _actor = source.userId {
    _subscription = source.accountChanges.listen((id) {
      if (id != _actor || source.userId != _actor) _reset();
    });
  }

  final WorkAttendanceSource source;
  late final StreamSubscription<String?> _subscription;
  String? _actor;
  bool _disposed = false;
  int _generation = 0;
  String? _actingId, _actionMessage;
  bool _actionFailed = false;
  int get sessionGeneration => _generation;
  bool currentSession(int generation) =>
      !_disposed &&
      generation == _generation &&
      _actor != null &&
      source.userId == _actor;
  bool get acting => currentSession(_generation) && _actingId != null;
  String? get actionMessage =>
      currentSession(_generation) ? _actionMessage : null;
  bool get actionFailed => currentSession(_generation) && _actionFailed;
  final _requests = <String, int>{};
  WorkAttendanceReadState<WorkerWorkAssignment> _worker =
      const WorkAttendanceReadState();
  WorkAttendanceReadState<CompanyWorkAssignment> _company =
      const WorkAttendanceReadState();
  WorkAttendanceReadState<WorkEvidence> _evidence =
      const WorkAttendanceReadState();

  WorkAttendanceReadState<WorkerWorkAssignment> get worker => _state(_worker);
  WorkAttendanceReadState<CompanyWorkAssignment> get company =>
      _state(_company);
  WorkAttendanceReadState<WorkEvidence> get evidence => _state(_evidence);
  // Authentication errors must remain observable while signed out.
  WorkAttendanceReadState<T> _state<T>(WorkAttendanceReadState<T> state) =>
      !_disposed && source.userId == _actor
      ? state
      : const WorkAttendanceReadState();

  void _reset() {
    ++_generation;
    _requests.clear();
    _actor = source.userId;
    _actingId = null;
    _actionMessage = null;
    _actionFailed = false;
    _worker = const WorkAttendanceReadState();
    _company = const WorkAttendanceReadState();
    _evidence = const WorkAttendanceReadState();
    notifyListeners();
    // Do not carry a previous account's company/assignment selection forward.
  }

  Future<void> loadWorkerAssignments() => _load(
    'worker',
    null,
    source.listMyAssignments,
    WorkerWorkAssignment.fromJson,
    (state) => _worker = state,
  );

  Future<void> loadCompanyAssignments(String companyId) => _load(
    'company',
    companyId,
    () => source.listCompanyAssignments(workUuid(companyId)),
    CompanyWorkAssignment.fromJson,
    (state) => _company = state,
  );

  Future<void> loadEvidence(String assignmentId) => _load(
    'evidence',
    assignmentId,
    () => source.listEvidence(workUuid(assignmentId)),
    WorkEvidence.fromJson,
    (state) => _evidence = state,
  );

  Future<void> checkIn(
    String assignmentId, {
    WorkAttendanceLocation location =
        const WorkAttendanceLocation.unavailable(),
  }) => _clock(assignmentId, true, location: location);

  Future<void> checkOut(
    String assignmentId, {
    WorkAttendanceLocation location =
        const WorkAttendanceLocation.unavailable(),
  }) => _clock(assignmentId, false, location: location);

  Future<void> _clock(
    String assignmentId,
    bool checkingIn, {
    WorkAttendanceLocation location =
        const WorkAttendanceLocation.unavailable(),
  }) async {
    if (_disposed || acting) return;
    if (source.userId != _actor) _reset();
    if (_actor == null) return;
    final generation = _generation;
    _actingId = assignmentId;
    _actionMessage = null;
    _actionFailed = false;
    notifyListeners();
    try {
      final id = workUuid(assignmentId);
      if (checkingIn) {
        await source.checkIn(id, location: location);
      } else {
        await source.checkOut(id, location: location);
      }
      if (!currentSession(generation)) return;
      // Never project the RPC timestamp into rows; reload server state.
      await loadWorkerAssignments();
      if (!currentSession(generation)) return;
      _actionFailed = worker.error != null;
      _actionMessage = _actionFailed
          ? 'Attendance request accepted, but the list could not be refreshed. Refresh before another action.'
          : checkingIn
          ? 'You’re checked in!'
          : 'You’re checked out!';
    } catch (failure) {
      if (!currentSession(generation)) return;
      // A lost response may still have committed. Reconcile without resubmitting.
      await loadWorkerAssignments();
      if (!currentSession(generation)) return;
      _actionFailed = true;
      _actionMessage = attendanceActionError(failure);
    } finally {
      if (currentSession(generation)) {
        _actingId = null;
        notifyListeners();
      }
    }
  }

  Future<void> _load<T>(
    String channel,
    String? scope,
    Future<List<Map<String, dynamic>>> Function() read,
    T Function(Map<String, dynamic>) parse,
    void Function(WorkAttendanceReadState<T>) set,
  ) async {
    if (_disposed) return;
    if (source.userId != _actor) _reset();
    final generation = _generation;
    final request = (_requests[channel] ?? 0) + 1;
    _requests[channel] = request;
    bool current() =>
        !_disposed &&
        generation == _generation &&
        request == _requests[channel] &&
        source.userId == _actor;
    set(WorkAttendanceReadState(loading: true, scopeId: scope));
    notifyListeners();
    try {
      if (_actor == null) throw const AuthException('Authentication required');
      final rows = await read();
      if (!current()) return;
      final parsed = List<T>.unmodifiable(rows.map(parse));
      set(WorkAttendanceReadState(rows: parsed, scopeId: scope));
    } catch (failure) {
      if (!current()) return;
      final kind = workAttendanceErrorKind(failure);
      set(
        WorkAttendanceReadState(
          scopeId: scope,
          errorKind: kind,
          error: switch (kind) {
            WorkAttendanceError.authentication =>
              'Your session has expired. Sign in again.',
            WorkAttendanceError.permission => 'Attendance access is denied. Check your account and company permissions.',
            WorkAttendanceError.invalidData =>
              'Unable to read attendance data. Please refresh and retry.',
            WorkAttendanceError.connection =>
              'Unable to load attendance. Check your connection and retry.',
          },
        ),
      );
    }
    if (current()) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _subscription.cancel();
    _worker = const WorkAttendanceReadState();
    _company = const WorkAttendanceReadState();
    _evidence = const WorkAttendanceReadState();
    super.dispose();
  }
}

String attendanceActionError(Object failure) {
  if (workAttendanceErrorKind(failure) == WorkAttendanceError.authentication ||
      failure is PostgrestException &&
          failure.message == 'You must be signed in.') {
    return 'Your session has expired. Sign in again before recording attendance.';
  }
  if (failure is PostgrestException) {
    const serverMessages = {
      'Work assignment not found.',
      'You cannot check in to this assignment.',
      'You cannot check out of this assignment.',
      'This assignment is not available for check-in.',
      'Check-in is outside the allowed shift window.',
      'This assignment is not active.',
      'You must check in before checking out.',
      'You have already checked out.',
      'Check-out cannot precede check-in.',
    };
    if (serverMessages.contains(failure.message)) return failure.message;
    if (failure.code == '42501') {
      return 'Attendance access is denied. Refresh and check your account.';
    }
  }
  return 'Could not confirm the attendance action. Refresh and check the recorded state before retrying.';
}

WorkAttendanceError workAttendanceErrorKind(Object failure) {
  if (failure is AuthException) return WorkAttendanceError.authentication;
  if (failure is PostgrestException) {
    if (['PGRST301', 'PGRST302', 'PGRST303', '28000'].contains(failure.code) ||
        failure.message == 'Authentication required') {
      return WorkAttendanceError.authentication;
    }
    // The deployed PL/pgSQL authorization exceptions use default SQLSTATE P0001.
    if (failure.code == '42501' ||
        failure.message.startsWith('Not authorized')) {
      return WorkAttendanceError.permission;
    }
  }
  if (failure is FormatException) return WorkAttendanceError.invalidData;
  return WorkAttendanceError.connection;
}
