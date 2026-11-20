import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/applicant_notification_repository.dart';
import 'package:jobmate/features/applications/applicant_unseen_controller.dart';

const job = '00000000-0000-4000-8000-000000000021';
const application = '00000000-0000-4000-8000-000000000031';

List<Map<String, Object>> rows(Object count, {String id = job}) => [
  {'job_id': id, 'unseen_count': count},
];

void main() {
  test('counts are strict and disabled results are empty', () async {
    Object response = [];
    final repo = ApplicantNotificationRepository.withRpc((name, params) async {
      expect(name, 'list_unseen_applicant_counts');
      expect(params, isEmpty);
      return response;
    });
    expect(await repo.listUnseenCounts(), isEmpty);
    response = rows(2);
    expect(await repo.listUnseenCounts(), {job: 2});
    for (final invalid in [
      null,
      rows(1.5),
      rows(-1),
      rows('2'),
      rows(2, id: 'bad'),
      [...rows(2), ...rows(3)],
    ]) {
      response = invalid ?? <String, Object>{};
      await expectLater(repo.listUnseenCounts(), throwsFormatException);
    }
  });

  test(
    'acknowledgment validates batches and propagates backend failures',
    () async {
      final denied = StateError('permission denied');
      var calls = 0;
      final repo = ApplicantNotificationRepository.withRpc((
        name,
        params,
      ) async {
        expect(name, 'acknowledge_applicants_seen');
        expect(params, {
          'p_job_id': job,
          'p_application_ids': [application, application],
        });
        if (++calls == 1) return 1;
        throw denied;
      });
      for (final ids in [
        <String>[],
        List.filled(101, application),
        [application, 'bad'],
      ]) {
        await expectLater(
          repo.acknowledge(job, ids),
          throwsA(anyOf(isArgumentError, isFormatException)),
        );
      }
      await expectLater(
        repo.acknowledge('bad', [application]),
        throwsFormatException,
      );
      expect(calls, 0);
      expect(await repo.acknowledge(job, [application, application]), 1);
      await expectLater(
        repo.acknowledge(job, [application, application]),
        throwsA(same(denied)),
      );
    },
  );

  late String? actor;
  late StreamController<String?> auth;
  late List<Completer<Object?>> reads;
  late ApplicantUnseenController controller;
  late int writes;

  setUp(() {
    actor = 'employer-a';
    auth = StreamController.broadcast(sync: true);
    reads = [];
    writes = 0;
    final repo = ApplicantNotificationRepository.withRpc((name, _) {
      if (name == 'acknowledge_applicants_seen') {
        writes++;
        return Future.value(1);
      }
      final result = Completer<Object?>();
      reads.add(result);
      return result.future;
    });
    controller = ApplicantUnseenController(
      repo,
      currentUserId: () => actor,
      accountChanges: auth.stream,
    );
  });

  tearDown(() async {
    controller.dispose();
    await auth.close();
  });

  void enter(String company) =>
      controller.enterWorkspace(accountId: actor, companyId: company);

  test(
    'coalesces reads and retains last known counts on failure; resumes',
    () async {
      enter('a');
      final pending = controller.refresh();
      expect(controller.loading, isTrue);
      expect(reads, hasLength(1));
      reads.single.complete(rows(4));
      await pending;
      expect(controller.hasUnseen, isTrue);
      expect(controller.countFor(job), 4);
      expect(controller.countFor(application), 0);

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      final failed = controller.refresh();
      reads.last.completeError(StateError('network failure'));
      await failed;
      expect(controller.refreshFailed, isTrue);
      expect(controller.countFor(job), 4);

      final retry = controller.refresh();
      reads.last.complete([]);
      await retry;
      expect(controller.hasUnseen, isFalse);
      expect(controller.refreshFailed, isFalse);
    },
  );

  test(
    'company changes, account switches, and logout reject stale reads',
    () async {
      enter('a');
      final previousCompany = controller.refresh();
      final first = reads.single;
      enter('b');
      final previousActor = controller.refresh();
      final second = reads.last;
      actor = 'employer-b';
      auth.add(actor);
      expect(controller.counts, isEmpty);
      expect(controller.loading, isFalse);
      enter('b');
      final current = controller.refresh();
      reads.last.complete(rows(5));
      await current;
      first.complete(rows(1));
      second.complete(rows(2));
      await Future.wait([previousCompany, previousActor]);
      expect(controller.countFor(job), 5);

      final beforeLogout = controller.refresh();
      actor = null;
      expect(controller.counts, isEmpty);
      auth.add(null);
      reads.last.complete(rows(6));
      await beforeLogout;
      expect(controller.hasUnseen, isFalse);
    },
  );

  test('display guard and post-write refresh supersede older reads', () async {
    enter('a');
    expect(controller.beginApplicantLoad(null), isNull);
    final scope = controller.beginApplicantLoad(job)!;
    await expectLater(
      controller.acknowledgeDisplayed(scope, [
        application,
      ], isCurrentDisplay: () => false),
      throwsStateError,
    );
    expect(writes, 0);

    final older = controller.refresh();
    final previous = reads.single;
    final write = controller.acknowledgeDisplayed(scope, [
      application,
    ], isCurrentDisplay: () => true);
    await Future<void>.delayed(Duration.zero);
    expect(reads, hasLength(2));
    reads.last.complete([]);
    expect(await write, 1);
    previous.complete(rows(8));
    await older;
    expect(controller.hasUnseen, isFalse);

    enter('b');
    await expectLater(
      controller.acknowledgeDisplayed(scope, [
        application,
      ], isCurrentDisplay: () => true),
      throwsStateError,
    );
    expect(writes, 1);
    final pending = controller.refresh();
    reads.last.complete([]);
    await pending;
  });
}
