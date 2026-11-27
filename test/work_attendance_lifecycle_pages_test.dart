import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_pages.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_routes.dart';
import 'package:jobmate/features/work_attendance/work_verification_pages.dart';
import 'package:jobmate/features/work_attendance/work_shift_ui.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:jobmate/shared/widgets/responsive_layout.dart';

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
      source.workerRead = () async => [
        lifecycleRow(status: status)
          ..['workplace_latitude'] = status == 'cancelled' ? 3.117777 : null
          ..['workplace_longitude'] = status == 'cancelled' ? 101.677777 : null,
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: WorkAttendancePage(repository: repository, history: true),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Show attendance records'));
      expect(
        find.text('View workplace on map'),
        status == 'cancelled' ? findsOneWidget : findsNothing,
      );
      for (final label in ['Check-in', 'Checkout']) {
        expect(
          find.descendant(
            of: find.widgetWithText(ShiftDetailPanel, label),
            matching: find.text('Not recorded'),
          ),
          findsOneWidget,
        );
      }
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
        await tap(tester, find.text('Show attendance records'));
        expect(
          find.text('Attendance resolution: Pending employer review'),
          findsNothing,
        );
        expect(find.text('Reviewed actual resolution'), findsOneWidget);
        if (!corrected) {
          expect(
            find.textContaining('No evidence submission is required'),
            findsOneWidget,
          );
          expect(find.text('Submit Evidence'), findsNothing);
        }
        expect(
          find.text(corrected ? 'Corrected Attendance' : 'Confirmed Absent'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('missed shift keeps guidance and a full record action', (
    tester,
  ) async {
    source.workerRead = () async => [
      lifecycleRow()
        ..['workplace_latitude'] = 3.117777
        ..['workplace_longitude'] = 101.677777,
    ];
    await tester.pumpWidget(
      MaterialApp(home: WorkAttendancePage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tap(tester, find.text('Show application shifts'));
    expect(find.text('Missed Attendance'), findsOneWidget);
    expect(find.text('Attendance summary'), findsNothing);
    expect(find.text('View original attendance & audit'), findsNothing);
    expect(find.text('View workplace on map'), findsOneWidget);
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
      expect(find.text('Show application shifts'), findsOneWidget);
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

  for (final employer in [false, true]) {
    testWidgets(
      'application priorities and refresh are independent for employer=$employer',
      (tester) async {
        const secondApplication = '33333333-3333-4333-8333-333333333333';
        final ids = List.generate(
          7,
          (index) => '44444444-4444-4444-8444-44444444444${index + 1}',
        );
        Map<String, dynamic> shift(
          int index,
          int day, {
          String status = 'scheduled',
          String verification = 'not_submitted',
          String? input,
          String? output,
        }) {
          final date = '2026-11-${day.toString().padLeft(2, '0')}';
          return lifecycleRow(
            company: employer,
            now: '2026-11-06T10:00:00Z',
            status: status,
            verification: verification,
            input: input,
            output: output,
          )..addAll({
            'assignment_id': ids[index],
            'scheduled_start': '${date}T01:00:00Z',
            'scheduled_end': '${date}T09:00:00Z',
          });
        }

        final rows = [
          shift(0, 3),
          shift(1, 9),
          shift(2, 8),
          shift(3, 5, status: 'cancelled'),
          shift(
            4,
            4,
            status: 'awaiting_verification',
            verification: employer ? 'pending_review' : 'not_submitted',
            input: '2026-11-04T01:00:00Z',
            output: '2026-11-04T09:00:00Z',
          ),
          shift(5, 8),
          shift(6, 10)..['application_id'] = secondApplication,
        ];
        source.workerRead = () async => rows;
        source.companyRead = (_) async => rows;
        final page = MaterialApp(
          home: employer
              ? WorkVerificationPage(
                  repository: repository,
                  companyId: id,
                  loadAccess: () async =>
                      const JobAccess({'company_id': id}, null),
                )
              : WorkAttendancePage(repository: repository),
        );
        await tester.pumpWidget(page);
        await tester.pumpAndSettle();
        final toggle = find.text('Show application shifts');
        expect(toggle, findsNWidgets(2));
        expect(find.byKey(ValueKey(ids[2])), findsNothing);
        expect(find.text('Sun, 8 Nov 2026'), findsOneWidget);
        expect(find.text('Next upcoming shift'), findsNWidgets(2));
        if (!employer) {
          expect(find.byKey(ValueKey(ids[4])), findsOneWidget);
        }
        await tap(tester, toggle.first);
        expect(toggle, findsOneWidget);
        expect(find.text('Next upcoming shift'), findsOneWidget);
        expect(find.byKey(ValueKey(ids[6])), findsNothing);
        final shiftWidgets = find.byWidgetPredicate(
          (widget) => ids.any((id) => widget.key == ValueKey(id)),
        );
        List<Key?> displayedOrder() => tester
            .widgetList(shiftWidgets)
            .map((widget) => widget.key)
            .toList();
        final expected = [4, 2, 5, 1, 3, 0].map((i) => ValueKey(ids[i]));
        expect(displayedOrder(), expected);
        if (employer) {
          await repository.loadCompanyAssignments(id);
        } else {
          await repository.loadWorkerAssignments();
        }
        await tester.pumpAndSettle();
        expect(displayedOrder(), expected);
        expect(toggle, findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(page);
        await tester.pumpAndSettle();
        expect(toggle, findsNWidgets(2));
      },
    );
  }

  testWidgets(
    'real history filters no-row missed shifts, recorded attendance and Details route',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      expect(find.text('Recorded attendance'), findsNothing);
      await tap(tester, find.text('Show attendance records'));
      expect(find.text('Missed Attendance'), findsOneWidget);
      expect(find.text('Attendance Recorded'), findsOneWidget);
      expect(find.text('Recorded attendance'), findsNWidgets(2));
      expect(find.textContaining('Scheduled: '), findsNWidgets(2));
      expect(find.text('Effective duration: 7 hours'), findsOneWidget);
      expect(
        find.textContaining('does not establish approved payable time'),
        findsOneWidget,
      );
      expect(find.textContaining('Recorded duration:'), findsNothing);
      expect(find.text('Original attendance records'), findsNothing);
      expect(find.textContaining('Original check-in:'), findsNothing);
      expect(find.text('9:00 AM'), findsOneWidget);
      expect(find.text('4:00 PM'), findsOneWidget);
      expect(find.text('Check in'), findsNothing);
      expect(find.text('Check out'), findsNothing);
      expect(find.text('Request engagement closure'), findsNothing);
      expect(find.text('Submit Evidence'), findsNothing);
      final recordedCard = find.byKey(const ValueKey(other));
      final width = tester.getSize(recordedCard).width;
      await tap(tester, find.byKey(const ValueKey('workspace-filters-toggle')));
      await tap(tester, find.widgetWithText(ChoiceChip, 'Issues'));
      expect(find.byKey(const ValueKey(id)), findsOneWidget);
      expect(find.byKey(const ValueKey(other)), findsNothing);
      await tap(tester, find.widgetWithText(ChoiceChip, 'Recorded'));
      expect(find.byKey(const ValueKey(id)), findsNothing);
      expect(find.byKey(const ValueKey(other)), findsOneWidget);
      expect(tester.getSize(recordedCard).width, greaterThan(width));
      await tap(tester, find.text('Details'));
      expect(find.text('Authorized details $other'), findsOneWidget);
      expect(source.checkIns, 0);
      expect(source.checkOuts, 0);
    },
  );

  testWidgets(
    'history groups expand independently across filters and refresh',
    (tester) async {
      final records = rows();
      records.last
        ..['application_id'] = id
        ..['company_name'] = 'Harbour Coffee';
      source.workerRead = () async => records;
      await tester.pumpWidget(
        MaterialApp(
          home: WorkAttendancePage(repository: repository, history: true),
        ),
      );
      await tester.pumpAndSettle();
      final show = find.text('Show attendance records');
      final hide = find.text('Hide attendance records');
      final missed = find.byKey(const ValueKey(id));
      final recorded = find.byKey(const ValueKey(other));
      expect(show, findsNWidgets(2));
      expect(find.text('Missed job'), findsOneWidget);
      expect(find.text('Recorded job'), findsOneWidget);
      expect(missed, findsNothing);
      expect(recorded, findsNothing);
      await tap(tester, show.first);
      expect(missed, findsOneWidget);
      expect(recorded, findsNothing);
      await tap(tester, show);
      expect(hide, findsNWidgets(2));
      final reads = source.calls;
      final search = find.widgetWithText(TextField, 'Search job or company');
      Future<void> query(String value) async {
        await tester.ensureVisible(search);
        await tester.enterText(search, value);
        await tester.pumpAndSettle();
      }

      final total = find.byKey(
        const ValueKey('attendance-overview-Total past shifts'),
      );
      void expectTotal() => expect(
        find.descendant(of: total, matching: find.text('2')),
        findsOneWidget,
      );
      expectTotal();
      await query('harbour');
      expect(find.text('Showing 1 of 2 loaded past shifts'), findsOneWidget);
      expect(recorded, findsOneWidget);
      expect(missed, findsNothing);
      await tap(tester, find.byKey(const ValueKey('workspace-filters-toggle')));
      await tap(tester, find.widgetWithText(ChoiceChip, 'Recorded'));
      expect(recorded, findsOneWidget);
      expect(missed, findsNothing);
      await query('missed job');
      expect(find.text('No matching attendance records'), findsOneWidget);
      expect(find.text('Showing 0 of 2 loaded past shifts'), findsOneWidget);
      expectTotal();
      await tap(tester, find.text('Clear search and filters'));
      expect(hide, findsNWidgets(2));
      await query('missed job');
      expect(missed, findsOneWidget);
      expect(recorded, findsNothing);
      await tap(tester, find.byTooltip('Clear search'));
      await tap(tester, find.widgetWithText(ChoiceChip, 'All'));
      expect(hide, findsNWidgets(2));
      expect(source.calls, reads);
      await tap(tester, find.byTooltip('Refresh assignments'));
      expect(hide, findsNWidgets(2));
      await tap(tester, hide.first);
      expect(missed, findsNothing);
      expect(recorded, findsOneWidget);
      expect(show, findsOneWidget);
      expect(hide, findsOneWidget);
    },
  );

  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets(
      'single overnight history record uses its group width at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 960);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        source.workerRead = () async => [
          lifecycleRow(
              status: 'completed',
              verification: 'verified',
              now: '2026-11-07T00:00:00Z',
              input: '2026-11-05T15:50:12Z',
              output: '2026-11-05T16:10:45Z',
            )
            ..['scheduled_start'] = '2026-11-05T15:30:00Z'
            ..['scheduled_end'] = '2026-11-05T16:10:00Z'
            ..['verified_at'] = '2026-11-06T03:15:30Z',
        ];
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(width == 390 ? 2 : 1)),
              child: child!,
            ),
            home: WorkAttendancePage(repository: repository, history: true),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, find.text('Show attendance records'));
        final card = find.byKey(const ValueKey(id));
        final grid = find.ancestor(
          of: card,
          matching: find.byType(ResponsiveGrid),
        );
        expect(tester.getSize(card).width, tester.getSize(grid).width);
        final checkIn = find.widgetWithText(ShiftDetailPanel, 'Check-in');
        final checkout = find.widgetWithText(ShiftDetailPanel, 'Checkout');
        expect(
          find.descendant(of: checkIn, matching: find.text('11:50:12 PM')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: checkout, matching: find.text('12:10:45 AM')),
          findsOneWidget,
        );
        expect(find.text('Thu, 5 Nov 2026 · MYT'), findsOneWidget);
        expect(find.text('Fri, 6 Nov 2026 · MYT'), findsOneWidget);
        expect(find.text('Late'), findsOneWidget);
        expect(find.text('Work verified by employer'), findsOneWidget);
        expect(find.text('06/11/2026 11:15:30 MYT'), findsOneWidget);
        expect(find.text('Effective duration: 20 minutes'), findsOneWidget);
        final first = tester.getRect(checkIn);
        final second = tester.getRect(checkout);
        if (width == 390) {
          expect(second.top, greaterThan(first.bottom));
        } else {
          expect(second.top, first.top);
          expect(second.left, greaterThan(first.right));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (status, message) in [
    ('pending_review', 'Evidence awaiting employer review'),
    ('more_evidence_required', 'Revision requested · Review employer feedback'),
  ]) {
    testWidgets('history distinguishes $status', (tester) async {
      source.workerRead = () async => [
        lifecycleRow(
          status: 'awaiting_verification',
          verification: status,
          input: '2026-11-05T01:00:00Z',
          output: '2026-11-05T08:00:00Z',
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: WorkAttendancePage(repository: repository, history: true),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Show attendance records'));
      expect(find.text(message), findsOneWidget);
      expect(find.text('Work verified by employer'), findsNothing);
      expect(find.text('Details'), findsOneWidget);
    });
  }

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
      await tap(tester, find.text('Show application shifts'));
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
      await tap(tester, find.byKey(const ValueKey('workspace-filters-toggle')));
      await tap(tester, dropdown);
      await tap(tester, find.text('Attendance Issues').last);
      await tap(tester, find.text('Show application shifts'));
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
        if (history) await tap(tester, find.text('Show attendance records'));
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
      source.companyRead = (_) async => [
        lifecycleRow(company: true)
          ..['workplace_latitude'] = 3.117777
          ..['workplace_longitude'] = 101.677777,
      ];
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
      await tap(tester, find.text('Show application shifts'));
      expect(find.text('View workplace on map'), findsOneWidget);
      await tap(tester, find.byTooltip('Show shift details'));
      expect(find.text('View workplace on map'), findsOneWidget);
      for (final label in [
        'Scheduled shift',
        'Check-in',
        'Checkout',
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

  for (final width in [320.0, 1200.0]) {
    testWidgets(
      'future employer shift shows a compact preview and details at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        source.companyRead = (_) async => [
          lifecycleRow(company: true, now: '2026-11-04T22:00:00Z')
            ..['workplace_latitude'] = 3.117
            ..['workplace_longitude'] = 101.677,
        ];
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
        expect(find.text('Next upcoming shift'), findsOneWidget);
        expect(find.text('Thu, 5 Nov 2026'), findsOneWidget);
        expect(find.text('9:00 AM – 5:00 PM MYT'), findsOneWidget);
        expect(find.text('Server location'), findsOneWidget);
        expect(
          find.text('Shift assignments are for Part-Time and Temporary jobs'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Other job types are not eligible for new shift assignments.',
          ),
          findsOneWidget,
        );
        final preview = find.byType(UpcomingShiftPreview);
        final addShift = find.widgetWithText(OutlinedButton, 'Add shift');
        expect(
          tester.getTopLeft(addShift).dy - tester.getBottomLeft(preview).dy,
          greaterThanOrEqualTo(12),
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Add shift'),
              )
              .onPressed,
          isNull,
        );
        await tap(tester, find.text('Show application shifts'));
        expect(find.text('Upcoming / Scheduled'), findsOneWidget);
        expect(find.text('Workplace: Server location'), findsOneWidget);
        expect(find.text('View workplace on map'), findsOneWidget);
        expect(find.text('Shift details'), findsOneWidget);
        expect(find.byTooltip('Show shift details'), findsNothing);
        expect(find.text('Workplace & GPS'), findsNothing);
        expect(find.text('Work Evidence'), findsNothing);
        expect(find.text('View attendance GPS'), findsNothing);
        expect(find.text('View original attendance & audit'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

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
        await tap(tester, find.text('Show application shifts'));
        await tap(tester, find.byTooltip('Show shift details'));
        expect(
          find.text(corrected ? 'Corrected Attendance' : 'Confirmed Absent'),
          findsOneWidget,
        );
        expect(find.text('Actual employer resolution reason'), findsOneWidget);
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
      await tap(tester, find.text('Show application shifts'));
      await tap(tester, find.byTooltip('Show shift details').first);
      await tester.ensureVisible(find.text('View attendance GPS').first);
      expect(tester.takeException(), isNull);
      expect(find.text('Review Attendance'), findsNothing);
    },
  );
}
