import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const id = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> assignment({bool company = false}) => {
  'assignment_id': id,
  'application_id': other,
  'job_id': id,
  'job_title': 'Server job',
  if (company) 'worker_id': other,
  if (!company) ...{'company_id': other, 'company_name': 'Server company'},
  'scheduled_start': '2026-11-05T09:00:00+08:00',
  'scheduled_end': '2026-11-05T09:00:00Z',
  'workplace_location': 'Server location',
  'assignment_status': 'scheduled',
  'verification_status': 'not_submitted',
  'check_in_at': null,
  'check_out_at': null,
  'verified_at': null,
};
Map<String, dynamic> evidenceRow() => {
  'evidence_id': id,
  'submission_round': 2,
  'description': 'Server evidence',
  'storage_path': '$id/file.pdf',
  'file_name': 'file.pdf',
  'mime_type': 'application/pdf',
  'submitted_by': other,
  'submitted_at': '2026-11-05T02:00:00Z',
};

class FakeSource implements WorkAttendanceSource {
  int checkIns = 0, checkOuts = 0;
  Future<DateTime> Function(String) onCheckIn = (_) async =>
      DateTime.utc(2026, 11, 5, 1);
  Future<DateTime> Function(String) onCheckOut = (_) async =>
      DateTime.utc(2026, 11, 5, 9);
  @override
  Future<DateTime> checkIn(
    String assignmentId, {
    WorkAttendanceLocation location =
        const WorkAttendanceLocation.unavailable(),
  }) {
    checkIns++;
    return onCheckIn(assignmentId);
  }

  @override
  Future<DateTime> checkOut(
    String assignmentId, {
    WorkAttendanceLocation location =
        const WorkAttendanceLocation.unavailable(),
  }) {
    checkOuts++;
    return onCheckOut(assignmentId);
  }

  @override
  String? userId = id;
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get accountChanges => changes.stream;
  Future<List<Map<String, dynamic>>> Function() workerRead = () async => [
    assignment(),
  ];
  Future<List<Map<String, dynamic>>> Function(String) companyRead = (_) async =>
      [assignment(company: true)];
  Future<List<Map<String, dynamic>>> Function(String) evidenceRead = (
    _,
  ) async => [evidenceRow()];
  int calls = 0;
  void switchAccount(String? actor) {
    userId = actor;
    changes.add(actor);
  }

  @override
  Future<List<Map<String, dynamic>>> listMyAssignments() {
    calls++;
    return workerRead();
  }

  @override
  Future<List<Map<String, dynamic>>> listCompanyAssignments(String companyId) {
    calls++;
    return companyRead(companyId);
  }

  @override
  Future<List<Map<String, dynamic>>> listEvidence(String assignmentId) {
    calls++;
    return evidenceRead(assignmentId);
  }
}

void main() {
  test('exact projections, UUIDs, UTC and nullable attendance timestamps', () {
    final row = assignment();
    final worker = WorkerWorkAssignment.fromJson(row);
    expect(worker.assignmentId, id);
    expect(worker.applicationId, other);
    expect(worker.jobId, id);
    expect(worker.companyId, other);
    expect(worker.companyName, 'Server company');
    expect(worker.jobTitle, 'Server job');
    expect(worker.workplaceLocation, 'Server location');
    expect(worker.scheduledStart, DateTime.utc(2026, 11, 5, 1));
    expect(worker.scheduledStart.isUtc, isTrue);
    expect(worker.scheduledEnd, DateTime.utc(2026, 11, 5, 9));
    expect(worker.checkInAt, isNull);
    expect(worker.checkOutAt, isNull);
    expect(worker.verifiedAt, isNull);
    expect(worker.attendanceState, WorkAttendanceState.notStarted);
    expect(worker.assignmentStatus, WorkAssignmentStatus.scheduled);
    expect(worker.verificationStatus, WorkVerificationStatus.notSubmitted);
    expect(
      CompanyWorkAssignment.fromJson(assignment(company: true)).workerId,
      other,
    );
    row['check_in_at'] = '2026-11-05T09:00:00+0800';
    expect(
      WorkerWorkAssignment.fromJson(row).attendanceState,
      WorkAttendanceState.checkedIn,
    );
    row['check_out_at'] = '2026-11-05T10:00:00+08:00';
    row['verified_at'] = '2026-11-05T03:00:00Z';
    final completed = WorkerWorkAssignment.fromJson(row);
    expect(completed.attendanceState, WorkAttendanceState.checkedOut);
    expect(completed.checkOutAt, DateTime.utc(2026, 11, 5, 2));
    expect(completed.verifiedAt, DateTime.utc(2026, 11, 5, 3));
    final evidence = WorkEvidence.fromJson(evidenceRow());
    expect(evidence.evidenceId, id);
    expect(evidence.submissionRound, 2);
    expect(evidence.description, 'Server evidence');
    expect(evidence.storagePath, '$id/file.pdf');
    expect(evidence.fileName, 'file.pdf');
    expect(evidence.mimeType, 'application/pdf');
    expect(evidence.submittedBy, other);
    expect(evidence.submittedAt, DateTime.utc(2026, 11, 5, 2));
    expect(workUuid(id.toUpperCase()), id);
  });

  test('reject malformed IDs, required fields, timestamps and enums', () {
    for (final entry in <String, dynamic>{
      'assignment_id': 'invalid',
      'job_title': null,
      'scheduled_start': '2026-11-05T09:00:00',
      'scheduled_end': 'invalid',
      'check_in_at': 1,
      'assignment_status': 'invented',
      'verification_status': 'invented',
    }.entries) {
      expect(
        () => WorkerWorkAssignment.fromJson(
          assignment()..[entry.key] = entry.value,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => WorkEvidence.fromJson(evidenceRow()..['submission_round'] = 1.5),
      throwsFormatException,
    );
    for (final value in [
      'scheduled',
      'active',
      'awaiting_verification',
      'completed',
      'cancelled',
      'disputed',
    ]) {
      expect(WorkAssignmentStatus.parse(value), isA<WorkAssignmentStatus>());
    }
    for (final value in [
      'not_submitted',
      'pending_review',
      'more_evidence_required',
      'verified',
      'disputed',
    ]) {
      expect(
        WorkVerificationStatus.parse(value),
        isA<WorkVerificationStatus>(),
      );
    }
  });

  group('repository', () {
    late FakeSource source;
    late WorkAttendanceRepository repo;
    setUp(() {
      source = FakeSource();
      repo = WorkAttendanceRepository(source);
    });
    tearDown(() async {
      repo.dispose();
      await source.changes.close();
    });

    test(
      'loading, immutable success, explicit scopes and empty results',
      () async {
        final pending = Completer<List<Map<String, dynamic>>>();
        source.workerRead = () => pending.future;
        final load = repo.loadWorkerAssignments();
        expect(repo.worker.loading, isTrue);
        pending.complete([assignment()]);
        await load;
        expect(repo.worker.loading, isFalse);
        expect(repo.worker.error, isNull);
        expect(() => repo.worker.rows.clear(), throwsUnsupportedError);
        source.companyRead = (company) async {
          expect(company, other);
          return [assignment(company: true)];
        };
        await repo.loadCompanyAssignments(other);
        expect(repo.company.scopeId, other);
        expect(repo.company.rows.single.workerId, other);
        source.evidenceRead = (selected) async {
          expect(selected, id);
          return [evidenceRow()];
        };
        await repo.loadEvidence(id);
        expect(repo.evidence.rows.single.submissionRound, 2);
        expect(repo.evidence.scopeId, id);
        source.workerRead = () async => [];
        source.companyRead = (_) async => [];
        source.evidenceRead = (_) async => [];
        await repo.loadWorkerAssignments();
        await repo.loadCompanyAssignments(other);
        await repo.loadEvidence(id);
        expect(repo.worker.rows, isEmpty);
        expect(repo.company.rows, isEmpty);
        expect(repo.evidence.rows, isEmpty);
        expect(repo.evidence.error, isNull);
      },
    );

    test(
      'authentication, permission, connection, invalid data and retry',
      () async {
        for (final (failure, kind) in <(Object, WorkAttendanceError)>[
          (const AuthException('expired'), WorkAttendanceError.authentication),
          (
            const PostgrestException(message: 'expired', code: 'PGRST301'),
            WorkAttendanceError.authentication,
          ),
          (
            const PostgrestException(
              message: 'Authentication required',
              code: 'P0001',
            ),
            WorkAttendanceError.authentication,
          ),
          (
            const PostgrestException(message: 'denied', code: '42501'),
            WorkAttendanceError.permission,
          ),
          (
            const PostgrestException(
              message: 'Not authorized to view this evidence',
              code: 'P0001',
            ),
            WorkAttendanceError.permission,
          ),
          (const SocketException('offline'), WorkAttendanceError.connection),
          (
            const FormatException('bad payload'),
            WorkAttendanceError.invalidData,
          ),
        ]) {
          source.workerRead = () => Future.error(failure);
          await repo.loadWorkerAssignments();
          expect(repo.worker.errorKind, kind);
          expect(repo.worker.loading, isFalse);
          expect(repo.worker.rows, isEmpty);
        }
        source.workerRead = () async => [assignment()..['job_id'] = null];
        await repo.loadWorkerAssignments();
        expect(repo.worker.errorKind, WorkAttendanceError.invalidData);
        source.workerRead = () async => [assignment()];
        await repo.loadWorkerAssignments();
        expect(repo.worker.error, isNull);
        await repo.loadCompanyAssignments('invalid');
        expect(repo.company.errorKind, WorkAttendanceError.invalidData);
        source.switchAccount(null);
        final count = source.calls;
        await repo.loadWorkerAssignments();
        expect(repo.worker.errorKind, WorkAttendanceError.authentication);
        expect(source.calls, count);
      },
    );

    test(
      'account switch clears all contexts; stale success/failure ignored',
      () async {
        await repo.loadCompanyAssignments(other);
        await repo.loadEvidence(id);
        final pending = Completer<List<Map<String, dynamic>>>();
        source.workerRead = () => pending.future;
        final old = repo.loadWorkerAssignments();
        source.switchAccount(other);
        expect(repo.worker.rows, isEmpty);
        expect(repo.company.scopeId, isNull);
        expect(repo.evidence.scopeId, isNull);
        source.workerRead = () async => [];
        await repo.loadWorkerAssignments();
        pending.complete([assignment()]);
        await old;
        expect(repo.worker.rows, isEmpty);
        final failed = Completer<List<Map<String, dynamic>>>();
        source.evidenceRead = (_) => failed.future;
        final oldEvidence = repo.loadEvidence(id);
        source.switchAccount(null);
        failed.completeError(const SocketException('old failure'));
        await oldEvidence;
        expect(repo.evidence.error, isNull);
        expect(repo.evidence.rows, isEmpty);
      },
    );

    test(
      'newer list and company/evidence selections supersede old requests',
      () async {
        final pending = Completer<List<Map<String, dynamic>>>();
        source.workerRead = () => pending.future;
        final old = repo.loadWorkerAssignments();
        source.workerRead = () async => [];
        await repo.loadWorkerAssignments();
        pending.complete([assignment()]);
        await old;
        expect(repo.worker.rows, isEmpty);
        final companyPending = Completer<List<Map<String, dynamic>>>();
        source.companyRead = (_) => companyPending.future;
        final oldCompany = repo.loadCompanyAssignments(id);
        source.companyRead = (_) async => [];
        await repo.loadCompanyAssignments(other);
        companyPending.completeError(const SocketException('stale'));
        await oldCompany;
        expect(repo.company.scopeId, other);
        expect(repo.company.error, isNull);
        final evidencePending = Completer<List<Map<String, dynamic>>>();
        source.evidenceRead = (_) => evidencePending.future;
        final oldEvidence = repo.loadEvidence(id);
        source.evidenceRead = (_) async => [];
        await repo.loadEvidence(other);
        evidencePending.complete([evidenceRow()]);
        await oldEvidence;
        expect(repo.evidence.scopeId, other);
        expect(repo.evidence.rows, isEmpty);
      },
    );

    test('identity getter hides data before auth stream delivery', () async {
      await repo.loadWorkerAssignments();
      source.userId = other;
      expect(repo.worker.rows, isEmpty);
      await repo.loadWorkerAssignments();
      expect(repo.worker.rows, hasLength(1));
    });
  });

  test('dispose cancels subscription and discards pending response', () async {
    final source = FakeSource();
    final repo = WorkAttendanceRepository(source);
    final pending = Completer<List<Map<String, dynamic>>>();
    source.workerRead = () => pending.future;
    final load = repo.loadWorkerAssignments();
    repo.dispose();
    expect(source.changes.hasListener, isFalse);
    pending.complete([assignment()]);
    await load;
    expect(repo.worker.rows, isEmpty);
    await source.changes.close();
  });

  test(
    'Supabase adapter uses only exact read RPCs and parameters (local mock)',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <(String, String, dynamic)>[];
      Object result = [];
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        requests.add((
          request.method,
          request.uri.path,
          body.isEmpty ? {} : jsonDecode(body),
        ));
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      final source = SupabaseWorkAttendanceSource(client);
      await expectLater(
        source.listMyAssignments(),
        throwsA(isA<AuthException>()),
      );
      expect(requests, isEmpty);
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'test-token',
          'token_type': 'bearer',
          'user': {'id': id},
        }),
      );
      await source.listMyAssignments();
      await source.listCompanyAssignments(other);
      await source.listEvidence(id);
      expect(requests.map((request) => request.$1), ['POST', 'POST', 'POST']);
      expect(requests.map((request) => request.$2), [
        '/rest/v1/rpc/list_my_work_assignments',
        '/rest/v1/rpc/list_company_work_assignments',
        '/rest/v1/rpc/list_work_evidence',
      ]);
      expect(requests[0].$3, isNull);
      expect(requests[1].$3, {'p_company_id': other});
      expect(requests[2].$3, {'p_assignment_id': id});
      result = {'invalid': true};
      await expectLater(source.listMyAssignments(), throwsFormatException);
      result = [1];
      await expectLater(source.listEvidence(id), throwsFormatException);
    },
  );
}
