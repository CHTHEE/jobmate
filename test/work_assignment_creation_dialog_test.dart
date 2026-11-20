import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_assignment_creation_dialog.dart';
import 'package:jobmate/features/jobs/workplace_map_picker.dart';
import 'package:jobmate/features/jobs/workplace_coordinates.dart';
import 'package:jobmate/features/work_attendance/work_assignment_creation_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_verification_pages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jobmate/features/work_attendance/engagement_closure_controls.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';

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
    WorkplacePicker? pickWorkplace,
    ThemeData? theme,
  }) async {
    if (width != null) {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
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
                    pickWorkplace: pickWorkplace ?? showWorkplacePicker,
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
    final dropdowns = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await tester.ensureVisible(dropdowns.first);
    await tester.tap(dropdowns.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('QA Assistant').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(dropdowns.last);
    await tester.tap(dropdowns.last);
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
    await tester.tap(find.text('Review Shift'));
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 1200.0]) {
    testWidgets(
      'Company job label stays within the scroll viewport at $width',
      (tester) async {
        await show(
          tester,
          width: width,
          scale: 1.6,
          theme: JobMateTheme.light(),
        );
        final label = find.text('Company job');
        final field = find.widgetWithText(
          DropdownButtonFormField<String>,
          'Company job',
        );
        final viewport = find
            .ancestor(of: field, matching: find.byType(SingleChildScrollView))
            .first;
        void expectLabelVisible() {
          final labelRect = tester.getRect(label);
          final viewportRect = tester.getRect(viewport);
          expect(labelRect.top, greaterThanOrEqualTo(viewportRect.top));
          expect(labelRect.bottom, lessThanOrEqualTo(viewportRect.bottom));
        }

        expectLabelVisible();
        Focus.of(tester.element(label)).requestFocus();
        await tester.pumpAndSettle();
        expect(Focus.of(tester.element(label)).hasFocus, isTrue);
        expectLabelVisible();

        await review(tester);
        expect(find.text('Select a job.'), findsOneWidget);
        expectLabelVisible();

        await tester.tap(field);
        await tester.pumpAndSettle();
        expect(find.text('QA Assistant').hitTestable(), findsOneWidget);
        expectLabelVisible();
        await tester.tap(find.text('QA Assistant').hitTestable());
        await tester.pumpAndSettle();
        expect(find.text('QA Assistant'), findsOneWidget);
        expect(find.text('Select a job.'), findsNothing);
        expectLabelVisible();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('missing v2 requires an explicit compatibility save', (
    tester,
  ) async {
    source.reserve = (_) async => throw const PostgrestException(
      message: 'Missing v2 reservation',
      code: 'PGRST202',
    );
    await show(tester);
    await fill(tester);
    await review(tester);
    final legacy = find.text('Save text only in compatibility mode');
    expect(legacy, findsNothing);
    await tester.tap(find.text('Confirm & Save'));
    await tester.pumpAndSettle();
    expect(source.reservations, 1);
    expect(source.creates, 0);
    expect(legacy, findsOneWidget);
    source.reserve = (payload) async {
      expect(payload.keys, isNot(contains('p_workplace_latitude')));
      return uid(80);
    };
    await tester.tap(legacy);
    await tester.pumpAndSettle();
    expect(source.creates, 1);
    expect(source.parameters!['p_workplace_location'], 'QA workplace');
    expect(source.parameters!.keys, isNot(contains('p_workplace_longitude')));
  });

  testWidgets('posting workplace prefills and an override survives refresh', (
    tester,
  ) async {
    var postingWorkplace = '  Mid Valley Megamall  ';
    source.jobs = (_) async => complete([
      {
        'job_id': uid(3),
        'company_id': source.company,
        'title': 'QA Assistant',
        'employment_type': 'part_time',
        'location': postingWorkplace,
        'latitude': 3.118,
        'longitude': 101.677,
      },
      {
        'job_id': uid(13),
        'company_id': source.company,
        'title': 'QA Associate',
        'employment_type': 'temporary',
        'latitude': 3.149,
        'longitude': 101.713,
      },
    ]);
    source.applicants = (job) async => complete([
      {
        'application_id': job == uid(3) ? uid(4) : uid(14),
        'applicant_id': uid(5),
        'applicant_name': job == uid(3) ? 'Synthetic worker' : 'Second worker',
        'status': 'hired',
      },
      if (job == uid(3))
        {
          'application_id': uid(6),
          'applicant_id': uid(7),
          'applicant_name': 'Another hired worker',
          'status': 'hired',
        },
    ]);
    final workplace = find.widgetWithText(TextFormField, 'Workplace location');
    String value() => tester.widget<TextFormField>(workplace).controller!.text;
    const inherited = (latitude: 3.118, longitude: 101.677);
    const override = (latitude: 3.149, longitude: 101.713);
    const manual = WorkplacePickerResult(override);
    const place = WorkplacePickerResult(
      override,
      placeAddress: '  Pavilion Kuala Lumpur, Malaysia  ',
    );
    var pickerResult = Future<WorkplacePickerResult?>.value();
    WorkplaceCoordinates? pickerInitial;
    String? pickerAddress;
    await show(
      tester,
      pickWorkplace: (_, initial, address, autoSearch) {
        pickerInitial = initial;
        pickerAddress = address;
        expect(autoSearch, isFalse);
        return pickerResult;
      },
    );
    Future<void> pick(String label) async {
      final action = find.text(label);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
    }

    expect(value(), isEmpty);
    await select(tester);
    expect(value(), 'Mid Valley Megamall');
    expect(find.text('Draft pin: 3.118000, 101.677000'), findsOneWidget);
    await pick('Change pin');
    expect(pickerInitial, inherited);
    expect(pickerAddress, 'Mid Valley Megamall');
    expect(value(), 'Mid Valley Megamall');
    expect(find.text('Draft pin: 3.118000, 101.677000'), findsOneWidget);
    await field(tester, 'Workplace location', 'Pavilion Kuala Lumpur');
    expect(find.text('No map pin selected'), findsOneWidget);
    await field(tester, 'Workplace location', 'Mid Valley Megamall');
    expect(find.text('No map pin selected'), findsOneWidget);
    expect(find.text('Keep existing pin'), findsOneWidget);
    await field(tester, 'Workplace location', 'Pavilion Kuala Lumpur');
    pickerResult = Future.value(manual);
    await pick('Choose pin');
    expect(pickerInitial, isNull);
    expect(pickerAddress, 'Pavilion Kuala Lumpur');
    expect(value(), 'Pavilion Kuala Lumpur');
    pickerResult = Future.value(place);
    await pick('Change pin');
    expect(value(), 'Pavilion Kuala Lumpur, Malaysia');
    expect(find.text('Draft pin: 3.149000, 101.713000'), findsOneWidget);
    expect(find.text('Keep existing pin'), findsNothing);
    await field(tester, 'Workplace location', 'Pavilion');
    postingWorkplace = 'Updated posting address';
    await repository.load(companyId: source.company);
    await tester.pumpAndSettle();
    expect(value(), 'Pavilion');
    expect(find.text('Edited workplace: Pavilion'), findsOneWidget);
    expect(find.text('Previous pin: 3.149000, 101.713000'), findsOneWidget);
    expect(find.text('No map pin selected'), findsOneWidget);
    pickerResult = Future.value(null);
    await pick('Choose pin');
    expect(value(), 'Pavilion');
    expect(find.text('Previous pin: 3.149000, 101.713000'), findsOneWidget);
    await pick('Keep existing pin');
    expect(find.text('Draft pin: 3.149000, 101.713000'), findsOneWidget);
    expect(find.text('Keep existing pin'), findsNothing);

    final stale = Completer<WorkplacePickerResult?>();
    pickerResult = stale.future;
    await pick('Change pin');
    await field(tester, 'Workplace location', 'Edited address');
    await field(
      tester,
      'Workplace location',
      'Pavilion Kuala Lumpur, Malaysia',
    );
    stale.complete(
      const WorkplacePickerResult(override, placeAddress: 'Stale address'),
    );
    await tester.pumpAndSettle();
    expect(value(), 'Pavilion Kuala Lumpur, Malaysia');
    expect(find.text('No map pin selected'), findsOneWidget);
    expect(find.text('Keep existing pin'), findsOneWidget);

    final dropdowns = find.byType(DropdownButtonFormField<String>);
    Future<void> choose(Finder dropdown, String label) async {
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    final oldApplicationResult = Completer<WorkplacePickerResult?>();
    pickerResult = oldApplicationResult.future;
    await pick('Choose pin');
    await choose(dropdowns.last, 'Another hired worker');
    oldApplicationResult.complete(place);
    await tester.pumpAndSettle();
    expect(value(), 'Updated posting address');
    expect(find.text('Draft pin: 3.118000, 101.677000'), findsOneWidget);
    expect(find.text('Keep existing pin'), findsNothing);
    await field(tester, 'Workplace location', 'Completely different workplace');
    await pick('Clear pin');
    expect(value(), 'Completely different workplace');
    expect(find.text('Keep existing pin'), findsNothing);
    expect(find.text('No map pin selected'), findsOneWidget);
    await choose(dropdowns.first, 'QA Associate');
    await choose(dropdowns.last, 'Second worker');
    expect(value(), isEmpty);
    expect(find.text('No map pin selected'), findsOneWidget);
    await field(tester, 'Workplace location', 'Manual address');
    expect(value(), 'Manual address');
    pickerResult = Future.value(place);
    await pick('Choose pin');
    await field(tester, 'Workplace location', 'Pending before account switch');
    expect(find.text('Keep existing pin'), findsOneWidget);
    final oldAccountResult = Completer<WorkplacePickerResult?>();
    pickerResult = oldAccountResult.future;
    await pick('Choose pin');
    source.account(uid(22));
    oldAccountResult.complete(place);
    await tester.pumpAndSettle();
    expect(find.textContaining('Account changed.'), findsOneWidget);
    expect(find.text('Keep existing pin'), findsNothing);
    expect(find.text('Draft pin: 3.149000, 101.713000'), findsNothing);
    expect(source.creates, 0);
  });

  testWidgets('Add shift saves each reviewed workplace independently', (
    tester,
  ) async {
    source.jobs = (_) async => complete([
      {
        'job_id': uid(3),
        'company_id': source.company,
        'title': 'QA Assistant',
        'employment_type': 'part_time',
        'location': 'Mid Valley Megamall',
        'latitude': 3.118,
        'longitude': 101.677,
      },
    ]);
    final workplace = find.widgetWithText(TextFormField, 'Workplace location');
    for (final (date, override, expected, keepPin) in [
      ('2026-11-07', 'Mid Valley', 'Mid Valley', true),
      ('2026-11-08', ' Pavilion Kuala Lumpur ', 'Pavilion Kuala Lumpur', false),
    ]) {
      await show(tester, applicationId: uid(4));
      expect(
        tester.widget<TextFormField>(workplace).controller!.text,
        'Mid Valley Megamall',
      );
      await field(tester, 'Shift date (MYT)', date);
      await field(tester, 'Start time (MYT)', '09:00');
      await field(tester, 'End time (MYT)', '17:00');
      await field(tester, 'Workplace location', override);
      if (keepPin) {
        final keep = find.text('Keep existing pin');
        await tester.ensureVisible(keep);
        await tester.tap(keep);
        await tester.pumpAndSettle();
      }
      final previousWrites = source.creates;
      await review(tester);
      expect(find.text(expected), findsOneWidget);
      expect(find.text('Keep existing pin'), findsNothing);
      if (keepPin) {
        expect(find.text('Draft pin: 3.118000, 101.677000'), findsOneWidget);
        expect(
          find.text('The workplace and map pin will be saved for this shift.'),
          findsOneWidget,
        );
      }
      expect(source.creates, previousWrites);
      await tester.tap(find.text('Confirm & Save'));
      await tester.pumpAndSettle();
      expect(source.creates, previousWrites + 1);
      expect(source.parameters!['p_workplace_location'], expected);
      expect(
        source.parameters!['p_workplace_latitude'],
        keepPin ? 3.118 : null,
      );
      expect(
        source.parameters!['p_workplace_longitude'],
        keepPin ? 101.677 : null,
      );
    }
  });

  testWidgets(
    'desktop time fields share a row and workplace stays in the form viewport',
    (tester) async {
      await show(tester, width: 1200);
      await select(tester);
      final start = find.widgetWithText(TextFormField, 'Start time (MYT)');
      final end = find.widgetWithText(TextFormField, 'End time (MYT)');
      final location = find.widgetWithText(TextFormField, 'Workplace location');
      final viewport = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      expect(tester.getTopLeft(start).dy, tester.getTopLeft(end).dy);
      expect(
        tester.getTopLeft(end).dx,
        greaterThan(tester.getTopLeft(start).dx),
      );
      expect(
        tester.getBottomRight(location).dy,
        lessThanOrEqualTo(tester.getBottomRight(viewport).dy),
      );
      expect(tester.takeException(), isNull);
      expect(source.creates, 0);
    },
  );

  testWidgets(
    'structured review uses actual references and Back preserves all form values',
    (tester) async {
      await show(tester, width: 1200);
      await fill(tester);
      await review(tester);
      expect(find.text('Review shift before saving'), findsOneWidget);
      expect(find.text('Saturday, 7 November 2026'), findsOneWidget);
      expect(find.text(uid(4)), findsNothing);
      expect(find.text('8h 0m'), findsOneWidget);
      expect(find.text('QA workplace'), findsOneWidget);
      expect(find.byTooltip('Close assignment dialog'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      for (final (label, value) in [
        ('Start time (MYT)', '9:00 AM'),
        ('End time (MYT)', '5:00 PM'),
        ('Workplace location', 'QA workplace'),
      ]) {
        expect(
          tester
              .widget<TextFormField>(find.widgetWithText(TextFormField, label))
              .controller!
              .text,
          value,
        );
      }
      expect(source.creates, 0);
    },
  );

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
      expect(find.text('9:05 AM – 5:00 PM MYT'), findsOneWidget);
      expect(find.text('Application reference'), findsNothing);
      expect(find.text(uid(4)), findsNothing);
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
        expect(find.text('Confirm & Save'), findsOneWidget);
        expect(source.creates, 0);
        await tester.tap(find.text('Confirm & Save'));
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
      expect(find.text('Confirm & Save'), findsNothing);
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
      expect(find.text('Confirm & Save'), findsNothing);
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
    expect(find.text('Confirm & Save'), findsNothing);
    expect(source.creates, 0);
    await field(tester, 'End time (MYT)', '23:07');
    expect(find.text('End time must be later than start time.'), findsNothing);
    await review(tester);
    expect(find.text('Confirm & Save'), findsOneWidget);
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
        await tester.tap(find.text('Confirm & Save'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'This shift already exists or overlaps another worker shift.',
          ),
          findsOneWidget,
        );
        expect(find.text('Confirm & Save'), findsNothing);
        expect(find.text('Back'), findsOneWidget);
        expect(find.byTooltip('Close assignment dialog'), findsOneWidget);
        expect(find.textContaining('private overlap detail'), findsNothing);
        expect(source.creates, backendConflict ? 1 : 0);
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        await field(tester, 'Shift date (MYT)', '2026-11-09');
        source.create = (_) async => uid(90);
        await review(tester);
        await tester.tap(find.text('Confirm & Save'));
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
        'Authorized company',
        'QA Assistant',
        'Synthetic worker',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(source.creates, 0);
      await tester.tap(find.text('Confirm & Save'));
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
    expect(find.text('Review Shift'), findsNothing);
    source.jobs = (_) async => complete([]);
    await tester.tap(find.text('Retry loading applications'));
    await tester.pumpAndSettle();
    expect(find.text('No eligible jobs available'), findsOneWidget);
    expect(find.textContaining('eligible hired worker'), findsOneWidget);
    expect(source.creates, 0);
  });

  testWidgets(
    'previous assignment keeps worker selectable for an additional shift',
    (tester) async {
      source.assignments = (_) async =>
          complete([assignment(company: true)..['application_id'] = uid(4)]);
      await show(tester);
      await fill(tester);
      expect(find.text('Review Shift'), findsOneWidget);
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
        expect(find.text('Review Shift'), findsNothing);
        expect(find.text('Confirm & Save'), findsNothing);
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
    final gateway = FakeEngagementClosureGateway();
    final preflight = Completer<Map<String, dynamic>>();
    final pending = Completer<Object?>();
    source.create = (_) => pending.future;
    await show(tester, closureGateway: gateway);
    await fill(tester);
    await review(tester);
    var statusRequests = 0;
    gateway.statusHandler = (_) {
      statusRequests++;
      return preflight.future;
    };
    final confirm = find.widgetWithText(FilledButton, 'Confirm & Save');
    final size = tester.getSize(confirm);
    await tester.tap(confirm);
    await tester.tap(confirm);
    expect(statusRequests, 0);
    await tester.pump();
    final saving = find.widgetWithText(FilledButton, 'Saving assignment...');
    expect(tester.getSize(saving), size);
    expect(tester.widget<FilledButton>(saving).onPressed, isNull);
    expect(
      find.descendant(
        of: saving,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(find.text('Review shift before saving'), findsOneWidget);
    expect(find.text('Synthetic worker'), findsOneWidget);
    expect(statusRequests, 1);
    expect(source.creates, 0);
    preflight.complete({'closure_status': 'open', 'eligible': true});
    await tester.pump(const Duration(milliseconds: 100));
    expect(source.creates, 1);
    expect(tester.widget<FilledButton>(saving).onPressed, isNull);
    expect(find.text('Check current assignment'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Back'))
          .onPressed,
      isNull,
    );
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
      await tester.tap(find.text('Confirm & Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Assignment was not created.'),
        findsOneWidget,
      );
      expect(find.textContaining('private backend details'), findsNothing);
      expect(source.creates, 1);
      source.create = (_) async => uid(90);
      await tester.tap(find.text('Confirm & Save'));
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
      await tester.tap(find.text('Confirm & Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Creation outcome is uncertain.'),
        findsOneWidget,
      );
      expect(find.text('Confirm & Save'), findsNothing);
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
      await tester.tap(find.text('Confirm & Save'));
      await tester.pump();
      source.account(null);
      await tester.pump();
      expect(find.textContaining('Account changed.'), findsOneWidget);
      expect(find.text('Worker: Synthetic worker'), findsNothing);
      pending.complete(uid(90));
      await tester.pumpAndSettle();
      expect(find.text('Confirmed ${uid(90)}'), findsNothing);
      expect(find.text('Confirm & Save'), findsNothing);
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
      await tester.tap(find.text('Confirm & Save'));
      await tester.pump();
      source.account(null);
      await tester.pump();
      pending.complete({'closure_status': 'open', 'eligible': true});
      await tester.pumpAndSettle();
      expect(source.reservations, 0);
      expect(source.creates, 0);
      expect(find.text('Confirm & Save'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dirty close requires confirmation', (tester) async {
    await show(tester);
    await select(tester);
    await tester.tap(find.byTooltip('Close assignment dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Your unsaved input will be lost.'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text('Create Assignment'), findsOneWidget);
    expect(source.creates, 0);
  });

  for (final (width, scale) in [
    (320.0, 1.6),
    (360.0, 1.0),
    (360.0, 2.0),
    (1200.0, 1.0),
  ]) {
    testWidgets('responsive form ${width}px text $scale', (tester) async {
      final pending = Completer<Object?>();
      source.create = (_) => pending.future;
      await show(tester, width: width, scale: scale);
      expect(
        find.text(
          'Only Part-Time and Temporary jobs with eligible hired workers are available.',
        ),
        findsOneWidget,
      );
      await fill(tester);
      await review(tester);
      expect(find.text('Confirm & Save'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(source.creates, 0);
      final confirm = find.widgetWithText(FilledButton, 'Confirm & Save');
      final size = tester.getSize(confirm);
      await tester.tap(confirm);
      await tester.pump();
      expect(
        tester.getSize(
          find.widgetWithText(FilledButton, 'Saving assignment...'),
        ),
        size,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
      pending.complete(uid(90));
      await tester.pumpAndSettle();
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
      await tester.tap(find.text('Confirm & Save'));
      await tester.pumpAndSettle();
      expect(find.text('New QA shift'), findsOneWidget);
      expect(find.byKey(ValueKey(uid(90))), findsNothing);
      final showShifts = find.descendant(
        of: find.byKey(ValueKey('application-${uid(4)}')),
        matching: find.text('Show application shifts'),
      );
      await tester.ensureVisible(showShifts);
      await tester.tap(showShifts);
      await tester.pumpAndSettle();
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
