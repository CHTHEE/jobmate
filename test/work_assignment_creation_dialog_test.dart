import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_assignment_creation_dialog.dart';
import 'package:jobmate/features/work_attendance/work_assignment_creation_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_verification_pages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_assignment_creation_repository_test.dart'
    show CandidateSource, uid, complete;
import 'work_attendance_repository_test.dart' show FakeSource, assignment;

void main() {
  late CandidateSource source;
  late WorkAssignmentCreationRepository repository;
  setUp(() {
    source = CandidateSource();
    repository = WorkAssignmentCreationRepository(
      source,
      ledger: WorkAssignmentCreationLedger(),
    );
  });
  tearDown(() async {
    repository.dispose();
    await source.changes.close();
  });

  Future<void> show(
    WidgetTester tester, {
    double? width,
    double scale = 1,
  }) async {
    if (width != null) {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showDialog<String>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => WorkAssignmentCreationDialog(
                    repository: repository,
                    companyId: source.company,
                  ),
                );
                if (context.mounted && result != null) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Confirmed $result')));
                }
              },
              child: const Text('Open creation'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open creation'));
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<String>).first,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('QA Assistant').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<String>).last,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Synthetic worker').last);
    await tester.pumpAndSettle();
  }

  Future<void> field(WidgetTester tester, String label, String value) async {
    final finder = find.widgetWithText(TextFormField, label);
    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
    await tester.pump();
  }

  Future<void> fill(WidgetTester tester) async {
    await select(tester);
    for (final entry in {
      'Start date (MYT)': '2026-11-07',
      'Start time (MYT)': '09:00',
      'End date (MYT)': '2026-11-07',
      'End time (MYT)': '17:00',
      'Workplace location': 'QA workplace',
    }.entries) {
      await field(tester, entry.key, entry.value);
    }
  }

  Future<void> review(WidgetTester tester) async {
    await tester.tap(find.text('Review assignment'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Malaysia date and 24-hour time pickers preserve editable validated fields',
    (tester) async {
      await show(tester);
      await fill(tester);
      final date = find.byTooltip('Choose Start date (MYT)');
      await tester.ensureVisible(date);
      await tester.tap(date);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final time = find.byTooltip('Choose Start time (MYT)');
      await tester.ensureVisible(time);
      await tester.tap(time);
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await review(tester);
      expect(find.text('Start (MYT): 2026-11-07 09:00'), findsOneWidget);
      expect(find.textContaining(uid(4)), findsNothing);
      expect(source.creates, 0);
    },
  );

  for (final padded in [false, true]) {
    testWidgets(
      'reported late-evening MYT inputs, surrounding whitespace: $padded',
      (tester) async {
        await show(tester);
        await select(tester);
        for (final entry in {
          'Start date (MYT)': '2026-11-05',
          'Start time (MYT)': '22:50',
          'End date (MYT)': '2026-11-05',
          'End time (MYT)': '23:50',
        }.entries) {
          await field(
            tester,
            entry.key,
            padded ? ' \u00a0${entry.value}\u00a0 ' : entry.value,
          );
        }
        await field(tester, 'Workplace location', 'QA workplace');
        await review(tester);
        expect(find.text('Use a valid date: YYYY-MM-DD.'), findsNothing);
        expect(find.text('Use 24-hour time: HH:mm.'), findsNothing);
        expect(find.text('Confirm creation'), findsOneWidget);
        expect(source.creates, 0);
        await tester.tap(find.text('Confirm creation'));
        await tester.pumpAndSettle();
        expect(
          source.parameters!['p_scheduled_start'],
          '2026-11-05T14:50:00.000Z',
        );
        expect(
          source.parameters!['p_scheduled_end'],
          '2026-11-05T15:50:00.000Z',
        );
      },
    );
  }

  testWidgets('reported schedule rejects equal and earlier end times', (
    tester,
  ) async {
    await show(tester);
    await fill(tester);
    await field(tester, 'Start date (MYT)', '2026-11-05');
    await field(tester, 'End date (MYT)', '2026-11-05');
    await field(tester, 'Start time (MYT)', '22:50');
    for (final end in ['22:50', '22:49']) {
      await field(tester, 'End time (MYT)', end);
      await review(tester);
      expect(find.text('End must be after start.'), findsOneWidget);
      expect(find.text('Confirm creation'), findsNothing);
      expect(source.creates, 0);
    }
  });

  testWidgets(
    'candidate selection, confirmation, explicit dispatch and UTC mapping',
    (tester) async {
      await show(tester);
      expect(source.creates, 0);
      await fill(tester);
      await review(tester);
      for (final text in [
        'Company: Authorized company',
        'Job: QA Assistant',
        'Worker: Synthetic worker',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(source.creates, 0);
      await tester.tap(find.text('Confirm creation'));
      await tester.pumpAndSettle();
      expect(source.creates, 1);
      expect(
        source.parameters!['p_scheduled_start'],
        '2026-11-07T01:00:00.000Z',
      );
      expect(source.parameters!['p_scheduled_end'], '2026-11-07T09:00:00.000Z');
      expect(find.text('Confirmed ${uid(90)}'), findsOneWidget);
    },
  );

  testWidgets('selection, date, end and location validation block creation', (
    tester,
  ) async {
    await show(tester);
    await review(tester);
    expect(find.text('Select a job.'), findsOneWidget);
    expect(find.text('Select a hired application.'), findsOneWidget);
    await fill(tester);
    await field(tester, 'End time (MYT)', '08:00');
    await review(tester);
    expect(find.text('End must be after start.'), findsOneWidget);
    await field(tester, 'End time (MYT)', '17:00');
    await field(tester, 'Start date (MYT)', '2026-02-30');
    await review(tester);
    expect(find.text('Use a valid date: YYYY-MM-DD.'), findsOneWidget);
    await field(tester, 'Start date (MYT)', '2026-11-07');
    await field(tester, 'Workplace location', 'x' * 501);
    await review(tester);
    expect(
      find.text('Enter a workplace location of up to 500 characters.'),
      findsOneWidget,
    );
    expect(source.creates, 0);
  });

  testWidgets('loading, empty and failed reads never offer creation', (
    tester,
  ) async {
    final pending = Completer<WorkAssignmentCandidateRead>();
    source.jobs = (_) => pending.future;
    // Do not settle while the loading indicator is animating.
    await tester.pumpWidget(
      MaterialApp(
        home: WorkAssignmentCreationDialog(
          repository: repository,
          companyId: source.company,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(Exception('offline private details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check your connection'), findsOneWidget);
    expect(find.text('Review assignment'), findsNothing);
    source.jobs = (_) async => complete([]);
    await tester.tap(find.text('Retry loading applications'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No eligible hired applications'),
      findsOneWidget,
    );
    expect(source.creates, 0);
  });

  testWidgets(
    'previous assignment keeps worker selectable for an additional shift',
    (tester) async {
      source.assignments = (_) async =>
          complete([assignment(company: true)..['application_id'] = uid(4)]);
      await show(tester);
      await fill(tester);
      expect(find.text('Review assignment'), findsOneWidget);
      expect(
        find.textContaining('Applications with any existing assignment'),
        findsNothing,
      );
      expect(source.creates, 0);
    },
  );

  testWidgets('duplicate taps disabled while confirmation is in flight', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    source.create = (_) => pending.future;
    await show(tester);
    await fill(tester);
    await review(tester);
    await tester.tap(find.text('Confirm creation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(source.creates, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Confirm creation'), findsNothing);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Check current assignment'),
    );
    expect(button.onPressed, isNull);
    pending.complete(uid(90));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'server rejection is safe and requires another explicit confirmation',
    (tester) async {
      source.create = (_) async => throw const PostgrestException(
        message: 'private backend details',
        code: 'P0001',
      );
      await show(tester);
      await fill(tester);
      await review(tester);
      await tester.tap(find.text('Confirm creation'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Assignment was not created.'),
        findsOneWidget,
      );
      expect(find.textContaining('private backend details'), findsNothing);
      expect(source.creates, 1);
      source.create = (_) async => uid(90);
      await tester.tap(find.text('Confirm creation'));
      await tester.pumpAndSettle();
      expect(source.creates, 2);
    },
  );

  testWidgets(
    'uncertain result blocks writes; read-only check cannot blindly retry',
    (tester) async {
      source.create = (_) async => throw TimeoutException('lost response');
      await show(tester);
      await fill(tester);
      await review(tester);
      await tester.tap(find.text('Confirm creation'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Creation outcome is uncertain.'),
        findsOneWidget,
      );
      expect(find.text('Confirm creation'), findsNothing);
      await tester.tap(find.text('Check current assignment'));
      await tester.pumpAndSettle();
      expect(source.creates, 1);
      expect(
        find.textContaining('Creation outcome is uncertain.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'account switch clears confirmation and ignores stale completion',
    (tester) async {
      final pending = Completer<Object?>();
      source.create = (_) => pending.future;
      await show(tester);
      await fill(tester);
      await review(tester);
      await tester.tap(find.text('Confirm creation'));
      await tester.pump();
      source.account(null);
      await tester.pump();
      expect(find.textContaining('Account changed.'), findsOneWidget);
      expect(find.text('Worker: Synthetic worker'), findsNothing);
      pending.complete(uid(90));
      await tester.pumpAndSettle();
      expect(find.text('Confirmed ${uid(90)}'), findsNothing);
      expect(find.text('Confirm creation'), findsNothing);
    },
  );

  testWidgets('dirty close requires confirmation', (tester) async {
    await show(tester);
    await select(tester);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Your unsaved input will be lost.'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text('Create Assignment'), findsOneWidget);
    expect(source.creates, 0);
  });

  for (final (width, scale) in [(360.0, 1.0), (360.0, 2.0), (1200.0, 1.0)]) {
    testWidgets('responsive form ${width}px text $scale', (tester) async {
      await show(tester, width: width, scale: scale);
      await fill(tester);
      await review(tester);
      expect(find.text('Confirm creation'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(source.creates, 0);
    });
  }

  testWidgets(
    'employer list opens dialog and refreshes authoritative assignments on success',
    (tester) async {
      final attendance = FakeSource()..userId = source.userId;
      final attendanceRepository = WorkAttendanceRepository(attendance);
      addTearDown(() async {
        attendanceRepository.dispose();
        await attendance.changes.close();
      });
      final original = assignment(company: true);
      final originalSnapshot = Map<String, dynamic>.of(original);
      attendance.companyRead = (_) async => [original];
      source.assignments = (_) async => complete([original]);
      source.create = (_) async {
        final created = assignment(company: true)
          ..['assignment_id'] = uid(90)
          ..['application_id'] = uid(4)
          ..['job_id'] = uid(3)
          ..['worker_id'] = uid(5)
          ..['job_title'] = 'New QA shift';
        attendance.companyRead = (_) async => [original, created];
        source.assignments = (_) async => complete([original, created]);
        return uid(90);
      };
      await tester.pumpWidget(
        MaterialApp(
          home: WorkVerificationPage(
            repository: attendanceRepository,
            companyId: source.company,
            loadAccess: () => source.access(),
            createAssignmentRepository: () => repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Assignment'));
      await tester.pumpAndSettle();
      await fill(tester);
      await review(tester);
      await tester.tap(find.text('Confirm creation'));
      await tester.pumpAndSettle();
      expect(find.text('New QA shift'), findsOneWidget);
      expect(find.byKey(ValueKey(uid(90))), findsOneWidget);
      expect(find.text('Server job'), findsOneWidget);
      expect(original, originalSnapshot);
      expect(
        find.text('Assignment confirmed. Refreshing company assignments.'),
        findsOneWidget,
      );
      expect(source.creates, 1);
    },
  );
}
