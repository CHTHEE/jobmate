import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_draft_controller.dart';
import 'package:jobmate/features/work_attendance/work_evidence_draft_page.dart';
import 'package:jobmate/features/work_attendance/work_evidence_pages.dart';
import 'package:jobmate/features/work_attendance/work_evidence_repository.dart';

import 'work_evidence_draft_controller_test.dart'
    show
        FakeDraftSession,
        assignmentA,
        assignmentB,
        pdf,
        png,
        file,
        ControlledFile;
import 'work_attendance_repository_test.dart' as work;

void main() {
  group('draft form', () {
    late FakeDraftSession session;
    late WorkEvidenceDraftController draft;
    late Future<List<XFile>> Function() selection;
    var closed = 0;
    setUp(() {
      session = FakeDraftSession();
      selection = () async => [];
      closed = 0;
      draft = WorkEvidenceDraftController(
        session: session,
        assignmentId: assignmentA,
        pickFiles: () => selection(),
      );
    });
    tearDown(() async {
      draft.dispose();
      await session.changes.close();
    });
    Future<void> show(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkEvidenceDraftPage(
            controller: draft,
            onClose: () => closed++,
          ),
        ),
      ),
    );
    Future<void> choose(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Choose evidence files'));
      await tester.tap(find.text('Choose evidence files'));
      await tester.pumpAndSettle();
    }

    Future<void> description(WidgetTester tester, String text) async {
      final field = find.byKey(const ValueKey('evidence-draft-description'));
      await tester.ensureVisible(field);
      await tester.enterText(field, text);
      await tester.pump();
    }

    testWidgets(
      'required description, file rules and disabled submission are explicit',
      (tester) async {
        await show(tester);
        expect(find.text('Enter a work description.'), findsOneWidget);
        expect(
          find.text('Choose between 1 and 5 evidence files.'),
          findsOneWidget,
        );
        expect(find.text('Draft not ready'), findsOneWidget);
        expect(find.text('Submission is not enabled yet.'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit Evidence'),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.textContaining('Nothing has been uploaded or submitted'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'selection shows names/sizes, ready state and removal; submit stays disabled',
      (tester) async {
        selection = () async => [
          file(pdf(), name: 'proof.pdf'),
          file(png(), name: 'photo.png'),
        ];
        await show(tester);
        await description(tester, ' Completed the assigned tasks. ');
        await choose(tester);
        expect(find.text('proof.pdf'), findsOneWidget);
        expect(find.text('photo.png'), findsOneWidget);
        expect(find.text('${pdf().length} B'), findsOneWidget);
        expect(find.text('Draft ready for future submission'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit Evidence'),
              )
              .onPressed,
          isNull,
        );
        await tester.ensureVisible(find.byTooltip('Remove proof.pdf'));
        await tester.tap(find.byTooltip('Remove proof.pdf'));
        await tester.pumpAndSettle();
        expect(find.text('proof.pdf'), findsNothing);
        await tester.ensureVisible(find.byTooltip('Remove photo.png'));
        await tester.tap(find.byTooltip('Remove photo.png'));
        await tester.pumpAndSettle();
        expect(find.text('Draft not ready'), findsOneWidget);
      },
    );

    testWidgets(
      'controller description limit and duplicate feedback preserve draft',
      (tester) async {
        selection = () async => [file(pdf(), name: 'proof.pdf')];
        await show(tester);
        await description(tester, List.filled(2001, 'a').join());
        expect(
          find.text('Use a description of at most 2,000 characters.'),
          findsOneWidget,
        );
        await description(tester, 'Work completed');
        await choose(tester);
        await choose(tester);
        expect(find.textContaining('duplicate file'), findsOneWidget);
        expect(find.text('proof.pdf'), findsOneWidget);
        expect(draft.files, hasLength(1));
        expect(draft.description, 'Work completed');
      },
    );

    testWidgets(
      'picker cancellation and unreadable selections show safe feedback',
      (tester) async {
        await show(tester);
        await choose(tester);
        expect(draft.files, isEmpty);
        expect(draft.error, isNull);
        selection = () async => [
          ControlledFile(
            reportedSize: 5,
            chunks: () => Stream.error(Exception('/private/account/file.pdf')),
          ),
        ];
        await choose(tester);
        expect(
          find.text(
            'Could not read the selected files. Choose readable files and retry.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('/private/account'), findsNothing);
        expect(draft.files, isEmpty);
      },
    );

    testWidgets(
      'invalid signatures and too many files use controller validation',
      (tester) async {
        await show(tester);
        selection = () async => [file(pdf(), name: 'wrong.png')];
        await choose(tester);
        expect(find.textContaining('contents match'), findsOneWidget);
        selection = () async => [
          for (var i = 0; i < 6; i++) file(pdf(i), name: 'proof-$i.pdf'),
        ];
        await choose(tester);
        expect(
          find.text('Choose at most 5 evidence files in total.'),
          findsOneWidget,
        );
        expect(draft.files, isEmpty);
      },
    );

    testWidgets(
      'account change clears visible input and cancels pending picker',
      (tester) async {
        await show(tester);
        await description(tester, 'Private work summary');
        final pending = Completer<List<XFile>>();
        selection = () => pending.future;
        await tester.ensureVisible(find.text('Choose evidence files'));
        await tester.tap(find.text('Choose evidence files'));
        await tester.pump();
        expect(find.text('Reading local files…'), findsOneWidget);
        session.account('worker-b');
        await tester.pumpAndSettle();
        expect(draft.description, isEmpty);
        expect(find.text('Private work summary'), findsNothing);
        expect(find.textContaining('Draft cleared'), findsOneWidget);
        pending.complete([file(pdf(), name: 'stale.pdf')]);
        await tester.pumpAndSettle();
        expect(find.text('stale.pdf'), findsNothing);
        expect(draft.ready, isFalse);
      },
    );

    testWidgets(
      'assignment changes and form disposal clear file bytes and text',
      (tester) async {
        selection = () async => [file(pdf(), name: 'proof.pdf')];
        await show(tester);
        await description(tester, 'Old assignment summary');
        await choose(tester);
        final old = draft.files.single;
        draft.changeAssignment(assignmentB);
        await tester.pumpAndSettle();
        expect(old.bytes, isEmpty);
        expect(find.text('proof.pdf'), findsNothing);
        expect(find.text('Old assignment summary'), findsNothing);
        await choose(tester);
        final retained = draft.files.single;
        await tester.pumpWidget(const SizedBox());
        expect(draft.files, isEmpty);
        expect(retained.bytes, isEmpty);
        expect(draft.description, isEmpty);
      },
    );

    testWidgets('closing a dirty draft confirms discard; Stay retains input', (
      tester,
    ) async {
      await show(tester);
      await description(tester, 'Keep until confirmed');
      await tester.ensureVisible(find.text('Close draft'));
      await tester.tap(find.text('Close draft'));
      await tester.pumpAndSettle();
      expect(find.text('Leave this page?'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(draft.description, 'Keep until confirmed');
      expect(closed, 0);
      await tester.ensureVisible(find.text('Close draft'));
      await tester.tap(find.text('Close draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave page'));
      await tester.pumpAndSettle();
      expect(closed, 1);
      expect(draft.description, isEmpty);
    });

    testWidgets(
      'close remains available during a pending read and cancels it after confirmation',
      (tester) async {
        final pending = Completer<List<XFile>>();
        selection = () => pending.future;
        await show(tester);
        await tester.ensureVisible(find.text('Choose evidence files'));
        await tester.tap(find.text('Choose evidence files'));
        await tester.pump();
        expect(draft.busy, isTrue);
        await tester.ensureVisible(find.text('Close draft'));
        await tester.tap(find.text('Close draft'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Leave this page?'), findsOneWidget);
        await tester.tap(find.text('Leave page'));
        await tester.pumpAndSettle();
        expect(closed, 1);
        expect(draft.busy, isFalse);
        pending.complete([file(pdf(), name: 'late.pdf')]);
        await tester.pumpAndSettle();
        expect(draft.files, isEmpty);
      },
    );

    for (final size in [
      const Size(320, 720),
      const Size(568, 320),
      const Size(1440, 900),
    ]) {
      testWidgets(
        'responsive draft form at $size with enlarged text and keyboard insets',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          selection = () async => [
            file(pdf(), name: '${List.filled(12, 'long-name').join('-')}.pdf'),
          ];
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.6),
                  viewInsets: const EdgeInsets.only(bottom: 120),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: WorkEvidenceDraftPage(controller: draft, onClose: () {}),
              ),
            ),
          );
          await description(tester, 'Completed work');
          await choose(tester);
          await tester.ensureVisible(find.text('Submit Evidence'));
          await tester.pumpAndSettle();
          expect(
            find.text('Draft ready for future submission'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('worker viewer draft integration', () {
    late work.FakeSource source;
    late WorkAttendanceRepository attendance;
    late WorkEvidenceRepository viewer;
    setUp(() {
      source = work.FakeSource();
      attendance = WorkAttendanceRepository(source);
      viewer = WorkEvidenceRepository.worker(attendance, assignmentId: work.id);
    });
    tearDown(() async {
      viewer.dispose();
      attendance.dispose();
      await source.changes.close();
    });

    testWidgets(
      'authorized worker opens local form with injected picker and no backend operations',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: WorkEvidencePage(
              repository: viewer,
              pickDraftFiles: () async => [file(pdf(), name: 'local-only.pdf')],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('file.pdf'), findsOneWidget);
        final reads = source.calls;
        await tester.ensureVisible(find.text('Prepare local evidence draft'));
        await tester.tap(find.text('Prepare local evidence draft'));
        await tester.pumpAndSettle();
        expect(find.byType(WorkEvidenceDraftPage), findsOneWidget);
        await tester.ensureVisible(find.text('Choose evidence files'));
        await tester.tap(find.text('Choose evidence files'));
        await tester.pumpAndSettle();
        expect(find.text('local-only.pdf'), findsOneWidget);
        expect(source.calls, reads);
        expect(source.checkIns, 0);
        expect(source.checkOuts, 0);
        await tester.ensureVisible(find.text('Close draft'));
        await tester.tap(find.text('Close draft'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Leave page'));
        await tester.pumpAndSettle();
        expect(find.byType(WorkEvidenceDraftPage), findsNothing);
        expect(find.text('file.pdf'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('system Back prompts before discarding a modal draft', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: WorkEvidencePage(repository: viewer)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Prepare local evidence draft'));
      await tester.tap(find.text('Prepare local evidence draft'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Unsaved draft');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Leave this page?'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved draft'), findsOneWidget);
      await tester.ensureVisible(find.text('Close draft'));
      await tester.tap(find.text('Close draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave page'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkEvidenceDraftPage), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'replacing the underlying assignment invalidates an open modal draft',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: WorkEvidencePage(
              repository: viewer,
              pickDraftFiles: () async => [
                file(pdf(), name: 'old-assignment.pdf'),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Prepare local evidence draft'));
        await tester.tap(find.text('Prepare local evidence draft'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          'Old assignment details',
        );
        await tester.ensureVisible(find.text('Choose evidence files'));
        await tester.tap(find.text('Choose evidence files'));
        await tester.pumpAndSettle();
        final controller = tester
            .widget<WorkEvidenceDraftPage>(find.byType(WorkEvidenceDraftPage))
            .controller;
        final held = controller.files.single;
        final prior = viewer;
        viewer = WorkEvidenceRepository.worker(
          attendance,
          assignmentId: work.other,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: WorkEvidencePage(
              key: const ValueKey('replacement-assignment'),
              repository: viewer,
            ),
          ),
        );
        await tester.pumpAndSettle();
        prior.dispose();
        expect(find.text('old-assignment.pdf'), findsNothing);
        expect(find.text('Old assignment details'), findsNothing);
        expect(held.bytes, isEmpty);
        expect(controller.files, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('employer viewer remains strictly read-only', (tester) async {
      viewer.dispose();
      viewer = WorkEvidenceRepository.employer(
        attendance,
        assignmentId: work.id,
        companyId: work.other,
        loadCompanyAccess: () async =>
            const JobAccess({'company_id': work.other}, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WorkEvidencePage(
            repository: viewer,
            pickDraftFiles: () async => throw StateError('Must not open'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Prepare local evidence draft'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('No evidence submitted yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'account change while modal open removes prior draft contents',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: WorkEvidencePage(
              repository: viewer,
              pickDraftFiles: () async => [
                file(pdf(), name: 'private-draft.pdf'),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Prepare local evidence draft'));
        await tester.tap(find.text('Prepare local evidence draft'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Private description');
        await tester.ensureVisible(find.text('Choose evidence files'));
        await tester.tap(find.text('Choose evidence files'));
        await tester.pumpAndSettle();
        final controller = tester
            .widget<WorkEvidenceDraftPage>(find.byType(WorkEvidenceDraftPage))
            .controller;
        final held = controller.files.single;
        source.switchAccount(work.other);
        await tester.pumpAndSettle();
        expect(find.text('private-draft.pdf'), findsNothing);
        expect(find.text('Private description'), findsNothing);
        expect(find.textContaining('Draft cleared'), findsOneWidget);
        expect(held.bytes, isEmpty);
        await tester.ensureVisible(find.text('Close draft'));
        await tester.tap(find.text('Close draft'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
