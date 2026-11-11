import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/company_workers_repository.dart';
import 'package:jobmate/features/work_attendance/work_assignment_creation_repository.dart';

import 'work_assignment_creation_repository_test.dart'
    show CandidateSource, complete, uid;
import 'work_attendance_repository_test.dart' show assignment;

Map<String, dynamic> hired(int application, int worker, String name) => {
  'application_id': uid(application),
  'applicant_id': uid(worker),
  'applicant_name': name,
  'status': 'hired',
};

Map<String, dynamic> workerShift(
  int number,
  int app,
  int worker,
  int job, {
  bool verified = false,
}) => assignment(company: true)
  ..['assignment_id'] = uid(number)
  ..['application_id'] = uid(app)
  ..['worker_id'] = uid(worker)
  ..['job_id'] = uid(job)
  ..['assignment_status'] = verified ? 'completed' : 'scheduled'
  ..['verification_status'] = verified ? 'verified' : 'not_submitted';

void main() {
  late CandidateSource source;
  late CompanyWorkersRepository repository;
  setUp(() {
    source = CandidateSource();
    repository = CompanyWorkersRepository(source);
  });
  tearDown(() async {
    repository.dispose();
    await source.changes.close();
  });

  test('groups real hired application projections by worker and includes zero shifts', () async {
    source.jobs = (_) async => complete([
      {'job_id': uid(3), 'company_id': source.company, 'title': 'First job'},
      {'job_id': uid(8), 'company_id': source.company, 'title': 'Second job'},
    ]);
    source.applicants = (job) async => complete(
      job == uid(3)
          ? [
              hired(4, 5, 'Alex'),
              hired(6, 7, 'Blair'),
              hired(9, 10, 'Not hired')..['status'] = 'offered',
            ]
          : [hired(11, 5, 'Alex')],
    );
    source.assignments = (_) async => complete([
      workerShift(20, 4, 5, 3, verified: true),
      workerShift(21, 11, 5, 8),
      workerShift(
        22,
        12,
        13,
        3,
        verified: true,
      ), // Not a listed hired application.
    ]);
    await repository.load();
    expect(repository.error, isNull);
    expect(repository.workers.map((w) => w.name), ['Alex', 'Blair']);
    expect(repository.workers.first.jobs.values, ['First job', 'Second job']);
    expect(repository.workers.first.assignedShifts, 2);
    expect(repository.workers.first.verifiedShifts, 1);
    expect(repository.workers.last.assignedShifts, 0);
    expect(repository.workers.last.verifiedShifts, 0);
    expect(
      source.calls
          .where((c) => c.$1 == 'jobs' || c.$1 == 'assignments')
          .every((c) => c.$2 == source.company),
      isTrue,
    );
    expect(source.creates, 0);
    expect(source.reservations, 0);
  });

  test('denied access never queries company records', () async {
    source.access = () async => const JobAccess(null, 'Denied');
    await repository.load();
    expect(repository.workers, isEmpty);
    expect(repository.error, isNotNull);
    expect(source.calls, [('access', null)]);
  });

  test(
    'foreign company jobs and contradictory applicants fail closed',
    () async {
      source.jobs = (_) async => complete([
        {'job_id': uid(3), 'company_id': uid(99), 'title': 'Foreign job'},
      ]);
      await repository.load();
      expect(repository.workers, isEmpty);
      expect(repository.error, isNotNull);
      expect(source.calls.where((c) => c.$1 == 'applicants'), isEmpty);
      source.jobs = (_) async => complete([
        {'job_id': uid(3), 'company_id': source.company, 'title': 'Own job'},
      ]);
      source.applicants = (_) async =>
          complete([hired(4, 5, 'Foreign worker')..['company_id'] = uid(99)]);
      await repository.load();
      expect(repository.workers, isEmpty);
      expect(repository.error, isNotNull);
    },
  );

  test(
    'incomplete lists fail closed; unavailable counts are omitted, never zero',
    () async {
      source.jobs = (_) async => WorkAssignmentCandidateRead([], total: 1);
      await repository.load();
      expect(repository.error, isNotNull);
      expect(repository.workers, isEmpty);
      source.jobs = (_) async => complete([
        {'job_id': uid(3), 'company_id': source.company, 'title': 'Own job'},
      ]);
      source.assignments = (_) async =>
          WorkAssignmentCandidateRead([], total: 1);
      await repository.load();
      expect(repository.error, isNull);
      expect(repository.workers.single.assignedShifts, isNull);
      expect(repository.workers.single.verifiedShifts, isNull);
      expect(repository.countsAvailable, isFalse);
    },
  );

  test(
    'wrong-company or mismatched shift identities cannot become counts',
    () async {
      source.assignments = (_) async =>
          complete([workerShift(20, 4, 5, 3)..['company_id'] = uid(99)]);
      await repository.load();
      expect(repository.workers.single.assignedShifts, isNull);
      source.assignments = (_) async => complete([workerShift(20, 4, 99, 3)]);
      await repository.load();
      expect(repository.workers.single.assignedShifts, isNull);
    },
  );

  test(
    'membership context change during reads discards the directory',
    () async {
      var calls = 0;
      source.access = () async => JobAccess({
        'company_id': ++calls == 1 ? source.company : uid(99),
        'company_name': 'Company',
      }, null);
      await repository.load();
      expect(repository.workers, isEmpty);
      expect(repository.error, isNotNull);
    },
  );

  test(
    'account switch clears records and ignores the old pending request',
    () async {
      final old = Completer<WorkAssignmentCandidateRead>();
      source.applicants = (_) => old.future;
      final load = repository.load();
      await Future<void>.delayed(Duration.zero);
      source.account(null);
      expect(repository.workers, isEmpty);
      old.complete(complete([hired(4, 5, 'Old worker')]));
      await load;
      await Future<void>.delayed(Duration.zero);
      expect(repository.workers, isEmpty);
      expect(repository.error, contains('Sign in'));
    },
  );

  test('empty and failed reads are distinct and retryable', () async {
    source.jobs = (_) async => complete([]);
    await repository.load();
    expect(repository.workers, isEmpty);
    expect(repository.error, isNull);
    source.jobs = (_) async => throw Exception('offline');
    await repository.load();
    expect(repository.error, isNotNull);
    expect(repository.workers, isEmpty);
    source.jobs = (_) async => complete([]);
    await repository.load();
    expect(repository.error, isNull);
  });
}
