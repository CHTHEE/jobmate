import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/applications/applications_page.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/features/applications/my_application_details_page.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';
import 'package:jobmate/features/chat/chat_application_button.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';

import 'fixtures/my_applications_source.dart';

void main() {
  _polishedDetailsTests();
  const id = 'bc697799-463f-4251-b6be-8888551c3712';
  late TestMyApplicationsSource source;
  setUp(() {
    source = TestMyApplicationsSource()
      ..rows = [applicationRow(id)]
      ..historyRows = [historyRow('initial')];
  });
  tearDown(() => source.changes.close());
  final back = kIsWeb
      ? find.text('Back to Applications')
      : find.byTooltip('Back to Applications');

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
  for (final width in [
    320.0,
    360.0,
    390.0,
    430.0,
    568.0,
    600.0,
    768.0,
    840.0,
    1024.0,
    1280.0,
    1440.0,
    1920.0,
  ]) {
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
      final initialEvent = find.byKey(const ValueKey('initial'));
      expect(initialEvent, findsOneWidget);
      expect(
        find.descendant(of: initialEvent, matching: find.text('Applied')),
        findsOneWidget,
      );
      expect(find.text('Applied'), findsNWidgets(2));
      expect(find.text('Applicant'), findsOneWidget);
      expect(find.text('Interview'), findsNothing);
      expect(find.text('Withdraw'), findsNothing);
      expect(find.text('DEMO / PREVIEW'), findsNothing);
      expect(find.textContaining(id), findsNothing);
      expect(
        find.textContaining('application reference', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('Application ID'), findsNothing);
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

  for (final (min, max, period, amount, periodLabel) in [
    ('1200', '1800', 'hourly', 'RM 12.00 – 18.00', 'Per hour'),
    (
      '9223372036854775807',
      '9223372036854775807',
      'daily',
      'RM 92233720368547758.07',
      'Per day',
    ),
    (null, '20000', 'daily', 'Up to RM 200.00', 'Per day'),
    ('1200', null, 'hourly', 'From RM 12.00', 'Per hour'),
  ]) {
    testWidgets('Shows recorded offer $amount and prioritizes actions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      source.rows = [applicationRow(id, status: 'offered')];
      source.offer = {
        'offer_id': '00000000-0000-4000-8000-000000000001',
        'application_id': id,
        'offer_version': 3,
        'employment_type': 'part_time',
        'salary_period': period,
        'salary_min_sen': min,
        'salary_max_sen': max,
        'currency': 'MYR',
        'issued_by': '00000000-0000-4000-8000-000000000003',
        'issued_at': '2026-11-04T10:11:37.58546Z',
        'payment_basis_supported': true,
        'is_current': true,
        'is_accepted': false,
      };
      const actor = 'Northern Regional Hospitality Recruitment Coordinator';
      source.historyRows = [
        historyRow('initial'),
        historyRow('earlier', status: 'offered'),
        {...historyRow('latest', status: 'offered'), 'changed_by_name': actor},
      ];
      await open(tester, scale: 2);
      await tester.pumpAndSettle();
      for (final label in [
        amount,
        periodLabel,
        'Offer version',
        'Version 3',
        'Issued on',
        actor,
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.textContaining('58546'), findsNothing);
      final latest = find.byKey(const ValueKey('latest'));
      expect(
        find.descendant(of: latest, matching: find.text('Latest')),
        findsOneWidget,
      );
      expect(find.text('Latest'), findsOneWidget);
      final accept = find.widgetWithText(FilledButton, 'Accept Offer');
      expect(tester.widget<FilledButton>(accept).onPressed, isNotNull);
      expect(
        find.widgetWithText(OutlinedButton, 'Decline Offer'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(accept).dy,
        lessThan(tester.getTopLeft(find.text('Application timeline')).dy),
      );
      expect(tester.takeException(), isNull);
      if (period == 'hourly' && max != null) {
        source.sendOfferAcceptance = (_, _, _) async {
          source.rows = [applicationRow(id, status: 'hired')];
        };
        await tester.ensureVisible(accept);
        await tester.tap(accept);
        await tester.pumpAndSettle();
        expect(source.offerAcceptances, isEmpty);
        await tester.tap(find.text('Confirm Accept Offer'));
        await tester.pumpAndSettle();
        expect(source.offerAcceptances, [
          (id, '00000000-0000-4000-8000-000000000001', 3),
        ]);
        expect(find.text("You've been hired!"), findsOneWidget);
      }
    });
  }

  testWidgets('Hired details prioritize messaging and explain restrictions', (
    tester,
  ) async {
    source.rows = [applicationRow(id, status: 'hired')];
    await open(tester);
    await tester.pumpAndSettle();
    expect(find.text("You've been hired!"), findsOneWidget);
    expect(find.textContaining('any assigned shifts'), findsOneWidget);
    expect(find.textContaining('Ending a hired arrangement'), findsOneWidget);
    expect(find.textContaining('legacy offer'), findsOneWidget);
    expect(find.text('Compensation offer'), findsNothing);
    final message = find.widgetWithText(FilledButton, 'Message Employer');
    final job = find.widgetWithText(OutlinedButton, 'View Job');
    expect(tester.getSize(message).width, tester.getSize(job).width);
    expect(tester.getTopLeft(message).dy, lessThan(tester.getTopLeft(job).dy));
    expect(
      tester
          .widget<ChatApplicationButton>(find.byType(ChatApplicationButton))
          .applicationId,
      id,
    );
    for (final action in ApplicationResponseAction.values) {
      expect(find.text(action.label), findsNothing);
    }
  });

  testWidgets(
    'Application details show loading, retry and unavailable states',
    (tester) async {
      final pending = Completer<List<Map<String, dynamic>>>();
      source.fetch = () => pending.future;
      await open(tester);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Application unavailable'), findsNothing);
      pending.completeError(StateError('Unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('Unable to load application'), findsOneWidget);
      source.fetch = () async => [];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Application unavailable'), findsOneWidget);
      expect(source.historyCalls, isEmpty);
    },
  );
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
      await tester.ensureVisible(back);
      await tester.tap(back);
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
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/applications');
    },
  );
}

const applicationId = '12345678-abcd-0123-abcd-123456789abc';

void _polishedDetailsTests() {
  for (final width in [320.0, 768.0, 1200.0]) {
    testWidgets('offered summary and history fit at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1050);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final source = TestMyApplicationsSource()
        ..rows = [
          {
            ...applicationRow(applicationId, status: 'offered'),
            'job_title':
                'Senior Customer Service and Front of House Coordinator',
            'resume_id': 'resume',
          },
        ]
        ..historyRows = [
          historyRow('applied'),
          historyRow('shortlisted', status: 'shortlisted'),
          {
            ...historyRow('offered', status: 'offered'),
            'changed_by_name': 'Hiring Manager',
            'note': 'Please review the offer.',
          },
        ];
      addTearDown(source.changes.close);
      await tester.pumpWidget(
        MaterialApp(
          home: MyApplicationDetailsPage(
            applicationId: applicationId,
            source: source,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Accept Offer'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Decline Offer'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, 'Withdraw Application'),
        findsOneWidget,
      );
      expect(find.byType(ChatApplicationButton), findsOneWidget);
      expect(find.text('Resume attached'), findsOneWidget);
      expect(
        find.text(MyApplicationStatus.offered.lifecycleExplanation!),
        findsOneWidget,
      );
      final first = find.byKey(const ValueKey('applied'));
      final last = find.byKey(const ValueKey('offered'));
      expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(last).dy));
      expect(find.text('Hiring Manager'), findsOneWidget);
      expect(find.text('Please review the offer.'), findsOneWidget);
      expect(find.textContaining(applicationId), findsNothing);
      expect(find.text('Application reference'), findsNothing);
      expect(find.textContaining('Application ID:'), findsNothing);
      expect(find.text('Copy ID'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'View Job returns to application and acceptance uses existing transition',
    (tester) async {
      final source = TestMyApplicationsSource()
        ..rows = [applicationRow(applicationId, status: 'offered')];
      source.sendResponse = (_, _) async {
        source.rows = [applicationRow(applicationId, status: 'hired')];
        return 'hired';
      };
      addTearDown(source.changes.close);
      final router = GoRouter(
        initialLocation: '/applications/$applicationId',
        routes: [
          GoRoute(
            path: '/applications',
            builder: (_, _) => const Text('Applications destination'),
          ),
          GoRoute(
            path: '/applications/:id',
            builder: (_, _) => MyApplicationDetailsPage(
              applicationId: applicationId,
              source: source,
            ),
          ),
          GoRoute(
            path: '/jobs/:jobId',
            builder: (_, state) =>
                Scaffold(body: Text('Job ${state.pathParameters['jobId']}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View Job'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View Job'));
      await tester.pumpAndSettle();
      expect(find.text('Job real-job-id'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept Offer'));
      await tester.pumpAndSettle();
      expect(source.responses, isEmpty);
      await tester.tap(find.text('Confirm Accept Offer'));
      await tester.pumpAndSettle();
      expect(source.responses.single, (applicationId, 'accept_offer'));
      expect(find.text('Hired'), findsOneWidget);
      for (final label in [
        'Accept Offer',
        'Decline Offer',
        'Withdraw Application',
      ]) {
        expect(find.text(label), findsNothing);
      }
      await tester.tap(
        (kIsWeb
            ? find.text('Back to Applications')
            : find.byTooltip('Back to Applications')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Applications destination'), findsOneWidget);
    },
  );
}
