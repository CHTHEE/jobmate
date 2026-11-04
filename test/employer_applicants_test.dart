import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/applications/applications_page.dart';
import 'package:jobmate/features/applications/employer_applicants_page.dart';
import 'package:jobmate/features/applications/employer_applicants_repository.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';
import 'package:jobmate/features/jobs/job_postings_page.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/jobs/job_preview.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/employer_applicants_source.dart';
import 'job_postings_test.dart' show TestJobs, completeJob;

void main() {
  late TestEmployerApplicantsSource source;
  setUp(() => source = TestEmployerApplicantsSource());
  tearDown(() => source.changes.close());
  test(
    'Maps eight fields and statuses, filters and orders actual applicants',
    () async {
      source.rows = [
        for (final status in MyApplicationStatus.values)
          {
            ...applicantRow(status.name, status: status.name),
            'applicant_name': status.name,
          },
      ];
      final repo = EmployerApplicantsRepository(source, 'real-job-id');
      addTearDown(repo.dispose);
      await repo.load();
      final submitted = repo.search(status: 'submitted').single;
      expect(submitted.id, 'submitted');
      expect(submitted.applicantId, 'real-applicant-id');
      expect(submitted.resumeId, isNull);
      expect(submitted.coverNote, isNull);
      expect(submitted.updatedAt, submitted.appliedAt);
      expect(repo.search(tab: 'Completed').length, 4);
      expect(
        repo.search(status: 'declined').single.status,
        MyApplicationStatus.declined,
      );
      expect(
        repo.search(status: 'withdrawn').single.status,
        MyApplicationStatus.withdrawn,
      );
      expect(repo.search(query: 'interview').single.name, 'interview');
      expect(repo.search(sort: 'Name').first.name, 'declined');
      expect(repo.search().first.id, 'withdrawn');
      expect(repo.search(sort: 'Oldest').first.id, 'declined');
    },
  );
  test(
    'No selected or unknown job never invokes applicants; closed jobs work',
    () async {
      for (final id in <String?>[null, 'unowned', 'closed-job-id']) {
        final repo = EmployerApplicantsRepository(source, id);
        await repo.load();
        repo.dispose();
      }
      expect(source.requests, ['closed-job-id']);
    },
  );
  test('Account switch prevents previous company applicant results', () async {
    final pending = Completer<List<Map<String, dynamic>>>();
    source.fetchApplicants = (_) => pending.future;
    final repo = EmployerApplicantsRepository(source, 'real-job-id');
    addTearDown(repo.dispose);
    final request = repo.load();
    await Future<void>.delayed(Duration.zero);
    source.fetchApplicants = (_) async => [applicantRow('new')];
    source.switchAccount('employer-b');
    pending.complete([applicantRow('old')]);
    await request;
    await Future<void>.delayed(Duration.zero);
    expect(repo.applicants.single.id, 'new');
    source.switchAccount(null);
    expect(repo.applicants, isEmpty);
    expect(repo.context, isNull);
  });
  test('Late results after job change/disposal are ignored', () async {
    final pending = Completer<List<Map<String, dynamic>>>();
    source.fetchApplicants = (_) => pending.future;
    final repo = EmployerApplicantsRepository(source, 'real-job-id');
    final request = repo.load();
    await Future<void>.delayed(Duration.zero);
    repo.dispose();
    pending.complete([applicantRow('late')]);
    await request;
    expect(repo.applicants, isEmpty);
  });
  test(
    'Refreshing company context removes applicants for a no-longer-owned job',
    () async {
      source.rows = [applicantRow('old-company')];
      final repo = EmployerApplicantsRepository(source, 'real-job-id');
      addTearDown(repo.dispose);
      await repo.load();
      source.data = const EmployerPostingContext(
        JobAccess({
          'company_id': 'other-company',
          'company_name': 'Other Company',
        }, null),
        [],
      );
      await repo.load();
      expect(repo.job, isNull);
      expect(repo.applicants, isEmpty);
      expect(source.requests, ['real-job-id']);
    },
  );
  Future<void> open(
    WidgetTester tester, {
    String? id = 'real-job-id',
    double scale = 1,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: JobMateTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: EmployerApplicantsPage(source: source, jobId: id),
    ),
  );
  for (final width in [320.0, 1440.0]) {
    testWidgets('Real applicants and job context render at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      source.rows = [
        {
          ...applicantRow('bc697799-463f-4251-b6be-8888551c3712'),
          'resume_id': 'resume-id',
          'cover_note': 'I would like to join the cafe.',
        },
      ];
      await open(tester, scale: width == 320 ? 1.6 : 1);
      await tester.pumpAndSettle();
      expect(find.text('Part-Time Cafe Crew'), findsOneWidget);
      expect(find.text('ABC Company'), findsOneWidget);
      expect(find.text('Alex Thee'), findsOneWidget);
      expect(find.text('Resume attached'), findsOneWidget);
      expect(find.text('I would like to join the cafe.'), findsOneWidget);
      expect(find.textContaining('Application ID: bc697799'), findsOneWidget);
      expect(find.text('DEMO / PREVIEW'), findsNothing);
      expect(find.text('Shortlist'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(source.requests, ['real-job-id']);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Honest loading, errors, retry, refresh and empty states', (
    tester,
  ) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    source.fetchApplicants = (_) => pending.future;
    await open(tester);
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(
      const PostgrestException(message: 'Denied', code: '42501'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load applicants'), findsOneWidget);
    source.fetchApplicants = (_) async => [];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No applicants yet'), findsOneWidget);
    source.fetchApplicants = (_) async => [applicantRow('real')];
    await tester.tap(find.byTooltip('Refresh applicants'));
    await tester.pumpAndSettle();
    expect(find.text('Alex Thee'), findsOneWidget);
    expect(find.text('No resume attached'), findsOneWidget);
  });
  testWidgets('Search and exact status filters retain distinct records', (
    tester,
  ) async {
    source.rows = [
      applicantRow('one'),
      {
        ...applicantRow('two', status: 'declined'),
        'applicant_name': 'Other applicant',
      },
    ];
    await open(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Other');
    await tester.pumpAndSettle();
    expect(find.text('Alex Thee'), findsNothing);
    expect(find.text('Other applicant'), findsOneWidget);
    await tester.ensureVisible(find.text('Clear filters'));
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    final filter = find.byType(DropdownButtonFormField<String>).at(1);
    await tester.ensureVisible(filter);
    await tester.tap(filter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Declined').last);
    await tester.pumpAndSettle();
    expect(find.text('Other applicant'), findsOneWidget);
    expect(find.text('Alex Thee'), findsNothing);
  });
  testWidgets(
    'Changing jobs ignores late old-job results and preserves closed context',
    (tester) async {
      final old = Completer<List<Map<String, dynamic>>>();
      source.fetchApplicants = (_) => old.future;
      await open(tester);
      await tester.pump();
      await tester.pump();
      source.fetchApplicants = (_) async => [
        {...applicantRow('new-job'), 'applicant_name': 'Closed job applicant'},
      ];
      await open(tester, id: 'closed-job-id');
      await tester.pumpAndSettle();
      old.complete([
        {...applicantRow('old-job'), 'applicant_name': 'Old job applicant'},
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Closed job applicant'), findsOneWidget);
      expect(find.text('Old job applicant'), findsNothing);
      expect(find.text('Closed posting'), findsOneWidget);
      expect(find.text('Edit Job'), findsNothing);
      expect(source.requests, ['real-job-id', 'closed-job-id']);
    },
  );
  testWidgets('Posting action preserves real ID, View Job and Edit Job paths', (
    tester,
  ) async {
    final posts = TestJobs()
      ..records = [
        {...completeJob(), 'job_id': 'real-job-id', 'status': 'published'},
      ];
    final module = Module2Repository(employerApplicantsSource: source);
    addTearDown(module.dispose);
    final router = GoRouter(
      initialLocation: '/job-postings',
      routes: [
        GoRoute(
          path: '/job-postings',
          builder: (_, _) =>
              JobPostingsPage(repository: posts, initialStatus: 'published'),
        ),
        GoRoute(
          path: '/applicants',
          builder: (_, state) => ApplicationsPage(
            employer: true,
            postingId: state.uri.queryParameters['posting'],
            repository: module,
          ),
        ),
        GoRoute(
          path: '/job-postings/:id/edit',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.pop(),
              child: Text('Edit ${state.pathParameters['id']}'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'View Applicants'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'View Applicants'));
    await tester.pumpAndSettle();
    expect(source.requests, ['real-job-id']);
    await tester.ensureVisible(find.text('View Job'));
    await tester.tap(find.text('View Job'));
    await tester.pumpAndSettle();
    expect(find.byType(JobPreview), findsOneWidget);
    Navigator.of(tester.element(find.byType(JobPreview))).pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit Job'));
    await tester.tap(find.text('Edit Job'));
    await tester.pumpAndSettle();
    expect(find.text('Edit real-job-id'), findsOneWidget);
  });
}
