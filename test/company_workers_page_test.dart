import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/work_attendance/company_workers_page.dart';
import 'package:jobmate/features/work_attendance/company_workers_repository.dart';
import 'package:jobmate/features/work_attendance/work_assignment_creation_repository.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:jobmate/shared/navigation/workspace_destinations.dart';

import 'company_workers_repository_test.dart' show hired, workerShift;
import 'work_assignment_creation_repository_test.dart'
    show CandidateSource, complete, uid;

void main() {
  late CandidateSource source;
  late CompanyWorkersRepository repository;
  setUp(() {
    source = CandidateSource();
    repository = CompanyWorkersRepository(source);
    source.jobs = (_) async => complete([
      {
        'job_id': uid(3),
        'company_id': source.company,
        'title': 'Retail assistant',
      },
      {
        'job_id': uid(8),
        'company_id': source.company,
        'title': 'Event assistant',
      },
    ]);
    source.applicants = (job) async => complete(
      job == uid(3)
          ? [hired(4, 5, 'Alex Worker')]
          : [hired(6, 7, 'Blair Worker')],
    );
  });
  tearDown(() async {
    repository.dispose();
    await source.changes.close();
  });

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CompanyWorkersPage(repository: repository)),
    );
    await tester.pumpAndSettle();
  }

  test('workers navigation points to the existing real workers path', () {
    final workers = workspaceDestinations('employer').values
        .expand((v) => v)
        .singleWhere((v) => v.$1 == AppRoutes.workers);
    expect(workers.$2, 'Company Workers');
    expect(AppRoutes.workers, '/workers');
  });

  testWidgets('real projections, local search/job filter and clear filters', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Alex Worker'), findsOneWidget);
    expect(find.text('Blair Worker'), findsOneWidget);
    expect(find.text('Assigned Shifts'), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byKey(ValueKey(uid(5))),
        matching: find.text('0'),
      ),
      findsNWidgets(2),
    );
    expect(find.text('Hired'), findsNWidgets(2));
    expect(find.text('AW'), findsOneWidget);
    expect(find.textContaining('demo'), findsNothing);
    final reads = source.calls.length;
    final search = find.widgetWithText(TextField, 'Search workers or jobs');
    await tester.ensureVisible(search);
    await tester.enterText(search, 'blair');
    await tester.pumpAndSettle();
    expect(find.text('Alex Worker'), findsNothing);
    expect(find.text('Blair Worker'), findsOneWidget);
    await tester.enterText(search, 'retail');
    await tester.pumpAndSettle();
    expect(find.text('Alex Worker'), findsOneWidget);
    expect(find.text('Blair Worker'), findsNothing);
    await tester.enterText(search, 'nobody');
    await tester.pumpAndSettle();
    expect(find.text('No matching workers'), findsOneWidget);
    await tester.ensureVisible(find.text('Clear filters'));
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    final job = find.widgetWithText(DropdownButtonFormField<String>, 'Job');
    await tester.ensureVisible(job);
    await tester.tap(job);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Event assistant').last);
    await tester.pumpAndSettle();
    expect(find.text('Alex Worker'), findsNothing);
    expect(find.text('Blair Worker'), findsOneWidget);
    expect(source.calls.length, reads);
    expect(source.creates, 0);
    expect(source.reservations, 0);
  });

  testWidgets('loading, empty, error and retry states', (tester) async {
    final pending = Completer<WorkAssignmentCandidateRead>();
    source.jobs = (_) => pending.future;
    await tester.pumpWidget(
      MaterialApp(home: CompanyWorkersPage(repository: repository)),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Company workers unavailable'), findsOneWidget);
    expect(find.text('Alex Worker'), findsNothing);
    source.jobs = (_) async => complete([]);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No hired workers yet'), findsOneWidget);
    expect(find.text('Company workers unavailable'), findsNothing);
  });

  testWidgets('missing counts do not display invented zeroes', (tester) async {
    source.assignments = (_) async => throw Exception('unavailable');
    await show(tester);
    expect(find.text('Alex Worker'), findsOneWidget);
    expect(
      find.text('Shift counts unavailable. Refresh to try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Assigned shifts:'), findsNothing);
    expect(find.textContaining('Verified shifts:'), findsNothing);
  });

  testWidgets('View Work Assignments uses the existing route', (tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.workers,
      routes: [
        GoRoute(
          path: AppRoutes.workers,
          builder: (_, _) => CompanyWorkersPage(repository: repository),
        ),
        GoRoute(
          path: AppRoutes.workVerification,
          builder: (_, _) =>
              const Scaffold(body: Text('Existing work assignments')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    final action = find.text('View Work Assignments').first;
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutes.workVerification,
    );
    expect(find.text('Existing work assignments'), findsOneWidget);
  });

  testWidgets('summary totals use loaded counts and stay unchanged by search', (
    tester,
  ) async {
    source.assignments = (_) async => complete([
      workerShift(20, 4, 5, 3, verified: true),
      workerShift(21, 6, 7, 8),
    ]);
    await show(tester);
    void total(String label, String expected) => expect(
      find.descendant(
        of: find.byKey(ValueKey('summary-$label')),
        matching: find.text(expected),
      ),
      findsOneWidget,
    );
    total('Hired Workers', '2');
    total('Total Assigned Shifts', '2');
    total('Verified Shifts', '1');
    final search = find.widgetWithText(TextField, 'Search workers or jobs');
    await tester.ensureVisible(search);
    await tester.enterText(search, 'Alex');
    await tester.pumpAndSettle();
    total('Hired Workers', '2');
    total('Total Assigned Shifts', '2');
    total('Verified Shifts', '1');
    expect(find.text('Blair Worker'), findsNothing);
  });

  testWidgets(
    'unavailable totals show dashes and count definitions are accessible',
    (tester) async {
      source.assignments = (_) async => throw Exception('offline');
      await show(tester);
      for (final label in ['Total Assigned Shifts', 'Verified Shifts']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('summary-$label')),
            matching: find.text('\u2014'),
          ),
          findsOneWidget,
        );
      }
      final info = find.text('About shift counts');
      await tester.ensureVisible(info);
      await tester.tap(info);
      await tester.pumpAndSettle();
      expect(find.textContaining('including cancelled shifts'), findsOneWidget);
      expect(find.textContaining('A dash means'), findsOneWidget);
    },
  );

  testWidgets('worker cards reveal all hired jobs without new reads', (
    tester,
  ) async {
    source.jobs = (_) async => complete([
      for (final (n, title) in [
        (3, 'First job'),
        (8, 'Second job'),
        (9, 'Third job'),
      ])
        {'job_id': uid(n), 'company_id': source.company, 'title': title},
    ]);
    source.applicants = (job) async => complete([
      hired(
        job == uid(3)
            ? 4
            : job == uid(8)
            ? 6
            : 10,
        5,
        'Alex Worker',
      ),
    ]);
    await show(tester);
    expect(find.text('3 hired jobs'), findsOneWidget);
    expect(find.text('First job'), findsOneWidget);
    expect(find.text('Second job'), findsOneWidget);
    expect(find.text('Third job'), findsNothing);
    final reads = source.calls.length;
      final reveal = find.text('+1 more');
    await tester.ensureVisible(reveal);
    await tester.tap(reveal);
    await tester.pumpAndSettle();
    expect(find.text('Third job'), findsOneWidget);
    await tester.tap(find.text('Show fewer jobs'));
    await tester.pumpAndSettle();
    expect(find.text('Third job'), findsNothing);
    expect(source.calls.length, reads);
  });

  testWidgets('a single worker keeps a compact desktop card', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    source.applicants = (_) async => complete([hired(4, 5, 'Alex Worker')]);
    // A single hired job keeps the directory small while the page remains wide.
    source.jobs = (_) async => complete([
      {
        'job_id': uid(3),
        'company_id': source.company,
        'title': 'Retail assistant',
      },
    ]);
    await show(tester);
    expect(tester.getSize(find.byKey(ValueKey(uid(5)))).width, lessThan(500));
    expect(find.text('View Work Assignments'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets('company worker cards fit $width with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: CompanyWorkersPage(repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alex Worker'), findsOneWidget);
      expect(find.text('Blair Worker'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
