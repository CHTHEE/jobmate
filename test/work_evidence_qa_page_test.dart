import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_draft_controller.dart';
import 'package:jobmate/features/work_attendance/work_evidence_pages.dart';
import 'package:jobmate/features/work_attendance/work_evidence_qa_page.dart';
import 'package:jobmate/features/work_attendance/work_evidence_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_submission_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_upload_repository.dart';

import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, id, other;
import 'work_evidence_draft_controller_test.dart'
    show FakeDraftSession, file, pdf;
import 'work_evidence_submission_repository_test.dart'
    show FakeSubmissionSource, FakeSubmissionReads;
import 'work_evidence_upload_repository_test.dart' show FakeUploadSource;

void main() {
  late FakeSource attendanceSource;
  late WorkAttendanceRepository attendance;
  late WorkEvidenceRepository viewer;
  late FakeDraftSession auth;
  late WorkEvidenceDraftController draft;
  late FakeUploadSource storage;
  late FakeSubmissionSource transport;
  late FakeSubmissionReads reads;
  late WorkEvidenceUploadRepository uploads;
  late WorkEvidenceSubmissionRepository submissions;
  late WorkEvidenceQaDependencies dependencies;
  late WorkEvidenceQaSession qaSession;
  late Map<String, dynamic> shift;
  late List<Map<String, dynamic>> evidence;

  setUp(() async {
    attendanceSource = FakeSource();
    shift = assignment()
      ..['assignment_id'] = supervisedWorkEvidenceQaAssignment
      ..['assignment_status'] = 'awaiting_verification'
      ..['verification_status'] = 'not_submitted'
      ..['check_in_at'] = '2026-11-05T01:00:00Z'
      ..['check_out_at'] = '2026-11-05T09:00:00Z';
    evidence = [];
    attendanceSource.workerRead = () async => [shift];
    attendanceSource.evidenceRead = (_) async => evidence;
    attendance = WorkAttendanceRepository(attendanceSource);
    viewer = WorkEvidenceRepository.worker(
      attendance,
      assignmentId: supervisedWorkEvidenceQaAssignment,
    );
    await viewer.load();
    auth = FakeDraftSession()..userId = id;
    draft = WorkEvidenceDraftController(
      session: auth,
      assignmentId: supervisedWorkEvidenceQaAssignment,
      pickFiles: () async => [file(pdf())],
    );
    draft.setDescription('QA completed shift');
    await draft.addFiles([file(pdf())]);
    storage = FakeUploadSource()..userId = id;
    uploads = WorkEvidenceUploadRepository(
      storage,
      assignmentId: supervisedWorkEvidenceQaAssignment,
    );
    transport = FakeSubmissionSource()..userId = id;
    reads = FakeSubmissionReads(transport);
    reads.assignments = () async =>
        WorkEvidenceReconciliationRead([shift], total: 1);
    reads.evidence = (_) async =>
        WorkEvidenceReconciliationRead(evidence, total: evidence.length);
    submissions = WorkEvidenceSubmissionRepository(
      transport,
      uploads: uploads,
      ledger: WorkEvidenceSubmissionLedger(),
      reads: reads,
    );
    qaSession = WorkEvidenceQaSession();
    dependencies = WorkEvidenceQaDependencies(
      draft: draft,
      uploads: uploads,
      submissions: submissions,
      session: qaSession,
    );
    transport.response = () async {
      shift['verification_status'] = 'pending_review';
      evidence = [
        {
          'evidence_id': other,
          'submission_round': 1,
          'description': 'QA completed shift',
          'storage_path': uploads.uploadedPaths.single,
          'file_name': uploads.uploadedPaths.single.split('/').last,
          'mime_type': 'application/pdf',
          'submitted_by': id,
          'submitted_at': '2026-11-05T10:00:00Z',
        },
      ];
      return 1;
    };
  });
  tearDown(() async {
    // Page owns dependencies when shown; these remaining resources are caller-owned.
    dependencies.dispose();
    draft.dispose();
    viewer.dispose();
    attendance.dispose();
    await attendanceSource.changes.close();
    await auth.changes.close();
    await storage.changes.close();
    await transport.changes.close();
  });
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkEvidenceQaPage(
            viewer: viewer,
            draft: draft,
            dependencies: dependencies,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(
    WidgetTester tester,
    String label, {
    bool settle = true,
  }) async {
    final button = find.text(label);
    await tester.ensureVisible(button);
    await tester.tap(button);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> arm(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
  }

  Future<void> upload(WidgetTester tester) async {
    await arm(tester);
    await press(tester, 'Upload real QA evidence');
    expect(storage.uploads, isEmpty);
    await press(tester, 'Confirm real action');
  }

  bool enabled(WidgetTester tester, String label) =>
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, label))
          .onPressed !=
      null;

  testWidgets(
    'two confirmations, explicit arming, real-adapter interfaces with fakes, authoritative refresh',
    (tester) async {
      await show(tester);
      expect(enabled(tester, 'Upload real QA evidence'), isFalse);
      expect(enabled(tester, 'Submit Evidence'), isFalse);
      expect(transport.calls, isEmpty);
      await upload(tester);
      expect(storage.uploads, hasLength(1));
      expect(transport.calls, isEmpty);
      expect(
        find.text(
          'Real upload batch confirmed. Evidence has not been submitted.',
        ),
        findsOneWidget,
      );
      await press(tester, 'Submit QA evidence once');
      expect(transport.calls, isEmpty);
      await press(tester, 'Confirm real action');
      expect(transport.calls, hasLength(1));
      expect(transport.calls.single.$1, supervisedWorkEvidenceQaAssignment);
      expect(transport.calls.single.$3, uploads.uploadedPaths);
      expect(viewer.assignment!.verificationStatus.name, 'pendingReview');
      expect(viewer.evidence.single.submissionRound, 1);
      expect(find.textContaining('QA session complete.'), findsOneWidget);
      expect(enabled(tester, 'Submit QA evidence once'), isFalse);
    },
  );
  testWidgets('cancelling either confirmation never dispatches that action', (
    tester,
  ) async {
    await show(tester);
    await arm(tester);
    await press(tester, 'Upload real QA evidence');
    await press(tester, 'Cancel');
    expect(storage.uploads, isEmpty);
    await press(tester, 'Upload real QA evidence');
    await press(tester, 'Confirm real action');
    await press(tester, 'Submit QA evidence once');
    await press(tester, 'Cancel');
    expect(transport.calls, isEmpty);
    expect(enabled(tester, 'Submit QA evidence once'), isTrue);
  });
  testWidgets(
    'duplicate uploads disabled and no automatic retry after partial/uncertain failure',
    (tester) async {
      final pending = Completer<void>();
      storage.onUpload = (_, _, _) => pending.future;
      await show(tester);
      await arm(tester);
      await press(tester, 'Upload real QA evidence');
      await press(tester, 'Confirm real action', settle: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(storage.uploads, hasLength(1));
      expect(enabled(tester, 'Upload real QA evidence'), isFalse);
      pending.completeError(TimeoutException('lost'));
      await tester.pumpAndSettle();
      expect(find.textContaining('QA session blocked.'), findsOneWidget);
      expect(enabled(tester, 'Upload real QA evidence'), isFalse);
      expect(enabled(tester, 'Submit QA evidence once'), isFalse);
      expect(storage.uploads, hasLength(1));
    },
  );
  testWidgets(
    'duplicate submissions disabled; ambiguous result stays blocked after read-only reconciliation',
    (tester) async {
      final pending = Completer<int>();
      transport.response = () => pending.future;
      await show(tester);
      await upload(tester);
      await press(tester, 'Submit QA evidence once');
      await press(tester, 'Confirm real action', settle: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(transport.calls, hasLength(1));
      expect(enabled(tester, 'Submit QA evidence once'), isFalse);
      pending.completeError(TimeoutException('lost'));
      await tester.pumpAndSettle();
      expect(find.textContaining('QA session blocked.'), findsOneWidget);
      expect(
        find.textContaining('manual investigation is required.'),
        findsWidgets,
      );
      expect(transport.calls, hasLength(1));
      expect(enabled(tester, 'Submit QA evidence once'), isFalse);
    },
  );
  testWidgets(
    'lost response with matching authoritative evidence confirms commit but never reopens writes',
    (tester) async {
      final commit = transport.response;
      transport.response = () async {
        await commit();
        throw TimeoutException('lost');
      };
      await show(tester);
      await upload(tester);
      await press(tester, 'Submit QA evidence once');
      await press(tester, 'Confirm real action');
      expect(
        find.textContaining('Fresh evidence confirms submission round 1.'),
        findsOneWidget,
      );
      expect(find.textContaining('QA session blocked.'), findsOneWidget);
      expect(enabled(tester, 'Submit QA evidence once'), isFalse);
      expect(transport.calls, hasLength(1));
    },
  );
  testWidgets(
    'fresh eligibility revoked before submission prevents RPC and blocks session',
    (tester) async {
      await show(tester);
      await upload(tester);
      shift['verification_status'] = 'pending_review';
      await press(tester, 'Submit QA evidence once');
      await press(tester, 'Confirm real action');
      expect(transport.calls, isEmpty);
      expect(find.textContaining('No submission was sent.'), findsOneWidget);
      expect(enabled(tester, 'Submit QA evidence once'), isFalse);
    },
  );
  testWidgets('account change during confirmation prevents upload', (
    tester,
  ) async {
    await show(tester);
    await arm(tester);
    await press(tester, 'Upload real QA evidence');
    auth.account(null);
    await tester.pump();
    await press(tester, 'Confirm real action');
    expect(storage.uploads, isEmpty);
    expect(transport.calls, isEmpty);
    expect(
      find.text('Account or assignment changed. Close this QA form.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'draft mutation invalidates confirmed batch without sending submission',
    (tester) async {
      await show(tester);
      await upload(tester);
      draft.setDescription('Changed');
      await tester.pumpAndSettle();
      expect(find.textContaining('QA session blocked.'), findsOneWidget);
      expect(transport.calls, isEmpty);
    },
  );
  testWidgets('definite server rejection remains blocked in QA mode', (
    tester,
  ) async {
    transport.response = () async =>
        throw const WorkEvidenceSubmissionRejected(false);
    await show(tester);
    await upload(tester);
    await press(tester, 'Submit QA evidence once');
    await press(tester, 'Confirm real action');
    expect(find.textContaining('QA session blocked.'), findsOneWidget);
    expect(enabled(tester, 'Submit QA evidence once'), isFalse);
    expect(transport.calls, hasLength(1));
  });
  testWidgets('failed reconciliation never unlocks the QA attempt', (
    tester,
  ) async {
    transport.response = () async => throw TimeoutException('lost');
    reads.evidence = (_) async => throw StateError('fake read failure');
    await show(tester);
    await upload(tester);
    await press(tester, 'Submit QA evidence once');
    await press(tester, 'Confirm real action');
    expect(find.textContaining('QA session blocked.'), findsOneWidget);
    expect(enabled(tester, 'Submit QA evidence once'), isFalse);
    expect(transport.calls, hasLength(1));
  });
  testWidgets(
    'partial upload preserves confirmed object without retrying failed file',
    (tester) async {
      await draft.addFiles([file(pdf(2), name: 'second.pdf')]);
      storage.onUpload = (_, _, _) async {
        if (storage.uploads.length == 2) throw TimeoutException('lost');
      };
      await show(tester);
      await upload(tester);
      expect(storage.uploads, hasLength(2));
      expect(uploads.uploadedPaths, hasLength(1));
      expect(find.textContaining('QA session blocked.'), findsOneWidget);
      expect(enabled(tester, 'Upload real QA evidence'), isFalse);
      expect(transport.calls, isEmpty);
    },
  );
  testWidgets(
    'narrow layout with enlarged text keeps confirmations reachable',
    (tester) async {
      tester.view.physicalSize = const Size(360, 850);
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
          home: Scaffold(
            body: WorkEvidenceQaPage(
              viewer: viewer,
              draft: draft,
              dependencies: dependencies,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await arm(tester);
      await press(tester, 'Upload real QA evidence');
      await press(tester, 'Cancel');
      expect(tester.takeException(), isNull);
      expect(storage.uploads, isEmpty);
    },
  );
  testWidgets(
    'running-session gate survives form recreation without another upload',
    (tester) async {
      await show(tester);
      await upload(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final nextUploads = WorkEvidenceUploadRepository(
        storage,
        assignmentId: supervisedWorkEvidenceQaAssignment,
      );
      final nextSubmissions = WorkEvidenceSubmissionRepository(
        transport,
        uploads: nextUploads,
        ledger: WorkEvidenceSubmissionLedger(),
      );
      dependencies = WorkEvidenceQaDependencies(
        draft: draft,
        uploads: nextUploads,
        submissions: nextSubmissions,
        session: qaSession,
      );
      await show(tester);
      expect(find.textContaining('QA session blocked.'), findsOneWidget);
      expect(enabled(tester, 'Upload real QA evidence'), isFalse);
      expect(storage.uploads, hasLength(1));
    },
  );
  testWidgets(
    'normal assignment has no QA entry, QA worker opens only injected dependencies',
    (tester) async {
      final otherViewer = WorkEvidenceRepository.worker(
        attendance,
        assignmentId: id,
      );
      await tester.pumpWidget(
        MaterialApp(home: WorkEvidencePage(repository: otherViewer)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Open supervised real QA submission'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkEvidencePage(
            repository: viewer,
            createQaDependencies: (local) {
              final u = WorkEvidenceUploadRepository(
                storage,
                assignmentId: supervisedWorkEvidenceQaAssignment,
              );
              return WorkEvidenceQaDependencies(
                draft: local,
                uploads: u,
                submissions: WorkEvidenceSubmissionRepository(
                  transport,
                  uploads: u,
                  ledger: WorkEvidenceSubmissionLedger(),
                ),
                session: qaSession,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await press(tester, 'Open supervised real QA submission');
      expect(find.text('SUPERVISED QA — REAL BACKEND'), findsOneWidget);
      expect(enabled(tester, 'Submit Evidence'), isFalse);
      expect(storage.uploads, isEmpty);
      otherViewer.dispose();
      dependencies.dispose(); // The directly constructed unused fixture.
    },
  );
}
