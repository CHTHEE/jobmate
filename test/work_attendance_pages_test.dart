import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_attendance_pages.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, other;

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
        'Assignment status: Completed',
        'Verification status: Verified',
        'Checked in: 06/11/2026 04:31 MYT',
        'Checked out: 06/11/2026 13:01 MYT',
        'Verified at: 06/11/2026 14:00 MYT',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.text('View details'), findsNothing);
      expect(find.text('Check In'), findsNothing);
      expect(
        find.widgetWithText(OutlinedButton, 'View Evidence'),
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
      expect(
        find.text('Verification status: More evidence required'),
        findsOneWidget,
      );
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
