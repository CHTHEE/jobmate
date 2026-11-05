import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_assignment_creation_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_repository_test.dart' show assignment;

String uid(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
WorkAssignmentCandidateRead complete(List<Map<String, dynamic>> rows) =>
    WorkAssignmentCandidateRead(rows, total: rows.length);

class CandidateSource implements WorkAssignmentCreationSource {
  int creates = 0;
  Map<String, dynamic>? parameters;
  Future<Object?> Function(Map<String, dynamic>) create = (_) async => uid(90);
  @override
  Future<Object?> createAssignment(Map<String, dynamic> parameters) {
    creates++;
    this.parameters = Map.of(parameters);
    return create(parameters);
  }

  @override
  String? userId = uid(1);
  String company = uid(2);
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get accountChanges => changes.stream;
  final calls = <(String, String?)>[];
  late Future<JobAccess> Function() access = () async => JobAccess({
    'company_id': company,
    'company_name': 'Authorized company',
  }, null);
  late Future<WorkAssignmentCandidateRead> Function(String) jobs = (_) async =>
      complete([
        {'job_id': uid(3), 'company_id': company, 'title': 'QA Assistant'},
      ]);
  Future<WorkAssignmentCandidateRead> Function(String) applicants = (_) async =>
      complete([
        {
          'application_id': uid(4),
          'applicant_id': uid(5),
          'applicant_name': 'Synthetic worker',
          'status': 'hired',
        },
      ]);
  Future<WorkAssignmentCandidateRead> Function(String) assignments = (
    _,
  ) async => complete([]);
  @override
  Future<JobAccess> loadAccess() {
    calls.add(('access', null));
    return access();
  }

  @override
  Future<WorkAssignmentCandidateRead> listJobs(String companyId) {
    calls.add(('jobs', companyId));
    return jobs(companyId);
  }

  @override
  Future<WorkAssignmentCandidateRead> listApplicants(String jobId) {
    calls.add(('applicants', jobId));
    return applicants(jobId);
  }

  @override
  Future<WorkAssignmentCandidateRead> listAssignments(String companyId) {
    calls.add(('assignments', companyId));
    return assignments(companyId);
  }

  void account(String? id) {
    userId = id;
    changes.add(id);
  }
}

void main() {
  late CandidateSource source;
  late WorkAssignmentCreationRepository repo;
  setUp(() {
    source = CandidateSource();
    repo = WorkAssignmentCreationRepository(
      source,
      ledger: WorkAssignmentCreationLedger(),
    );
  });
  tearDown(() async {
    repo.dispose();
    await source.changes.close();
  });

  Map<String, dynamic> applicant(int n, {String status = 'hired'}) => {
    'application_id': uid(n),
    'applicant_id': uid(n + 100),
    'applicant_name': 'Worker $n',
    'status': status,
  };
  Map<String, dynamic> existing(
    int applicationId, {
    String status = 'scheduled',
    int assignmentId = 90,
  }) => assignment(company: true)
    ..['assignment_id'] = uid(assignmentId)
    ..['application_id'] = uid(applicationId)
    ..['assignment_status'] = status;
  void expectBlocked(WorkAssignmentCreationError kind) {
    expect(repo.state.loading, isFalse);
    expect(repo.state.candidates, isEmpty);
    expect(repo.state.errorKind, kind);
    expect(repo.state.companyId, isNull);
  }

  test('eligible result preserves confirmation fields with explicit scoped read arguments', () async {
    await repo.load(companyId: source.company);
    expect(repo.state.error, isNull);
    final row = repo.state.candidates.single;
    expect(row.companyId, source.company);
    expect(row.companyName, 'Authorized company');
    expect(row.applicationId, uid(4));
    expect(row.workerId, uid(5));
    expect(row.applicantName, 'Synthetic worker');
    expect(row.jobId, uid(3));
    expect(row.jobTitle, 'QA Assistant');
    expect(source.calls, [
      ('access', null),
      ('jobs', uid(2)),
      ('assignments', uid(2)),
      ('applicants', uid(3)),
      ('assignments', uid(2)),
      ('access', null),
    ]);
    expect(() => repo.state.candidates.clear(), throwsUnsupportedError);
  });

  for (final status in [
    'scheduled',
    'active',
    'awaiting_verification',
    'completed',
    'cancelled',
    'disputed',
  ]) {
    test('hired filtering excludes existing $status assignments', () async {
      source.applicants = (_) async => complete([
        applicant(4),
        applicant(6),
        applicant(7, status: 'offered'),
      ]);
      source.assignments = (_) async => complete([existing(4, status: status)]);
      await repo.load();
      expect(repo.state.candidates.map((row) => row.applicationId), [uid(6)]);
    });
  }

  test('multiple legitimate shifts for one application are excluded without ambiguity', () async {
    source.assignments = (_) async =>
        complete([existing(4), existing(4, assignmentId: 91)]);
    await repo.load();
    expect(repo.state.error, isNull);
    expect(repo.state.candidates, isEmpty);
  });

  test(
    'all jobs are read and one failing job blocks the whole candidate set',
    () async {
      source.jobs = (_) async => complete([
        {'job_id': uid(3), 'company_id': source.company, 'title': 'First'},
        {'job_id': uid(9), 'company_id': source.company, 'title': 'Second'},
      ]);
      source.applicants = (id) async {
        if (id == uid(9)) throw Exception('private backend details');
        return complete([applicant(4)]);
      };
      await repo.load();
      expectBlocked(WorkAssignmentCreationError.connection);
      expect(repo.state.error, isNot(contains('private')));
    },
  );

  test('empty jobs still require successful complete assignment and access rechecks', () async {
    source.jobs = (_) async => complete([]);
    await repo.load();
    expect(repo.state.error, isNull);
    expect(repo.state.candidates, isEmpty);
    expect(
      source.calls.where((call) => call.$1 == 'assignments'),
      hasLength(2),
    );
  });

  test(
    'anonymous access and denied or ambiguous companies fail closed',
    () async {
      source.account(null);
      await repo.load();
      expectBlocked(WorkAssignmentCreationError.authentication);
      expect(source.calls, isEmpty);
      source.account(uid(1));
      source.access = () async => const JobAccess(null, 'Denied');
      await repo.load();
      expectBlocked(WorkAssignmentCreationError.permission);
      source.access = () async => throw const PostgrestException(
        message: 'ambiguous',
        code: 'PGRST116',
      );
      await repo.load();
      expectBlocked(WorkAssignmentCreationError.permission);
    },
  );

  test('caller-selected company must match fresh access', () async {
    await repo.load(companyId: uid(8));
    expectBlocked(WorkAssignmentCreationError.permission);
    expect(source.calls.map((call) => call.$1), ['access']);
  });

  for (final field in ['company_id', 'company_name']) {
    test('missing company $field blocks eligibility', () async {
      source.access = () async => JobAccess(
        {'company_id': source.company, 'company_name': 'Company'}
          ..remove(field),
        null,
      );
      await repo.load();
      expectBlocked(WorkAssignmentCreationError.incompleteData);
    });
  }

  test('foreign company job is not queried for applicants', () async {
    source.jobs = (_) async => complete([
      {'job_id': uid(3), 'company_id': uid(8), 'title': 'Foreign'},
    ]);
    await repo.load();
    expectBlocked(WorkAssignmentCreationError.permission);
    expect(source.calls.where((call) => call.$1 == 'applicants'), isEmpty);
  });

  for (final stage in ['jobs', 'applicants', 'assignments']) {
    for (final total in <int?>[null, 1]) {
      test(
        '$stage missing or truncated count $total is not treated as empty',
        () async {
          final incomplete = WorkAssignmentCandidateRead([], total: total);
          switch (stage) {
            case 'jobs':
              source.jobs = (_) async => incomplete;
            case 'applicants':
              source.applicants = (_) async => incomplete;
            case 'assignments':
              source.assignments = (_) async => incomplete;
          }
          await repo.load();
          expectBlocked(WorkAssignmentCreationError.incompleteData);
        },
      );
    }
  }

  for (final field in [
    'application_id',
    'applicant_id',
    'applicant_name',
    'status',
  ]) {
    test('missing applicant $field fails the entire load', () async {
      source.applicants = (_) async => complete([applicant(4)..remove(field)]);
      await repo.load();
      expectBlocked(WorkAssignmentCreationError.incompleteData);
    });
  }

  for (final field in ['job_id', 'company_id', 'title']) {
    test('missing job $field fails the entire load', () async {
      source.jobs = (_) async => complete([
        {'job_id': uid(3), 'company_id': source.company, 'title': 'QA'}
          ..remove(field),
      ]);
      await repo.load();
      expectBlocked(WorkAssignmentCreationError.incompleteData);
    });
  }

  test('unknown status, malformed UUID, blank name and contradictory job provenance fail closed', () async {
    for (final malformed in [
      applicant(4, status: 'unknown'),
      applicant(4)..['applicant_id'] = 'bad',
      applicant(4)..['applicant_name'] = ' ',
      applicant(4)..['job_id'] = uid(8),
      applicant(4)..['company_id'] = uid(8),
    ]) {
      source.applicants = (_) async => complete([malformed]);
      await repo.load();
      expectBlocked(WorkAssignmentCreationError.incompleteData);
    }
  });

  test('duplicate applications even identical rows are ambiguous rather than deduplicated', () async {
    source.applicants = (_) async => complete([applicant(4), applicant(4)]);
    await repo.load();
    expectBlocked(WorkAssignmentCreationError.incompleteData);
  });

  test('duplicate jobs and duplicate assignment IDs fail closed', () async {
    source.jobs = (_) async => complete(
      List.generate(
        2,
        (_) => {'job_id': uid(3), 'company_id': source.company, 'title': 'QA'},
      ),
    );
    await repo.load();
    expectBlocked(WorkAssignmentCreationError.incompleteData);
    source.jobs = (_) async => complete([]);
    source.assignments = (_) async => complete([existing(4), existing(4)]);
    await repo.load();
    expectBlocked(WorkAssignmentCreationError.incompleteData);
  });

  test('incomplete assignment fields and failed assignment reads never expose candidates', () async {
    source.assignments = (_) async =>
        complete([existing(4)..remove('application_id')]);
    await repo.load();
    expectBlocked(WorkAssignmentCreationError.incompleteData);
    source.assignments = (_) async => throw Exception('offline');
    await repo.load();
    expectBlocked(WorkAssignmentCreationError.connection);
  });

  test(
    'final assignment recheck excludes newly assigned application',
    () async {
      var count = 0;
      source.assignments = (_) async =>
          complete(++count == 1 ? [] : [existing(4)]);
      await repo.load();
      expect(repo.state.error, isNull);
      expect(repo.state.candidates, isEmpty);
    },
  );

  test('failed final assignment read and revoked final access discard all provisional results', () async {
    var reads = 0;
    source.assignments = (_) async {
      if (++reads == 2) throw Exception('offline');
      return complete([]);
    };
    await repo.load();
    expectBlocked(WorkAssignmentCreationError.connection);
    source.assignments = (_) async => complete([]);
    var access = 0;
    source.access = () async => ++access == 1
        ? JobAccess({
            'company_id': source.company,
            'company_name': 'Company',
          }, null)
        : const JobAccess(null, 'Revoked');
    await repo.load();
    expectBlocked(WorkAssignmentCreationError.permission);
  });

  test('company changes without account changes are caught by final authorization read', () async {
    var reads = 0;
    source.access = () async => JobAccess({
      'company_id': ++reads == 1 ? uid(2) : uid(8),
      'company_name': 'Company',
    }, null);
    await repo.load();
    expectBlocked(WorkAssignmentCreationError.contextChanged);
  });

  test('loading clears previous candidates; account changes invalidate stale completion', () async {
    await repo.load();
    final pending = Completer<WorkAssignmentCandidateRead>();
    source.applicants = (_) => pending.future;
    final request = repo.load();
    await Future<void>.delayed(Duration.zero);
    expect(repo.state.loading, isTrue);
    expect(repo.state.candidates, isEmpty);
    source.account(uid(10));
    expectBlocked(WorkAssignmentCreationError.contextChanged);
    pending.complete(complete([applicant(4)]));
    await request;
    expectBlocked(WorkAssignmentCreationError.contextChanged);
  });

  test('new company load supersedes older request even if old response arrives last', () async {
    final old = Completer<WorkAssignmentCandidateRead>();
    source.applicants = (_) => old.future;
    final first = repo.load(companyId: uid(2));
    await Future<void>.delayed(Duration.zero);
    source.company = uid(8);
    source.applicants = (_) async => complete([applicant(12)]);
    await repo.load(companyId: uid(8));
    old.complete(complete([applicant(4)]));
    await first;
    expect(repo.state.companyId, uid(8));
    expect(repo.state.candidates.single.applicationId, uid(12));
  });

  test(
    'duplicate application across separate jobs fails the whole load',
    () async {
      source.jobs = (_) async => complete([
        {'job_id': uid(3), 'company_id': source.company, 'title': 'First'},
        {'job_id': uid(9), 'company_id': source.company, 'title': 'Second'},
      ]);
      source.applicants = (_) async => complete([applicant(4)]);
      await repo.load();
      expectBlocked(WorkAssignmentCreationError.incompleteData);
    },
  );

  test(
    'an assignment seen in either complete read is conservatively excluded',
    () async {
      var reads = 0;
      source.assignments = (_) async =>
          complete(++reads == 1 ? [existing(4)] : []);
      await repo.load();
      expect(repo.state.error, isNull);
      expect(repo.state.candidates, isEmpty);
    },
  );

  test('silent actor change hides loaded rows immediately', () async {
    await repo.load();
    source.userId = uid(10);
    expect(repo.state.candidates, isEmpty);
    expect(repo.state.companyId, isNull);
  });

  test(
    'disposal during an outstanding read suppresses completion notifications',
    () async {
      final pending = Completer<WorkAssignmentCandidateRead>();
      source.jobs = (_) => pending.future;
      var notifications = 0;
      repo.addListener(() => notifications++);
      final request = repo.load();
      await Future<void>.delayed(Duration.zero);
      repo.dispose();
      final before = notifications;
      pending.complete(complete([]));
      await request;
      expect(notifications, before);
      expect(repo.state.candidates, isEmpty);
    },
  );

  test(
    'account away-and-back and disposal cannot resurrect stale rows',
    () async {
      final pending = Completer<WorkAssignmentCandidateRead>();
      source.jobs = (_) => pending.future;
      final request = repo.load();
      await Future<void>.delayed(Duration.zero);
      source.account(null);
      source.account(uid(1));
      pending.complete(complete([]));
      await request;
      expectBlocked(WorkAssignmentCreationError.contextChanged);
      repo.dispose();
      await repo.load();
      expect(repo.state.candidates, isEmpty);
    },
  );

  group('explicit creation', () {
    final start = DateTime.utc(2026, 11, 7, 1),
        end = DateTime.utc(2026, 11, 7, 9);
    Future<WorkAssignmentCandidate> candidate() async {
      await repo.load();
      return repo.state.candidates.single;
    }

    Future<WorkAssignmentCreateResult> create(
      WorkAssignmentCandidate row, {
      String location = 'QA workplace',
    }) =>
        repo.create(candidate: row, start: start, end: end, location: location);
    test('hired status revoked before confirmation blocks the write', () async {
      final row = await candidate();
      final changed = Map<String, dynamic>.of(
        (await source.applicants(uid(3))).rows.single,
      )..['status'] = 'withdrawn';
      source.applicants = (_) async => complete([changed]);
      await create(row);
      expect(source.creates, 0);
    });
    test('changed worker confirmation data requires reselection', () async {
      final row = await candidate();
      final changed = Map<String, dynamic>.of(
        (await source.applicants(uid(3))).rows.single,
      )..['applicant_name'] = 'Changed name';
      source.applicants = (_) async => complete([changed]);
      await create(row);
      expect(source.creates, 0);
    });
    test(
      'expired session error is explicit and does not leak backend text',
      () async {
        final row = await candidate();
        source.create = (_) async => throw const PostgrestException(
          message: 'private auth detail',
          code: 'PGRST303',
        );
        final result = await create(row);
        expect(result.status, WorkAssignmentCreateStatus.rejected);
        expect(result.message, contains('Session expired'));
        expect(repo.statusFor(row), WorkAssignmentCreateStatus.idle);
        expect(source.creates, 1);
      },
    );

    Map<String, dynamic> matchingAssignment() => assignment(company: true)
      ..['assignment_id'] = uid(90)
      ..['application_id'] = uid(4)
      ..['job_id'] = uid(3)
      ..['worker_id'] = uid(5)
      ..['scheduled_start'] = start.toIso8601String()
      ..['scheduled_end'] = end.toIso8601String()
      ..['workplace_location'] = 'QA workplace';

    test(
      'MYT conversion ignores device zone and rejects invalid dates/times',
      () {
        expect(
          workAssignmentMalaysiaUtc('2026-11-07', '00:30'),
          DateTime.utc(2026, 11, 6, 16, 30),
        );
        for (final (date, time) in [
          ('2026-02-30', '10:00'),
          ('2026-13-01', '10:00'),
          ('2026-11-07', '24:00'),
          ('2026-11-07', '09:60'),
          ('2026-1-1', '9:00'),
        ]) {
          expect(workAssignmentMalaysiaUtc(date, time), isNull);
        }
      },
    );
    test(
      'exact RPC parameters and authoritative UUID; repeat remains blocked',
      () async {
        final row = await candidate();
        final result = await create(row, location: ' QA workplace ');
        expect(result.status, WorkAssignmentCreateStatus.success);
        expect(result.assignmentId, uid(90));
        expect(source.parameters, {
          'p_application_id': uid(4),
          'p_scheduled_start': start.toIso8601String(),
          'p_scheduled_end': end.toIso8601String(),
          'p_workplace_location': 'QA workplace',
        });
        await create(row);
        expect(source.creates, 1);
      },
    );
    test(
      'blank/oversized location and invalid/nonUTC schedules never dispatch',
      () async {
        final row = await candidate();
        for (final location in ['', '  ', 'x' * 501]) {
          expect(
            (await create(row, location: location)).status,
            WorkAssignmentCreateStatus.rejected,
          );
        }
        for (final last in [
          start,
          start.subtract(const Duration(minutes: 1)),
          DateTime(2026, 11, 7),
        ]) {
          await repo.create(
            candidate: row,
            start: start,
            end: last,
            location: 'QA',
          );
        }
        expect(source.creates, 0);
        expect(
          (await create(row, location: 'x' * 500)).status,
          WorkAssignmentCreateStatus.success,
        );
      },
    );
    test(
      'fresh hired, company, fields and absence checks fail closed',
      () async {
        final row = await candidate();
        source.applicants = (_) async => complete([]);
        expect((await create(row)).status, WorkAssignmentCreateStatus.rejected);
        expect(source.creates, 0);
      },
    );
    test('new existing assignment blocks the selected application', () async {
      final row = await candidate();
      source.assignments = (_) async => complete([matchingAssignment()]);
      expect((await create(row)).status, WorkAssignmentCreateStatus.rejected);
      expect(source.creates, 0);
    });
    test('incomplete assignment recheck cannot become eligible', () async {
      final row = await candidate();
      source.assignments = (_) async =>
          WorkAssignmentCandidateRead([], total: 1);
      await create(row);
      expect(source.creates, 0);
    });
    test('changed company during preflight prevents dispatch', () async {
      final row = await candidate();
      source.company = uid(7);
      await create(row);
      expect(source.creates, 0);
    });
    test('duplicate starts during RPC are blocked', () async {
      final row = await candidate();
      final pending = Completer<Object?>();
      source.create = (_) => pending.future;
      final first = create(row);
      await Future<void>.delayed(Duration.zero);
      expect(repo.creating, isTrue);
      await create(row);
      expect(source.creates, 1);
      pending.complete(uid(90));
      expect((await first).status, WorkAssignmentCreateStatus.success);
    });
    test('concurrent repositories share application lock', () async {
      final row = await candidate();
      final other = WorkAssignmentCreationRepository(
        source,
        ledger: repo.ledger,
      );
      addTearDown(other.dispose);
      final pending = Completer<Object?>();
      source.create = (_) => pending.future;
      final first = create(row);
      await Future<void>.delayed(Duration.zero);
      await other.create(
        candidate: row,
        start: start,
        end: end,
        location: 'QA',
      );
      expect(source.creates, 1);
      pending.complete(uid(90));
      await first;
    });
    test('account change during preflight discards stale request', () async {
      final row = await candidate();
      final pending = Completer<JobAccess>();
      source.access = () => pending.future;
      final action = create(row);
      source.account(uid(10));
      pending.complete(
        JobAccess({
          'company_id': source.company,
          'company_name': 'Authorized company',
        }, null),
      );
      expect((await action).status, WorkAssignmentCreateStatus.rejected);
      expect(source.creates, 0);
    });
    test('candidate from another account cannot be submitted even for same company', () async {
      final row = await candidate();
      source.account(uid(10));
      await repo.load();
      await create(row);
      expect(source.creates, 0);
    });
    test('stale successful completion is not published and old account stays locked', () async {
      final row = await candidate();
      final pending = Completer<Object?>();
      source.create = (_) => pending.future;
      final action = create(row);
      await Future<void>.delayed(Duration.zero);
      source.account(uid(10));
      expect(repo.statusFor(row), WorkAssignmentCreateStatus.idle);
      pending.complete(uid(90));
      expect((await action).assignmentId, isNull);
      source.account(uid(1));
      expect(repo.statusFor(row), WorkAssignmentCreateStatus.uncertain);
      await create(row);
      expect(source.creates, 1);
    });
    test(
      'structured server rejection allows fresh explicitly confirmed retry',
      () async {
        final row = await candidate();
        source.create = (_) async => throw const PostgrestException(
          message: 'private detail',
          code: 'P0001',
        );
        final result = await create(row);
        expect(result.status, WorkAssignmentCreateStatus.rejected);
        expect(result.message, isNot(contains('private detail')));
        source.create = (_) async => uid(90);
        expect((await create(row)).status, WorkAssignmentCreateStatus.success);
        expect(source.creates, 2);
      },
    );
    for (final error in [
      TimeoutException('lost response'),
      const FormatException('invalid response'),
      const PostgrestException(message: 'gateway', code: '504'),
    ]) {
      test(
        'ambiguous $error stays locked through recreation and empty reads',
        () async {
          final row = await candidate();
          source.create = (_) async => throw error;
          expect(
            (await create(row)).status,
            WorkAssignmentCreateStatus.uncertain,
          );
          expect(
            (await repo.reconcile(row)).status,
            WorkAssignmentCreateStatus.uncertain,
          );
          final restored = WorkAssignmentCreationRepository(
            source,
            ledger: repo.ledger,
          );
          addTearDown(restored.dispose);
          await restored.create(
            candidate: row,
            start: start,
            end: end,
            location: 'QA',
          );
          expect(source.creates, 1);
        },
      );
    }
    test(
      'lost response positively reconciles exact assignment from fresh reads',
      () async {
        final row = await candidate();
        source.create = (_) async {
          source.assignments = (_) async => complete([matchingAssignment()]);
          throw TimeoutException('lost');
        };
        final result = await create(row);
        expect(result.status, WorkAssignmentCreateStatus.success);
        expect(result.assignmentId, uid(90));
        expect(result.message, contains('found'));
        expect(source.creates, 1);
      },
    );
    test('mismatched, duplicate, incomplete and unauthorized reconciliation remains blocked', () async {
      final row = await candidate();
      source.create = (_) async => throw TimeoutException('lost');
      await create(row);
      source.assignments = (_) async =>
          complete([matchingAssignment()..['workplace_location'] = 'other']);
      expect(
        (await repo.reconcile(row)).status,
        WorkAssignmentCreateStatus.uncertain,
      );
      source.assignments = (_) async =>
          complete([matchingAssignment(), matchingAssignment()]);
      expect(
        (await repo.reconcile(row)).status,
        WorkAssignmentCreateStatus.uncertain,
      );
      source.assignments = (_) async =>
          WorkAssignmentCandidateRead([matchingAssignment()], total: 2);
      expect(
        (await repo.reconcile(row)).status,
        WorkAssignmentCreateStatus.uncertain,
      );
      source.access = () async => const JobAccess(null, 'denied');
      expect(
        (await repo.reconcile(row)).status,
        WorkAssignmentCreateStatus.uncertain,
      );
      expect(source.creates, 1);
    });
  });

  test('Supabase creation adapter sends exact POST once, including gateway failure (loopback fake)', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    var fail = false;
    final parameters = <String, dynamic>{
      'p_application_id': uid(4),
      'p_scheduled_start': '2026-11-07T01:00:00.000Z',
      'p_scheduled_end': '2026-11-07T09:00:00.000Z',
      'p_workplace_location': 'QA',
    };
    server.listen((request) async {
      requests++;
      expect(request.method, 'POST');
      expect(request.uri.path, '/rest/v1/rpc/create_work_assignment');
      expect(jsonDecode(await utf8.decoder.bind(request).join()), parameters);
      request.response.headers.contentType = ContentType.json;
      request.response.statusCode = fail ? 503 : 200;
      request.response.write(
        jsonEncode(
          fail ? {'message': 'fake unavailable', 'code': '503'} : uid(90),
        ),
      );
      await request.response.close();
    });
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });
    final adapter = SupabaseWorkAssignmentCreationSource(client);
    await expectLater(
      adapter.createAssignment(parameters),
      throwsA(isA<AuthException>()),
    );
    expect(requests, 0);
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'fake-token',
        'token_type': 'bearer',
        'user': {'id': uid(1)},
      }),
    );
    expect(await adapter.createAssignment(parameters), uid(90));
    fail = true;
    await expectLater(
      adapter.createAssignment(parameters),
      throwsA(isA<PostgrestException>()),
    );
    expect(requests, 2);
  });
}
