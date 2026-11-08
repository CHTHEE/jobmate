import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_models.dart';
import 'work_evidence_draft_controller.dart';
import 'work_evidence_upload_repository.dart';

abstract class WorkEvidenceWorkflowSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<Object?> call(String rpc, Map<String, dynamic> parameters);
}

class SupabaseWorkEvidenceWorkflowSource implements WorkEvidenceWorkflowSource {
  SupabaseWorkEvidenceWorkflowSource(this.client);
  final SupabaseClient client;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((e) => e.session?.user.id);
  @override
  Future<Object?> call(String rpc, Map<String, dynamic> parameters) async {
    final actor = userId;
    if (actor == null) throw const AuthException('Authentication required');
    final value = await client
        .rpc(rpc, params: parameters)
        .retry(enabled: false, requestTimeout: const Duration(seconds: 30));
    if (actor != userId) throw const AuthException('Account changed');
    return value;
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) throw const FormatException('Invalid workflow response');
  return Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(value));
}

int _round(Object? value, {bool zero = false}) {
  if (value is! int || value < (zero ? 0 : 1)) {
    throw const FormatException('Invalid round');
  }
  return value;
}

class WorkEvidenceHistoryEvent {
  WorkEvidenceHistoryEvent(Map<String, dynamic> row)
    : id = workUuid(row['verification_id']),
      action = row['action'] as String,
      round = row['submission_round'] == null
          ? null
          : _round(row['submission_round']),
      note = row['note'] as String?,
      actorId = workUuid(row['performed_by']),
      at = DateTime.parse(row['created_at'] as String).toUtc() {
    if (![
          'evidence_submitted',
          'evidence_resubmitted',
          'more_evidence_requested',
          'verified',
          'disputed',
        ].contains(action) ||
        !RegExp(
          r'(Z|[+-]\d{2}:?\d{2})$',
          caseSensitive: false,
        ).hasMatch(row['created_at'] as String)) {
      throw const FormatException('Invalid verification history');
    }
  }
  final String id, action, actorId;
  final int? round;
  final String? note;
  final DateTime at;
}

class WorkEvidenceWorkflowSnapshot {
  WorkEvidenceWorkflowSnapshot(
    Object? value,
    String assignmentId,
    bool employer,
  ) {
    final row = _map(value);
    if (row['contract_version'] != 1 ||
        workUuid(row['assignment_id']) != assignmentId ||
        row['viewer_role'] != (employer ? 'employer' : 'worker') ||
        row['attendance_complete'] is! bool ||
        row['attempts'] is! List ||
        row['history'] is! List) {
      throw const FormatException('Workflow contract unavailable');
    }
    round = _round(row['latest_round'], zero: true);
    assignmentStatus = WorkAssignmentStatus.parse(row['assignment_status']);
    verificationStatus = WorkVerificationStatus.parse(
      row['verification_status'],
    );
    attendanceComplete = row['attendance_complete'] as bool;
    attempts = List.unmodifiable((row['attempts'] as List).map(_map));
    review = row['review'] == null ? null : _map(row['review']);
    final ids = <String>{};
    history = List.unmodifiable(
      (row['history'] as List).map((raw) {
        final item = _map(raw);
        if (workUuid(item['assignment_id']) != assignmentId) {
          throw const FormatException('History scope changed');
        }
        final event = WorkEvidenceHistoryEvent(item);
        if (!ids.add(event.id) ||
            (event.round != null && event.round! > round)) {
          throw const FormatException('Ambiguous history');
        }
        return event;
      }),
    );
    final rounds = <int>{};
    for (final attempt in attempts) {
      _validateRequest(attempt, assignmentId, review: false);
      if ((attempt['target_round'] as int) > round + 1) {
        throw const FormatException('Future attempt round');
      }
      if (!rounds.add(_round(attempt['target_round']))) {
        throw const FormatException('Duplicate attempts');
      }
    }
    if (review != null) {
      _validateRequest(review!, assignmentId, review: true);
      if (review!['submission_round'] != round) {
        throw const FormatException('Review round changed');
      }
    }
  }
  late final int round;
  late final bool attendanceComplete;
  late final WorkAssignmentStatus assignmentStatus;
  late final WorkVerificationStatus verificationStatus;
  late final List<Map<String, dynamic>> attempts;
  late final Map<String, dynamic>? review;
  late final List<WorkEvidenceHistoryEvent> history;
  Map<String, dynamic>? get pendingAttempt =>
      attempts.where((a) => a['target_round'] == round + 1).firstOrNull;
  bool get canSubmit =>
      attendanceComplete &&
      assignmentStatus == WorkAssignmentStatus.awaitingVerification &&
      ((round == 0 &&
              verificationStatus == WorkVerificationStatus.notSubmitted) ||
          (round > 0 &&
              verificationStatus ==
                  WorkVerificationStatus.moreEvidenceRequired));
  bool get canReview =>
      round > 0 &&
      assignmentStatus == WorkAssignmentStatus.awaitingVerification &&
      verificationStatus == WorkVerificationStatus.pendingReview;
}

void _validateRequest(
  Map<String, dynamic> row,
  String assignment, {
  required bool review,
}) {
  workUuid(row['request_id']);
  if (workUuid(row['assignment_id']) != assignment ||
      !(review
              ? ['prepared', 'committed']
              : ['prepared', 'committed', 'blocked'])
          .contains(row['state'])) {
    throw const FormatException('Invalid request identity');
  }
  _round(row[review ? 'submission_round' : 'target_round']);
  if (!review) {
    final paths = row['storage_paths'];
    final description = row['description'];
    if (description is! String ||
        description.trim().isEmpty ||
        description.runes.length > 2000 ||
        paths is! List ||
        paths.isEmpty ||
        paths.length > 5 ||
        paths.toSet().length != paths.length ||
        paths.any(
          (p) =>
              p is! String ||
              !RegExp(
                '^$assignment/[A-Za-z0-9][A-Za-z0-9._-]{0,199}\\.(jpg|jpeg|png|webp|pdf)\$',
              ).hasMatch(p),
        )) {
      throw const FormatException('Invalid reserved evidence payload');
    }
  }
  workUuid(row[review ? 'actor_id' : 'worker_id']);
  if (row['state'] == 'committed') {
    workUuid(row[review ? 'history_id' : 'submission_id']);
  }
  if (review &&
      (!['verified', 'more_evidence_requested'].contains(row['decision']) ||
          (row['decision'] == 'more_evidence_requested' &&
              (row['reason'] is! String ||
                  (row['reason'] as String).trim().isEmpty)))) {
    throw const FormatException('Invalid review decision');
  }
}

class _WriteGate {
  bool running = false;
  String? requestId;
}

class WorkEvidenceWorkflowLedger {
  final _gates = <(String, String, bool, int), _WriteGate>{};
}

final _appLedger = WorkEvidenceWorkflowLedger();

/// Durable round reservations are authoritative; local locks additionally block
/// reopening an uncertain upload/preparation. Empty reads never unlock a write.
class WorkEvidenceWorkflowController extends ChangeNotifier {
  WorkEvidenceWorkflowController(
    this.source, {
    required this.assignmentId,
    required this.employer,
    WorkEvidenceWorkflowLedger? ledger,
  }) : ledger = ledger ?? _appLedger,
       _actor = source.userId {
    _subscription = source.accountChanges.listen((id) {
      if (id != _actor || source.userId != _actor) {
        _invalidated = true;
        _snapshot = null;
        ++_read;
        if (!_disposed) notifyListeners();
      }
    });
  }
  final WorkEvidenceWorkflowSource source;
  final String assignmentId;
  final bool employer;
  final WorkEvidenceWorkflowLedger ledger;
  final String? _actor;
  late final StreamSubscription<String?> _subscription;
  bool _disposed = false, _invalidated = false;
  int _read = 0;
  bool busy = false, loading = false;
  String? message;
  WorkEvidenceWorkflowSnapshot? _snapshot;
  bool get current =>
      !_disposed && !_invalidated && _actor != null && source.userId == _actor;
  WorkEvidenceWorkflowSnapshot? get snapshot => current ? _snapshot : null;
  (String, String, bool, int) _key(int round) =>
      (_actor ?? '', assignmentId, employer, round);
  bool get newWriteBlocked {
    final value = snapshot;
    return !current ||
        busy ||
        value == null ||
        ledger._gates.containsKey(
          _key(employer ? value.round : value.round + 1),
        );
  }

  Future<void> load() async {
    if (!current) return;
    final request = ++_read;
    loading = true;
    _snapshot = null;
    notifyListeners();
    try {
      final raw = await source.call('work_evidence_workflow_context', {
        'p_assignment_id': workUuid(assignmentId),
      });
      if (!current || request != _read) return;
      final value = WorkEvidenceWorkflowSnapshot(raw, assignmentId, employer);
      for (final a in value.attempts) {
        if (a['worker_id'] != _actor) {
          throw const FormatException('Attempt owner changed');
        }
      }
      _snapshot = value;
      final requests = employer
          ? [if (value.review != null) value.review!]
          : value.attempts;
      for (final request in requests) {
        final target =
            request[employer ? 'submission_round' : 'target_round'] as int;
        if (request['state'] == 'committed' &&
            ledger._gates[_key(target)]?.requestId == request['request_id']) {
          message = employer ? 'Review recorded.' : 'Evidence submitted.';
        }
      }
      // Storage can accept an upload before the durable prepare RPC creates a
      // reservation. Keep the local gate until a fresh server snapshot confirms
      // the round remains eligible and has no reservation. The prepare RPC
      // serializes on the assignment row and has a unique (assignment, round)
      // constraint, so a late prepare cannot create a second submission.
      // Any orphaned Storage objects are deliberately left untouched.
      if (!employer && value.canSubmit && value.pendingAttempt == null) {
        final key = _key(value.round + 1);
        final gate = ledger._gates[key];
        if (gate != null && !gate.running && gate.requestId == null) {
          ledger._gates.remove(key);
          message =
              'Refresh found no reserved evidence action. You can submit again; any unreferenced uploaded files were left untouched.';
        }
      }
    } catch (_) {
      if (current && request == _read) message = 'Secure evidence workflow could not be loaded. Check access and server setup, then refresh.';
    } finally {
      if (current && request == _read) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> submit(
    WorkEvidenceDraftController draft,
    WorkEvidenceUploadRepository uploads,
  ) async {
    final before = snapshot;
    if (employer ||
        before == null ||
        !before.canSubmit ||
        before.pendingAttempt != null ||
        newWriteBlocked ||
        !draft.ready ||
        draft.assignmentId != assignmentId ||
        draft.session.userId != _actor ||
        uploads.source.userId != _actor) {
      return false;
    }
    final round = before.round;
    final key = _key(round + 1);
    final gate = _WriteGate()..running = true;
    ledger._gates[key] = gate; // Before any await, across controller lifetimes.
    busy = true;
    notifyListeners();
    final description = draft.description;
    final files = List.of(draft.files);
    var uploadDispatched = false;
    bool draftCurrent() =>
        current &&
        draft.assignmentId == assignmentId &&
        draft.session.userId == _actor &&
        draft.description == description &&
        listEquals(files, draft.files);
    try {
      await load();
      if (!draftCurrent() ||
          snapshot?.round != round ||
          snapshot?.canSubmit != true ||
          snapshot?.pendingAttempt != null) {
        return false;
      }
      uploadDispatched = true;
      final uploaded = await uploads.upload(files);
      if (!draftCurrent() ||
          !uploaded.complete ||
          !uploads.isCurrent(uploaded)) {
        message = 'Upload could not be confirmed. Files may exist. Do not upload again; refresh to recover any reserved submission.';
        return false;
      }
      final receipt = uploads.validateConfirmedBatch(
        result: uploaded,
        draft: draft,
      );
      if (receipt == null ||
          !uploads.isConfirmedBatchCurrent(receipt, draft: draft)) {
        throw const FormatException('Draft changed');
      }
      final attempt = _map(
        await source.call('prepare_my_work_evidence_submission', {
          'p_assignment_id': assignmentId,
          'p_expected_previous_round': round,
          'p_description': description.trim(),
          'p_storage_paths': receipt.uploadedPaths,
        }),
      );
      if (!draftCurrent()) return false;
      _validateRequest(attempt, assignmentId, review: false);
      if (attempt['worker_id'] != _actor ||
          attempt['target_round'] != round + 1 ||
          attempt['description'] != description.trim() ||
          !listEquals(
            attempt['storage_paths'] as List?,
            receipt.uploadedPaths,
          )) {
        throw const FormatException('Reserved payload changed');
      }
      gate.requestId = attempt['request_id'] as String;
      return await _commit(attempt, review: false);
    } catch (_) {
      if (current) message = 'Submission outcome is uncertain. Refresh for request-based recovery. Do not upload or submit a new batch.';
    } finally {
      gate.running = false;
      if (!uploadDispatched) ledger._gates.remove(key);
      busy = false;
      if (current) {
        await load();
        if (current) notifyListeners();
      }
    }
    return false;
  }

  Future<bool> review(String decision, String? reason) async {
    final before = snapshot;
    if (!employer ||
        before == null ||
        !before.canReview ||
        before.review != null ||
        newWriteBlocked ||
        !['verified', 'more_evidence_requested'].contains(decision) ||
        (decision == 'more_evidence_requested' &&
            (reason == null ||
                reason.trim().isEmpty ||
                reason.trim().runes.length > 1000))) {
      return false;
    }
    final gate = _WriteGate()..running = true;
    ledger._gates[_key(before.round)] = gate;
    busy = true;
    notifyListeners();
    try {
      final request = _map(
        await source.call('prepare_work_evidence_review', {
          'p_assignment_id': assignmentId,
          'p_expected_round': before.round,
          'p_decision': decision,
          'p_reason': decision == 'verified' ? null : reason!.trim(),
        }),
      );
      if (!current) return false;
      _validateRequest(request, assignmentId, review: true);
      if (request['actor_id'] != _actor ||
          request['submission_round'] != before.round ||
          request['decision'] != decision ||
          request['reason'] !=
              (decision == 'verified' ? null : reason!.trim())) {
        throw const FormatException('Review changed');
      }
      gate.requestId = request['request_id'] as String;
      return await _commit(request, review: true);
    } catch (_) {
      if (current) message = 'Review outcome is uncertain. Refresh to recover the original decision; do not choose another decision.';
    } finally {
      gate.running = false;
      busy = false;
      if (current) {
        await load();
        if (current) notifyListeners();
      }
    }
    return false;
  }

  Future<bool> resume() async {
    final before = snapshot;
    if (!current || busy || before == null) return false;
    final request = employer ? before.review : before.pendingAttempt;
    if (request == null ||
        request['state'] != 'prepared' ||
        request[employer ? 'actor_id' : 'worker_id'] != _actor) {
      return false;
    }
    final round = _round(
      request[employer ? 'submission_round' : 'target_round'],
    );
    final gate = ledger._gates.putIfAbsent(_key(round), _WriteGate.new);
    if (gate.running) return false;
    gate.requestId = request['request_id'] as String;
    gate.running = true;
    busy = true;
    notifyListeners();
    try {
      return await _commit(request, review: employer);
    } catch (_) {
      if (current) message = 'Outcome remains uncertain. Refresh to reconcile this same server request.';
    } finally {
      gate.running = false;
      busy = false;
      if (current) {
        await load();
        if (current) notifyListeners();
      }
    }
    return false;
  }

  Future<bool> _commit(
    Map<String, dynamic> request, {
    required bool review,
  }) async {
    if (!current) return false;
    if (request['state'] == 'blocked') {
      message = 'The server blocked this reserved round. Contact support; no replacement attempt is allowed.';
      return false;
    }
    final result = request['state'] == 'committed'
        ? request
        : _map(
            await source.call(
              review
                  ? 'commit_work_evidence_review'
                  : 'submit_work_evidence_idempotent',
              {
                'p_assignment_id': assignmentId,
                'p_request_id': request['request_id'],
              },
            ),
          );
    if (!current) return false;
    _validateRequest(result, assignmentId, review: review);
    if (!['committed', 'blocked'].contains(result['state']) ||
        (review &&
            (result['decision'] != request['decision'] ||
                result['reason'] != request['reason'])) ||
        (!review &&
            (result['description'] != request['description'] ||
                !listEquals(
                  result['storage_paths'] as List?,
                  request['storage_paths'] as List?,
                )))) {
      throw const FormatException('Request outcome or payload changed');
    }
    if (result['request_id'] != request['request_id'] ||
        result[review ? 'submission_round' : 'target_round'] !=
            request[review ? 'submission_round' : 'target_round'] ||
        result[review ? 'actor_id' : 'worker_id'] != _actor) {
      throw const FormatException('Request identity changed');
    }
    message = result['state'] == 'committed'
        ? (review ? 'Review recorded.' : 'Evidence submitted.')
        : 'The reserved round is blocked. Do not create another attempt; contact support.';
    return result['state'] == 'committed';
  }

  @override
  void dispose() {
    _disposed = true;
    ++_read;
    _snapshot = null;
    _subscription.cancel();
    super.dispose();
  }
}
