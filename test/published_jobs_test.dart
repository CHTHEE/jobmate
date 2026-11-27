import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/browse_jobs_page.dart';
import 'package:jobmate/features/applications/job_details_page.dart';
import 'package:jobmate/features/applications/module2_repository.dart';

import 'fixtures/published_jobs_source.dart';
import 'fixtures/job_application_gateway.dart';
import 'fixtures/my_applications_source.dart';

import 'package:jobmate/features/applications/job_application_form.dart';

import 'job_marketplace_application_workflow_test.dart' show demoRouter;

Map<String, dynamic> publishedRow(String id, {bool visible = false}) => {
  'job_id': id,
  'company_id': 'company-id',
  'company_name': 'Actual Company',
  'title': 'Flutter Developer',
  'department': 'Engineering',
  'employment_type': 'full_time',
  'work_arrangement': 'remote',
  'location': 'Kuala Lumpur',
  'salary_visible': visible,
  'salary_min': visible ? 4000 : null,
  'salary_max': visible ? 6000 : null,
  'salary_period': visible ? 'monthly' : null,
  'vacancies': 2,
  'application_deadline': '2099-12-31',
  'original_description': 'Build useful software.',
  'role_overview': 'Develop our Flutter app.',
  'responsibilities': ['Build features'],
  'requirements': ['Dart'],
  'benefits': ['Flexible hours'],
  'published_at': '2026-11-04T01:00:00Z',
};

void main() {
  test(
    'discovery hides expired rows but saved and direct projections retain them',
    () async {
      final source = TestPublishedJobsSource()
        ..rows = [
          {...publishedRow('today'), 'application_deadline': '2026-11-27'},
          {...publishedRow('future'), 'application_deadline': '2026-11-29'},
          {...publishedRow('invalid'), 'application_deadline': '2026-02-30'},
          {...publishedRow('draft'), 'status': 'draft'},
          {...publishedRow('closed'), 'status': 'closed'},
        ];
      var now = DateTime.utc(2026, 11, 27, 15, 59, 59);
      final repo = PublishedJobsRepository(source, now: () => now);
      addTearDown(repo.dispose);
      addTearDown(source.changes.close);
      await repo.load();
      expect(repo.searchJobs(sort: 'Deadline').map((job) => job.id), [
        'today',
        'future',
      ]);
      repo.toggleSave('today');
      now = DateTime.utc(2026, 11, 27, 16);
      expect(repo.searchJobs().single.id, 'future');
      expect(repo.job('today'), isNotNull);
      expect(repo.searchJobs(savedOnly: true).single.id, 'today');
      repo.toggleSave('today');
      expect(repo.searchJobs(savedOnly: true), isEmpty);
      expect(source.calls, 1);
    },
  );

  test(
    'Real catalogue filters, sorts, saves and never mixes demo jobs',
    () async {
      final source = TestPublishedJobsSource()
        ..rows = [
          publishedRow('real-one'),
          {
            ...publishedRow('real-two', visible: true),
            'title': 'Accountant',
            'location': 'Shah Alam',
            'employment_type': 'part_time',
            'work_arrangement': 'on_site',
            'published_at': '2026-11-03',
            'application_deadline': '2099-11-01',
          },
        ];
      final repo = Module2Repository(publishedSource: source);
      addTearDown(repo.dispose);
      addTearDown(source.changes.close);
      await repo.browse.load();
      expect(repo.browse.jobs.map((j) => j.id), ['real-one', 'real-two']);
      expect(repo.browse.job('real-one')!.text('status'), 'published');
      expect(
        repo.browse
            .searchJobs(
              query: 'actual',
              location: 'kuala',
              type: 'full_time',
              arrangement: 'remote',
            )
            .single
            .id,
        'real-one',
      );
      expect(repo.browse.searchJobs(query: 'useful').length, 2);
      expect(repo.browse.searchJobs(sort: 'Title').first.id, 'real-two');
      expect(repo.browse.searchJobs(sort: 'Deadline').first.id, 'real-two');
      expect(repo.browse.searchJobs().first.id, 'real-one');
      repo.browse.toggleSave('real-one');
      expect(repo.browse.searchJobs(savedOnly: true).single.id, 'real-one');
      await repo.browse.load();
      expect(repo.browse.saved('real-one'), isTrue);
      repo.browse.toggleSave('real-one');
      expect(repo.browse.searchJobs(savedOnly: true), isEmpty);
      final before = repo.applications.length;
      await expectLater(repo.submit('real-one', ''), throwsStateError);
      expect(repo.applications.length, before);
    },
  );

  test(
    'Account changes invalidate pending reads, cached jobs and saved IDs',
    () async {
      final source = TestPublishedJobsSource()..rows = [publishedRow('old')];
      final repo = PublishedJobsRepository(source);
      addTearDown(repo.dispose);
      addTearDown(source.changes.close);
      await repo.load();
      repo.toggleSave('old');
      final pending = Completer<List<Map<String, dynamic>>>();
      source.fetch = () => pending.future;
      final oldRequest = repo.load();
      source.fetch = () async => [publishedRow('new')];
      source.switchAccount('seeker-b');
      pending.complete([publishedRow('stale')]);
      await oldRequest;
      await Future<void>.delayed(Duration.zero);
      expect(repo.jobs.map((j) => j.id), ['new']);
      expect(repo.saved('old'), isFalse);
      source.switchAccount(null);
      expect(repo.jobs, isEmpty);
      expect(repo.loaded, isFalse);
      await repo.load();
      expect(repo.error, contains('Sign in'));
    },
  );

  test('Reset and dispose ignore in-flight responses', () async {
    final source = TestPublishedJobsSource();
    addTearDown(source.changes.close);
    final pending = Completer<List<Map<String, dynamic>>>();
    source.fetch = () => pending.future;
    final repo = PublishedJobsRepository(source);
    final request = repo.load();
    repo.reset();
    repo.dispose();
    pending.complete([publishedRow('late')]);
    await request;
    expect(repo.jobs, isEmpty);
  });

  testWidgets('Browse shows loading, honest failure, retry and empty refresh', (
    tester,
  ) async {
    final source = TestPublishedJobsSource();
    final pending = Completer<List<Map<String, dynamic>>>();
    source.fetch = () => pending.future;
    final repo = Module2Repository(publishedSource: source);
    addTearDown(repo.dispose);
    addTearDown(source.changes.close);
    await tester.pumpWidget(
      MaterialApp(home: BrowseJobsPage(repository: repo)),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('Service unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load jobs'), findsOneWidget);
    expect(find.text('Retail Assistant'), findsNothing);
    source.fetch = () async => [];
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No jobs accepting applications'), findsOneWidget);
    source.fetch = () async => [publishedRow('real-id')];
    await tester.tap(find.byTooltip('Refresh jobs'));
    await tester.pumpAndSettle();
    expect(find.text('Flutter Developer'), findsOneWidget);
    expect(find.text('Actual Company'), findsOneWidget);
    expect(find.text('Salary not disclosed'), findsOneWidget);
  });

  for (final width in [320.0, 1440.0]) {
    testWidgets('Direct details reload and Apply uses real gateway at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = TestPublishedJobsSource()
        ..rows = [publishedRow('real-id')];
      final gateway = TestApplicationGateway();
      addTearDown(gateway.changes.close);
      final repo = Module2Repository(
        publishedSource: source,
        applicationGatewayFactory: () => gateway,
        myApplicationsSource: TestMyApplicationsSource(),
      );
      addTearDown(repo.dispose);
      addTearDown(source.changes.close);
      final router = demoRouter(repo, '/jobs/real-id');
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(source.calls, 1);
      expect(find.text('Actual Company'), findsWidgets);
      expect(find.text('Develop our Flutter app.'), findsOneWidget);
      expect(find.text('Build useful software.'), findsOneWidget);
      expect(find.text('Salary not disclosed'), findsOneWidget);
      final before = repo.applications.length;
      await tester.ensureVisible(find.text('Apply Now'));
      await tester.tap(find.text('Apply Now'));
      await tester.pumpAndSettle();
      expect(find.byType(JobApplicationForm), findsOneWidget);
      expect(find.byType(ApplyDemoForm), findsNothing);
      expect(repo.applications.length, before);
      source.switchAccount(null);
      gateway.switchAccount(null);
      await tester.pumpAndSettle();
      expect(find.textContaining('Flutter Developer'), findsNothing);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      source.actor = 'seeker-a';
      source.rows = [];
      await tester.tap(find.byTooltip('Refresh job'));
      await tester.pumpAndSettle();
      expect(find.text('Job unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('open details and its stale Apply dialog enforce MYT rollover', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 27, 15, 59, 58);
    final jobs = TestPublishedJobsSource()
      ..rows = [
        {...publishedRow('midnight'), 'application_deadline': '2026-11-27'},
      ];
    final applications = TestMyApplicationsSource();
    final gateway = TestApplicationGateway();
    final module = Module2Repository(
      publishedSource: jobs,
      publishedClock: () => now,
      myApplicationsSource: applications,
      applicationGatewayFactory: () => gateway,
    );
    addTearDown(module.dispose);
    addTearDown(jobs.changes.close);
    addTearDown(applications.changes.close);
    addTearDown(gateway.changes.close);
    await tester.pumpWidget(
      MaterialApp(
        home: JobDetailsPage(jobId: 'midnight', repository: module),
      ),
    );
    await tester.pumpAndSettle();
    final apply = find.widgetWithText(FilledButton, 'Apply Now');
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    final submit = find.widgetWithText(FilledButton, 'Submit application');
    await tester.ensureVisible(submit);
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

    now = DateTime.utc(2026, 11, 27, 16);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(gateway.submissions, 0);
    expect(
      find.descendant(
        of: find.byType(JobApplicationForm),
        matching: find.text('Application deadline has passed.'),
      ),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    expect(
      find.text('This job is no longer accepting new applications.'),
      findsOneWidget,
    );
    expect(jobs.calls, 1);
  });

  testWidgets('Visible null salary is safe and hidden values are discarded', (
    tester,
  ) async {
    final hidden = BrowseJob.published({
      ...publishedRow('hidden'),
      'salary_min': 9999,
      'salary_max': 99999,
    });
    expect(hidden.fields.containsKey('salary_min'), isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobFacts(
            BrowseJob.published({
              ...publishedRow('null', visible: true),
              'salary_min': null,
              'salary_max': null,
            }),
          ),
        ),
      ),
    );
    expect(find.text('Salary not disclosed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
