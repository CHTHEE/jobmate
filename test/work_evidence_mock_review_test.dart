import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_mock_review.dart';
import 'package:jobmate/features/work_attendance/work_evidence_pages.dart';
import 'package:jobmate/features/work_attendance/work_evidence_repository.dart';

import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, evidenceRow, id, other;

void main() {
  late FakeSource source;
  late WorkAttendanceRepository attendance;
  late WorkEvidenceRepository viewer;
  late MockWorkEvidenceReviewOperations operations;
  late Map<String, dynamic> row;

  setUp(() {
    source = FakeSource();
    row = assignment(company: true)
      ..['assignment_status'] = 'awaiting_verification'
      ..['verification_status'] = 'pending_review'
      ..['check_in_at'] = '2026-11-05T01:00:00Z'
      ..['check_out_at'] = '2026-11-05T09:00:00Z';
    source.companyRead = (_) async => [row];
    source.evidenceRead = (_) async => [evidenceRow()];
    attendance = WorkAttendanceRepository(source);
    viewer = WorkEvidenceRepository.employer(
      attendance,
      assignmentId: id,
      companyId: other,
      loadCompanyAccess: () async =>
          const JobAccess({'company_id': other}, null),
    );
    operations = MockWorkEvidenceReviewOperations();
  });
  tearDown(() async {
    viewer.dispose();
    attendance.dispose();
    await source.changes.close();
  });

  Future<void> show(WidgetTester tester, {bool inject = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorkEvidencePage(
          repository: viewer,
          mockReviewOperations: inject ? operations : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, String action) async {
    await tester.ensureVisible(find.text(action));
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  testWidgets('default viewer remains read only despite eligible metadata', (
    tester,
  ) async {
    await show(tester, inject: false);
    expect(find.text('Request More Evidence'), findsNothing);
    expect(find.text('Verify'), findsNothing);
    expect(operations.calls, isEmpty);
  });

  testWidgets(
    'injected employer mode shows explicit simulation and confirms verify',
    (tester) async {
      await show(tester);
      expect(find.text('MOCK employer evidence review'), findsOneWidget);
      expect(find.textContaining('No review RPCs are called'), findsOneWidget);
      final readCalls = source.calls;
      await open(tester, 'Verify');
      expect(operations.calls, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(operations.calls, isEmpty);
      await open(tester, 'Verify');
      await tester.tap(find.text('Confirm mock verification'));
      await tester.pumpAndSettle();
      expect(operations.calls.single, (
        MockWorkEvidenceReviewAction.verify,
        id,
        null,
      ));
      expect(
        find.text(
          'Mock verification succeeded. Real assignment and database state are unchanged.',
        ),
        findsOneWidget,
      );
      expect(row['verification_status'], 'pending_review');
      expect(row['assignment_status'], 'awaiting_verification');
      expect(source.calls, readCalls); // No fabricated mutation or refresh.
      expect(source.checkIns + source.checkOuts, 0);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Verify'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'request requires valid reason and sends only trimmed text after confirmation',
    (tester) async {
      await show(tester);
      await open(tester, 'Request More Evidence');
      final confirm = find.widgetWithText(FilledButton, 'Confirm mock request');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('mock-review-reason')),
        '   ',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('mock-review-reason')),
        List.filled(1001, 'x').join(),
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('mock-review-reason')),
        '  Please clarify the completed tasks.  ',
      );
      await tester.pump();
      expect(operations.calls, isEmpty);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(operations.calls.single, (
        MockWorkEvidenceReviewAction.requestMore,
        id,
        'Please clarify the completed tasks.',
      ));
      expect(
        find.text(
          'Mock evidence request succeeded. Real assignment and database state are unchanged.',
        ),
        findsOneWidget,
      );
      expect(viewer.assignment!.verificationStatus.name, 'pendingReview');
    },
  );

  testWidgets(
    'loading prevents duplicate actions, failure allows reconfirmed retry',
    (tester) async {
      operations = MockWorkEvidenceReviewOperations(
        outcomes: [false, true],
        delay: const Duration(seconds: 1),
      );
      await show(tester);
      await open(tester, 'Verify');
      await tester.tap(find.text('Confirm mock verification'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Simulating review...'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Verify'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Request More Evidence'),
            )
            .onPressed,
        isNull,
      );
      expect(operations.calls, hasLength(1));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(
        find.text(
          'Mock review failed. No database changes were made. Try again.',
        ),
        findsOneWidget,
      );
      await open(tester, 'Verify');
      expect(operations.calls, hasLength(1));
      await tester.tap(find.text('Confirm mock verification'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(operations.calls, hasLength(2));
    },
  );

  for (final status in [
    'not_submitted',
    'more_evidence_required',
    'verified',
    'disputed',
  ]) {
    testWidgets('$status assignments expose no mock review controls', (
      tester,
    ) async {
      row['verification_status'] = status;
      await show(tester);
      expect(find.text('Request More Evidence'), findsNothing);
      expect(find.text('Verify'), findsNothing);
      expect(operations.calls, isEmpty);
    });
  }

  testWidgets('wrong assignment status and missing evidence hide controls', (
    tester,
  ) async {
    row['assignment_status'] = 'active';
    await show(tester);
    expect(find.text('Request More Evidence'), findsNothing);
    row['assignment_status'] = 'awaiting_verification';
    source.evidenceRead = (_) async => [];
    await viewer.load();
    await tester.pumpAndSettle();
    expect(find.text('Request More Evidence'), findsNothing);
    expect(find.text('Verify'), findsNothing);
  });

  testWidgets(
    'verify needs completed ordered attendance while request follows its own SQL gate',
    (tester) async {
      row['check_out_at'] = null;
      await show(tester);
      expect(find.text('Request More Evidence'), findsOneWidget);
      expect(find.text('Verify'), findsNothing);
      row['check_out_at'] = '2026-11-05T00:00:00Z';
      await viewer.load();
      await tester.pumpAndSettle();
      expect(find.text('Verify'), findsNothing);
    },
  );

  testWidgets('worker viewer cannot expose injected employer controls', (
    tester,
  ) async {
    viewer.dispose();
    viewer = WorkEvidenceRepository.worker(attendance, assignmentId: id);
    source.workerRead = () async => [
      assignment()
        ..['assignment_status'] = 'awaiting_verification'
        ..['verification_status'] = 'pending_review',
    ];
    await show(tester);
    expect(find.text('Request More Evidence'), findsNothing);
    expect(find.text('Verify'), findsNothing);
    expect(find.text('Prepare local evidence draft'), findsOneWidget);
  });

  testWidgets('company authorization denial exposes no mock review actions', (
    tester,
  ) async {
    viewer.dispose();
    viewer = WorkEvidenceRepository.employer(
      attendance,
      assignmentId: id,
      companyId: other,
      loadCompanyAccess: () async => const JobAccess(null, 'Denied'),
    );
    await show(tester);
    expect(find.text('Evidence access denied'), findsOneWidget);
    expect(find.text('Request More Evidence'), findsNothing);
    expect(operations.calls, isEmpty);
  });

  testWidgets(
    'account change during confirmation hides reason and prevents dispatch',
    (tester) async {
      await show(tester);
      await open(tester, 'Request More Evidence');
      await tester.enterText(
        find.byKey(const ValueKey('mock-review-reason')),
        'Private synthetic reason',
      );
      source.switchAccount(null);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mock-review-reason')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm mock request'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(operations.calls, isEmpty);
    },
  );

  testWidgets('logout during fake operation cannot publish stale success', (
    tester,
  ) async {
    operations = MockWorkEvidenceReviewOperations(
      delay: const Duration(seconds: 1),
    );
    await show(tester);
    await open(tester, 'Verify');
    await tester.tap(find.text('Confirm mock verification'));
    await tester.pump(const Duration(milliseconds: 350));
    source.switchAccount(null);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Mock verification succeeded'), findsNothing);
    expect(find.text('Sign in required'), findsOneWidget);
    expect(operations.calls, hasLength(1));
  });

  testWidgets(
    'narrow enlarged-text layout supports confirmation and cancellation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: WorkEvidencePage(
            repository: viewer,
            mockReviewOperations: operations,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await open(tester, 'Request More Evidence');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(operations.calls, isEmpty);
    },
  );
}
