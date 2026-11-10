import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/work_attendance/work_assignment_creation_repository.dart';
import 'package:jobmate/features/work_attendance/work_verification_pages.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/engagement_closure_controls.dart';

import 'work_assignment_creation_repository_test.dart'
    show CandidateSource, uid, complete;
import 'work_attendance_repository_test.dart' show FakeSource, assignment;
import 'work_attendance_gps_test.dart' show GpsSource, gpsRow;

class _ShiftGpsSource extends GpsSource {
  _ShiftGpsSource() {
    userId = uid(1);
  }
  final reads = <String>[];
  @override
  Future<List<Map<String, dynamic>>> read(
    String companyId,
    String assignmentId,
  ) async {
    expect(companyId, uid(2));
    reads.add(assignmentId);
    return [
      gpsRow()
        ..['company_id'] = companyId
        ..['assignment_id'] = assignmentId,
    ];
  }
}

Map<String, dynamic> shift(int number, {int application = 4}) =>
    assignment(company: true)
      ..['assignment_id'] = uid(number)
      ..['application_id'] = uid(application)
      ..['job_id'] = uid(3)
      ..['worker_id'] = uid(5)
      ..['job_title'] = 'QA Assistant';

class FakeEngagementClosureGateway implements EngagementClosureGateway {
  @override
  Future<Map<String, dynamic>> status(String applicationId) async => {
    'closure_status': 'open',
    'eligible': true,
  };

  @override
  Future<DateTime> close(String applicationId, String reason) async =>
      throw UnimplementedError();

  @override
  Future<String> request(String applicationId, String reason) async =>
      throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> companyRequests() async =>
      throw UnimplementedError();

  @override
  Future<DateTime?> respond(
    String requestId,
    String decision,
    String reason,
  ) async => throw UnimplementedError();
}

void main() {
  late CandidateSource candidates;
  late FakeSource source;
  late WorkAttendanceRepository repository;
  late List<Map<String, dynamic>> rows;
  late _ShiftGpsSource gps;
  setUp(() {
    candidates = CandidateSource();
    source = FakeSource()..userId = candidates.userId;
    repository = WorkAttendanceRepository(source);
    rows = [shift(10)];
    source.companyRead = (_) async => rows;
    candidates.assignments = (_) async => complete(rows);
    gps = _ShiftGpsSource();
  });
  tearDown(() async {
    repository.dispose();
    await source.changes.close();
    await candidates.changes.close();
    await gps.changes.close();
  });

  Widget page() => WorkVerificationPage(
    repository: repository,
    companyId: candidates.company,
    loadAccess: () => candidates.access(),
    loadWorkerName: (_, _) async => 'Synthetic worker',
    gpsSource: gps,
    closureGateway: FakeEngagementClosureGateway(),
    createAssignmentRepository: () => WorkAssignmentCreationRepository(
      candidates,
      ledger: WorkAssignmentCreationLedger(),
      now: () => DateTime.utc(2026, 11, 1),
    ),
  );

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: page()));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> schedule(
    WidgetTester tester, {
    String startDate = '2026-11-07',
    String startTime = '09:00',
    String endDate = '2026-11-07',
    String endTime = '17:00',
  }) async {
    for (final entry in {
      'Shift date (MYT)': startDate,
      'Start time (MYT)': startTime,
      'End time (MYT)': endTime,
      'Workplace location': 'Agreed workplace',
    }.entries) {
      final field = find.widgetWithText(TextFormField, entry.key);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      if (entry.key.contains('time (MYT)')) {
        final parts = entry.value.split(':').map(int.parse).toList();
        await tester.tap(field);
        await tester.pumpAndSettle();
        // Grouping tests supply the picker result; dial/input interactions are
        // covered by work_assignment_creation_dialog_test.dart.
        Navigator.of(tester.element(find.byType(TimePickerDialog))).pop(
          TimeOfDay(hour: parts[0], minute: parts[1]),
        );
        await tester.pumpAndSettle();
      } else {
        await tester.enterText(field, entry.value);
      }
      await tester.pump();
    }
  }

  for (final (timestamp, expected) in <(String?, String?)>[
    (null, null),
    ('2026-11-05T00:30:00Z', 'On Time'),
    ('2026-11-05T01:15:00Z', 'On Time'),
    ('2026-11-05T01:15:01Z', 'Late'),
  ]) {
    testWidgets('saved check-in timing presentation: $timestamp', (
      tester,
    ) async {
      rows = [shift(10)..['check_in_at'] = timestamp];
      await show(tester);
      expect(
        find.textContaining('Check-in timing:'),
        expected == null ? findsNothing : findsOneWidget,
      );
      if (expected != null) {
        expect(
          find.text('Check-in timing: $expected (15-minute grace period)'),
          findsOneWidget,
        );
      }
      expect(source.checkIns, 0);
      expect(source.checkOuts, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'groups only by application ID with worker, count and chronological shifts',
    (tester) async {
      rows = [
        shift(10)
          ..['scheduled_start'] = '2026-11-07T01:00:00Z'
          ..['scheduled_end'] = '2026-11-07T09:00:00Z',
        shift(12, application: 6),
        shift(11),
      ];
      await show(tester);
      final group = find.byKey(ValueKey('application-${uid(4)}'));
      final separate = find.byKey(ValueKey('application-${uid(6)}'));
      expect(group, findsOneWidget);
      expect(separate, findsOneWidget);
      expect(find.text('Worker: Synthetic worker'), findsNWidgets(2));
      expect(find.text('QA Assistant'), findsNWidgets(2));
      expect(find.text('2 shifts'), findsOneWidget);
      expect(find.text('1 shift'), findsOneWidget);
      expect(
        tester
            .widgetList<Card>(
              find.descendant(of: group, matching: find.byType(Card)),
            )
            .map((card) => card.key),
        [ValueKey(uid(11)), ValueKey(uid(10))],
      );
      expect(
        find.descendant(of: separate, matching: find.byType(Card)),
        findsOneWidget,
      );
      expect(repository.company.rows.map((row) => row.assignmentId), [
        uid(10),
        uid(12),
        uid(11),
      ]);
    },
  );

  testWidgets(
    'group Add shift creates independent daily schedules after confirmation',
    (tester) async {
      candidates.applicants = (_) async => complete([
        for (final app in [4, 6])
          {
            'application_id': uid(app),
            'applicant_id': uid(5),
            'applicant_name': 'Synthetic worker',
            'status': 'hired',
          },
      ]);
      rows.add(shift(12, application: 6));
      final original = rows.map(Map<String, dynamic>.of).toList();
      final parameters = <Map<String, dynamic>>[];
      candidates.create = (params) async {
        parameters.add(Map.of(params));
        final number = 90 + parameters.length;
        rows.add(
          shift(number)
            ..['scheduled_start'] = params['p_scheduled_start']
            ..['scheduled_end'] = params['p_scheduled_end']
            ..['workplace_location'] = params['p_workplace_location'],
        );
        return uid(number);
      };
      await show(tester);
      for (final lateEvening in [false, true]) {
        final group = find.byKey(ValueKey('application-${uid(4)}'));
        await tap(
          tester,
          find.descendant(of: group, matching: find.text('Add shift')),
        );
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.textContaining('Worker: Synthetic worker'), findsWidgets);
        if (lateEvening) {
          await schedule(
            tester,
            startDate: '2026-11-09',
            startTime: '22:30',
            endDate: '2026-11-09',
            endTime: '23:15',
          );
        } else {
          await schedule(tester);
        }
        await tap(tester, find.text('Review assignment'));
        expect(candidates.creates, lateEvening ? 1 : 0);
        await tap(tester, find.text('Confirm creation'));
        expect(find.byType(AlertDialog), findsNothing);
      }
      expect(parameters.map((p) => p['p_application_id']), [uid(4), uid(4)]);
      expect(parameters.map((p) => p['p_scheduled_start']), [
        '2026-11-07T01:00:00.000Z',
        '2026-11-09T14:30:00.000Z',
      ]);
      expect(parameters.map((p) => p['p_scheduled_end']), [
        '2026-11-07T09:00:00.000Z',
        '2026-11-09T15:15:00.000Z',
      ]);
      expect(rows.take(2), original);
      expect(find.text('3 shifts'), findsOneWidget);
      expect(find.text('1 shift'), findsOneWidget);
    },
  );

  testWidgets('Add shift fails closed if application is no longer eligible', (
    tester,
  ) async {
    // Other eligible applications must not become a fallback selection.
    candidates.applicants = (_) async => complete([
      {
        'application_id': uid(6),
        'applicant_id': uid(5),
        'applicant_name': 'Synthetic worker',
        'status': 'hired',
      },
    ]);
    await show(tester);
    await tap(tester, find.text('Add shift'));
    expect(
      find.textContaining('no longer available for scheduling'),
      findsOneWidget,
    );
    expect(find.text('Review assignment'), findsNothing);
    expect(candidates.creates, 0);
    expect(candidates.reservations, 0);
    await tap(tester, find.text('Close'));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'scoped creation retries reads, protects input and rejects overlaps',
    (tester) async {
      candidates.jobs = (_) async => throw TimeoutException('offline');
      await show(tester);
      await tap(tester, find.text('Add shift'));
      expect(find.textContaining('Check your connection'), findsOneWidget);
      candidates.jobs = (_) async => complete([
        {
          'job_id': uid(3),
          'company_id': candidates.company,
          'title': 'QA Assistant',
        },
      ]);
      await tap(tester, find.text('Retry loading applications'));
      await schedule(tester, startDate: '2026-11-05', endDate: '2026-11-05');
      await tap(tester, find.text('Close'));
      expect(find.text('Your unsaved input will be lost.'), findsOneWidget);
      await tap(tester, find.text('Stay'));
      await tap(tester, find.text('Review assignment'));
      await tap(tester, find.text('Confirm creation'));
      expect(
        find.text(
          'This shift already exists or overlaps another worker shift.',
        ),
        findsOneWidget,
      );
      expect(candidates.reservations, 0);
      expect(candidates.creates, 0);
    },
  );

  testWidgets(
    'grouped shifts preserve independent completion, GPS and evidence actions',
    (tester) async {
      rows = [
        shift(10)
          ..['assignment_status'] = 'completed'
          ..['verification_status'] = 'verified'
          ..['check_in_at'] = '2026-11-05T01:00:00Z'
          ..['check_out_at'] = '2026-11-05T09:00:00Z'
          ..['verified_at'] = '2026-11-05T10:00:00Z',
        shift(11)
          ..['assignment_status'] = 'awaiting_verification'
          ..['verification_status'] = 'pending_review',
      ];
      final router = GoRouter(
        initialLocation: '/work-verification',
        routes: [
          GoRoute(path: '/work-verification', builder: (_, _) => page()),
          GoRoute(
            path: '/work-verification/:assignmentId/evidence',
            builder: (_, state) => Scaffold(
              body: Text('Evidence ${state.pathParameters['assignmentId']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final completed = find.byKey(ValueKey(uid(10)));
      final pending = find.byKey(ValueKey(uid(11)));
      expect(
        find.descendant(
          of: completed,
          matching: find.text('Completed / Verified'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pending, matching: find.text('Pending Review')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: pending,
          matching: find.textContaining('Verified at:'),
        ),
        findsNothing,
      );
      for (final number in [10, 11]) {
        final card = find.byKey(ValueKey(uid(number)));
        await tap(
          tester,
          find.descendant(of: card, matching: find.text('View attendance GPS')),
        );
        expect(gps.reads.last, uid(number));
        await tap(tester, find.text('Close'));
        await tap(
          tester,
          find.descendant(of: card, matching: find.byType(FilledButton)),
        );
        expect(find.text('Evidence ${uid(number)}'), findsOneWidget);
        router.pop();
        await tester.pumpAndSettle();
      }
      expect(gps.reads, [uid(10), uid(11)]);
      expect(source.checkIns, 0);
      expect(source.checkOuts, 0);
    },
  );

  for (final width in [320.0, 840.0, 1440.0]) {
    testWidgets('grouped employer shifts fit $width with large text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      rows.add(shift(11));
      for (final row in rows) {
        row['job_title'] = List.filled(10, 'Long job title').join(' ');
      }
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: page(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 shifts'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('Add shift'));
      await schedule(tester);
      await tap(tester, find.text('Review assignment'));
      expect(find.text('Confirm creation'), findsOneWidget);
      expect(candidates.creates, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
