import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';
import 'package:jobmate/features/work_attendance/work_attendance_resolution_dialog.dart';

import 'work_attendance_lifecycle_test.dart' show lifecycleRow;
import 'work_attendance_resolution_test.dart'
    show ResolutionSource, resolutionContext;

void main() {
  late ResolutionSource source;
  setUp(() => source = ResolutionSource());
  tearDown(() async => source.changes.close());
  Future<void> show(
    WidgetTester tester, {
    bool correcting = false,
    double width = 800,
    double scale = 1,
    bool stale = false,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final row = CompanyWorkAssignment.fromJson(
      lifecycleRow(
          company: true,
          now: '2026-11-07T10:00:00Z',
          status: correcting ? 'active' : 'scheduled',
          input: correcting ? '2026-11-05T01:00:00Z' : null,
        )
        ..['attendance_resolution'] = stale
            ? (resolutionContext()..['version'] = 'b' * 32)
            : null,
    );
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
              onPressed: () => showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => WorkAttendanceResolutionDialog(
                  assignment: row,
                  source: source,
                  workerName: 'Authorized worker',
                ),
              ),
              child: const Text('Open review'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> decision(WidgetTester tester, String label) async {
    await tap(tester, find.byType(DropdownButtonFormField<String>));
    await tap(tester, find.text(label).last);
  }

  testWidgets(
    'absence review requires reason and explicit confirmation with no invented attendance',
    (tester) async {
      await show(tester);
      await decision(tester, 'Confirm absence');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review decision'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Enter a resolution reason.'), findsNothing);
      expect(source.writes, isEmpty);
      await tester.enterText(
        find.byType(TextFormField),
        'No attendance confirmed with the worker',
      );
      await tap(tester, find.text('Review decision'));
      expect(find.text('Confirm attendance resolution'), findsOneWidget);
      expect(source.writes, isEmpty);
      await tap(tester, find.text('Confirm absence'));
      expect(source.writes, hasLength(1));
      expect(source.writes.single['p_check_in_at'], isNull);
      expect(source.writes.single['p_check_out_at'], isNull);
      expect(find.text('Confirmed Absent'), findsOneWidget);
      expect(find.text('Attendance resolved'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tap(tester, find.text('Done'));
      expect(find.byType(WorkAttendanceResolutionDialog), findsNothing);
    },
  );
  testWidgets(
    'correction pickers convert MYT AM/PM and preserve original device timestamps',
    (tester) async {
      source.context = resolutionContext(absence: false);
      await show(tester, correcting: true);
      await decision(tester, 'Correct attendance');
      final originalDetails = tester.widget<ExpansionTile>(
        find.widgetWithText(
          ExpansionTile,
          'Original attendance & correction rules',
        ),
      );
      expect(
        originalDetails.expandedCrossAxisAlignment,
        CrossAxisAlignment.stretch,
      );
      expect(originalDetails.expandedAlignment, Alignment.centerLeft);
      final actualConfirmation = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(
        actualConfirmation.controlAffinity,
        ListTileControlAffinity.leading,
      );
      expect(actualConfirmation.titleAlignment, ListTileTitleAlignment.top);
      for (final (label, hour) in [
        ('Choose corrected check-in (MYT)', 9),
        ('Choose corrected checkout (MYT)', 16),
      ]) {
        await tap(tester, find.text(label));
        Navigator.of(tester.element(find.byType(DatePickerDialog)))
            .pop(DateTime(2026, 11, 5));
        await tester.pumpAndSettle();
        expect(find.byType(TimePickerDialog), findsOneWidget);
        Navigator.of(tester.element(find.byType(TimePickerDialog)))
            .pop(TimeOfDay(hour: hour, minute: 0));
        await tester.pumpAndSettle();
      }
      await tap(tester, find.byType(CheckboxListTile));
      await tester.enterText(
        find.byType(TextFormField),
        'Actual times confirmed; checkout was missing',
      );
      await tap(tester, find.text('Review decision'));
      await tap(tester, find.text('Confirm correction'));
      expect(source.writes.single['p_check_in_at'], '2026-11-05T01:00:00.000Z');
      expect(
        source.writes.single['p_check_out_at'],
        '2026-11-05T08:00:00.000Z',
      );
      expect(find.text('Original attendance & correction rules'), findsNothing);
      expect(find.text('Corrected Attendance'), findsOneWidget);
    },
  );
  testWidgets(
    'changed server version blocks decisions based on stale displayed attendance',
    (tester) async {
      await show(tester, stale: true);
      expect(
        find.textContaining('Close and refresh before reviewing'),
        findsOneWidget,
      );
      expect(find.text('Review decision'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(source.writes, isEmpty);
      await tap(tester, find.text('Close'));
      expect(find.byType(WorkAttendanceResolutionDialog), findsNothing);
    },
  );
  testWidgets('dirty review keeps a practical exit with discard confirmation', (
    tester,
  ) async {
    await show(tester);
    await tester.enterText(find.byType(TextFormField), 'Unsaved reason');
    await tap(tester, find.text('Close'));
    expect(find.text('Discard attendance review?'), findsOneWidget);
    await tap(tester, find.text('Keep editing'));
    expect(find.text('Unsaved reason'), findsOneWidget);
    expect(source.writes, isEmpty);
  });
  testWidgets('review is accessible at 320px enlarged text without overflow', (
    tester,
  ) async {
    await show(tester, width: 320, scale: 1.6);
    await decision(tester, 'Confirm absence');
    await tester.ensureVisible(find.byType(TextFormField));
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
          .onPressed,
      isNotNull,
    );
  });
}
