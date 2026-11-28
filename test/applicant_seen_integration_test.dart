import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jobmate/features/applications/applicant_notification_repository.dart';
import 'package:jobmate/features/applications/applicant_unseen_controller.dart';
import 'package:jobmate/features/applications/employer_applicants_page.dart';
import 'package:jobmate/features/applications/employer_applicants_repository.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';

import 'fixtures/employer_applicants_source.dart';

String id(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
final firstJob = id(1);
final secondJob = id(2);

Map<String, dynamic> row(int value, {String name = 'Alex Thee'}) => {
  ...applicantRow(id(value)),
  'applicant_name': name,
};

class _Harness {
  _Harness(WidgetTester tester) {
    source.data = EmployerPostingContext(
      const JobAccess({'company_id': 'company-id'}, null),
      [
        for (final job in [firstJob, secondJob])
          {'job_id': job, 'title': 'Job $job', 'status': 'published'},
      ],
    );
    controller = ApplicantUnseenController(
      ApplicantNotificationRepository.withRpc((name, params) async {
        if (name == 'list_unseen_applicant_counts') {
          reads++;
          return <Map<String, dynamic>>[];
        }
        expect(name, 'acknowledge_applicants_seen');
        final ids = List<String>.of(
          params['p_application_ids'] as List<String>,
        );
        writes.add((params['p_job_id'] as String, ids));
        return await send(ids);
      }),
      currentUserId: () => source.userId,
      accountChanges: source.accountChanges,
    )..enterWorkspace(accountId: source.userId, companyId: 'company-id');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await source.changes.close();
    });
  }

  final source = TestEmployerApplicantsSource();
  final writes = <(String, List<String>)>[];
  late final ApplicantUnseenController controller;
  int reads = 0;
  Future<int> Function(List<String>) send = (ids) async => ids.length;

  Future<void> show(WidgetTester tester, String? job) => tester.pumpWidget(
    MaterialApp(
      home: EmployerApplicantsPage(
        source: source,
        jobId: job,
        applicantUnseen: controller,
      ),
    ),
  );
}

void main() {
  testWidgets('quiet refresh stops batching when the selected job disappears', (
    tester,
  ) async {
    final h = _Harness(tester);
    final firstBatch = Completer<int>();
    h.source.rows = [for (var i = 100; i < 201; i++) row(i)];
    h.send = (ids) =>
        h.writes.length == 1 ? firstBatch.future : Future.value(ids.length);
    await h.show(tester, firstJob);
    await tester.pumpAndSettle();
    expect(h.writes.single.$1, firstJob);
    expect(h.writes.single.$2, hasLength(100));

    h.source.data = EmployerPostingContext(
      const JobAccess({'company_id': 'company-id'}, null),
      const [],
    );
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(find.text('Job unavailable'), findsOneWidget);

    firstBatch.complete(100);
    await tester.pumpAndSettle();
    expect(h.writes.map((batch) => batch.$2.length), [100]);
    expect(find.text('Job unavailable'), findsOneWidget);
    expect(find.text('Alex Thee'), findsNothing);
  });

  testWidgets('a covered applicant page waits until it is visible', (
    tester,
  ) async {
    final h = _Harness(tester);
    final result = Completer<List<Map<String, dynamic>>>();
    h.source.fetchApplicants = (_) => result.future;
    await h.show(tester, firstJob);
    await tester.pump();
    final context = tester.element(find.byType(EmployerApplicantsPage));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Cover applicants')),
      ),
    );
    await tester.pump();
    result.complete([row(100)]);
    await tester.pumpAndSettle();
    expect(h.writes, isEmpty);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(h.writes.single.$2, [id(100)]);
  });

  testWidgets(
    'selected-job display acknowledges unique IDs and refreshes counts',
    (tester) async {
      final h = _Harness(tester);
      final result = Completer<List<Map<String, dynamic>>>();
      h.source.fetchApplicants = (_) => result.future;
      await h.show(tester, firstJob);
      await tester.pump();
      expect(h.writes, isEmpty);
      result.complete([row(100), row(100)]);
      // A submission after the RPC snapshot is outside that snapshot.
      h.source.rows = [row(100), row(101)];
      await tester.pumpAndSettle();
      expect(h.writes, hasLength(1));
      expect(h.writes.single.$1, firstJob);
      expect(h.writes.single.$2, [id(100)]);
      expect(h.reads, 2);
      await tester.pump();
      expect(h.writes, hasLength(1));
    },
  );

  testWidgets('unselected, empty and failed lists send no acknowledgments', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.show(tester, null);
    await tester.pumpAndSettle();
    expect(h.source.requests, isEmpty);
    await h.show(tester, firstJob);
    await tester.pumpAndSettle();
    expect(find.text('No applicants yet'), findsOneWidget);
    h.source.fetchApplicants = (_) async =>
        throw const PostgrestException(message: 'List failed', code: '503');
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load applicants'), findsOneWidget);
    expect(h.writes, isEmpty);
  });

  testWidgets('stale requests from a previous job and account are ignored', (
    tester,
  ) async {
    final h = _Harness(tester);
    final staleJob = Completer<List<Map<String, dynamic>>>();
    final staleAccount = Completer<List<Map<String, dynamic>>>();
    h.source.fetchApplicants = (job) {
      if (job == firstJob) return staleJob.future;
      if (h.source.actor == 'employer-a') return staleAccount.future;
      return Future.value([row(102)]);
    };
    await h.show(tester, firstJob);
    await tester.pump();
    await h.show(tester, secondJob);
    await tester.pump();
    h.source.switchAccount('employer-b');
    h.controller.enterWorkspace(
      accountId: 'employer-b',
      companyId: 'company-id',
    );
    staleJob.complete([row(100)]);
    staleAccount.complete([row(101)]);
    await tester.pumpAndSettle();
    expect(h.writes, hasLength(1));
    expect(h.writes.single.$1, secondJob);
    expect(h.writes.single.$2, [id(102)]);
  });

  testWidgets('large lists send bounded batches and stop on workspace change', (
    tester,
  ) async {
    final h = _Harness(tester);
    final gate = Completer<int>();
    h.source.rows = [for (var i = 100; i < 201; i++) row(i)];
    h.send = (ids) =>
        h.writes.length == 1 ? gate.future : Future.value(ids.length);
    await h.show(tester, firstJob);
    await tester.pumpAndSettle();
    expect(h.writes.single.$2, hasLength(100));
    gate.complete(100);
    await tester.pumpAndSettle();
    expect(h.writes.map((call) => call.$2.length), [100, 1]);
    expect(h.writes.expand((call) => call.$2).toSet(), {
      for (var i = 100; i < 201; i++) id(i),
    });
    expect(h.reads, 2);

    final secondGate = Completer<int>();
    h.send = (_) => secondGate.future;
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(h.writes, hasLength(3));
    h.controller.enterWorkspace(
      accountId: h.source.userId,
      companyId: 'other-company',
    );
    await tester.pumpAndSettle();
    final readsAfterSwitch = h.reads;
    secondGate.complete(100);
    await tester.pumpAndSettle();
    expect(h.writes, hasLength(3));
    expect(h.reads, readsAfterSwitch);
  });

  testWidgets(
    'receipt failure is secondary and refresh respects the active filter',
    (tester) async {
      final h = _Harness(tester);
      h.source.rows = [row(100), row(101, name: 'Blake')];
      h.send = (_) async =>
          throw const PostgrestException(message: 'Denied', code: '42501');
      await h.show(tester, firstJob);
      await tester.pumpAndSettle();
      expect(h.writes, hasLength(1));
      expect(h.reads, 1);
      expect(find.text('Unable to load applicants'), findsNothing);

      final query = find.byType(TextField);
      await tester.ensureVisible(query);
      await tester.enterText(query, 'Blake');
      await tester.pumpAndSettle();
      expect(h.writes, hasLength(1));
      h.send = (ids) async => ids.length;
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Blake',
        ),
        findsOneWidget,
      );
      expect(find.text('Alex Thee'), findsNothing);
      expect(h.writes, hasLength(2));
      expect(h.writes.last.$2, [id(101)]);
      expect(h.reads, 2);
      final shortlist = find.text('Shortlist');
      await tester.ensureVisible(shortlist);
      await tester.tap(shortlist);
      await tester.pumpAndSettle();
      final confirm = find.text('Confirm Shortlist');
      await tester.ensureVisible(confirm);
      final update = Completer<void>();
      h.source.sendUpdate = () => update.future;
      await tester.tap(confirm);
      await tester.pump();
      expect(h.source.updates.single.$1, id(101));
      final requestsDuringUpdate = h.source.requests.length;
      await tester.pump(const Duration(seconds: 15));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(h.source.requests, hasLength(requestsDuringUpdate));
      h.source.rows = [
        row(100),
        {...row(101, name: 'Blake'), 'status': 'shortlisted'},
      ];
      update.complete();
      await tester.pumpAndSettle();
      expect(find.text('Application shortlisted'), findsOneWidget);
      expect(h.source.updates.single.$1, id(101));
    },
  );
}
