import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_pages.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_routes.dart';
import 'package:jobmate/features/work_attendance/work_verification_pages.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';

import 'work_attendance_lifecycle_test.dart' show lifecycleRow;
import 'work_attendance_repository_test.dart' show FakeSource, id, other;
import 'work_attendance_resolution_test.dart' show resolutionContext;
import 'work_attendance_resolution_test.dart' show ResolutionSource;
import 'work_attendance_resolution_test.dart' show auditFor;

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

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  for (final status in ['scheduled', 'cancelled', 'disputed']) {
    testWidgets('history missing timestamps use actual lifecycle $status', (
      tester,
    ) async {
      source.workerRead = () async => [lifecycleRow(status: status)];
      await tester.pumpWidget(
        MaterialApp(
          home: WorkAttendancePage(repository: repository, history: true),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('View original attendance & audit'));
      expect(find.text('Check-in: Not recorded'), findsOneWidget);
      expect(find.text('Checkout: Not recorded'), findsOneWidget);
      expect(
        find.text('Attendance resolution: Pending employer review'),
        status == 'scheduled' ? findsOneWidget : findsNothing,
      );
      expect(find.text('Check in'), findsNothing);
      expect(find.text('Check out'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final corrected in [false, true]) {
    testWidgets(
      'history retains actual resolution instead of pending review corrected=$corrected',
      (tester) async {
        final audit = auditFor({
          'p_request_id': other,
          'p_decision': corrected ? 'corrected' : 'confirmed_absent',
          'p_reason': 'Reviewed actual resolution',
          'p_check_in_at': corrected ? '2026-11-05T01:10:00Z' : null,
          'p_check_out_at': corrected ? '2026-11-05T08:00:00Z' : null,
        });
        source.workerRead = () async => [
          lifecycleRow(
            status: corrected ? 'awaiting_verification' : 'scheduled',
          )..['attendance_resolution'] = resolutionContext(resolution: audit),
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: WorkAttendancePage(repository: repository, history: true),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, find.text('View original attendance & audit'));
        expect(
          find.text('Attendance resolution: Pending employer review'),
          findsNothing,
        );
        expect(
          find.text('Resolution reason: Reviewed actual resolution'),
          findsOneWidget,
        );
        expect(
          find.text(corrected ? 'Corrected Attendance' : 'Confirmed Absent'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('missed shift has distinct summary and full record labels', (
    tester,
  ) async {
    source.workerRead = () async => [lifecycleRow()];
    await tester.pumpWidget(
      MaterialApp(home: WorkAttendancePage(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Attendance summary'), findsOneWidget);
    expect(find.text('View Full Record'), findsOneWidget);
    expect(find.text('Show attendance details'), findsNothing);
    expect(find.text('View attendance details'), findsNothing);
  });

  List<Map<String, dynamic>> rows({bool company = false}) => [
    lifecycleRow(company: company)..['job_title'] = 'Missed job',
    lifecycleRow(
        company: company,
        status: 'awaiting_verification',
        input: '2026-11-05T01:00:00Z',
        output: '2026-11-05T08:00:00Z',
      )
      ..['assignment_id'] = other
      ..['job_title'] = 'Recorded job',
  ];

  testWidgets(
    'collapsed worker group keeps overdue checkout and evidence actions visible',
    (tester) async {
      source.workerRead = () async => [
        lifecycleRow(
          status: 'active',
          input: '2026-11-05T01:00:00Z',
          now: '2026-11-05T10:00:00Z',
        ),
        lifecycleRow(
          status: 'awaiting_verification',
          input: '2026-11-05T01:00:00Z',
          output: '2026-11-05T08:00:00Z',
        )..['assignment_id'] = other,
      ];
      await tester.pumpWidget(
        MaterialApp(home: WorkAttendancePage(repository: repository)),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Hide job shifts'));
      expect(
        find.text('Shifts needing action remain visible below.'),
        findsOneWidget,
      );
      expect(find.text('Check out'), findsOneWidget);
      expect(find.text('Submit Evidence'), findsOneWidget);
      expect(source.checkOuts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real history filters no-row missed shifts, recorded attendance and Details route',
    (tester) async {
      source.workerRead = () async => rows();
      final router = GoRouter(
        initialLocation: AppRoutes.attendanceHistory,
        routes: [
          workAttendanceRoute(
            source: source,
            history: true,
            checkAccess: () async => true,
          ),
          GoRoute(
            path: '${AppRoutes.workAttendance}/:assignmentId/evidence',
            builder: (_, state) => Scaffold(
              body: Text(
                'Authorized details ${state.pathParameters['assignmentId']}',
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('Missed Attendance'), findsOneWidget);
      expect(find.text('Attendance Recorded'), findsOneWidget);
      expect(find.text('Check in'), findsNothing);
      expect(find.text('Check out'), findsNothing);
      expect(find.text('Request engagement closure'), findsNothing);
      expect(find.text('Submit Evidence'), findsNothing);
      await tap(tester, find.widgetWithText(ChoiceChip, 'Issues'));
      expect(find.byKey(const ValueKey(id)), findsOneWidget);
      expect(find.byKey(const ValueKey(other)), findsNothing);
      await tap(tester, find.widgetWithText(ChoiceChip, 'Recorded'));
      expect(find.byKey(const ValueKey(id)), findsNothing);
      expect(find.byKey(const ValueKey(other)), findsOneWidget);
      await tap(tester, find.text('Details'));
      expect(find.text('Authorized details $other'), findsOneWidget);
      expect(source.checkIns, 0);
      expect(source.checkOuts, 0);
    },
  );

  for (final after in [false, true]) {
    testWidgets(
      'ordinary checkout recovery is inclusive at end+24h (after=$after)',
      (tester) async {
        source.workerRead = () async => [
          lifecycleRow(
            status: 'active',
            input: '2026-11-05T01:00:00Z',
            now: after ? '2026-11-06T09:00:00.000001Z' : '2026-11-06T09:00:00Z',
          )..['attendance_resolution'] = resolutionContext(),
        ];
        await tester.pumpWidget(
          MaterialApp(home: WorkAttendancePage(repository: repository)),
        );
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(FilledButton, 'Check out'),
          after ? findsNothing : findsOneWidget,
        );
        expect(source.checkOuts, 0);
      },
    );
  }

  testWidgets(
    'real review capability resolves only selected shift and refreshes issue count',
    (tester) async {
      final gateway = ResolutionSource();
      addTearDown(gateway.changes.close);
      final sibling = lifecycleRow(company: true)..['assignment_id'] = other;
      final originalSibling = Map.of(sibling);
      source.companyRead = (_) async => [
        lifecycleRow(company: true, now: '2026-11-07T10:00:00Z')
          ..['attendance_resolution'] = gateway.context,
        sibling,
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: WorkVerificationPage(
            repository: repository,
            companyId: id,
            loadAccess: () async => const JobAccess({'company_id': id}, null),
            resolutionSource: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final target = find.byKey(const ValueKey(id));
      expect(
        find.descendant(of: target, matching: find.text('Scheduled')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: target,
          matching: find.textContaining('Contact the employer'),
        ),
        findsNothing,
      );
      await tap(tester, find.text('Review Attendance'));
      await tap(tester, find.byType(DropdownButtonFormField<String>).last);
      await tap(tester, find.text('Confirm absence').last);
      await tester.enterText(
        find.byType(TextFormField),
        'Confirmed absence after employer review',
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Review decision'));
      await tap(tester, find.text('Confirm absence'));
      await tap(tester, find.text('Done'));
      expect(gateway.writes, hasLength(1));
      expect(gateway.writes.single['p_assignment_id'], id);
      expect(sibling, originalSibling);
      expect(find.text('Confirmed Absent'), findsOneWidget);
      expect(find.text('Review Attendance'), findsNothing);
      final issues = find.byKey(const ValueKey('overview-Attendance issues'));
      expect(
        find.descendant(of: issues, matching: find.text('1')),
        findsOneWidget,
      );
      await tap(tester, issues);
      expect(find.byKey(const ValueKey(id)), findsNothing);
      expect(find.byKey(const ValueKey(other)), findsOneWidget);
    },
  );

  testWidgets(
    'overdue and incomplete retain ordinary checkout; missed disables check-in',
    (tester) async {
      source.workerRead = () async => [
        lifecycleRow(),
        lifecycleRow(
          now: '2026-11-07T09:00:00Z',
          status: 'active',
          input: '2026-11-05T01:00:00Z',
        )..['assignment_id'] = other,
      ];
      await tester.pumpWidget(
        MaterialApp(home: WorkAttendancePage(repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Incomplete Attendance'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Check in'), findsNothing);
      final checkOut = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Check out'),
      );
      expect(checkOut.onPressed, isNotNull);
      expect(source.checkOuts, 0);
      source.workerRead = () async => [];
      source.switchAccount(other);
      await tester.pumpAndSettle();
      expect(find.text('Incomplete Attendance'), findsNothing);
      expect(find.text('Missed Attendance'), findsNothing);
    },
  );

  testWidgets(
    'employer issues filter only matches individual shifts and keeps expansion across refresh',
    (tester) async {
      source.companyRead = (_) async => rows(company: true);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkVerificationPage(
            repository: repository,
            companyId: id,
            loadAccess: () async => const JobAccess({'company_id': id}, null),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('overview-Attendance issues')),
        findsOneWidget,
      );
      final dropdown = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Shift status',
      );
      await tap(tester, dropdown);
      await tap(tester, find.text('Attendance Issues').last);
      expect(find.byKey(const ValueKey(id)), findsOneWidget);
      expect(find.byKey(const ValueKey(other)), findsNothing);
      expect(find.text('1 matching of 2 shifts'), findsOneWidget);
      await tap(tester, find.byTooltip('Show shift details'));
      expect(find.byTooltip('Hide shift details'), findsOneWidget);
      await tap(tester, find.byTooltip('Refresh company assignments'));
      expect(find.byTooltip('Hide shift details'), findsOneWidget);
      await tap(tester, find.text('Hide application shifts'));
      expect(find.byTooltip('Hide shift details'), findsNothing);
      await tap(tester, find.text('Show application shifts'));
      expect(find.byTooltip('Hide shift details'), findsOneWidget);
      expect(source.checkIns, 0);
      expect(source.checkOuts, 0);
    },
  );

  for (final history in [false, true]) {
    testWidgets(
      'lifecycle worker view history=$history fits 320px at 1.6 text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        source.workerRead = () async => rows();
        await tester.pumpWidget(
          MaterialApp(
            builder: (_, child) => MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: child!,
            ),
            home: WorkAttendancePage(repository: repository, history: history),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.text(history ? 'Details' : 'Submit Evidence').first,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'missed shift has structured truthful empty states and only one warning',
    (tester) async {
      source.companyRead = (_) async => [lifecycleRow(company: true)];
      await tester.pumpWidget(
        MaterialApp(
          home: WorkVerificationPage(
            repository: repository,
            companyId: id,
            loadAccess: () async => const JobAccess({'company_id': id}, null),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Show shift details'));
      for (final label in [
        'Scheduled',
        'Check-in',
        'Check-out',
        'Evidence',
        'Workplace & GPS',
        'Work Evidence',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Not recorded'), findsNWidgets(2));
      expect(
        find.textContaining(
          'No attendance was recorded before this shift ended.',
        ),
        findsOneWidget,
      );
      expect(find.text('No device attendance recorded.'), findsOneWidget);
      expect(
        find.text('No evidence has been submitted for this shift.'),
        findsOneWidget,
      );
      expect(find.text('Review Attendance'), findsNothing);
      expect(source.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final corrected in [false, true]) {
    testWidgets(
      'resolved employer card preserves audit and original times at 320px (corrected=$corrected)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final audit = auditFor({
          'p_request_id': other,
          'p_decision': corrected ? 'corrected' : 'confirmed_absent',
          'p_reason': 'Actual employer resolution reason',
          'p_check_in_at': corrected ? '2026-11-05T01:10:00Z' : null,
          'p_check_out_at': corrected ? '2026-11-05T08:00:00Z' : null,
        });
        source.companyRead = (_) async => [
          lifecycleRow(
            company: true,
            now: '2026-11-07T10:00:00Z',
            status: corrected ? 'awaiting_verification' : 'scheduled',
            input: corrected ? '2026-11-05T01:00:00Z' : null,
          )..['attendance_resolution'] = resolutionContext(resolution: audit),
        ];
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.6)),
              child: child!,
            ),
            home: WorkVerificationPage(
              repository: repository,
              companyId: id,
              loadAccess: () async => const JobAccess({'company_id': id}, null),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, find.byTooltip('Show shift details'));
        expect(
          find.text(corrected ? 'Corrected Attendance' : 'Confirmed Absent'),
          findsOneWidget,
        );
        await tap(tester, find.text('View original attendance & audit'));
        expect(
          find.text('Resolution reason: Actual employer resolution reason'),
          findsOneWidget,
        );
        expect(find.text('Review Attendance'), findsNothing);
        if (corrected) {
          expect(
            find.text('Original check-in: 05/11/2026 09:00:00 MYT'),
            findsOneWidget,
          );
          expect(find.text('Original checkout: Not recorded'), findsOneWidget);
          expect(find.textContaining('Corrected duration:'), findsOneWidget);
        }
        if (corrected) {
          await tester.ensureVisible(find.text('View attendance GPS'));
        } else {
          expect(find.text('View attendance GPS'), findsNothing);
          expect(find.text('View Full Record'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        expect(source.checkIns, 0);
        expect(source.checkOuts, 0);
      },
    );
  }

  testWidgets(
    'employer lifecycle details and existing actions fit 320px enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      source.companyRead = (_) async => rows(company: true);
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: WorkVerificationPage(
            repository: repository,
            companyId: id,
            loadAccess: () async => const JobAccess({'company_id': id}, null),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Show shift details').first);
      await tester.ensureVisible(find.text('View attendance GPS').first);
      expect(tester.takeException(), isNull);
      expect(find.text('Review Attendance'), findsNothing);
    },
  );
}
