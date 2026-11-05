import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_assignment_people.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';

import 'work_assignment_creation_repository_test.dart'
    show CandidateSource, complete, uid;
import 'work_attendance_repository_test.dart' show assignment;

void main() {
  late CandidateSource source;
  late WorkAssignmentPeopleRepository repo;
  late CompanyWorkAssignment row;
  setUp(() {
    source = CandidateSource();
    repo = WorkAssignmentPeopleRepository(source);
    row = CompanyWorkAssignment.fromJson(
      assignment(company: true)
        ..['job_id'] = uid(3)
        ..['application_id'] = uid(4)
        ..['worker_id'] = uid(5),
    );
  });
  tearDown(() => source.changes.close());
  test(
    'uses authorized job/application/worker identity to resolve actual name',
    () async {
      expect(await repo.workerName(row, uid(2)), 'Synthetic worker');
      expect(source.creates, 0);
    },
  );
  test('foreign company never reads applicants', () async {
    expect(await repo.workerName(row, uid(9)), isNull);
    expect(source.calls.where((r) => r.$1 == 'applicants'), isEmpty);
  });
  test(
    'missing, duplicate and failed name data never fabricate a name',
    () async {
      final records = (await source.applicants(uid(3))).rows;
      source.applicants = (_) async =>
          complete([records.single, records.single]);
      expect(await repo.workerName(row, uid(2)), isNull);
      source.applicants = (_) async => complete([]);
      expect(await repo.workerName(row, uid(2)), isNull);
      source.applicants = (_) async => throw StateError('offline');
      expect(await repo.workerName(row, uid(2)), isNull);
    },
  );
  test('account away/back invalidates late authorized name read', () async {
    final pending = Completer<void>();
    final applicants = source.applicants;
    source.applicants = (job) async {
      await pending.future;
      return applicants(job);
    };
    final result = repo.workerName(row, uid(2));
    await Future<void>.delayed(Duration.zero);
    source.account(uid(8));
    source.account(uid(1));
    pending.complete();
    expect(await result, isNull);
  });
}
