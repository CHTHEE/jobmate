import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/employer_applicants_page.dart';
import 'package:jobmate/features/applications/employer_applicants_repository.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/employer_applicants_source.dart';

void main() {
  late TestEmployerApplicantsSource source;
  late EmployerApplicantsRepository repo;
  setUp(() async {
    source = TestEmployerApplicantsSource()
      ..rows = [applicantRow('mock-application')];
    repo = EmployerApplicantsRepository(source, 'real-job-id');
    await repo.load();
  });
  tearDown(() async {
    repo.dispose();
    await source.changes.close();
  });

  test('Only the six allowed transitions exist; offered and terminal states have none', () async {
    final allowed = {
      MyApplicationStatus.submitted: [
        MyApplicationStatus.shortlisted,
        MyApplicationStatus.rejected,
      ],
      MyApplicationStatus.shortlisted: [
        MyApplicationStatus.interview,
        MyApplicationStatus.rejected,
      ],
      MyApplicationStatus.interview: [
        MyApplicationStatus.offered,
        MyApplicationStatus.rejected,
      ],
    };
    for (final status in MyApplicationStatus.values) {
      source.rows = [applicantRow('mock-application', status: status.name)];
      await repo.load();
      final applicant = repo.applicants.single;
      expect(applicant.employerNext, allowed[status] ?? []);
      for (final next in MyApplicationStatus.values.where(
        (s) => !applicant.employerNext.contains(s),
      )) {
        await expectLater(
          repo.updateStatus(applicant, next, ''),
          throwsStateError,
        );
      }
    }
    expect(source.updates, isEmpty);
  });
  test('Allowed transitions call RPC, trim note and refresh without optimistic status', () async {
    final applicant = repo.applicants.single;
    final pending = Completer<void>();
    source.sendUpdate = () => pending.future;
    final request = repo.updateStatus(
      applicant,
      MyApplicationStatus.shortlisted,
      '  reviewed  ',
    );
    await Future<void>.delayed(Duration.zero);
    expect(source.updates.single.$1, 'mock-application');
    expect(source.updates.single.$3, 'reviewed');
    expect(repo.applicants.single.status, MyApplicationStatus.submitted);
    await expectLater(
      repo.updateStatus(applicant, MyApplicationStatus.rejected, ''),
      throwsStateError,
    );
    source.rows = [applicantRow('mock-application', status: 'shortlisted')];
    pending.complete();
    await request;
    expect(repo.applicants.single.status, MyApplicationStatus.shortlisted);
    expect(source.requests, ['real-job-id', 'real-job-id']);
    expect(source.updates.length, 1);
  });
  test(
    'Optional blank note becomes null, overlong notes never submit',
    () async {
      await expectLater(
        repo.updateStatus(
          repo.applicants.single,
          MyApplicationStatus.shortlisted,
          'x' * 2001,
        ),
        throwsStateError,
      );
      expect(source.updates, isEmpty);
      await repo.updateStatus(
        repo.applicants.single,
        MyApplicationStatus.shortlisted,
        '   ',
      );
      expect(source.updates.single.$3, isNull);
    },
  );
  test(
    'RPC failure preserves status and refreshes concurrent changes',
    () async {
      final applicant = repo.applicants.single;
      source.sendUpdate = () => Future.error(
        const PostgrestException(message: 'Invalid transition', code: 'P0001'),
      );
      await expectLater(
        repo.updateStatus(applicant, MyApplicationStatus.shortlisted, ''),
        throwsA(isA<PostgrestException>()),
      );
      expect(repo.applicants.single.status, MyApplicationStatus.submitted);
      source.fetchApplicants = (_) async => [
        applicantRow('mock-application', status: 'offered'),
      ];
      await expectLater(
        repo.updateStatus(
          repo.applicants.single,
          MyApplicationStatus.rejected,
          '',
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(repo.applicants.single.status, MyApplicationStatus.offered);
      expect(source.requests.length, 3);
    },
  );
  test('Company change before submission blocks RPC', () async {
    source.fetchJobs = () async => const EmployerPostingContext(
      JobAccess({'company_id': 'other-company', 'company_name': 'Other'}, null),
      [],
    );
    await expectLater(
      repo.updateStatus(
        repo.applicants.single,
        MyApplicationStatus.shortlisted,
        '',
      ),
      throwsStateError,
    );
    expect(source.updates, isEmpty);
    expect(repo.applicants, isEmpty);
  });
  test(
    'Disposed job page cannot confirm a pending result or submit again',
    () async {
      final separate = EmployerApplicantsRepository(source, 'real-job-id');
      await separate.load();
      final applicant = separate.applicants.single;
      final pending = Completer<void>();
      source.sendUpdate = () => pending.future;
      final request = separate.updateStatus(
        applicant,
        MyApplicationStatus.shortlisted,
        '',
      );
      final assertion = expectLater(request, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      separate.dispose();
      pending.complete();
      await assertion;
      await expectLater(
        separate.updateStatus(applicant, MyApplicationStatus.rejected, ''),
        throwsStateError,
      );
      expect(source.updates.length, 1);
    },
  );
  test('Account switching discards pending update results', () async {
    final pending = Completer<void>();
    source.sendUpdate = () => pending.future;
    final request = repo.updateStatus(
      repo.applicants.single,
      MyApplicationStatus.shortlisted,
      'note',
    );
    final assertion = expectLater(request, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    source.switchAccount(null);
    pending.complete();
    await assertion;
    expect(repo.applicants, isEmpty);
    expect(repo.updating, isFalse);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EmployerApplicantsPage(source: source, jobId: 'real-job-id'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Shortlist'));
    await tester.tap(find.text('Shortlist'));
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 1440.0]) {
    testWidgets('Confirmation, note and real success behavior at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester);
      expect(source.updates, isEmpty);
      expect(find.text('Shortlist applicant?'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, ' Reviewed ');
      final pending = Completer<void>();
      source.sendUpdate = () => pending.future;
      await tester.ensureVisible(find.text('Confirm Shortlist'));
      await tester.tap(find.text('Confirm Shortlist'));
      await tester.pump();
      expect(find.text('Application status updated'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Updating…'),
            )
            .onPressed,
        isNull,
      );
      source.rows = [applicantRow('mock-application', status: 'shortlisted')];
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Application status updated'), findsOneWidget);
      expect(source.updates.single.$3, 'Reviewed');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Shortlist'), findsNothing);
      expect(find.text('Move to Interview'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'Failure retains note and previous status, stale transition is disabled',
    (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField).last, 'Keep note');
      source.sendUpdate = () => Future.error(
        const PostgrestException(
          message: 'Concurrent transition rejected',
          code: 'P0001',
        ),
      );
      source.fetchApplicants = (_) async => [
        applicantRow('mock-application', status: 'offered'),
      ];
      await tester.tap(find.text('Confirm Shortlist'));
      await tester.pumpAndSettle();
      expect(find.text('Concurrent transition rejected'), findsOneWidget);
      expect(find.text('Application status updated'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'Keep note',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm Shortlist'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets('Dirty note asks before discard; logout hides note and result', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField).last, 'Private note');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard status note?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    source.switchAccount(null);
    await tester.pumpAndSettle();
    expect(find.text('Session changed'), findsOneWidget);
    expect(find.text('Private note'), findsNothing);
    expect(find.text('Confirm Shortlist'), findsNothing);
    expect(source.updates, isEmpty);
  });
}
