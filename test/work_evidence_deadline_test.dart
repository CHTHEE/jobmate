import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';
import 'package:jobmate/features/work_attendance/work_attendance_pages.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_deadline.dart';
import 'package:jobmate/features/work_attendance/work_evidence_draft_controller.dart';
import 'package:jobmate/features/work_attendance/work_evidence_upload_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_workflow.dart';
import 'package:jobmate/features/work_attendance/work_evidence_pages.dart';
import 'package:jobmate/features/work_attendance/work_evidence_repository.dart';
import 'package:jobmate/features/work_attendance/work_verification_pages.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';

import 'work_attendance_repository_test.dart'
    show assignment, FakeSource, id, other;
import 'work_evidence_workflow_test.dart'
    show EvidenceServer, WorkflowSource, UploadSource;
import 'work_evidence_draft_controller_test.dart' show file, pdf;

final checkout = DateTime.utc(2026, 12, 31, 15, 30);

Map<String, dynamic> checkedOut() => assignment()
  ..['assignment_status'] = 'awaiting_verification'
  ..['check_in_at'] = checkout
      .subtract(const Duration(hours: 8))
      .toIso8601String()
  ..['check_out_at'] = checkout.toIso8601String();

WorkerWorkAssignment workerRow([Map<String, dynamic>? fields]) =>
    WorkerWorkAssignment.fromJson(fields ?? checkedOut());

void main() {
  testWidgets(
    'fresh workflow status replaces stale overdue projection without a page reload',
    (tester) async {
      final now = DateTime.now().toUtc();
      final row = checkedOut()
        ..['check_in_at'] = now
            .subtract(const Duration(days: 4))
            .toIso8601String()
        ..['check_out_at'] = now
            .subtract(const Duration(days: 3))
            .toIso8601String();
      final source = FakeSource()
        ..workerRead = (() async => [row])
        ..evidenceRead = ((_) async => []);
      final attendance = WorkAttendanceRepository(source);
      final viewer = WorkEvidenceRepository.worker(
        attendance,
        assignmentId: id,
      );
      final server = EvidenceServer()
        ..status = 'pending_review'
        ..round = 1;
      final workflow = WorkflowSource(server, id);
      addTearDown(() async {
        viewer.dispose();
        attendance.dispose();
        await source.changes.close();
        await workflow.changes.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: WorkEvidencePage(repository: viewer, workflowSource: workflow),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Evidence: Submitted'), findsOneWidget);
      expect(find.text('Evidence: Overdue'), findsNothing);
      server.status = 'more_evidence_required';
      final refresh = find.text('Refresh verification status');
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(find.text('Evidence: More Evidence Required'), findsOneWidget);
      expect(find.text('Evidence: Overdue'), findsNothing);
      expect(
        viewer.assignment!.verificationStatus,
        WorkVerificationStatus.notSubmitted,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'initial due uses actual UTC checkout plus 24 hours, never scheduled end',
    () {
      final fields = checkedOut()..['scheduled_end'] = '2099-01-01T00:00:00Z';
      final timing = EvidenceDeadline.fromAssignment(
        workerRow(fields),
        now: checkout,
      );
      expect(timing.dueAt, DateTime.utc(2027, 1, 1, 15, 30));
      expect(timing.state, EvidenceDeadlineState.notYetDue);
      fields['check_out_at'] = '2026-12-31T23:30:00+08:00';
      expect(
        EvidenceDeadline.fromAssignment(workerRow(fields), now: checkout).dueAt,
        timing.dueAt,
      );
    },
  );

  for (final (elapsed, expected) in [
    (
      const Duration(hours: 19, minutes: 59, seconds: 59),
      EvidenceDeadlineState.notYetDue,
    ),
    (const Duration(hours: 20), EvidenceDeadlineState.dueSoon),
    (
      const Duration(hours: 23, minutes: 59, seconds: 59),
      EvidenceDeadlineState.dueSoon,
    ),
    (const Duration(hours: 24), EvidenceDeadlineState.overdue),
    (const Duration(hours: 24, microseconds: 1), EvidenceDeadlineState.overdue),
    (const Duration(days: 100), EvidenceDeadlineState.overdue),
  ]) {
    test('deadline boundary at $elapsed is $expected', () {
      expect(
        EvidenceDeadline.fromAssignment(
          workerRow(),
          now: checkout.add(elapsed),
        ).state,
        expected,
      );
    });
  }

  test(
    'missing or contradictory attendance never falls back to scheduled end',
    () {
      for (final fields in [
        checkedOut()..['check_out_at'] = null,
        checkedOut()..['check_in_at'] = null,
        checkedOut()
          ..['check_in_at'] = checkout
              .add(const Duration(hours: 1))
              .toIso8601String(),
      ]) {
        final timing = EvidenceDeadline.fromAssignment(
          workerRow(fields),
          now: checkout.add(const Duration(days: 4)),
        );
        expect(timing.state, EvidenceDeadlineState.unavailable);
        expect(timing.dueAt, isNull);
      }
      final clockBehind = EvidenceDeadline.fromAssignment(
        workerRow(),
        now: checkout.subtract(const Duration(seconds: 1)),
      );
      expect(clockBehind.state, EvidenceDeadlineState.unavailable);
      expect(clockBehind.dueAt, checkout.add(const Duration(hours: 24)));
      expect(
        EvidenceDeadline.fromAssignment(
          workerRow(assignment()),
          now: checkout,
        ).state,
        EvidenceDeadlineState.notStarted,
      );
    },
  );

  for (final (status, expected) in [
    ('pending_review', EvidenceDeadlineState.submitted),
    ('more_evidence_required', EvidenceDeadlineState.moreEvidenceRequired),
    ('verified', EvidenceDeadlineState.verified),
  ]) {
    test(
      '$status takes precedence over elapsed target without inventing a new deadline',
      () {
        final fields = checkedOut()..['verification_status'] = status;
        if (status == 'verified') fields['assignment_status'] = 'completed';
        final timing = EvidenceDeadline.fromAssignment(
          workerRow(fields),
          now: checkout.add(const Duration(days: 10)),
        );
        expect(timing.state, expected);
        expect(timing.dueAt, checkout.add(const Duration(hours: 24)));
        fields['check_out_at'] = null;
        expect(
          EvidenceDeadline.fromAssignment(
            workerRow(fields),
            now: checkout,
          ).state,
          expected,
        );
      },
    );
  }

  test('cancelled/disputed/completed shifts never become overdue evidence failures', () {
    for (final status in ['cancelled', 'disputed', 'completed']) {
      final fields = checkedOut()..['assignment_status'] = status;
      expect(
        EvidenceDeadline.fromAssignment(
          workerRow(fields),
          now: checkout.add(const Duration(days: 10)),
        ).state,
        EvidenceDeadlineState.notApplicable,
      );
    }
  });

  testWidgets(
    'summary displays MYT year rollover and refreshes on minute and resume',
    (tester) async {
      var now = checkout.add(const Duration(hours: 23, minutes: 59));
      final row = workerRow();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EvidenceDeadlineSummary(assignment: row, clock: () => now),
          ),
        ),
      );
      expect(
        find.text('Suggested initial evidence due: 01/01/2027 23:30 MYT'),
        findsOneWidget,
      );
      expect(find.text('Evidence: Due soon'), findsOneWidget);
      now = checkout.add(const Duration(hours: 24));
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('Evidence: Overdue'), findsOneWidget);
      now = checkout.add(const Duration(hours: 5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Evidence: Not yet due'), findsOneWidget);
      final submitted = checkedOut()
        ..['verification_status'] = 'pending_review';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EvidenceDeadlineSummary(
              assignment: workerRow(submitted),
              clock: () => now,
            ),
          ),
        ),
      );
      expect(find.text('Evidence: Submitted'), findsOneWidget);
      expect(find.text('Evidence: Overdue'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('overdue is advisory and cannot block actual controller submission or resubmission', () async {
    expect(
      EvidenceDeadline.fromAssignment(
        workerRow(),
        now: checkout.add(const Duration(days: 4)),
      ).state,
      EvidenceDeadlineState.overdue,
    );
    final server = EvidenceServer();
    final source = WorkflowSource(server, id);
    final controller = WorkEvidenceWorkflowController(
      source,
      assignmentId: id,
      employer: false,
      ledger: WorkEvidenceWorkflowLedger(),
    );
    addTearDown(() async {
      controller.dispose();
      await source.changes.close();
    });
    for (final round in [1, 2]) {
      if (round == 2) {
        server.round = 1;
        server.status = 'more_evidence_required';
      }
      final draft = WorkEvidenceDraftController(
        session: source,
        assignmentId: id,
      )..setDescription('Late evidence round $round');
      final uploads = WorkEvidenceUploadRepository(
        UploadSource(source),
        assignmentId: id,
      );
      try {
        await draft.addFiles([file(pdf(round))]);
        await controller.load();
        expect(controller.snapshot!.canSubmit, isTrue);
        expect(await controller.submit(draft, uploads), isTrue);
        expect(server.round, round);
        expect(
          controller.snapshot!.verificationStatus,
          WorkVerificationStatus.pendingReview,
        );
      } finally {
        draft.dispose();
        uploads.dispose();
      }
    }
    expect(server.evidence, hasLength(2));
    expect(source.calls, contains('submit_work_evidence_idempotent'));
  });

  for (final employer in [false, true]) {
    testWidgets(
      '${employer ? 'employer' : 'worker'} grouped shifts keep independent timing and enabled evidence actions',
      (tester) async {
        final now = DateTime.now().toUtc();
        Map<String, dynamic> row(String shiftId, Duration ago) =>
            assignment(company: employer)
              ..['assignment_id'] = shiftId
              ..['assignment_status'] = 'awaiting_verification'
              ..['check_in_at'] = now
                  .subtract(ago + const Duration(hours: 8))
                  .toIso8601String()
              ..['check_out_at'] = now.subtract(ago).toIso8601String();
        final rows = [
          row(id, const Duration(days: 3)),
          row(other, const Duration(hours: 1)),
        ];
        final source = FakeSource()
          ..workerRead = (() async => rows)
          ..companyRead = ((_) async => rows);
        final repository = WorkAttendanceRepository(source);
        addTearDown(() async {
          repository.dispose();
          await source.changes.close();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: employer
                ? WorkVerificationPage(
                    repository: repository,
                    companyId: id,
                    loadAccess: () async =>
                        const JobAccess({'company_id': id}, null),
                  )
                : WorkAttendancePage(repository: repository),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('2 shifts'), findsOneWidget);
        final late = find.byKey(const ValueKey(id));
        final recent = find.byKey(const ValueKey(other));
        expect(
          find.descendant(of: late, matching: find.text('Evidence: Overdue')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: recent,
            matching: find.text('Evidence: Not yet due'),
          ),
          findsOneWidget,
        );
        if (employer) {
          final button = find.descendant(
            of: late,
            matching: find.widgetWithText(FilledButton, 'View Evidence'),
          );
          expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
        } else {
          final button = find.descendant(
            of: late,
            matching: find.widgetWithText(OutlinedButton, 'Submit Evidence'),
          );
          expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
        }
        expect(source.checkIns, 0);
        expect(source.checkOuts, 0);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final width in [320.0, 840.0, 1440.0]) {
    testWidgets('advisory deadline fits $width with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: EvidenceDeadlineSummary(
                assignment: workerRow(),
                clock: () => checkout.add(const Duration(days: 2)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Evidence: Overdue'), findsOneWidget);
      expect(find.textContaining('does not block submission'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
