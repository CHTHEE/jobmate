import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'work_attendance_models.dart';

abstract class WorkAttendanceResolutionSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<Map<String, dynamic>> read(String assignmentId);
  Future<Map<String, dynamic>> resolve(Map<String, dynamic> payload);
}

class SupabaseWorkAttendanceResolutionSource
    implements WorkAttendanceResolutionSource {
  SupabaseWorkAttendanceResolutionSource(this.client);
  final SupabaseClient client;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((e) => e.session?.user.id);
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> parameters,
  ) async {
    final actor = userId;
    if (actor == null) throw const AuthException('Authentication required.');
    final value = await client
        .rpc(name, params: parameters)
        .retry(enabled: false, requestTimeout: const Duration(seconds: 30));
    if (userId != actor) throw const AuthException('Account changed.');
    if (value is! Map) {
      throw const FormatException('Invalid attendance review response.');
    }
    return Map<String, dynamic>.from(value);
  }

  @override
  Future<Map<String, dynamic>> read(String assignmentId) => _call(
    'read_work_attendance_resolution',
    {'p_assignment_id': workUuid(assignmentId)},
  );
  @override
  Future<Map<String, dynamic>> resolve(Map<String, dynamic> payload) =>
      _call('resolve_work_attendance', payload);
}

/// One immutable payload/request ID survives an uncertain response. No automatic
/// submission/retry, optimistic outcome, or cross-account continuation.
class WorkAttendanceResolutionController extends ChangeNotifier {
  WorkAttendanceResolutionController(this.source, this.assignmentId)
    : _actor = source.userId {
    _subscription = source.accountChanges.listen((_) {
      if (source.userId != _actor) {
        ++_generation;
        snapshot = null;
        _attempt = null;
        message = 'Account changed. Close this review.';
        notifyListeners();
      }
    });
  }
  final WorkAttendanceResolutionSource source;
  final String assignmentId;
  final String? _actor;
  late final StreamSubscription<String?> _subscription;
  bool _disposed = false, busy = false, uncertain = false;
  int _generation = 0;
  WorkAttendanceResolution? snapshot;
  Map<String, dynamic>? _attempt;
  String? message;
  bool get current => !_disposed && _actor != null && source.userId == _actor;
  bool get resolved => current && snapshot?.decision != null;
  bool _matchesAttempt(WorkAttendanceResolution value) =>
      _attempt != null &&
      value.requestId == _attempt!['p_request_id'] &&
      value.decision == _attempt!['p_decision'] &&
      value.actorId == _actor &&
      value.reason == _attempt!['p_reason'] &&
      value.correctedCheckInAt?.toUtc().toIso8601String() ==
          _attempt!['p_check_in_at'] &&
      value.correctedCheckOutAt?.toUtc().toIso8601String() ==
          _attempt!['p_check_out_at'];

  Future<void> load() async {
    if (!current || busy) return;
    final generation = _generation;
    busy = true;
    notifyListeners();
    try {
      final next = WorkAttendanceResolution.fromJson(
        await source.read(assignmentId),
        assignmentId,
      );
      if (!current || generation != _generation) return;
      snapshot = next;
      if (_matchesAttempt(next)) {
        uncertain = false;
        message = 'Attendance resolution recorded.';
      } else if (next.decision != null && _attempt != null) {
        uncertain = false;
        message = 'A different resolution is already recorded. Review its audit; your requested change was not confirmed.';
      } else if (!uncertain) {
        message = null;
      }
    } catch (_) {
      if (current && generation == _generation) {
        snapshot = null;
        message =
            'Unable to refresh attendance review. Check access and retry.';
      }
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> submit({
    required String decision,
    required String reason,
    DateTime? input,
    DateTime? output,
  }) async {
    if (!current || busy || uncertain || resolved || snapshot == null) return;
    final before = snapshot!;
    if (reason.trim().isEmpty ||
        reason.trim().length > 2000 ||
        (decision == 'confirmed_absent' &&
            (!before.canConfirmAbsence || input != null || output != null)) ||
        (decision == 'corrected' &&
            (!before.canCorrect ||
                input == null ||
                output == null ||
                output.isBefore(input))) ||
        !{'confirmed_absent', 'corrected'}.contains(decision)) {
      message = 'Choose an eligible decision, valid times and a reason.';
      notifyListeners();
      return;
    }
    _attempt = Map.unmodifiable({
      'p_assignment_id': assignmentId,
      'p_request_id': const Uuid().v4(),
      'p_expected_version': before.version,
      'p_decision': decision,
      'p_reason': reason.trim(),
      'p_check_in_at': input?.toUtc().toIso8601String(),
      'p_check_out_at': output?.toUtc().toIso8601String(),
    });
    await _send();
  }

  Future<void> retrySame() async {
    if (current && uncertain && !busy && !resolved && _attempt != null) {
      await _send();
    }
  }

  Future<void> _send() async {
    final generation = _generation;
    busy = true;
    message = null;
    notifyListeners();
    try {
      final next = WorkAttendanceResolution.fromJson(
        await source.resolve(_attempt!),
        assignmentId,
      );
      if (!current || generation != _generation) return;
      if (!_matchesAttempt(next)) {
        throw const FormatException('Unconfirmed resolution.');
      }
      snapshot = next;
      uncertain = false;
      message = 'Attendance resolution recorded.';
    } catch (error) {
      if (!current || generation != _generation) return;
      final rejected =
          error is PostgrestException &&
          {'22023', '42501', '28000', '55P03'}.contains(error.code);
      uncertain = !rejected;
      if (rejected) _attempt = null;
      message = rejected
          ? 'The server rejected this review. Refresh attendance before reviewing again.'
          : 'The outcome is uncertain. Check the saved resolution before retrying the same request.';
      // Reconcile once, without resubmitting. An absent result is not proof of failure.
      try {
        final next = WorkAttendanceResolution.fromJson(
          await source.read(assignmentId),
          assignmentId,
        );
        if (!current || generation != _generation) return;
        snapshot = next;
        if (_matchesAttempt(next)) {
          uncertain = false;
          message = 'Attendance resolution recorded.';
        } else if (next.decision != null && _attempt != null) {
          uncertain = false;
          message = 'A different resolution is already recorded. Review its audit; your requested change was not confirmed.';
        }
      } catch (_) {
        if (current) snapshot = null;
      }
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _subscription.cancel();
    super.dispose();
  }
}
