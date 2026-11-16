import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_attendance_lifecycle.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';
import 'package:jobmate/features/work_attendance/work_attendance_resolution.dart';
import 'package:jobmate/features/work_attendance/work_evidence_deadline.dart';
import 'package:jobmate/features/work_attendance/work_evidence_workflow.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_lifecycle_test.dart' show lifecycleRow;
import 'work_attendance_repository_test.dart' show id, other;

Map<String, dynamic> resolutionContext({
  Map<String, dynamic>? resolution,
  bool absence = true,
  bool correction = true,
}) => {
  'contract_version': 2,
  'assignment_id': id,
  'version': 'a' * 32,
  'can_confirm_absence': absence,
  'can_correct': correction,
  'checkout_recovery_enforced': true,
  'recovery_cutoff': '2026-11-06T09:00:00Z',
  'resolution': resolution,
};
Map<String, dynamic> auditFor(Map<String, dynamic> payload) => {
  'request_id': payload['p_request_id'],
  'resolved_by': id,
  'decision': payload['p_decision'],
  'reason': payload['p_reason'],
  'resolved_at': '2026-11-07T09:00:00Z',
  'corrected_check_in_at': payload['p_check_in_at'],
  'corrected_check_out_at': payload['p_check_out_at'],
};

class ResolutionSource implements WorkAttendanceResolutionSource {
  @override
  String? userId = id;
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get accountChanges => changes.stream;
  Map<String, dynamic> context = resolutionContext();
  final writes = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? write;
  @override
  Future<Map<String, dynamic>> read(String assignmentId) async => context;
  @override
  Future<Map<String, dynamic>> resolve(Map<String, dynamic> payload) async {
    writes.add(Map.of(payload));
    if (write != null) return write!(payload);
    return context = resolutionContext(
      resolution: auditFor(payload),
      absence: false,
      correction: false,
    );
  }
}

void main() {
  late ResolutionSource source;
  late WorkAttendanceResolutionController controller;
  setUp(() {
    source = ResolutionSource();
    controller = WorkAttendanceResolutionController(source, id);
  });
  tearDown(() async {
    controller.dispose();
    await source.changes.close();
  });

  test('server eligibility plus required reason; no write on loading or invalid selection', () async {
    await controller.submit(decision: 'confirmed_absent', reason: 'attended?');
    expect(source.writes, isEmpty);
    await controller.load();
    await controller.submit(decision: 'confirmed_absent', reason: '   ');
    expect(source.writes, isEmpty);
    await controller.submit(
      decision: 'confirmed_absent',
      reason: ' No attendance confirmed ',
    );
    expect(source.writes, hasLength(1));
    expect(source.writes.single['p_reason'], 'No attendance confirmed');
    expect(controller.resolved, isTrue);
    expect(controller.snapshot!.decision, 'confirmed_absent');
    await controller.submit(decision: 'confirmed_absent', reason: 'duplicate');
    expect(source.writes, hasLength(1));
  });
  test('server disallows absence when attendance exists; correction requires chronological times', () async {
    source.context = resolutionContext(absence: false);
    await controller.load();
    await controller.submit(
      decision: 'confirmed_absent',
      reason: 'incorrect shortcut',
    );
    await controller.submit(
      decision: 'corrected',
      reason: 'actual attendance',
      input: DateTime.utc(2026, 11, 5, 9),
      output: DateTime.utc(2026, 11, 5, 1),
    );
    expect(source.writes, isEmpty);
    await controller.submit(
      decision: 'corrected',
      reason: 'actual attendance',
      input: DateTime.utc(2026, 11, 5, 1),
      output: DateTime.utc(2026, 11, 5, 8),
    );
    expect(controller.snapshot!.decision, 'corrected');
  });
  for (final code in ['42501', '22023', '55P03']) {
    test(
      'server denial/conflict $code creates no optimistic success or automatic retry',
      () async {
        source.write = (_) async =>
            throw PostgrestException(message: 'denied', code: code);
        await controller.load();
        await controller.submit(
          decision: 'confirmed_absent',
          reason: 'reviewed',
        );
        expect(controller.resolved, isFalse);
        expect(controller.uncertain, isFalse);
        expect(source.writes, hasLength(1));
      },
    );
  }
  test('lost committed response reconciles the same request without a second write', () async {
    source.write = (payload) async {
      source.context = resolutionContext(resolution: auditFor(payload));
      throw Exception('lost response');
    };
    await controller.load();
    await controller.submit(decision: 'confirmed_absent', reason: 'reviewed');
    expect(controller.resolved, isTrue);
    expect(controller.uncertain, isFalse);
    expect(source.writes, hasLength(1));
  });
  test(
    'uncertain retry preserves identical immutable ID and payload',
    () async {
      source.write = (_) async => throw Exception('offline');
      await controller.load();
      await controller.submit(decision: 'confirmed_absent', reason: 'reviewed');
      expect(controller.uncertain, isTrue);
      await controller.submit(
        decision: 'confirmed_absent',
        reason: 'replacement not allowed',
      );
      expect(source.writes, hasLength(1));
      source.write = null;
      await controller.retrySame();
      expect(source.writes, hasLength(2));
      expect(source.writes.first, source.writes.last);
      expect(controller.resolved, isTrue);
    },
  );
  test('busy submission blocks concurrent taps and account change drops stale completion', () async {
    final result = Completer<Map<String, dynamic>>();
    source.write = (_) => result.future;
    await controller.load();
    final sending = controller.submit(
      decision: 'confirmed_absent',
      reason: 'reviewed',
    );
    await controller.submit(decision: 'confirmed_absent', reason: 'duplicate');
    expect(source.writes, hasLength(1));
    source.userId = other;
    source.changes.add(other);
    result.complete(
      resolutionContext(resolution: auditFor(source.writes.single)),
    );
    await sending;
    expect(controller.snapshot, isNull);
    expect(controller.current, isFalse);
  });
  test('scope/contract validation fails closed for a different shift', () {
    expect(
      () => WorkAttendanceResolution.fromJson(
        resolutionContext()..['assignment_id'] = other,
        id,
      ),
      throwsFormatException,
    );
    expect(
      () => WorkAttendanceResolution.fromJson(
        resolutionContext()..['contract_version'] = 1,
        id,
      ),
      throwsFormatException,
    );
  });
  test('corrected attendance preserves originals, remains unverified and uses effective advisory timing', () {
    final audit = auditFor({
      'p_request_id': other,
      'p_decision': 'corrected',
      'p_reason': 'Missing checkout confirmed',
      'p_check_in_at': '2026-11-05T01:00:00Z',
      'p_check_out_at': '2026-11-05T08:00:00Z',
    });
    final row = WorkerWorkAssignment.fromJson(
      lifecycleRow(now: '2026-11-07T10:00:00Z', status: 'awaiting_verification')
        ..['attendance_resolution'] = resolutionContext(resolution: audit),
    );
    expect(row.checkInAt, isNull);
    expect(row.checkOutAt, isNull);
    expect(row.effectiveCheckInAt, DateTime.utc(2026, 11, 5, 1));
    expect(row.verificationStatus, WorkVerificationStatus.notSubmitted);
    expect(AttendanceLifecycle.of(row), AttendanceLifecycle.corrected);
    expect(AttendanceLifecycle.of(row).isIssue, isFalse);
    expect(AttendanceHistoryFilter.recorded.matches(row), isTrue);
    final timing = EvidenceDeadline.fromAssignment(
      row,
      now: DateTime.utc(2026, 11, 7, 10),
    );
    expect(timing.dueAt, DateTime.utc(2026, 11, 6, 8));
    expect(timing.state, EvidenceDeadlineState.overdue);
  });
  test('manual correction retains server evidence eligibility and never auto-verifies', () {
    final context = <String, dynamic>{
      'contract_version': 1,
      'assignment_id': id,
      'viewer_role': 'worker',
      'latest_round': 0,
      'assignment_status': 'awaiting_verification',
      'verification_status': 'not_submitted',
      'attendance_complete': false,
      'attempts': [],
      'review': null,
      'history': [],
    };
    expect(WorkEvidenceWorkflowSnapshot(context, id, false).canSubmit, isFalse);
    context['attendance_complete'] = true;
    final ready = WorkEvidenceWorkflowSnapshot(context, id, false);
    expect(ready.canSubmit, isTrue);
    expect(ready.canReview, isFalse);
    expect(ready.verificationStatus, WorkVerificationStatus.notSubmitted);
  });
  test(
    'historical correction can recover actual checkout beyond ordinary cutoff',
    () async {
      source.context = resolutionContext(absence: false);
      await controller.load();
      await controller.submit(
        decision: 'corrected',
        reason: 'Actual later checkout explicitly confirmed',
        input: DateTime.utc(2026, 11, 5, 1),
        output: DateTime.utc(2026, 11, 6, 12),
      );
      expect(controller.resolved, isTrue);
      expect(
        controller.snapshot!.correctedCheckOutAt,
        DateTime.utc(2026, 11, 6, 12),
      );
      expect(
        source.writes.single['p_check_out_at'],
        '2026-11-06T12:00:00.000Z',
      );
    },
  );
  test(
    'a competing saved audit never confirms our uncertain payload',
    () async {
      source.write = (payload) async {
        source.context = resolutionContext(
          resolution: auditFor({
            ...payload,
            'p_request_id': other,
            'p_reason': 'Another authorized review',
          }),
        );
        throw TimeoutException('Response lost');
      };
      await controller.load();
      await controller.submit(
        decision: 'confirmed_absent',
        reason: 'Our review',
      );
      expect(controller.resolved, isTrue);
      expect(controller.uncertain, isFalse);
      expect(controller.snapshot!.reason, 'Another authorized review');
      expect(
        controller.message,
        contains('your requested change was not confirmed'),
      );
      await controller.retrySame();
      expect(source.writes, hasLength(1));
    },
  );
  test('confirmed absence is historical but never Recorded, verified or unresolved', () {
    final audit = auditFor({
      'p_request_id': other,
      'p_decision': 'confirmed_absent',
      'p_reason': 'No attendance confirmed',
    });
    final row = WorkerWorkAssignment.fromJson(
      lifecycleRow()
        ..['attendance_resolution'] = resolutionContext(resolution: audit),
    );
    expect(AttendanceLifecycle.of(row), AttendanceLifecycle.confirmedAbsent);
    expect(AttendanceHistoryFilter.all.matches(row), isTrue);
    expect(AttendanceHistoryFilter.recorded.matches(row), isFalse);
    expect(AttendanceHistoryFilter.issues.matches(row), isFalse);
    expect(row.assignmentStatus, WorkAssignmentStatus.scheduled);
    expect(row.checkInAt, isNull);
    expect(row.checkOutAt, isNull);
    expect(
      EvidenceDeadline.fromAssignment(
        row,
        now: DateTime.utc(2026, 11, 10),
      ).state,
      EvidenceDeadlineState.notApplicable,
    );
  });
  test(
    'future shifts stay operational; past cancelled records remain in All only',
    () {
      final future = WorkerWorkAssignment.fromJson(
        lifecycleRow(now: '2026-11-04T09:00:00Z'),
      );
      expect(AttendanceHistoryFilter.all.matches(future), isFalse);
      final cancelled = WorkerWorkAssignment.fromJson(
        lifecycleRow(status: 'cancelled'),
      );
      expect(AttendanceHistoryFilter.all.matches(cancelled), isTrue);
      expect(AttendanceHistoryFilter.recorded.matches(cancelled), isFalse);
      expect(AttendanceHistoryFilter.issues.matches(cancelled), isFalse);
    },
  );
}
