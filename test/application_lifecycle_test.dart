import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/employer_applicants_page.dart';
import 'package:jobmate/features/applications/employer_applicants_repository.dart';
import 'package:jobmate/features/applications/my_application_details_page.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/employer_applicants_source.dart';
import 'fixtures/my_applications_source.dart';
import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, evidenceRow, id, other;

void main() {
  late TestMyApplicationsSource worker;
  late TestEmployerApplicantsSource employer;
  late MyApplicationDetailsRepository details;
  late EmployerApplicantsRepository applicants;

  setUp(() {
    worker = TestMyApplicationsSource();
    employer = TestEmployerApplicantsSource();
    details = MyApplicationDetailsRepository(worker, id);
    applicants = EmployerApplicantsRepository(employer, 'real-job-id');
  });
  tearDown(() async {
    details.dispose();
    applicants.dispose();
    await worker.changes.close();
    await employer.changes.close();
  });

  for (final action in ApplicationResponseAction.values) {
    test(
      '${action.label} has a distinct authoritative result for both roles',
      () async {
        worker.rows = [applicationRow(id, status: 'offered')];
        employer.rows = [applicantRow(id, status: 'offered')];
        await details.load();
        await applicants.load();
        expect(applicants.applicants.single.employerNext, isEmpty);
        worker.sendResponse = (applicationId, wireAction) async {
          expect(applicationId, id);
          expect(wireAction, action.wireName);
          worker.rows = [applicationRow(id, status: action.result.name)];
          employer.rows = [applicantRow(id, status: action.result.name)];
          worker.historyRows = [
            historyRow('result', status: action.result.name),
          ];
          return 'Server acknowledgement';
        };
        await details.respond(details.application!, action.wireName);
        await applicants.load();
        expect(details.application!.status, action.result);
        expect(applicants.applicants.single.status, action.result);
        expect(details.events.single.newStatus, action.result);
        expect(details.responseError, isNull);
        for (final repeated in ApplicationResponseAction.values) {
          await expectLater(
            details.respond(details.application!, repeated.wireName),
            throwsStateError,
          );
        }
        expect(worker.responses, [(id, action.wireName)]);
        expect(employer.updates, isEmpty);
      },
    );
  }

  test('conflicting offer actions stay locked during the RPC and authoritative refresh', () async {
    worker.rows = [applicationRow(id, status: 'offered')];
    await details.load();
    final selected = details.application!;
    final response = Completer<String>();
    worker.sendResponse = (_, _) => response.future;
    final pending = details.respond(selected, 'accept_offer');
    for (final action in ['accept_offer', 'decline_offer', 'withdraw']) {
      await expectLater(details.respond(selected, action), throwsStateError);
    }
    final refresh = Completer<List<Map<String, dynamic>>>();
    worker.fetch = () => refresh.future;
    response.complete('hired');
    await Future<void>.delayed(Duration.zero);
    expect(details.responding, isTrue);
    for (final action in ['accept_offer', 'decline_offer', 'withdraw']) {
      await expectLater(details.respond(selected, action), throwsStateError);
    }
    refresh.complete([applicationRow(id, status: 'hired')]);
    await pending;
    expect(details.application!.status, MyApplicationStatus.hired);
    expect(worker.responses, [(id, 'accept_offer')]);
  });

  test(
    'an unowned application and a signed-out session cannot dispatch actions',
    () async {
      worker.rows = [applicationRow(other, status: 'offered')];
      await details.load();
      expect(details.application, isNull);
      final foreign = MyJobApplication(
        applicationRow(other, status: 'offered'),
      );
      for (final action in ApplicationResponseAction.values) {
        await expectLater(
          details.respond(foreign, action.wireName),
          throwsStateError,
        );
      }
      expect(worker.historyCalls, isEmpty);
      worker.rows = [applicationRow(id, status: 'offered')];
      await details.load();
      final selected = details.application!;
      worker.switchAccount(null);
      await expectLater(
        details.respond(selected, 'accept_offer'),
        throwsStateError,
      );
      expect(worker.responses, isEmpty);
      expect(details.events, isEmpty);
    },
  );

  test('server denial reconciles a concurrently accepted offer and blocks later decline', () async {
    worker.rows = [applicationRow(id, status: 'offered')];
    await details.load();
    worker.sendResponse = (_, _) async {
      worker.rows = [applicationRow(id, status: 'hired')];
      worker.historyRows = [historyRow('accepted', status: 'hired')];
      throw const PostgrestException(message: 'Denied', code: '42501');
    };
    await details.respond(details.application!, 'decline_offer');
    expect(details.application!.status, MyApplicationStatus.hired);
    expect(details.responseError, contains('access denied'));
    await expectLater(
      details.respond(details.application!, 'decline_offer'),
      throwsStateError,
    );
    await expectLater(
      details.respond(details.application!, 'withdraw'),
      throwsStateError,
    );
    expect(worker.responses, [(id, 'decline_offer')]);
  });

  test('post-hire actions never dispatch and leave independent local work records intact', () async {
    worker.rows = [applicationRow(id, status: 'hired')];
    employer.rows = [applicantRow(id, status: 'hired')];
    await details.load();
    await applicants.load();
    final shifts = [
      assignment()..['application_id'] = id,
      assignment()
        ..['assignment_id'] = other
        ..['application_id'] = id
        ..['assignment_status'] = 'active'
        ..['check_in_at'] = '2026-11-05T01:00:00Z',
      assignment()
        ..['assignment_id'] = '33333333-3333-4333-8333-333333333333'
        ..['application_id'] = id
        ..['assignment_status'] = 'completed'
        ..['verification_status'] = 'verified'
        ..['check_in_at'] = '2026-11-05T01:00:00Z'
        ..['check_out_at'] = '2026-11-05T09:00:00Z'
        ..['verified_at'] = '2026-11-05T10:00:00Z',
    ];
    final evidence = [evidenceRow()];
    final snapshot = shifts.map(Map<String, dynamic>.of).toList();
    final evidenceSnapshot = evidence.map(Map<String, dynamic>.of).toList();
    final workSource = FakeSource()
      ..workerRead = (() async => shifts)
      ..evidenceRead = ((_) async => evidence);
    final work = WorkAttendanceRepository(workSource);
    addTearDown(() async {
      work.dispose();
      await workSource.changes.close();
    });
    await work.loadWorkerAssignments();
    await work.loadEvidence(id);
    final loadedShifts = work.worker.rows;
    final loadedEvidence = work.evidence.rows;
    for (final action in [
      ...ApplicationResponseAction.values.map((a) => a.wireName),
      'cancel',
    ]) {
      await expectLater(
        details.respond(details.application!, action),
        throwsStateError,
      );
    }
    for (final next in MyApplicationStatus.values) {
      await expectLater(
        applicants.updateStatus(applicants.applicants.single, next, ''),
        throwsStateError,
      );
    }
    expect(worker.responses, isEmpty);
    expect(employer.updates, isEmpty);
    expect(work.worker.rows, same(loadedShifts));
    expect(work.evidence.rows, same(loadedEvidence));
    expect(shifts, snapshot);
    expect(evidence, evidenceSnapshot);
    expect(workSource.checkIns, 0);
    expect(workSource.checkOuts, 0);
  });

  for (final status in [
    MyApplicationStatus.offered,
    MyApplicationStatus.hired,
    MyApplicationStatus.declined,
    MyApplicationStatus.withdrawn,
  ]) {
    for (final employerView in [false, true]) {
      testWidgets(
        '${status.label} has consistent lifecycle presentation for ${employerView ? 'employer' : 'worker'}',
        (tester) async {
          tester.view.physicalSize = const Size(320, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          worker.rows = [applicationRow(id, status: status.name)];
          employer.rows = [applicantRow(id, status: status.name)];
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: employerView
                  ? EmployerApplicantsPage(
                      source: employer,
                      jobId: 'real-job-id',
                    )
                  : MyApplicationDetailsPage(applicationId: id, source: worker),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(status.label), findsWidgets);
          expect(find.text(status.lifecycleExplanation!), findsOneWidget);
          expect(find.text('Cancel hired arrangement'), findsNothing);
          if (status != MyApplicationStatus.offered || employerView) {
            for (final action in ApplicationResponseAction.values) {
              expect(find.text(action.label), findsNothing);
            }
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
