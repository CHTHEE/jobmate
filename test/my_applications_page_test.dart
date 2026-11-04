import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/applications/applications_page.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/features/applications/my_applications_page.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';

import 'fixtures/my_applications_source.dart';

void main() {
  late TestMyApplicationsSource source;
  late Module2Repository module;
  setUp(() {
    source = TestMyApplicationsSource();
    module = Module2Repository(myApplicationsSource: source);
  });
  tearDown(() async {
    module.dispose();
    await source.changes.close();
  });
  Future<void> showPage(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: JobMateTheme.light(),
      home: ApplicationsPage(repository: module),
    ),
  );

  for (final width in [320.0, 1440.0]) {
    testWidgets('Real cards preserve responsive UI at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      source.rows = [applicationRow('bc697799-463f-4251-b6be-8888551c3712')];
      await showPage(tester);
      await tester.pumpAndSettle();
      expect(find.byType(MyApplicationsPage), findsOneWidget);
      expect(find.text('Part-Time Cafe Crew'), findsOneWidget);
      expect(find.text('ABC Company'), findsOneWidget);
      expect(find.text('Applied'), findsOneWidget);
      expect(find.text('Applied: 2026-11-04'), findsOneWidget);
      expect(find.text('DEMO / PREVIEW'), findsNothing);
      expect(find.textContaining('Demo candidate'), findsNothing);
      expect(
        find.byKey(const ValueKey('bc697799-463f-4251-b6be-8888551c3712')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'View Application'),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('Withdraw'), findsNothing);
      expect(find.text('Resume not provided'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Loading, failure, retry and empty states never show demo rows', (
    tester,
  ) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    source.fetch = () => pending.future;
    await showPage(tester);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('Unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load applications'), findsOneWidget);
    expect(find.text('Retail Assistant'), findsNothing);
    source.fetch = () async => [];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No applications yet'), findsOneWidget);
    source.fetch = () async => [applicationRow('real')];
    await tester.tap(find.byTooltip('Refresh applications'));
    await tester.pumpAndSettle();
    expect(find.text('ABC Company'), findsOneWidget);
  });

  testWidgets(
    'Search, status and completed filters distinguish declined/withdrawn',
    (tester) async {
      source.rows = [
        applicationRow('applied'),
        {
          ...applicationRow('declined', status: 'declined'),
          'job_title': 'Declined job',
        },
        {
          ...applicationRow('withdrawn', status: 'withdrawn'),
          'job_title': 'Withdrawn job',
        },
      ];
      await showPage(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Completed'));
      await tester.pumpAndSettle();
      expect(find.text('Part-Time Cafe Crew'), findsNothing);
      expect(find.text('Declined'), findsOneWidget);
      expect(find.text('Withdrawn'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Declined job');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('declined')), findsOneWidget);
      expect(find.text('Withdrawn job'), findsNothing);
      await tester.enterText(find.byType(TextField), 'no match');
      await tester.pumpAndSettle();
      expect(find.text('No applications found'), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(TextButton, 'Clear filters').first,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Clear filters').first);
      await tester.pumpAndSettle();
      final statusField = find.byType(DropdownButtonFormField<String>).first;
      await tester.ensureVisible(statusField);
      await tester.tap(statusField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Declined').last);
      await tester.pumpAndSettle();
      expect(find.text('Declined job'), findsOneWidget);
      expect(find.text('Withdrawn job'), findsNothing);
    },
  );

  testWidgets(
    'Account switch removes previous cards and logout cannot keep cache',
    (tester) async {
      source.rows = [applicationRow('old')];
      await showPage(tester);
      await tester.pumpAndSettle();
      source.rows = [
        {...applicationRow('new'), 'company_name': 'New account company'},
      ];
      source.switchAccount('seeker-b');
      await tester.pumpAndSettle();
      expect(find.text('ABC Company'), findsNothing);
      expect(find.text('New account company'), findsOneWidget);
      source.switchAccount(null);
      await tester.pumpAndSettle();
      expect(find.text('New account company'), findsNothing);
      expect(module.myApplications.applications, isEmpty);
    },
  );

  testWidgets('Returning from a job refreshes and preserves the real job ID', (
    tester,
  ) async {
    source.rows = [applicationRow('old')];
    String? openedJob;
    final router = GoRouter(
      initialLocation: '/applications',
      routes: [
        GoRoute(
          path: '/applications',
          builder: (_, _) => ApplicationsPage(repository: module),
        ),
        GoRoute(
          path: '/jobs/:id',
          builder: (context, state) {
            openedJob = state.pathParameters['id'];
            return Scaffold(
              body: TextButton(
                onPressed: () => context.pop(),
                child: const Text('Return'),
              ),
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View Job'));
    await tester.tap(find.text('View Job'));
    await tester.pumpAndSettle();
    expect(openedJob, 'real-job-id');
    source.rows = [
      applicationRow('old'),
      {...applicationRow('new'), 'job_title': 'New application'},
    ];
    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();
    expect(source.calls, 2);
    expect(find.text('New application'), findsOneWidget);
  });
}
