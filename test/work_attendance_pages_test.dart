import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';
import 'package:jobmate/features/work_attendance/work_attendance_pages.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, id, other;

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

  testWidgets(
    'groups by application ID with all shifts expanded and chronological',
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
      final cards = find.descendant(of: group, matching: find.byType(Card));
      expect(tester.widgetList<Card>(cards).map((card) => card.key), [
        const ValueKey(other),
        const ValueKey(id),
      ]);
      expect(
        find.descendant(of: separate, matching: find.byType(Card)),
        findsOneWidget,
      );
      expect(find.text('Attendance details'), findsNWidgets(3));
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
      await showPage(tester);
      await tester.pumpAndSettle();
      expect(find.text('Attendance details'), findsOneWidget);
      expect(find.text('Workplace: Server location'), findsOneWidget);
      expect(find.text('Check-in not recorded'), findsOneWidget);
      expect(find.text('Check-out not recorded'), findsOneWidget);
      expect(
        find.text('GPS status: Not included in shift summary'),
        findsOneWidget,
      );
      expect(find.textContaining('Simulated'), findsNothing);
      expect(source.checkIns, 0);
      expect(source.checkOuts, 0);
    },
  );

  testWidgets('loading, error, retry and empty state', (tester) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    source.workerRead = () => pending.future;
    await showPage(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Refresh assignments'), findsOneWidget);
    pending.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load assignments'), findsOneWidget);
    expect(find.textContaining('Check your connection'), findsOneWidget);
    source.workerRead = () async => [];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No work assignments'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(source.calls, 2);
  });

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
      await showPage(tester);
      await tester.pumpAndSettle();
      for (final text in [
        'Server job',
        'Server company',
        'Scheduled start: 06/11/2026 04:30 MYT',
        'Scheduled end: 06/11/2026 13:00 MYT',
        'Completed / Verified',
        'Work verified successfully',
        'Checked in: 06/11/2026 04:31 MYT',
        'Checked out: 06/11/2026 13:01 MYT',
        'Verified at: 06/11/2026 14:00 MYT',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
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
      expect(find.text('No work assignments'), findsOneWidget);
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
      expect(find.text('No work assignments'), findsOneWidget);
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
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: WorkAttendancePage(repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('More Evidence Required'), findsOneWidget);
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
