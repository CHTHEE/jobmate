import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_models.dart';
import 'work_evidence_draft_controller.dart';
import 'work_evidence_upload_repository.dart';

abstract class WorkEvidenceSubmissionSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<int> submit(
    String assignmentId,
    String description,
    List<String> paths,
  );
}

/// HTTP exact-count metadata is separate from the SQL row projection. A missing
/// or truncated response can never establish commitment or permit a retry.
class WorkEvidenceReconciliationRead {
  WorkEvidenceReconciliationRead(
    List<Map<String, dynamic>> rows, {
    required this.total,
  }) : rows = List.unmodifiable(
         rows.map((r) => Map<String, dynamic>.unmodifiable(r)),
       );
  final List<Map<String, dynamic>> rows;
  final int? total;
  List<Map<String, dynamic>> get completeRows {
    if (total == null || total != rows.length) {
      throw const FormatException('Incomplete evidence read');
    }
    return rows;
  }
}

abstract class WorkEvidenceSubmissionReadSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<WorkEvidenceReconciliationRead> listMyAssignments();
  Future<WorkEvidenceReconciliationRead> listEvidence(String assignmentId);
}

enum WorkEvidenceReconciliationStatus {
  committed,
  notEligibleOrChanged,
  uncertain,
}

class WorkEvidenceReconciliationResult {
  const WorkEvidenceReconciliationResult._(
    this._owner,
    this._generation,
    this._request,
    this.status, [
    this.submissionRound,
  ]);
  final Object _owner;
  final int _generation, _request;
  final WorkEvidenceReconciliationStatus status;
  final int? submissionRound;

  /// None of these states grants permission to submit again. In particular,
  /// changed eligibility is not proof that the original transaction failed.
  String get message => switch (status) {
    WorkEvidenceReconciliationStatus.committed => 'Fresh authorized evidence confirms the submitted batch. Refresh the assignment and evidence viewer.',
    WorkEvidenceReconciliationStatus.notEligibleOrChanged => 'The assignment is no longer eligible or has changed. Submission remains blocked; the original outcome is not confirmed.',
    WorkEvidenceReconciliationStatus.uncertain => 'Submission outcome remains uncertain. Do not retry; further authorized reconciliation is required.',
  };
}

enum WorkEvidenceSubmissionError {
  authentication,
  invalidDraft,
  invalidated,
  busy,
  alreadySubmitted,
  permission,
  rejected,
  reconciliationRequired,
}

/// Only an explicit database rejection proves this transaction rolled back.
/// Other transport errors, including authentication exceptions after dispatch,
/// are ambiguous. Never expose server messages/paths to a caller's UI.
class WorkEvidenceSubmissionRejected implements Exception {
  const WorkEvidenceSubmissionRejected(this.permission);
  final bool permission;
}

class SupabaseWorkEvidenceSubmissionSource
    implements WorkEvidenceSubmissionSource, WorkEvidenceSubmissionReadSource {
  SupabaseWorkEvidenceSubmissionSource(this.client);
  final SupabaseClient client;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);

  Future<WorkEvidenceReconciliationRead> _read(
    String function, [
    Map<String, dynamic>? parameters,
  ]) async {
    final actor = userId;
    if (actor == null) throw const AuthException('Authentication required');
    final response = await client
        .rpc(function, params: parameters)
        .count(CountOption.exact);
    if (actor != userId) throw const AuthException('Account changed');
    final data = response.data;
    if (data is! List || data.any((r) => r is! Map)) {
      throw const FormatException('Invalid evidence read');
    }
    return WorkEvidenceReconciliationRead(
      data.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
      total: response.count,
    );
  }

  @override
  Future<WorkEvidenceReconciliationRead> listMyAssignments() =>
      _read('list_my_work_assignments');
  @override
  Future<WorkEvidenceReconciliationRead> listEvidence(String assignmentId) =>
      _read('list_work_evidence', {'p_assignment_id': workUuid(assignmentId)});

  @override
  Future<int> submit(
    String assignmentId,
    String description,
    List<String> paths,
  ) async {
    try {
      final value = await client
          .rpc(
            'submit_work_evidence',
            params: {
              'p_assignment_id': assignmentId,
              'p_description': description,
              'p_storage_paths': paths,
            },
          )
          .retry(enabled: false, requestTimeout: const Duration(seconds: 30));
      if (value is! int || value < 1) {
        throw const FormatException('Unconfirmed submission response');
      }
      return value;
    } on PostgrestException catch (error) {
      // These are explicit PostgreSQL errors, not HTTP/gateway error guesses.
      if (error.code == '42501' || error.code == '28000') {
        throw const WorkEvidenceSubmissionRejected(true);
      }
      if (error.code == 'P0001' || error.code == '22023') {
        throw const WorkEvidenceSubmissionRejected(false);
      }
      rethrow;
    }
  }
}

enum _SubmissionLock { inFlight, confirmed, reconciliation }

/// Share across repository lifetimes. Default scope is the running app, so a
/// rebuilt UI cannot clear an ambiguous outcome (nor bypass a confirmed batch).
/// Positive reconciliation marks the original attempt confirmed; it never
/// unlocks this assignment for another round. This in-memory ledger
/// does not survive process restart/browser reload; future UI integration needs
/// a durable reconciliation gate before enabling submission across restarts.
class WorkEvidenceSubmissionLedger {
  final Map<(String, String), _SubmissionLock> _locks = {};
  final Map<(String, String), _SubmissionAttempt> _attempts = {};
}

class _SubmissionAttempt {
  _SubmissionAttempt(this.description, List<String> paths)
    : paths = List.unmodifiable(paths);
  final String description;
  final List<String> paths;
  int? round;
}

class WorkEvidenceSubmissionResult {
  const WorkEvidenceSubmissionResult._(
    this._owner,
    this._generation,
    this.error, [
    this.submissionRound,
  ]);
  final Object _owner;
  final int _generation;
  final WorkEvidenceSubmissionError? error;
  final int? submissionRound;
  bool get requiresRefresh => submissionRound != null;
  bool get requiresReconciliation =>
      error == WorkEvidenceSubmissionError.reconciliationRequired;
  String? get message => switch (error) {
    null => null,
    WorkEvidenceSubmissionError.authentication => 'Sign in before submitting.',
    WorkEvidenceSubmissionError.invalidDraft =>
      'Check the description and confirmed evidence files.',
    WorkEvidenceSubmissionError.invalidated => 'The draft or account changed. Refresh authorized evidence before continuing.',
    WorkEvidenceSubmissionError.busy => 'A submission is already in progress.',
    WorkEvidenceSubmissionError.alreadySubmitted => 'Evidence was submitted. Refresh authorized assignment and evidence data.',
    WorkEvidenceSubmissionError.permission =>
      'Evidence submission access denied.',
    WorkEvidenceSubmissionError.rejected =>
      'The server rejected this submission. Check assignment eligibility.',
    WorkEvidenceSubmissionError.reconciliationRequired => 'Submission outcome is unknown. Fresh authorized assignment and evidence reads are required before another attempt.',
  };
}

/// Service only; no UI wiring, uploads, cleanup writes, or automatic retries.
/// Caller owns source/upload/draft lifecycles. Success requests a refresh but
/// does not imply reads occurred. Check isCurrent before displaying results.
class WorkEvidenceSubmissionRepository {
  WorkEvidenceSubmissionRepository(
    this.source, {
    required this.uploads,
    WorkEvidenceSubmissionLedger? ledger,
    WorkEvidenceSubmissionReadSource? reads,
  }) : reads =
           reads ??
           (source is WorkEvidenceSubmissionReadSource
               ? source as WorkEvidenceSubmissionReadSource
               : null),
       _ledger = ledger ?? _appLedger {
    _actor = source.userId;
    _subscription = source.accountChanges.listen((id) {
      if (id != _actor || source.userId != _actor) {
        _actor = source.userId;
        ++_generation;
      }
    });
  }
  static final _appLedger = WorkEvidenceSubmissionLedger();
  final WorkEvidenceSubmissionSource source;
  final WorkEvidenceUploadRepository uploads;
  final WorkEvidenceSubmissionReadSource? reads;
  final WorkEvidenceSubmissionLedger _ledger;
  late final StreamSubscription<String?> _subscription;
  String? _actor;
  int _generation = 0;
  bool _disposed = false, _busy = false;
  bool _reconciling = false;
  int _reconciliationRequest = 0;

  bool isReconciliationCurrent(WorkEvidenceReconciliationResult result) =>
      !_disposed &&
      identical(result._owner, this) &&
      result._generation == _generation &&
      result._request == _reconciliationRequest &&
      _actor != null &&
      _actor == source.userId &&
      reads?.userId == _actor;

  /// Reconcile ONLY a recorded, trusted dispatched attempt. No UI-supplied
  /// descriptions or paths can be used as proof. Retains locks for changed,
  /// absent, failed, incomplete and ambiguous observations, including restarts of
  /// this repository using the same ledger. Does not survive an app restart.
  Future<WorkEvidenceReconciliationResult> reconcile({
    required String assignmentId,
  }) async {
    if (_actor != source.userId) {
      _actor = source.userId;
      ++_generation;
    }
    final actor = _actor, generation = _generation;
    if (!_reconciling) ++_reconciliationRequest;
    final request = _reconciliationRequest;
    WorkEvidenceReconciliationResult result(
      WorkEvidenceReconciliationStatus status, [
      int? round,
    ]) => WorkEvidenceReconciliationResult._(
      this,
      generation,
      request,
      status,
      round,
    );
    WorkEvidenceReconciliationResult uncertain() =>
        result(WorkEvidenceReconciliationStatus.uncertain);
    final reader = reads;
    if (_disposed ||
        _busy ||
        _reconciling ||
        actor == null ||
        reader == null ||
        reader.userId != actor) {
      return uncertain();
    }
    String id;
    try {
      id = workUuid(assignmentId);
    } on FormatException {
      return uncertain();
    }
    final key = (actor, id), attempt = _ledger._attempts[(actor, id)];
    if (attempt == null ||
        _ledger._locks[key] == null ||
        _ledger._locks[key] == _SubmissionLock.inFlight) {
      return uncertain();
    }
    var changed = false;
    final subscription = reader.accountChanges.listen((id) {
      if (id != actor) changed = true;
    });
    bool current() =>
        !_disposed &&
        !changed &&
        generation == _generation &&
        request == _reconciliationRequest &&
        actor == source.userId &&
        reader.userId == actor &&
        identical(attempt, _ledger._attempts[key]);
    WorkerWorkAssignment? assignment(WorkEvidenceReconciliationRead read) {
      final seen = <String>{};
      final matches = <WorkerWorkAssignment>[];
      for (final row in read.completeRows) {
        final item = WorkerWorkAssignment.fromJson(row);
        if (!seen.add(item.assignmentId)) {
          throw const FormatException('Ambiguous assignments');
        }
        if (item.assignmentId == id) matches.add(item);
      }
      return matches.singleOrNull;
    }

    _reconciling = true;
    try {
      final before = assignment(await reader.listMyAssignments());
      if (!current() || before == null) return uncertain();
      // The worker RPC independently proves current ownership and active role;
      // list_work_evidence has its own authorization check. UUIDs alone do not.
      final evidence = (await reader.listEvidence(id)).completeRows
          .map(WorkEvidence.fromJson)
          .toList();
      if (!current()) return uncertain();
      final ids = <String>{}, paths = <String>{};
      for (final row in evidence) {
        if (!ids.add(row.evidenceId) ||
            !paths.add(row.storagePath) ||
            !row.storagePath.startsWith('$id/')) {
          return uncertain();
        }
      }
      final after = assignment(await reader.listMyAssignments());
      if (!current() ||
          after == null ||
          before.applicationId != after.applicationId ||
          before.jobId != after.jobId ||
          before.companyId != after.companyId) {
        return uncertain();
      }
      if (evidence.isEmpty) return uncertain();
      final expected = attempt.paths.toSet();
      if (expected.isEmpty ||
          expected.length > 5 ||
          expected.length != attempt.paths.length ||
          expected.any((p) => !p.startsWith('$id/'))) {
        return uncertain();
      }
      final selected = evidence
          .where((e) => expected.contains(e.storagePath))
          .toList();
      if (selected.isNotEmpty) {
        final round = selected.first.submissionRound;
        final wholeRound = evidence
            .where((e) => e.submissionRound == round)
            .toList();
        if (selected.length != expected.length ||
            wholeRound.length != expected.length ||
            selected.any(
              (e) =>
                  e.submissionRound != round ||
                  e.submittedBy != actor ||
                  e.description != attempt.description,
            ) ||
            (attempt.round != null && attempt.round != round) ||
            after.verificationStatus == WorkVerificationStatus.notSubmitted ||
            after.checkInAt == null ||
            after.checkOutAt == null) {
          return uncertain();
        }
        attempt.round = round;
        _ledger._locks[key] = _SubmissionLock.confirmed;
        return result(WorkEvidenceReconciliationStatus.committed, round);
      }
      final eligible =
          after.assignmentStatus == WorkAssignmentStatus.awaitingVerification &&
          [
            WorkVerificationStatus.notSubmitted,
            WorkVerificationStatus.moreEvidenceRequired,
          ].contains(after.verificationStatus) &&
          after.checkInAt != null &&
          after.checkOutAt != null;
      return result(
        eligible
            ? WorkEvidenceReconciliationStatus.uncertain
            : WorkEvidenceReconciliationStatus.notEligibleOrChanged,
      );
    } catch (_) {
      return uncertain();
    } finally {
      _reconciling = false;
      // Cleanup must not hold the authoritative outcome behind stream shutdown.
      // The scoped listener is detached immediately; no further reads/writes run.
      unawaited(subscription.cancel());
    }
  }

  bool isCurrent(WorkEvidenceSubmissionResult result) =>
      !_disposed &&
      identical(result._owner, this) &&
      result._generation == _generation &&
      _actor != null &&
      _actor == source.userId &&
      result.error != WorkEvidenceSubmissionError.invalidated;

  Future<WorkEvidenceSubmissionResult> submit({
    required WorkEvidenceDraftController draft,
    required WorkEvidenceConfirmedBatch receipt,
  }) async {
    if (_actor != source.userId) {
      _actor = source.userId;
      ++_generation;
    }
    final generation = _generation, actor = _actor;
    WorkEvidenceSubmissionResult result(
      WorkEvidenceSubmissionError? error, [
      int? round,
    ]) => WorkEvidenceSubmissionResult._(this, generation, error, round);
    if (_disposed) return result(WorkEvidenceSubmissionError.invalidated);
    if (actor == null) {
      return result(WorkEvidenceSubmissionError.authentication);
    }
    if (_busy) return result(WorkEvidenceSubmissionError.busy);
    final key = (actor, receipt.assignmentId);
    final lock = _ledger._locks[key];
    if (lock != null) {
      return result(switch (lock) {
        _SubmissionLock.inFlight => WorkEvidenceSubmissionError.busy,
        _SubmissionLock.confirmed =>
          WorkEvidenceSubmissionError.alreadySubmitted,
        _SubmissionLock.reconciliation =>
          WorkEvidenceSubmissionError.reconciliationRequired,
      });
    }
    final description = draft.description;
    if (!draft.ready ||
        draft.descriptionError != null ||
        draft.session.userId != actor ||
        !uploads.isConfirmedBatchCurrent(receipt, draft: draft)) {
      return result(WorkEvidenceSubmissionError.invalidDraft);
    }
    var changed = false;
    bool current() =>
        !_disposed &&
        generation == _generation &&
        source.userId == actor &&
        draft.session.userId == actor &&
        !changed &&
        draft.description == description &&
        uploads.isConfirmedBatchCurrent(receipt, draft: draft);
    void observe() {
      if (!current()) changed = true;
    }

    draft.addListener(observe);
    uploads.addListener(observe);
    _busy = true;
    var dispatched = false;
    try {
      // Yield before dispatch; observe transient edits, including change-back.
      await Future<void>.value();
      if (!current()) return result(WorkEvidenceSubmissionError.invalidated);
      // Atomic with dispatch in this isolate; another repository may have
      // acquired the shared assignment lock during preparation.
      if (_ledger._locks.containsKey(key)) {
        return result(WorkEvidenceSubmissionError.busy);
      }
      _ledger._locks[key] = _SubmissionLock.inFlight;
      final attempt = _SubmissionAttempt(
        description.trim(),
        receipt.uploadedPaths,
      );
      _ledger._attempts[key] = attempt;
      dispatched = true;
      final round = await source.submit(
        receipt.assignmentId,
        description.trim(),
        receipt.uploadedPaths,
      );
      if (round < 1) throw const FormatException('Unconfirmed round');
      // Preserve remote outcome even if its local account/draft was invalidated.
      _ledger._locks[key] = _SubmissionLock.confirmed;
      attempt.round = round;
      if (!current()) return result(WorkEvidenceSubmissionError.invalidated);
      return result(null, round);
    } catch (error) {
      if (dispatched) {
        if (error is WorkEvidenceSubmissionRejected) {
          _ledger._locks.remove(key); // Explicit transaction rollback only.
          _ledger._attempts.remove(key);
        } else {
          _ledger._locks[key] = _SubmissionLock.reconciliation;
        }
      }
      if (!current()) return result(WorkEvidenceSubmissionError.invalidated);
      if (error is WorkEvidenceSubmissionRejected) {
        return result(
          error.permission
              ? WorkEvidenceSubmissionError.permission
              : WorkEvidenceSubmissionError.rejected,
        );
      }
      return result(WorkEvidenceSubmissionError.reconciliationRequired);
    } finally {
      draft.removeListener(observe);
      uploads.removeListener(observe);
      _busy = false;
    }
  }

  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_subscription.cancel());
    // Intentionally retain assignment locks, including in-flight requests.
  }
}
