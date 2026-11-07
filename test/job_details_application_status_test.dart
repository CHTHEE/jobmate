import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/applications/job_details_page.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';

import 'fixtures/published_jobs_source.dart';
import 'fixtures/my_applications_source.dart';
import 'fixtures/job_application_gateway.dart';
import 'published_jobs_test.dart' show publishedRow;

void main() {
  late TestPublishedJobsSource jobs;
  late TestMyApplicationsSource applications;
  late TestApplicationGateway gateway;
  late Module2Repository module;
  late GoRouter router;
  Map<String, dynamic> existing(String status) =>
      applicationRow('application', status: status)..['job_id'] = 'job';
  setUp(() {
    jobs = TestPublishedJobsSource()..rows = [publishedRow('job')];
    applications = TestMyApplicationsSource();
    gateway = TestApplicationGateway();
    module = Module2Repository(
      publishedSource: jobs,
      myApplicationsSource: applications,
      applicationGatewayFactory: () => gateway,
    );
    router = GoRouter(
      initialLocation: '/jobs/job',
      routes: [
        GoRoute(
          path: '/jobs/:id',
          builder: (_, state) => JobDetailsPage(
            jobId: state.pathParameters['id']!,
            repository: module,
          ),
        ),
        GoRoute(
          path: '/applications/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Application ${state.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/away',
          builder: (_, _) => const Scaffold(body: Text('Other page')),
        ),
      ],
    );
  });
  tearDown(() async {
    router.dispose();
    module.dispose();
    await jobs.changes.close();
    await applications.changes.close();
    await gateway.changes.close();
  });
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  for (final status in MyApplicationStatus.values) {
    testWidgets(
      'existing ${status.label} application replaces Apply and retains owned details link',
      (tester) async {
        applications.rows = [existing(status.name)];
        await show(tester);
        expect(find.text('Apply Now'), findsNothing);
        expect(
          find.text('Application status: ${status.label}'),
          findsOneWidget,
        );
        await tap(tester, 'View Application');
        expect(find.text('Application application'), findsOneWidget);
        expect(gateway.submissions, 0);
      },
    );
  }
  testWidgets(
    'unknown/error lookup cannot enable Apply; retry resolves empty list',
    (tester) async {
      final pending = Completer<List<Map<String, dynamic>>>();
      applications.fetch = () => pending.future;
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final checking = find.widgetWithText(
        FilledButton,
        'Checking application status…',
      );
      expect(tester.widget<FilledButton>(checking).onPressed, isNull);
      pending.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Apply Now'), findsNothing);
      applications.fetch = () async => [];
      await tap(tester, 'Retry application status');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply Now'),
            )
            .onPressed,
        isNotNull,
      );
      expect(gateway.submissions, 0);
    },
  );
  testWidgets(
    'successful submission immediately replaces Apply even if subsequent list is stale',
    (tester) async {
      await show(tester);
      await tap(tester, 'Apply Now');
      await tap(tester, 'Submit application');
      expect(find.text('Application submitted'), findsWidgets);
      await tap(tester, 'Done');
      expect(find.text('Apply Now'), findsNothing);
      expect(find.text('View Application'), findsOneWidget);
      expect(gateway.submissions, 1);
    },
  );
  testWidgets('return navigation refreshes changed lifecycle state', (
    tester,
  ) async {
    await show(tester);
    router.push('/away');
    await tester.pumpAndSettle();
    applications.rows = [existing('hired')];
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Application status: Hired'), findsOneWidget);
    expect(find.text('Apply Now'), findsNothing);
  });
  testWidgets(
    'account change discards stale lookup and never leaks previous application',
    (tester) async {
      final pending = Completer<List<Map<String, dynamic>>>();
      applications.fetch = () => pending.future;
      await show(tester);
      applications.fetch = () async => [];
      jobs.switchAccount('seeker-b');
      applications.switchAccount('seeker-b');
      await tester.pumpAndSettle();
      pending.complete([existing('hired')]);
      await tester.pumpAndSettle();
      expect(find.text('View Application'), findsNothing);
      expect(find.text('Application status: Hired'), findsNothing);
      expect(find.text('Apply Now'), findsOneWidget);
    },
  );
}
