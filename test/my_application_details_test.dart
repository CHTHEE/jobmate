import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/applications/applications_page.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/features/applications/my_application_details_page.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';

import 'fixtures/my_applications_source.dart';

void main() {
  const id = 'bc697799-463f-4251-b6be-8888551c3712';
  late TestMyApplicationsSource source;
  setUp(() {
    source = TestMyApplicationsSource()
      ..rows = [applicationRow(id)]
      ..historyRows = [historyRow('initial')];
  });
  tearDown(() => source.changes.close());

  test('Maps all seven history fields and all statuses distinctly', () {
    final initial = ApplicationHistoryEvent(historyRow('initial'));
    expect(initial.id, 'initial');
    expect(initial.previousStatus, isNull);
    expect(initial.newStatus, MyApplicationStatus.submitted);
    expect(initial.changedBy, 'seeker-a');
    expect(initial.changedByName, 'Applicant');
    expect(initial.note, isNull);
    expect(initial.changedAt, DateTime.parse('2026-11-04T10:11:37.58546Z'));
    for (final status in MyApplicationStatus.values) {
      final event = ApplicationHistoryEvent({
        ...historyRow('event', status: status.name),
        'previous_status': 'submitted',
        'note': 'Actual note',
      });
      expect(event.newStatus, status);
      expect(event.previousStatus, MyApplicationStatus.submitted);
      expect(event.note, 'Actual note');
    }
  });
  test(
    'Unknown applications never request history; no inferred events',
    () async {
      final repo = MyApplicationDetailsRepository(source, 'unowned');
      addTearDown(repo.dispose);
      await repo.load();
      expect(repo.application, isNull);
      expect(source.historyCalls, isEmpty);
      expect(repo.events, isEmpty);
    },
  );
  test('Account switch ignores previous account history and verifies new ownership', () async {
    final pending = Completer<List<Map<String, dynamic>>>();
    source.fetchHistory = (_) => pending.future;
    final repo = MyApplicationDetailsRepository(source, id);
    addTearDown(repo.dispose);
    final request = repo.load();
    await Future<void>.delayed(Duration.zero);
    expect(source.historyCalls, [id]);
    source.rows = [];
    source.switchAccount('seeker-b');
    pending.complete([historyRow('previous-account')]);
    await request;
    await Future<void>.delayed(Duration.zero);
    expect(repo.application, isNull);
    expect(repo.events, isEmpty);
    expect(source.historyCalls.length, 1);
  });
  test('Late responses after disposal cannot update detail state', () async {
    final pending = Completer<List<Map<String, dynamic>>>();
    source.fetchHistory = (_) => pending.future;
    final repo = MyApplicationDetailsRepository(source, id);
    final request = repo.load();
    await Future<void>.delayed(Duration.zero);
    repo.dispose();
    pending.complete([historyRow('late')]);
    await request;
    expect(repo.events, isEmpty);
  });

  Future<void> open(WidgetTester tester, {double scale = 1}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: JobMateTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: MyApplicationDetailsPage(applicationId: id, source: source),
        ),
      );
  for (final width in [320.0, 1440.0]) {
    testWidgets('Real details show exactly the initial event at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      source.rows = [
        {
          ...applicationRow(id),
          'cover_note': 'My submitted note',
          'resume_id': 'resume-id',
        },
      ];
      await open(tester, scale: width == 320 ? 1.6 : 1);
      await tester.pumpAndSettle();
      expect(find.text('Part-Time Cafe Crew'), findsOneWidget);
      expect(find.text('ABC Company'), findsOneWidget);
      expect(find.text('Resume attached'), findsOneWidget);
      expect(find.text('My submitted note'), findsOneWidget);
      expect(
        find
            .byType(ListTile)
            .evaluate()
            .where(
              (e) => (e.widget as ListTile).key == const ValueKey('initial'),
            )
            .length,
        1,
      );
      expect(find.text('Applied'), findsNWidgets(2));
      expect(find.text('Applicant'), findsOneWidget);
      expect(find.text('Interview'), findsNothing);
      expect(find.text('Withdraw'), findsNothing);
      expect(find.text('DEMO / PREVIEW'), findsNothing);
      expect(source.historyCalls, [id]);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('History loading, error/retry and empty states retain details', (
    tester,
  ) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    source.fetchHistory = (_) => pending.future;
    await open(tester);
    await tester.pump();
    await tester.pump();
    expect(find.text('Loading status history…'), findsOneWidget);
    pending.completeError(StateError('Network failure'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load status history'), findsOneWidget);
    expect(find.text('Part-Time Cafe Crew'), findsOneWidget);
    source.fetchHistory = (_) async => [];
    await tester.ensureVisible(find.text('Retry history'));
    await tester.tap(find.text('Retry history'));
    await tester.pumpAndSettle();
    expect(find.text('No status history available.'), findsOneWidget);
    expect(find.text('No resume attached'), findsOneWidget);
    expect(find.text('Cover note'), findsNothing);
  });
  testWidgets(
    'List-to-details, View Job return refresh and Back work with real IDs',
    (tester) async {
      final module = Module2Repository(myApplicationsSource: source);
      addTearDown(module.dispose);
      String? openedJob;
      final router = GoRouter(
        initialLocation: '/applications',
        routes: [
          GoRoute(
            path: '/applications',
            builder: (_, _) => ApplicationsPage(repository: module),
          ),
          GoRoute(
            path: '/applications/:id',
            builder: (_, state) => ApplicationDetailsPage(
              applicationId: state.pathParameters['id']!,
              repository: module,
            ),
          ),
          GoRoute(
            path: '/jobs/:id',
            builder: (context, state) {
              openedJob = state.pathParameters['id'];
              return Scaffold(
                body: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Return from job'),
                ),
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View Application'));
      await tester.tap(find.text('View Application'));
      await tester.pumpAndSettle();
      expect(
        GoRouterState.of(tester.element(find.byType(MyApplicationDetailsPage)))
            .pathParameters['id'],
        id,
      );
      await tester.ensureVisible(find.text('View Job').last);
      await tester.tap(find.text('View Job').last);
      await tester.pumpAndSettle();
      expect(openedJob, 'real-job-id');
      source.historyRows = [
        historyRow('initial'),
        {
          ...historyRow('review', status: 'shortlisted'),
          'previous_status': 'submitted',
          'changed_by_name': 'Recruiter',
          'note': 'Review complete',
          'changed_at': '2026-11-05T01:00:00Z',
        },
      ];
      source.rows = [applicationRow(id, status: 'shortlisted')];
      await tester.tap(find.text('Return from job'));
      await tester.pumpAndSettle();
      expect(find.text('Review complete'), findsOneWidget);
      expect(find.text('Recruiter'), findsOneWidget);
      expect(source.historyCalls.length, 2);
      await tester.ensureVisible(find.text('Back to Applications'));
      await tester.tap(find.text('Back to Applications'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/applications');
    },
  );
  testWidgets(
    'Direct route has safe return and logout clears visible details',
    (tester) async {
      final module = Module2Repository(myApplicationsSource: source);
      addTearDown(module.dispose);
      final router = GoRouter(
        initialLocation: '/applications/$id',
        routes: [
          GoRoute(
            path: '/applications',
            builder: (_, _) => ApplicationsPage(repository: module),
          ),
          GoRoute(
            path: '/applications/:id',
            builder: (_, state) => ApplicationDetailsPage(
              applicationId: state.pathParameters['id']!,
              repository: module,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      source.switchAccount(null);
      await tester.pumpAndSettle();
      expect(find.text('Part-Time Cafe Crew'), findsNothing);
      expect(find.text('Applicant'), findsNothing);
      await tester.tap(find.text('Back to Applications'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/applications');
    },
  );
}
