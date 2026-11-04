import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/applications/applications_page.dart';
import 'package:jobmate/features/applications/browse_jobs_page.dart';
import 'package:jobmate/features/applications/job_details_page.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/features/applications/module2_widgets.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';

GoRouter demoRouter(Module2Repository repo, String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('Dashboard root')),
    ),
    GoRoute(
      path: AppRoutes.browseJobs,
      builder: (_, _) => BrowseJobsPage(repository: repo),
    ),
    GoRoute(
      path: '${AppRoutes.browseJobs}/:id',
      builder: (_, state) =>
          JobDetailsPage(jobId: state.pathParameters['id']!, repository: repo),
    ),
    GoRoute(
      path: AppRoutes.applications,
      builder: (_, _) => ApplicationsPage(repository: repo),
    ),
    GoRoute(
      path: '${AppRoutes.applications}/:id',
      builder: (_, state) => ApplicationDetailsPage(
        applicationId: state.pathParameters['id']!,
        repository: repo,
      ),
    ),
    GoRoute(
      path: AppRoutes.applicants,
      builder: (_, state) => ApplicationsPage(
        employer: true,
        postingId: state.uri.queryParameters['posting'],
        repository: repo,
      ),
    ),
    GoRoute(
      path: '${AppRoutes.applicants}/:id',
      builder: (_, state) => ApplicationDetailsPage(
        employer: true,
        applicationId: state.pathParameters['id']!,
        repository: repo,
      ),
    ),
    GoRoute(
      path: AppRoutes.profile,
      builder: (_, _) => const Scaffold(body: Text('Profile root')),
    ),
    GoRoute(
      path: AppRoutes.jobPostings,
      builder: (_, _) => const Scaffold(body: Text('Postings root')),
    ),
    GoRoute(
      path: AppRoutes.company,
      builder: (_, _) => const Scaffold(body: Text('Company root')),
    ),
  ],
);

void main() {
  testWidgets('Access gate has loading, error, retry and denied states', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Module2Gate(
          role: 'job_seeker',
          checkAccess: () {
            calls++;
            return calls == 1 ? pending.future : Future.value(false);
          },
          child: const Text('Protected demo content'),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to check access'), findsOneWidget);
    expect(find.text('Back to Dashboard'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Page unavailable'), findsOneWidget);
    expect(find.text('Protected demo content'), findsNothing);
  });
  testWidgets(
    'Employer rejects sample with internal note and terminal actions disable',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = Module2Repository();
      addTearDown(repo.dispose);
      final router = demoRouter(repo, '${AppRoutes.applicants}/demo-seed-0');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: JobMateTheme.light(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      final reject = find.widgetWithText(OutlinedButton, 'Reject');
      await tester.ensureVisible(reject);
      await tester.tap(reject);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Internal demo reason');
      await tester.ensureVisible(find.text('Confirm demo change'));
      await tester.tap(find.text('Confirm demo change'));
      await tester.pumpAndSettle();
      expect(repo.application('demo-seed-0')!.stage, ApplicationStage.rejected);
      expect(
        repo.application('demo-seed-0')!.internalNote,
        'Internal demo reason',
      );
      expect(tester.widget<OutlinedButton>(reject).onPressed, isNull);
      router.go('${AppRoutes.applications}/demo-seed-0');
      await tester.pumpAndSettle();
      expect(find.text('Internal demo reason'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test('Status mapping and terminal transitions are explicit', () {
    expect(
      ApplicationStage.fromLabel('Reviewing'),
      ApplicationStage.shortlisted,
    );
    expect(
      ApplicationStage.fromLabel('Shortlisted'),
      ApplicationStage.shortlisted,
    );
    expect(ApplicationStage.fromLabel('unknown'), isNull);
    for (final stage in [
      ApplicationStage.hired,
      ApplicationStage.rejected,
      ApplicationStage.withdrawn,
    ]) {
      expect(stage.completed, isTrue);
      expect(stage.employerNext, isEmpty);
      expect(stage.canWithdraw, isFalse);
    }
  });
  test('Public projection drops hidden compensation and nonpublic fields', () {
    final job = BrowseJob({
      'salary_visible': false,
      'salary_min': 900001,
      'salary_max': 900002,
      'salary_period': 'monthly',
      'original_description': 'private draft input',
    }, company: 'Test');
    expect(job.fields.keys, isNot(contains('salary_min')));
    expect(job.fields.keys, isNot(contains('salary_max')));
    expect(job.fields.keys, isNot(contains('salary_period')));
    expect(job.fields.keys, isNot(contains('original_description')));
    expect(job.fields.toString(), isNot(contains('900001')));
  });
  test('Catalogue filtering, saving and sorting exclude closed jobs', () {
    final repo = Module2Repository();
    addTearDown(repo.dispose);
    expect(repo.searchJobs().length, 4);
    expect(
      repo.searchJobs().every((j) => j.text('status') == 'published'),
      isTrue,
    );
    expect(repo.searchJobs(query: 'pixel').single.title, 'Flutter Intern');
    expect(
      repo
          .searchJobs(
            type: 'internship',
            arrangement: 'hybrid',
            location: 'kuala',
          )
          .single
          .id,
      'demo-job-2',
    );
    expect(repo.searchJobs(query: 'communication').length, 4);
    expect(repo.searchJobs(query: 'no match'), isEmpty);
    repo.toggleSave('demo-job-2');
    expect(repo.searchJobs(savedOnly: true).single.id, 'demo-job-2');
    repo.toggleSave('demo-job-2');
    expect(repo.searchJobs(savedOnly: true), isEmpty);
    expect(
      repo.searchJobs(sort: 'Title').first.title,
      'Customer Support Associate',
    );
  });
  test(
    'Application preview validates duplicates, closed jobs, deadline and note',
    () async {
      final repo = Module2Repository();
      addTearDown(repo.dispose);
      await expectLater(repo.submit('demo-job-1', ''), throwsStateError);
      await expectLater(repo.submit('demo-job-4', ''), throwsStateError);
      await expectLater(repo.submit('demo-job-5', ''), throwsStateError);
      await expectLater(repo.submit('missing', ''), throwsStateError);
      await expectLater(
        repo.submit('demo-job-2', 'x' * 1001),
        throwsStateError,
      );
      await repo.submit('demo-job-2', ' Cover note ');
      expect(
        repo
            .searchApplications(mineOnly: true)
            .where((a) => a.jobId == 'demo-job-2')
            .single
            .note,
        'Cover note',
      );
      await expectLater(repo.submit('demo-job-2', ''), throwsStateError);
    },
  );
  test('Both roles share stages, counts and chronological history', () async {
    final repo = Module2Repository();
    addTearDown(repo.dispose);
    await repo.submit('demo-job-2', 'Hello');
    final a = repo.searchApplications(mineOnly: true).first;
    expect(
      () => repo.transition(a.id, ApplicationStage.hired, employer: true),
      throwsStateError,
    );
    for (final stage in [
      ApplicationStage.shortlisted,
      ApplicationStage.interview,
      ApplicationStage.offered,
    ]) {
      repo.transition(a.id, stage, employer: true);
    }
    repo.transition(a.id, ApplicationStage.hired, employer: false);
    expect(
      repo.searchApplications(mineOnly: true, tab: 'Completed'),
      contains(a),
    );
    expect(
      repo.searchApplications(jobId: a.jobId, stage: ApplicationStage.hired),
      contains(a),
    );
    expect(a.timeline.map((e) => e.$1), [
      ApplicationStage.applied,
      ApplicationStage.shortlisted,
      ApplicationStage.interview,
      ApplicationStage.offered,
      ApplicationStage.hired,
    ]);
    expect(
      () => repo.transition(a.id, ApplicationStage.rejected, employer: true),
      throwsStateError,
    );
  });
  test('Withdrawal, rejection and reset retain coherent local state', () {
    final repo = Module2Repository();
    addTearDown(repo.dispose);
    final mine = repo
        .searchApplications(mineOnly: true, stage: ApplicationStage.applied)
        .single;
    repo.transition(mine.id, ApplicationStage.withdrawn, employer: false);
    expect(repo.applied(mine.jobId), isTrue);
    expect(
      repo.searchApplications(mineOnly: true, tab: 'Active'),
      isNot(contains(mine)),
    );
    final other = repo
        .searchApplications(stage: ApplicationStage.shortlisted)
        .first;
    expect(
      () => repo.transition(
        other.id,
        ApplicationStage.withdrawn,
        employer: false,
      ),
      throwsStateError,
    );
    repo.transition(
      other.id,
      ApplicationStage.rejected,
      employer: true,
      note: 'Internal sample',
    );
    expect(other.internalNote, 'Internal sample');
    repo.toggleSave('demo-job-2');
    repo.reset();
    expect(repo.saved('demo-job-2'), isFalse);
    expect(repo.application(mine.id)!.stage, ApplicationStage.applied);
  });
  testWidgets('Route exit retains an unsubmitted cover note in the session', (
    tester,
  ) async {
    final repo = Module2Repository();
    addTearDown(repo.dispose);
    final router = demoRouter(repo, '${AppRoutes.browseJobs}/demo-job-2');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply Now (demo)'));
    await tester.tap(find.text('Apply Now (demo)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Retained demo draft');
    expect(repo.noteDraft('cover:demo-job-2'), 'Retained demo draft');
    // Dispose the modal/page, as can happen with a declarative browser route exit.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApplyDemoForm(job: repo.job('demo-job-2')!, repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Retained demo draft',
    );
    repo.reset();
    expect(repo.noteDraft('cover:demo-job-2'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 768.0, 1440.0]) {
    for (final page in [
      AppRoutes.browseJobs,
      AppRoutes.applications,
      AppRoutes.applicants,
      '${AppRoutes.browseJobs}/demo-job-2',
      '${AppRoutes.applicants}/demo-seed-1',
    ]) {
      testWidgets('$page responsive demo at $width', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = Module2Repository();
        addTearDown(repo.dispose);
        final router = demoRouter(repo, page);
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(theme: JobMateTheme.light(), routerConfig: router),
        );
        await tester.pumpAndSettle();
        expect(find.text('DEMO / PREVIEW'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (page == AppRoutes.browseJobs) {
          await tester.enterText(
            find.byType(TextField).first,
            'no matching jobs',
          );
          await tester.pumpAndSettle();
          expect(find.text('No matching jobs'), findsOneWidget);
        }
        if (page == '${AppRoutes.browseJobs}/demo-job-2') {
          expect(find.text('Salary not disclosed'), findsOneWidget);
          expect(
            find.byType(BackButton),
            kIsWeb ? findsNothing : findsOneWidget,
          );
        }
      });
    }
    testWidgets(
      'Apply sheet protects note and records local success at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = Module2Repository();
        addTearDown(repo.dispose);
        final router = demoRouter(repo, '${AppRoutes.browseJobs}/demo-job-2');
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(theme: JobMateTheme.light(), routerConfig: router),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Apply Now (demo)'));
        await tester.tap(find.text('Apply Now (demo)'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'My demo note');
        await tester.ensureVisible(find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Discard cover note?'), findsOneWidget);
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Submit demo application'));
        await tester.tap(find.text('Submit demo application'));
        await tester.pumpAndSettle();
        expect(find.text('Demo application recorded'), findsOneWidget);
        expect(repo.applied('demo-job-2'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Real posting entry does not manufacture applicants', (
    tester,
  ) async {
    final repo = Module2Repository();
    addTearDown(repo.dispose);
    final router = demoRouter(
      repo,
      '${AppRoutes.applicants}?posting=real-job-id',
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Live applications are not connected'), findsOneWidget);
    expect(find.textContaining('Sample candidate'), findsNothing);
    expect(find.textContaining('demo applications'), findsNothing);
  });
  testWidgets('Direct job route has in-app return fallback', (tester) async {
    final repo = Module2Repository();
    addTearDown(repo.dispose);
    final router = demoRouter(repo, '${AppRoutes.browseJobs}/unknown');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Job unavailable'), findsOneWidget);
    await tester.tap(
      kIsWeb ? find.text('Back to Browse Jobs') : find.byType(BackButton),
    );
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutes.browseJobs,
    );
    expect(tester.takeException(), isNull);
  });
}
