import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/work_attendance/engagement_closure_controls.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';
import 'package:jobmate/features/work_attendance/work_attendance_pages.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_routes.dart';
import 'package:jobmate/features/work_attendance/work_evidence_pages.dart';
import 'package:jobmate/features/work_attendance/work_shift_ui.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, id, other;
import 'work_assignment_creation_repository_test.dart' show uid;
import 'work_attendance_resolution_test.dart' show auditFor, resolutionContext;
import 'work_verification_grouping_test.dart' show FakeEngagementClosureGateway;

void main() {
  late FakeSource source;
  late WorkAttendanceRepository repository;

  setUp(() {
    source = FakeSource();
    repository = WorkAttendanceRepository(source);
  });

  tearDown(() async {
    repository.dispose();
    await source.changes.close();
  });

  Future<void> showPage(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(home: WorkAttendancePage(repository: repository)),
  );

  Future<GoRouter> showPageWithDetails(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.workAttendance,
      routes: [
        GoRoute(
          path: AppRoutes.workAttendance,
          builder: (_, _) => WorkAttendancePage(repository: repository),
        ),
        workAttendanceRoute(
          source: source,
          checkAccess: () async => true,
          evidence: true,
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> expand(WidgetTester tester, {Finder? group}) async {
    final toggle = find.text('Show application shifts');
    final scoped = group == null
        ? toggle
        : find.descendant(of: group, matching: toggle);
    await tester.ensureVisible(scoped);
    await tester.tap(scoped);
    await tester.pumpAndSettle();
  }

  testWidgets('shift grid keeps normal column widths after filtering', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    source.workerRead = () async => [
      for (var i = 1; i <= 4; i++)
        assignment()
          ..['assignment_id'] = uid(i)
          ..['attendance_as_of'] = i == 1
              ? '2026-11-04T00:00:00Z'
              : '2026-11-07T12:00:00Z',
    ];
    await showPage(tester);
    await tester.pumpAndSettle();
    await expand(tester);
    Rect bounds(int i) => tester.getRect(find.byKey(ValueKey(uid(i))));
    final first = bounds(1);
    final fourth = bounds(4);
    expect(bounds(3).top, first.top);
    expect(fourth.top, greaterThan(first.top));
    expect(fourth.left, first.left);
    expect(fourth.width, first.width);

    await tester.tap(find.byKey(const ValueKey('workspace-filters-toggle')));
    await tester.pumpAndSettle();
    final upcoming = find.widgetWithText(ChoiceChip, 'Upcoming');
    await tester.ensureVisible(upcoming);
    await tester.tap(upcoming);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey(uid(2))), findsNothing);
    expect(bounds(1).left, first.left);
    expect(bounds(1).width, first.width);
    expect(
      find.text('Thu, 5 Nov 2026 · 9:00 AM – 5:00 PM MYT'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('upcoming shift stays compact and opens the full audit', (
    tester,
  ) async {
    source.workerRead = () async => [
      assignment()
        ..['employment_type'] = 'full_time'
        ..['attendance_as_of'] = '2026-11-04T22:00:00Z'
        ..['workplace_latitude'] = 3.117
        ..['workplace_longitude'] = 101.677,
    ];
    final router = await showPageWithDetails(tester);
    expect(find.textContaining('Device clock'), findsNothing);
    expect(
      find.text('All times are Malaysia time (MYT, UTC+08:00).'),
      findsOneWidget,
    );
    expect(find.text('Show application shifts'), findsOneWidget);
    expect(find.text('Next upcoming shift'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('application-$other')),
        matching: find.text('Upcoming'),
      ),
      findsOneWidget,
    );
    expect(find.text('Thu, 5 Nov 2026'), findsOneWidget);
    expect(find.text('9:00 AM – 5:00 PM MYT'), findsOneWidget);
    expect(find.text('Server location'), findsOneWidget);
    await expand(tester);
    expect(find.text('Upcoming / Scheduled'), findsOneWidget);
    expect(find.text('Workplace: Server location'), findsOneWidget);
    expect(find.text('View workplace on map'), findsOneWidget);
    expect(find.textContaining('Check-in opens 60 minutes'), findsOneWidget);
    expect(
      tester
              .getTopLeft(find.widgetWithText(OutlinedButton, 'Shift details'))
              .dy -
          tester
              .getBottomLeft(find.textContaining('Check-in opens 60 minutes'))
              .dy,
      greaterThanOrEqualTo(8),
    );
    for (final label in [
      'Attendance summary',
      'Check-in: Not recorded',
      'Checkout: Not recorded',
      'View original attendance & audit',
      'Technical details',
      'View Evidence',
      'Check in',
    ]) {
      expect(find.text(label), findsNothing);
    }
    await tap(tester, 'Shift details');
    expect(
      GoRouterState.of(tester.element(find.byType(WorkEvidencePage))).uri.path,
      '${AppRoutes.workAttendance}/$id/evidence',
    );
    expect(find.text('Attendance & verification history'), findsOneWidget);
    expect(find.text('View original attendance & audit'), findsNothing);
    expect(find.text('Technical details'), findsNothing);
    await tap(tester, 'Attendance & verification history');
    expect(find.text('Assignment: $id'), findsNothing);
    expect(find.textContaining(id), findsNothing);
    expect(find.textContaining('server snapshot'), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Hide application shifts'), findsOneWidget);

    source.workerRead = () async => [
      assignment()..['attendance_as_of'] = '2026-11-05T00:30:00Z',
    ];
    await repository.loadWorkerAssignments();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide application shifts'));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Check in');
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(source.checkIns, 0);
  });

  testWidgets('cancelled shift retains recorded attendance and detail access', (
    tester,
  ) async {
    source.workerRead = () async => [
      assignment()
        ..['assignment_status'] = 'cancelled'
        ..['check_in_at'] = '2026-11-05T01:05:00Z'
        ..['attendance_as_of'] = '2026-11-05T10:00:00Z',
    ];
    await showPageWithDetails(tester);
    expect(find.text('No upcoming shifts.'), findsOneWidget);
    expect(find.text('Next upcoming shift'), findsNothing);
    await expand(tester);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('9:05 AM'), findsOneWidget);
    expect(find.text('Device-recorded · MYT'), findsOneWidget);
    expect(find.text('Not recorded'), findsOneWidget);
    expect(find.text('Check in'), findsNothing);
    expect(find.text('Check out'), findsNothing);
    await tap(tester, 'View Evidence');
    expect(find.text('Attendance & verification history'), findsNothing);
    expect(find.textContaining('Original check-in:'), findsNothing);
    expect(find.text('9:05 AM'), findsOneWidget);
    expect(find.text('Device-recorded'), findsOneWidget);
  });

  for (final (timestamp, expected) in <(String?, String?)>[
    (null, null),
    ('2026-11-05T00:30:00Z', 'On Time'),
    ('2026-11-05T01:15:00Z', 'On Time'),
    ('2026-11-05T01:15:01Z', 'Late'),
  ]) {
    testWidgets('saved check-in timing presentation: $timestamp', (
      tester,
    ) async {
      source.workerRead = () async => [
        assignment()..['check_in_at'] = timestamp,
      ];
      await showPage(tester);
      await tester.pumpAndSettle();
      await expand(tester);
      expect(
        find.byType(ShiftAttendanceSummary),
        expected == null ? findsNothing : findsOneWidget,
      );
      if (expected != null) {
        expect(find.text(expected), findsOneWidget);
        expect(find.text('Device-recorded · MYT'), findsOneWidget);
        expect(find.text('Not recorded'), findsOneWidget);
      }
      expect(source.checkIns, 0);
      expect(source.checkOuts, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 1200.0]) {
    testWidgets('application toggle sits below the preview at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      source.workerRead = () async => [
        assignment()..['attendance_as_of'] = '2026-11-04T22:00:00Z',
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: WorkAttendancePage(
            repository: repository,
            closureGateway: FakeEngagementClosureGateway(eligible: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final show = find.widgetWithText(TextButton, 'Show application shifts');
      expect(show, findsOneWidget);
      expect(find.byTooltip('Show job shifts'), findsNothing);
      expect(find.byTooltip('Hide job shifts'), findsNothing);
      expect(
        tester.getTopLeft(show).dy -
            tester.getBottomLeft(find.byType(UpcomingShiftPreview)).dy,
        greaterThanOrEqualTo(12),
      );
      const engagementTitle = 'Engagement status & closure';
      final tile = find.widgetWithText(ExpansionTile, engagementTitle);
      final expansion = tester.widget<ExpansionTile>(tile);
      expect(expansion.shape, const Border());
      expect(expansion.collapsedShape, const Border());
      expect(find.text('Engagement status: Open'), findsNothing);
      await tap(tester, engagementTitle);
      expect(find.text('Engagement status: Open'), findsOneWidget);
      expect(find.text('Not yet eligible for closure'), findsOneWidget);
      final reason = find.text(unresolvedEngagementShiftsReason);
      final requirements = find.widgetWithText(
        OutlinedButton,
        'View closure requirements',
      );
      final content = tester.getRect(find.byType(EngagementClosureControls));
      final heading = tester.getRect(tile);
      expect(content.left, closeTo(heading.left, 1));
      expect(content.right, closeTo(heading.right, 1));
      expect(tester.getTopLeft(reason).dx, closeTo(content.left, 1));
      expect(
        tester.getTopLeft(requirements).dy - tester.getBottomLeft(reason).dy,
        greaterThanOrEqualTo(12),
      );
      await tap(tester, 'View closure requirements');
      expect(find.text('Closure requirements'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: reason),
        findsOneWidget,
      );
      await tap(tester, 'Close');
      expect(show, findsOneWidget);
      expect(find.text('Shift details'), findsNothing);
      await tap(tester, 'Show application shifts');
      expect(
        find.widgetWithText(TextButton, 'Hide application shifts'),
        findsOneWidget,
      );
      expect(find.text('Shift details'), findsOneWidget);
      expect(find.text('Engagement status: Open'), findsOneWidget);
      await tap(tester, 'Hide application shifts');
      expect(show, findsOneWidget);
      expect(find.text('Shift details'), findsNothing);
      expect(find.text('Engagement status: Open'), findsOneWidget);
      await tap(tester, engagementTitle);
      expect(find.text('Engagement status: Open'), findsNothing);
      expect(requirements, findsNothing);
      expect(show, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('verified corrected Worker attendance cards fit at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final resolution = auditFor({
        'p_request_id': other,
        'p_decision': 'corrected',
        'p_reason': 'Employer correction',
        'p_check_in_at': '2026-11-05T09:32:00Z',
        'p_check_out_at': '2026-11-05T09:58:00Z',
      });
      source.workerRead = () async => [
        assignment()
          ..['scheduled_start'] = '2026-11-05T09:30:00Z'
          ..['scheduled_end'] = '2026-11-05T10:00:00Z'
          ..['attendance_as_of'] = '2026-11-07T12:00:00Z'
          ..['assignment_status'] = 'completed'
          ..['verification_status'] = 'verified'
          ..['attendance_resolution'] = resolutionContext(
            resolution: resolution,
          ),
      ];
      final router = await showPageWithDetails(tester);
      await expand(tester);
      expect(find.text('Attendance summary'), findsOneWidget);
      expect(find.text('Corrected · On Time'), findsOneWidget);
      expect(find.text('5:32 PM'), findsOneWidget);
      expect(find.text('5:58 PM'), findsOneWidget);
      expect(find.text('Employer-corrected · MYT'), findsNWidgets(2));
      expect(find.text('Duration: 26 minutes'), findsOneWidget);
      expect(
        find.text(
          'These times were corrected by the employer. Duration does not confirm approved payable time.',
        ),
        findsOneWidget,
      );
      final checkIn = tester.getRect(
        find.widgetWithText(ShiftDetailPanel, 'Check-in'),
      );
      final checkout = tester.getRect(
        find.widgetWithText(ShiftDetailPanel, 'Checkout'),
      );
      if (width == 320) {
        expect(checkout.top, greaterThan(checkIn.bottom));
      } else {
        expect(checkout.top, checkIn.top);
        expect(checkout.left, greaterThan(checkIn.right));
      }
      await tap(tester, 'View Verification Details');
      expect(find.byType(WorkEvidencePage), findsOneWidget);
      final schedule = tester.getTopLeft(find.text('Shift information'));
      final attendance = tester.getTopLeft(find.text('Recorded attendance'));
      if (width == 320) {
        expect(attendance.dy, greaterThan(schedule.dy));
      } else {
        expect(attendance.dx, greaterThan(schedule.dx));
        expect(attendance.dy, schedule.dy);
      }
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Hide application shifts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'groups by application ID and retains legacy chronology after expansion',
    (tester) async {
      const third = '33333333-3333-4333-8333-333333333333';
      final rows = [
        assignment()..['scheduled_start'] = '2026-11-07T01:00:00Z',
        assignment()
          ..['assignment_id'] = third
          ..['application_id'] = id,
        assignment()..['assignment_id'] = other,
      ];
      source.workerRead = () async => rows;
      await showPage(tester);
      await tester.pumpAndSettle();
      final group = find.byKey(const ValueKey('application-$other'));
      final separate = find.byKey(const ValueKey('application-$id'));
      expect(group, findsOneWidget);
      expect(separate, findsOneWidget);
      expect(find.text('Server job'), findsNWidgets(2));
      expect(find.text('Server company'), findsNWidgets(2));
      expect(find.text('2 shifts'), findsOneWidget);
      expect(find.text('1 shift'), findsOneWidget);
      expect(find.text('Show application shifts'), findsNWidgets(2));
      await expand(tester, group: group);
      await expand(tester, group: separate);
      final cards = find.descendant(of: group, matching: find.byType(Card));
      expect(tester.widgetList<Card>(cards).map((card) => card.key), [
        const ValueKey(other),
        const ValueKey(id),
      ]);
      expect(
        find.descendant(of: separate, matching: find.byType(Card)),
        findsOneWidget,
      );
      expect(find.text('Attendance summary'), findsNothing);
      expect(find.text('Attendance details'), findsNothing);
      // Presentation sorting must not mutate repository/server order.
      expect(repository.worker.rows.map((row) => row.assignmentId), [
        id,
        third,
        other,
      ]);
    },
  );

  testWidgets(
    'grouped shifts retain their own clock actions and evidence route',
    (tester) async {
      source.workerRead = () async => [
        assignment(),
        assignment()
          ..['assignment_id'] = other
          ..['assignment_status'] = 'active'
          ..['check_in_at'] = '2026-11-05T02:00:00Z',
      ];
      final clocked = <String>[];
      source.onCheckIn = (value) async {
        clocked.add('in:$value');
        return DateTime.utc(2026, 11, 5);
      };
      source.onCheckOut = (value) async {
        clocked.add('out:$value');
        return DateTime.utc(2026, 11, 5);
      };
      final router = GoRouter(
        initialLocation: '/work-attendance',
        routes: [
          GoRoute(
            path: '/work-attendance',
            builder: (_, _) => WorkAttendancePage(
              repository: repository,
              captureLocation: () async =>
                  const WorkAttendanceLocation.unavailable(),
            ),
          ),
          GoRoute(
            path: '/work-attendance/:assignmentId/evidence',
            builder: (_, state) => Scaffold(
              body: Text(
                'Evidence for ${state.pathParameters['assignmentId']}',
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tap(find.text('Check in'));
      await tap(find.text('Continue without GPS'));
      await tap(find.text('Check out'));
      await tap(find.text('Confirm Check-Out'));
      await tap(find.text('Continue without GPS'));
      expect(clocked, ['in:$id', 'out:$other']);
      for (final shiftId in [id, other]) {
        final card = find.byKey(ValueKey(shiftId));
        await tap(
          find.descendant(of: card, matching: find.byType(OutlinedButton)),
        );
        expect(find.text('Evidence for $shiftId'), findsOneWidget);
        router.pop();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'attendance details show missing server times without inventing GPS results',
    (tester) async {
      await showPageWithDetails(tester);
      await expand(tester);
      expect(find.text('View original attendance & audit'), findsNothing);
      await tap(tester, 'View Evidence');
      await tap(tester, 'Attendance & verification history');
      expect(find.text('View original attendance & audit'), findsNothing);
      expect(find.text('Workplace: Server location'), findsOneWidget);
      expect(find.text('Not recorded'), findsNWidgets(2));
      expect(find.text('No attendance events recorded yet.'), findsOneWidget);
      expect(find.textContaining('Original check-in:'), findsNothing);
      expect(find.text('View attendance GPS'), findsNothing);
      expect(find.textContaining('Simulated'), findsNothing);
      expect(source.checkIns, 0);
      expect(source.checkOuts, 0);
    },
  );

  testWidgets('loading, error, retry and empty state', (tester) async {
    final banner = find.text(
      'Work shifts are for Part-Time and Temporary jobs',
    );
    final empty = find.text('No work shifts scheduled yet');
    final pending = Completer<List<Map<String, dynamic>>>();
    source.workerRead = () => pending.future;
    await showPage(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(banner, findsOneWidget);
    expect(empty, findsNothing);
    expect(find.byTooltip('Refresh assignments'), findsOneWidget);
    pending.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load assignments'), findsOneWidget);
    expect(banner, findsOneWidget);
    expect(empty, findsNothing);
    expect(find.textContaining('Check your connection'), findsOneWidget);
    source.workerRead = () async => [];
    await tap(tester, 'Retry');
    expect(find.text('No work shifts scheduled yet'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(source.calls, 2);
  });

  for (final width in [320.0, 768.0, 1200.0]) {
    testWidgets('worker availability and empty schedule fit at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      source.workerRead = () async => [];
      await showPage(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('Work shifts are for Part-Time and Temporary jobs'),
        findsOneWidget,
      );
      expect(
        find.textContaining("If you're hired for a Part-Time or Temporary job"),
        findsOneWidget,
      );
      expect(find.text('No work shifts scheduled yet'), findsOneWidget);
      expect(
        find.text(
          'Your shifts will appear here once an employer schedules them for you.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'real fields, MYT rollover, nullable timestamps and evidence link',
    (tester) async {
      source.workerRead = () async => [
        assignment()
          ..['scheduled_start'] = '2026-11-05T20:30:00Z'
          ..['scheduled_end'] = '2026-11-06T05:00:00Z'
          ..['assignment_status'] = 'completed'
          ..['verification_status'] = 'verified'
          ..['check_in_at'] = '2026-11-05T20:31:00Z'
          ..['check_out_at'] = '2026-11-06T05:01:00Z'
          ..['verified_at'] = '2026-11-06T06:00:00Z',
      ];
      final router = await showPageWithDetails(tester);
      await expand(tester);
      expect(find.text('4:31 AM'), findsOneWidget);
      expect(find.text('1:01 PM'), findsOneWidget);
      expect(find.text('View original attendance & audit'), findsNothing);
      await tap(tester, 'View Verification Details');
      expect(find.text('Attendance & verification history'), findsNothing);
      expect(find.text('4:31 AM'), findsOneWidget);
      expect(find.text('1:01 PM'), findsOneWidget);
      expect(find.text('Date: Friday, 6 November 2026'), findsOneWidget);
      expect(find.text('Time: 4:30 AM – 1:00 PM MYT'), findsOneWidget);
      expect(find.textContaining(id), findsNothing);
      router.pop();
      await tester.pumpAndSettle();
      for (final text in [
        'Server job',
        'Server company',
        'Work Verified',
        '4:31 AM',
        '1:01 PM',
        'Verified at: Fri, 6 Nov 2026 2:00 PM MYT',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(
        find.textContaining('Suggested initial evidence due:'),
        findsNothing,
      );
      expect(
        find.text('Evidence has been verified; no submission is due.'),
        findsOneWidget,
      );
      expect(find.text('View details'), findsNothing);
      expect(find.text('Check In'), findsNothing);
      expect(
        find.widgetWithText(OutlinedButton, 'View Verification Details'),
        findsOneWidget,
      );
      source.workerRead = () async => [assignment()];
      await tester.tap(find.byTooltip('Refresh assignments'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Checked in:'), findsNothing);
      expect(find.textContaining('Checked out:'), findsNothing);
      expect(find.textContaining('Verified at:'), findsNothing);
    },
  );

  for (final error in [
    const AuthException('expired'),
    const PostgrestException(
      message: 'Not authorized to view assignments',
      code: 'P0001',
    ),
  ]) {
    testWidgets('safe access error: ${error.runtimeType}', (tester) async {
      source.workerRead = () async => throw error;
      await showPage(tester);
      await tester.pumpAndSettle();
      expect(
        find.text(
          error is AuthException
              ? 'Sign in required'
              : 'Attendance access denied',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Server job'), findsNothing);
    });
  }

  testWidgets(
    'account change clears content, reloads and ignores stale result',
    (tester) async {
      await showPage(tester);
      await tester.pumpAndSettle();
      expect(find.text('Server job'), findsOneWidget);
      final old = Completer<List<Map<String, dynamic>>>();
      source.workerRead = () => old.future;
      await tester.tap(find.byTooltip('Refresh assignments'));
      await tester.pump();
      source.workerRead = () async => [];
      source.switchAccount(other);
      await tester.pumpAndSettle();
      expect(find.text('Server job'), findsNothing);
      expect(find.text('No work shifts scheduled yet'), findsOneWidget);
      old.complete([assignment()]);
      await tester.pumpAndSettle();
      expect(find.text('Server job'), findsNothing);
      source.switchAccount(null);
      await tester.pumpAndSettle();
      expect(find.text('Sign in required'), findsOneWidget);
      expect(find.text('Server company'), findsNothing);
    },
  );

  testWidgets(
    'caller owns injected repository; replacement detaches old listener',
    (tester) async {
      await showPage(tester);
      await tester.pumpAndSettle();
      final replacementSource = FakeSource()..workerRead = (() async => []);
      final replacement = WorkAttendanceRepository(replacementSource);
      await tester.pumpWidget(
        MaterialApp(home: WorkAttendancePage(repository: replacement)),
      );
      await tester.pumpAndSettle();
      expect(find.text('No work shifts scheduled yet'), findsOneWidget);
      source.switchAccount(other);
      await tester.pumpAndSettle();
      expect(replacementSource.calls, 1);
      await tester.pumpWidget(const SizedBox());
      await replacement.loadWorkerAssignments();
      expect(replacementSource.calls, 2);
      replacement.dispose();
      await replacementSource.changes.close();
    },
  );

  for (final width in [320.0, 840.0, 1440.0]) {
    testWidgets('layout at $width with large text and long content', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      source.workerRead = () async => [
        assignment()
          ..['job_title'] = List.filled(12, 'Long job title').join(' ')
          ..['company_name'] = List.filled(12, 'Long company name').join(' ')
          ..['workplace_location'] = List.filled(
            12,
            'Long workplace location',
          ).join(' ')
          ..['verification_status'] = 'more_evidence_required',
      ];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(width == 320 ? 2 : 1.6)),
            child: child!,
          ),
          home: WorkAttendancePage(repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Verification: More evidence required'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
