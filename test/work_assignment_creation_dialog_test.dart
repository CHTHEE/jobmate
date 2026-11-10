import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_assignment_creation_dialog.dart';
import 'package:jobmate/features/work_attendance/work_assignment_creation_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_verification_pages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jobmate/features/work_attendance/engagement_closure_controls.dart';

import 'work_assignment_creation_repository_test.dart'
    show CandidateSource, uid, complete;
import 'work_attendance_repository_test.dart' show FakeSource, assignment;

class FakeEngagementClosureGateway implements EngagementClosureGateway {
  Future<Map<String, dynamic>> Function(String)? statusHandler;
  @override
  Future<Map<String, dynamic>> status(String applicationId) async =>
      statusHandler != null
      ? await statusHandler!(applicationId)
      : {'closure_status': 'open', 'eligible': true};

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
  late CandidateSource source;
  late WorkAssignmentCreationRepository repository;
  setUp(() {
    source = CandidateSource();
    repository = WorkAssignmentCreationRepository(
      source,
      ledger: WorkAssignmentCreationLedger(),
      now: () => DateTime.utc(2026, 11, 1),
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
    String? applicationId,
    EngagementClosureGateway? closureGateway,
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
                    applicationId: applicationId,
                    closureGateway:
                        closureGateway ?? FakeEngagementClosureGateway(),
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
    await tester.pumpAndSettle();
    if (label.contains('time (MYT)')) {
      final parts = value.trim().split(':').map(int.parse).toList();
      await tester.tap(finder);
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.byTooltip('Switch to text input mode'));
      await tester.pumpAndSettle();
      final inputs = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(
        inputs.at(0),
        '${parts[0] % 12 == 0 ? 12 : parts[0] % 12}',
      );
      await tester.enterText(inputs.at(1), parts[1].toString().padLeft(2, '0'));
      await tester.tap(find.text(parts[0] < 12 ? 'AM' : 'PM').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    } else {
      await tester.enterText(finder, value);
    }
    await tester.pump();
  }

  Future<void> fill(WidgetTester tester) async {
    await select(tester);
    for (final entry in {
      'Shift date (MYT)': '2026-11-07',
      'Start time (MYT)': '09:00',
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
    'one scheduling notice and contextual workplace error clear on edit',
    (tester) async {
      await show(tester, applicationId: uid(4));
      expect(find.text('Add shift'), findsOneWidget);
      expect(find.text('Before you schedule'), findsOneWidget);
      expect(
        find.text(
          'The shift must start in the future and finish on the same calendar day (Malaysia time).',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'For overnight work, create a separate shift for the next day.',
        ),
        findsOneWidget,
      );
      expect(find.text('Enter a workplace location.'), findsNothing);
      await review(tester);
      expect(find.text('Enter a workplace location.'), findsOneWidget);
      await field(tester, 'Workplace location', 'Agreed workplace');
      expect(find.text('Enter a workplace location.'), findsNothing);
      expect(source.creates, 0);
    },
  );

  testWidgets(
    'Malaysia date and Material time picker preserve selected values',
    (tester) async {
      await show(tester);
      await fill(tester);
      final date = find.byTooltip('Choose Shift date (MYT)');
      await tester.ensureVisible(date);
      await tester.tap(date);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Choose Start time (MYT)'), findsOneWidget);
      expect(find.byType(TimePickerDialog), findsNothing);
      await field(tester, 'Start time (MYT)', '09:05');
      await review(tester);
      expect(find.text('Start (MYT): 2026-11-07 9:05 AM'), findsOneWidget);
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
          'Shift date (MYT)': '2026-11-05',
          'Start time (MYT)': '22:50',
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
    await field(tester, 'Shift date (MYT)', '2026-11-05');
    await field(tester, 'Start time (MYT)', '22:50');
    for (final end in ['22:50', '22:49']) {
      await field(tester, 'End time (MYT)', end);
      await review(tester);
      expect(
        find.text('End time must be later than start time.'),
        findsOneWidget,
      );
      expect(find.text('Confirm creation'), findsNothing);
      expect(source.creates, 0);
    }
  });

  testWidgets(
    'past shift shows a clear message without offering confirmation',
    (tester) async {
      await show(tester);
      await fill(tester);
      await field(tester, 'Shift date (MYT)', '2026-10-31');
      await review(tester);
      expect(
        find.text(
          'This start time has already passed. Choose a later time or date.',
        ),
        findsOneWidget,
      );
      expect(find.text('Confirm creation'), findsNothing);
      expect(source.creates, 0);
    },
  );

  testWidgets('overnight time is rejected without rolling into next day', (
    tester,
  ) async {
    await show(tester);
    await fill(tester);
    await field(tester, 'Start time (MYT)', '22:53');
    await field(tester, 'End time (MYT)', '02:07');
    await review(tester);
    expect(
      find.text('End time must be later than start time.'),
      findsOneWidget,
    );
    expect(find.text('Confirm creation'), findsNothing);
    expect(source.creates, 0);
    await field(tester, 'End time (MYT)', '23:07');
    expect(find.text('End time must be later than start time.'), findsNothing);
    await review(tester);
    expect(find.text('Confirm creation'), findsOneWidget);
  });

  testWidgets(
    'empty fields stay neutral until review and valid selections clear errors',
    (tester) async {
      await show(tester);
      await select(tester);
      expect(find.text('Choose a start time.'), findsNothing);
      expect(find.text('Choose an end time.'), findsNothing);
      await review(tester);
      expect(find.text('Choose a start time.'), findsOneWidget);
      expect(find.text('Choose an end time.'), findsOneWidget);
      await field(tester, 'Start time (MYT)', '00:00');
      expect(find.text('Choose a start time.'), findsNothing);
      final start = tester.widget<TextField>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Start time (MYT)'),
          matching: find.byType(TextField),
        ),
      );
      expect(start.readOnly, isTrue);
      expect(find.text('12:00 AM'), findsOneWidget);
      expect(find.text('End date (MYT)'), findsNothing);
      expect(source.creates, 0);
    },
  );

  for (final conflictCode in <String?>[null, '23P01', '23505']) {
    final backendConflict = conflictCode != null;
    testWidgets(
      'confirmed ${backendConflict ? 'backend $conflictCode' : 'preflight'} overlap blocks confirmation until editing',
      (tester) async {
        if (backendConflict) {
          source.create = (_) async => throw PostgrestException(
            message: 'private overlap detail',
            code: conflictCode,
          );
        } else {
          source.assignments = (_) async => complete([
            assignment(company: true)
              ..['application_id'] = uid(4)
              ..['job_id'] = uid(3)
              ..['worker_id'] = uid(5)
              ..['scheduled_start'] = '2026-11-07T01:00:00Z'
              ..['scheduled_end'] = '2026-11-07T09:00:00Z',
          ]);
        }
        await show(tester);
        await fill(tester);
        await review(tester);
        await tester.tap(find.text('Confirm creation'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'This shift already exists or overlaps another worker shift.',
          ),
          findsOneWidget,
        );
        expect(find.text('Confirm creation'), findsNothing);
        expect(find.text('Edit'), findsOneWidget);
        expect(find.text('Close'), findsOneWidget);
        expect(find.textContaining('private overlap detail'), findsNothing);
        expect(source.creates, backendConflict ? 1 : 0);
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        await field(tester, 'Shift date (MYT)', '2026-11-09');
        source.create = (_) async => uid(90);
        await review(tester);
        await tester.tap(find.text('Confirm creation'));
        await tester.pumpAndSettle();
        expect(source.creates, backendConflict ? 2 : 1);
        expect(find.text('Confirmed ${uid(90)}'), findsOneWidget);
      },
    );
  }

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
    expect(
      find.text('End time must be later than start time.'),
      findsOneWidget,
    );
    await field(tester, 'End time (MYT)', '17:00');
    await field(tester, 'Shift date (MYT)', '2026-02-30');
    await review(tester);
    expect(find.text('Use a valid date: YYYY-MM-DD.'), findsOneWidget);
    await field(tester, 'Shift date (MYT)', '2026-11-07');
    await field(tester, 'Workplace location', 'x' * 501);
    await review(tester);
    expect(find.text('Use no more than 500 characters.'), findsOneWidget);
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
          closureGateway: FakeEngagementClosureGateway(),
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

  for (final scoped in [false, true]) {
    testWidgets(
      'reopened uncertain creation supports read-only reconciliation (scoped: $scoped)',
      (tester) async {
        await repository.load(companyId: source.company);
        source.create = (_) async => throw TimeoutException('lost response');
        final result = await repository.create(
          candidate: repository.state.candidates.single,
          start: DateTime.utc(2026, 11, 7, 1),
          end: DateTime.utc(2026, 11, 7, 9),
          location: 'QA workplace',
        );
        expect(result.status, WorkAssignmentCreateStatus.uncertain);
        expect(source.creates, 1);
        await show(tester, applicationId: scoped ? uid(4) : null);
        if (!scoped) await select(tester);
        expect(find.text('Review assignment'), findsNothing);
        expect(find.text('Confirm creation'), findsNothing);
        expect(find.text('Check current assignment'), findsOneWidget);
        await tester.tap(find.text('Check current assignment'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Creation outcome is uncertain.'),
          findsOneWidget,
        );
        expect(source.creates, 1);
        source.lookup = (_) async => uid(90);
        await tester.tap(find.text('Check current assignment'));
        await tester.pumpAndSettle();
        expect(find.text('Confirmed ${uid(90)}'), findsOneWidget);
        expect(source.lookedUpRequest, uid(80));
        expect(source.creates, 1);
        expect(source.reservations, 1);
      },
    );
  }

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

  testWidgets(
    'account switch during closure preflight never dispatches creation',
    (tester) async {
      final gateway = FakeEngagementClosureGateway();
      final pending = Completer<Map<String, dynamic>>();
      await show(tester, closureGateway: gateway);
      await fill(tester);
      await review(tester);
      gateway.statusHandler = (_) => pending.future;
      await tester.tap(find.text('Confirm creation'));
      await tester.pump();
      source.account(null);
      await tester.pump();
      pending.complete({'closure_status': 'open', 'eligible': true});
      await tester.pumpAndSettle();
      expect(source.reservations, 0);
      expect(source.creates, 0);
      expect(find.text('Confirm creation'), findsNothing);
      expect(tester.takeException(), isNull);
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
            closureGateway: FakeEngagementClosureGateway(),
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
