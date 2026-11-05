import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_evidence_draft_controller.dart';
import 'package:jobmate/features/work_attendance/work_evidence_draft_page.dart';

import 'work_evidence_draft_controller_test.dart'
    show FakeDraftSession, assignmentA, assignmentB, file, pdf, png;

void main() {
  late FakeDraftSession session;
  late WorkEvidenceDraftController draft;
  late WorkEvidenceMockUploadSource source;

  setUp(() {
    session = FakeDraftSession();
    draft = WorkEvidenceDraftController(
      session: session,
      assignmentId: assignmentA,
      pickFiles: () async => [file(pdf()), file(png(), name: 'photo.png')],
    );
    source = WorkEvidenceMockUploadSource(session: session);
  });
  tearDown(() async {
    draft.dispose();
    await session.changes.close();
  });

  Future<void> show(
    WidgetTester tester, {
    bool mock = true,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: WorkEvidenceDraftPage(
              controller: draft,
              mockUploadSource: mock ? source : null,
              onClose: () {},
            ),
          ),
        ),
      ),
    );
  }

  Future<void> prepare(WidgetTester tester) async {
    final field = find.byKey(const ValueKey('evidence-draft-description'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Completed the assigned work.');
    await tester.ensureVisible(find.text('Choose evidence files'));
    await tester.tap(find.text('Choose evidence files'));
    await tester.pumpAndSettle();
  }

  Finder getUpload() => find.byKey(const ValueKey('evidence-mock-upload'));
  void expectSubmissionDisabled(WidgetTester tester) => expect(
    tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Submit Evidence'),
        )
        .onPressed,
    isNull,
  );
  Future<void> upload(WidgetTester tester) async {
    await tester.ensureVisible(getUpload());
    await tester.tap(getUpload());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'normal production draft has no upload wiring and submission stays disabled',
    (tester) async {
      await show(tester, mock: false);
      await prepare(tester);
      expect(getUpload(), findsNothing);
      expect(source.eligibilityChecks, 0);
      expect(source.attemptedPaths, isEmpty);
      expectSubmissionDisabled(tester);
    },
  );

  testWidgets('mock injection requires validation and never auto starts', (
    tester,
  ) async {
    await show(tester);
    expect(tester.widget<OutlinedButton>(getUpload()).onPressed, isNull);
    expect(
      find.textContaining('no files are sent to Supabase'),
      findsOneWidget,
    );
    await prepare(tester);
    expect(tester.widget<OutlinedButton>(getUpload()).onPressed, isNotNull);
    expect(source.eligibilityChecks, 0);
    expect(source.attemptedPaths, isEmpty);
    expectSubmissionDisabled(tester);
  });

  testWidgets('explicit mock upload confirms batch without exposing paths', (
    tester,
  ) async {
    await show(tester);
    await prepare(tester);
    await upload(tester);
    expect(
      find.text('Mock upload batch confirmed. Nothing was submitted.'),
      findsOneWidget,
    );
    expect(find.text('Simulated files confirmed: 2 of 2.'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(getUpload()).onPressed, isNull);
    expect(source.attemptedPaths, hasLength(2));
    expect(source.eligibilityChecks, 1);
    for (final path in source.attemptedPaths) {
      expect(find.textContaining(path), findsNothing);
    }
    expectSubmissionDisabled(tester);
  });

  testWidgets('pending upload disables duplicate starts and draft editing', (
    tester,
  ) async {
    source = WorkEvidenceMockUploadSource(
      session: session,
      delay: const Duration(seconds: 1),
    );
    await show(tester);
    await prepare(tester);
    await tester.ensureVisible(getUpload());
    await tester.tap(getUpload());
    await tester.pump();
    expect(find.text('Uploading evidence (mock)'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(getUpload()).onPressed, isNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Choose evidence files'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Remove photo.png',
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(getUpload());
    expect(source.eligibilityChecks, 1);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(source.attemptedPaths, hasLength(2));
    expectSubmissionDisabled(tester);
  });

  testWidgets(
    'partial failure retries unchanged pending file with stable path',
    (tester) async {
      source = WorkEvidenceMockUploadSource(
        session: session,
        outcomes: [true, false, true],
      );
      await show(tester);
      await prepare(tester);
      await upload(tester);
      expect(find.text('Mock upload partially failed'), findsOneWidget);
      expect(find.text('Simulated files confirmed: 1 of 2.'), findsOneWidget);
      expect(find.text('Retry Upload'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      final original = source.attemptedPaths;
      await upload(tester);
      expect(
        find.text('Mock upload batch confirmed. Nothing was submitted.'),
        findsOneWidget,
      );
      expect(source.attemptedPaths, [
        original.first,
        original.last,
        original.last,
      ]);
      expect(source.eligibilityChecks, 2);
      expectSubmissionDisabled(tester);
    },
  );

  testWidgets('initial mock failure exposes an explicit retry', (tester) async {
    source = WorkEvidenceMockUploadSource(
      session: session,
      outcomes: [false, true, true],
    );
    await show(tester);
    await prepare(tester);
    await upload(tester);
    expect(
      find.text('Mock upload failed. Retry is available.'),
      findsOneWidget,
    );
    expect(find.text('Retry Upload'), findsOneWidget);
    expect(source.attemptedPaths, hasLength(1));
    await upload(tester);
    expect(source.attemptedPaths, hasLength(3));
    expect(source.attemptedPaths[0], source.attemptedPaths[1]);
    expectSubmissionDisabled(tester);
  });

  testWidgets(
    'external changed batch blocks retry instead of resetting uploaded state',
    (tester) async {
      source = WorkEvidenceMockUploadSource(
        session: session,
        outcomes: [true, false],
      );
      await show(tester);
      await prepare(tester);
      await upload(tester);
      draft.removeFile(draft.files.last.id);
      await tester.pump();
      expect(
        find.text(
          'Draft or account changed. Close and reopen; this batch cannot be retried.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<OutlinedButton>(getUpload()).onPressed, isNull);
      expect(find.textContaining('Simulated files confirmed:'), findsNothing);
      expect(source.attemptedPaths, hasLength(2));
      expectSubmissionDisabled(tester);
    },
  );

  for (final changeAccount in [true, false]) {
    testWidgets(
      '${changeAccount ? 'account' : 'assignment'} change hides in-flight results',
      (tester) async {
        source = WorkEvidenceMockUploadSource(
          session: session,
          delay: const Duration(seconds: 1),
        );
        await show(tester);
        await prepare(tester);
        await tester.ensureVisible(getUpload());
        await tester.tap(getUpload());
        await tester.pump();
        if (changeAccount) {
          session.account('worker-b');
        } else {
          draft.changeAssignment(assignmentB);
        }
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(source.attemptedPaths, hasLength(1));
        expect(
          find.text('Mock upload batch confirmed. Nothing was submitted.'),
          findsNothing,
        );
        expect(find.textContaining('Simulated files confirmed:'), findsNothing);
        expect(tester.widget<OutlinedButton>(getUpload()).onPressed, isNull);
        expectSubmissionDisabled(tester);
      },
    );
  }

  testWidgets('unmount cancels remaining mock batch without stale UI updates', (
    tester,
  ) async {
    source = WorkEvidenceMockUploadSource(
      session: session,
      delay: const Duration(seconds: 1),
    );
    await show(tester);
    await prepare(tester);
    await tester.ensureVisible(getUpload());
    await tester.tap(getUpload());
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(source.attemptedPaths, hasLength(1));
    expect(draft.files, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow layout and enlarged text retain accessible mock controls',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await show(tester, textScale: 1.8);
      await prepare(tester);
      await upload(tester);
      expect(
        find.text('Mock upload batch confirmed. Nothing was submitted.'),
        findsOneWidget,
      );
      expectSubmissionDisabled(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
