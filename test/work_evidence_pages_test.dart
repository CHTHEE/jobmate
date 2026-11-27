import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_pages.dart';
import 'package:jobmate/features/work_attendance/work_evidence_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_workflow.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, evidenceRow, id, other;
import 'work_attendance_resolution_test.dart' show resolutionContext, auditFor;

class _ReadOnlyMissedWorkflow implements WorkEvidenceWorkflowSource {
  _ReadOnlyMissedWorkflow(this.source, {this.employer = false});
  final FakeSource source;
  final bool employer;
  final calls = <String>[];
  @override
  String? get userId => source.userId;
  @override
  Stream<String?> get accountChanges => source.accountChanges;
  @override
  Future<Object?> call(String rpc, Map<String, dynamic> parameters) async {
    calls.add(rpc);
    if (rpc != 'work_evidence_workflow_context') {
      throw StateError('Unexpected write');
    }
    return {
      'contract_version': 1,
      'assignment_id': id,
      'viewer_role': employer ? 'employer' : 'worker',
      'latest_round': 0,
      'assignment_status': 'scheduled',
      'verification_status': 'not_submitted',
      'attendance_complete': false,
      'attempts': [],
      'history': [],
      'review': null,
    };
  }
}

void main() {
  late FakeSource source;
  late WorkAttendanceRepository attendance;
  late WorkEvidenceRepository viewer;
  setUp(() {
    source = FakeSource();
    attendance = WorkAttendanceRepository(source);
    viewer = WorkEvidenceRepository.worker(attendance, assignmentId: id);
  });
  tearDown(() async {
    viewer.dispose();
    attendance.dispose();
    await source.changes.close();
  });
  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(home: WorkEvidencePage(repository: viewer)),
  );

  for (final width in [320.0, 1200.0]) {
    testWidgets('upcoming worker details disclose history at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      source.workerRead = () async => [
        assignment()
          ..['attendance_as_of'] = '2026-11-04T22:00:00Z'
          ..['workplace_latitude'] = 3.117
          ..['workplace_longitude'] = 101.677,
      ];
      source.evidenceRead = (_) async => [];
      final workflow = _ReadOnlyMissedWorkflow(source);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkEvidencePage(repository: viewer, workflowSource: workflow),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shift details'), findsWidgets);
      for (final label in [
        'Server job',
        'Server company',
        'Upcoming / Scheduled',
        'Date: Thursday, 5 November 2026',
        'Time: 9:00 AM – 5:00 PM MYT',
        'Workplace: Server location',
        'View workplace on map',
        'Check-in is not available yet.',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.textContaining('No submission is due yet'), findsOneWidget);
      for (final label in [
        'Check-in: Not recorded',
        'Checkout: Not recorded',
        'View original attendance & audit',
        'Technical details',
        'Latest submission round: 0',
        'No verification events recorded yet.',
        'No work evidence',
        'Submit work evidence',
      ]) {
        expect(find.text(label), findsNothing);
      }
      Future<void> expand(String label) async {
        final tile = find.text(label);
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
      }

      await expand('Attendance & verification history');
      expect(find.text('No verification events recorded yet.'), findsOneWidget);
      expect(find.text('No attendance events recorded yet.'), findsOneWidget);
      expect(find.text('Technical details'), findsNothing);
      expect(find.text('View original attendance & audit'), findsNothing);
      expect(find.textContaining(id), findsNothing);
      expect(find.textContaining('server snapshot'), findsNothing);
      expect(workflow.calls, ['work_evidence_workflow_context']);
      expect(tester.takeException(), isNull);
    });
  }

  for (final employer in [false, true]) {
    testWidgets(
      'friendly filenames across latest and earlier rounds employer=$employer',
      (tester) async {
        if (employer) {
          viewer.dispose();
          viewer = WorkEvidenceRepository.employer(
            attendance,
            assignmentId: id,
            companyId: other,
            loadCompanyAccess: () async =>
                const JobAccess({'company_id': other}, null),
          );
          source.companyRead = (_) async => [
            assignment(company: true)
              ..['assignment_status'] = 'awaiting_verification'
              ..['verification_status'] = 'pending_review',
          ];
        }
        source.evidenceRead = (_) async => [
          evidenceRow()..['file_name'] = '$id.pdf',
          evidenceRow()
            ..['evidence_id'] = other
            ..['file_name'] = 'Site report.pdf',
          evidenceRow()
            ..['submission_round'] = 1
            ..['file_name'] = '$other.png'
            ..['mime_type'] = 'image/png',
          evidenceRow()
            ..['submission_round'] = 1
            ..['evidence_id'] = other
            ..['file_name'] = 'Work photo.png'
            ..['mime_type'] = 'image/png',
        ];
        await show(tester);
        await tester.pumpAndSettle();
        expect(find.text('Evidence PDF 1'), findsOneWidget);
        expect(find.text('Site report.pdf'), findsOneWidget);
        await tester.ensureVisible(find.text('Earlier submissions (1)'));
        await tester.tap(find.text('Earlier submissions (1)'));
        await tester.pumpAndSettle();
        expect(find.text('Evidence Image 1'), findsOneWidget);
        expect(find.text('Work photo.png'), findsOneWidget);
        expect(find.text('$id.pdf'), findsNothing);
        expect(find.text('$other.png'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('missed server lifecycle never becomes Scheduled in workflow', (
    tester,
  ) async {
    source.workerRead = () async => [
      assignment()..['attendance_as_of'] = '2026-11-07T12:00:00Z',
    ];
    source.evidenceRead = (_) async => [];
    final workflow = _ReadOnlyMissedWorkflow(source);
    await tester.pumpWidget(
      MaterialApp(
        home: WorkEvidencePage(repository: viewer, workflowSource: workflow),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Missed Attendance'), findsOneWidget);
    expect(find.text('Scheduled'), findsNothing);
    expect(find.text('Your next shift'), findsNothing);
    expect(
      find.textContaining('No evidence submission is due'),
      findsOneWidget,
    );
    expect(find.text('Submit work evidence'), findsNothing);
    expect(workflow.calls, ['work_evidence_workflow_context']);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets(
      'employer upcoming details show one evidence message at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        viewer.dispose();
        viewer = WorkEvidenceRepository.employer(
          attendance,
          assignmentId: id,
          companyId: other,
          loadCompanyAccess: () async =>
              const JobAccess({'company_id': other}, null),
        );
        source.companyRead = (_) async => [
          assignment(company: true)
            ..['attendance_as_of'] = '2026-11-04T22:00:00Z'
            ..['workplace_latitude'] = width == 320 ? 3.117 : null
            ..['workplace_longitude'] = width == 320 ? 101.677 : null,
        ];
        source.evidenceRead = (_) async =>
            throw StateError('Evidence requires submission');
        final workflow = _ReadOnlyMissedWorkflow(source, employer: true);
        await tester.pumpWidget(
          MaterialApp(
            home: WorkEvidencePage(
              repository: viewer,
              loadWorkerName: (_, _) async => 'Actual worker',
              workflowSource: workflow,
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in [
          'Server job',
          'Worker: Actual worker',
          'Upcoming / Scheduled',
          'Date: Thursday, 5 November 2026',
          'Time: 9:00 AM – 5:00 PM MYT',
          'Workplace: Server location',
          'Awaiting scheduled shift.',
          'Evidence and verification',
          'Evidence submission follows completed attendance. No submission is due yet.',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('Shift details'), findsWidgets);
        expect(
          find.text('View workplace on map'),
          width == 320 ? findsOneWidget : findsNothing,
        );
        for (final label in [
          'Check-in: Not recorded',
          'Checkout: Not recorded',
          'Verification: Not submitted',
          'Latest submission round: 0',
          'No verification events recorded yet.',
          'No evidence submitted yet',
          'View attendance GPS',
          'Technical details',
        ]) {
          expect(find.text(label), findsNothing);
        }
        expect(workflow.calls, ['work_evidence_workflow_context']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'unsafe filename metadata uses friendly fallback without path or token',
    (tester) async {
      source.evidenceRead = (_) async => [
        evidenceRow()..['file_name'] = '$id/private.pdf?token=secret',
      ];
      await show(tester);
      await tester.pumpAndSettle();
      expect(find.text('Evidence PDF 1'), findsOneWidget);
      expect(find.textContaining('token='), findsNothing);
      expect(find.textContaining('$id/'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final corrected in [false, true]) {
    testWidgets(
      'worker evidence retains resolution audit corrected=$corrected',
      (tester) async {
        final audit = auditFor({
          'p_request_id': other,
          'p_decision': corrected ? 'corrected' : 'confirmed_absent',
          'p_reason': 'Actual reviewed resolution',
          'p_check_in_at': corrected ? '2026-11-05T01:10:00Z' : null,
          'p_check_out_at': corrected ? '2026-11-05T08:00:00Z' : null,
        });
        source.workerRead = () async => [
          assignment()
            ..['assignment_status'] = corrected
                ? 'awaiting_verification'
                : 'scheduled'
            ..['check_in_at'] = corrected ? '2026-11-05T01:00:00Z' : null
            ..['attendance_as_of'] = '2026-11-07T12:00:00Z'
            ..['attendance_resolution'] = resolutionContext(resolution: audit),
        ];
        source.evidenceRead = (_) async => [];
        await show(tester);
        await tester.pumpAndSettle();
        expect(
          find.text(corrected ? 'Corrected Attendance' : 'Confirmed Absent'),
          findsOneWidget,
        );
        expect(find.text('View original attendance & audit'), findsNothing);
        expect(find.text('Actual reviewed resolution'), findsOneWidget);
        expect(find.textContaining('Resolved by employer:'), findsOneWidget);
        if (!corrected) {
          expect(
            find.textContaining('No evidence submission is required'),
            findsOneWidget,
          );
          expect(find.text('Submit work evidence'), findsNothing);
        }
        final history = find.text('Attendance & verification history');
        await tester.ensureVisible(history);
        await tester.tap(history);
        await tester.pumpAndSettle();
        expect(find.text('Actual reviewed resolution'), findsOneWidget);
        expect(find.textContaining('Resolved by employer:'), findsOneWidget);
        expect(find.textContaining(other), findsNothing);
        if (corrected) {
          expect(find.text('9:10 AM'), findsOneWidget);
          expect(find.text('4:00 PM'), findsOneWidget);
          expect(find.text('Employer-corrected'), findsNWidgets(2));
          expect(find.text('Corrected · On Time'), findsOneWidget);
          expect(
            find.text('Corrected duration: 6 hours 50 minutes'),
            findsOneWidget,
          );
          expect(find.textContaining('Original check-in:'), findsOneWidget);
        }
        expect(source.checkIns, 0);
        expect(source.checkOuts, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets(
      'employer confirmed absence does not request evidence at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        viewer.dispose();
        viewer = WorkEvidenceRepository.employer(
          attendance,
          assignmentId: id,
          companyId: other,
          loadCompanyAccess: () async =>
              const JobAccess({'company_id': other}, null),
        );
        source.companyRead = (_) async => [
          assignment(company: true)
            ..['attendance_as_of'] = '2026-11-07T12:00:00Z'
            ..['attendance_resolution'] = resolutionContext(
              resolution: auditFor({
                'p_request_id': other,
                'p_decision': 'confirmed_absent',
                'p_reason': 'Employer confirmed the missed shift',
                'p_check_in_at': null,
                'p_check_out_at': null,
              }),
            ),
        ];
        final workflow = _ReadOnlyMissedWorkflow(source, employer: true);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(width == 390 ? 2 : 1)),
              child: child!,
            ),
            home: WorkEvidencePage(
              repository: viewer,
              workflowSource: workflow,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Confirmed Absent'), findsOneWidget);
        expect(
          find.text('Employer confirmed the missed shift'),
          findsOneWidget,
        );
        expect(
          find.textContaining('No evidence submission is required'),
          findsOneWidget,
        );
        expect(
          find.textContaining('No work or payment has been approved'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Refresh after the worker submits evidence'),
          findsNothing,
        );
        expect(find.text('Review submitted evidence'), findsNothing);
        expect(find.text('View Report'), findsNothing);
        expect(workflow.calls, ['work_evidence_workflow_context']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'employer details use actual evidence metadata and preserve corrected attendance audit',
    (tester) async {
      viewer.dispose();
      viewer = WorkEvidenceRepository.employer(
        attendance,
        assignmentId: id,
        companyId: other,
        loadCompanyAccess: () async =>
            const JobAccess({'company_id': other}, null),
      );
      final audit = auditFor({
        'p_request_id': other,
        'p_decision': 'corrected',
        'p_reason': 'Actual reviewed correction',
        'p_check_in_at': '2026-11-05T01:10:24Z',
        'p_check_out_at': '2026-11-05T08:00:00Z',
      });
      source.companyRead = (_) async => [
        assignment(company: true)
          ..['assignment_status'] = 'awaiting_verification'
          ..['verification_status'] = 'pending_review'
          ..['check_in_at'] = '2026-11-05T01:00:00Z'
          ..['check_out_at'] = null
          ..['attendance_resolution'] = resolutionContext(resolution: audit),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: WorkEvidencePage(
            repository: viewer,
            loadWorkerName: (_, _) async => 'Actual worker',
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'Worker: Actual worker',
        'Attendance correction',
        'Verification: Pending review',
        "Worker's submission note",
        'file.pdf',
        'Server evidence',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Technical details'), findsNothing);
      expect(find.textContaining(other), findsNothing);
      expect(find.text('Actual reviewed correction'), findsOneWidget);
      expect(find.text('Original checkout: Not recorded'), findsOneWidget);
      expect(find.textContaining('Corrected duration:'), findsOneWidget);
      expect(find.text('Corrected check-in'), findsOneWidget);
      expect(find.text('Corrected checkout'), findsOneWidget);
      expect(find.text('9:10:24 AM'), findsOneWidget);
      expect(find.text('Employer-corrected'), findsNWidgets(2));
      expect(find.text('Thu, 5 Nov 2026 · MYT'), findsNWidgets(2));
      expect(find.text('4:00 PM'), findsOneWidget);
      expect(find.text('Verify Work'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  final longNote = [
    List.filled(10, 'The worker completed the assigned event setup.').join(' '),
    List.filled(
      8,
      'This second paragraph describes the final checks.',
    ).join(' '),
  ].join('\n\n');
  for (final width in [320.0, 1200.0]) {
    testWidgets(
      'verified employer details fit $width with enlarged text and retain compact preview',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        viewer.dispose();
        viewer = WorkEvidenceRepository.employer(
          attendance,
          assignmentId: id,
          companyId: other,
          loadCompanyAccess: () async =>
              const JobAccess({'company_id': other}, null),
        );
        source.companyRead = (_) async => [
          assignment(company: true)
            ..['assignment_status'] = 'completed'
            ..['verification_status'] = 'verified'
            ..['check_in_at'] = '2026-11-05T01:00:00Z'
            ..['check_out_at'] = '2026-11-05T08:00:00Z'
            ..['verified_at'] = '2026-11-05T09:00:00Z',
        ];
        source.evidenceRead = (_) async => [
          evidenceRow()
            ..['file_name'] = List.filled(8, 'Long actual filename').join('-')
            ..['description'] = longNote,
          evidenceRow()
            ..['evidence_id'] = other
            ..['file_name'] = 'Work photo.png'
            ..['mime_type'] = 'image/png',
        ];
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: WorkEvidencePage(repository: viewer),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Work Verification Details'), findsWidgets);
        expect(find.text('Work Verified'), findsOneWidget);
        expect(
          find.textContaining('No further evidence submission is due.'),
          findsOneWidget,
        );
        expect(find.text('Verify Work'), findsNothing);
        expect(find.text('Device-recorded'), findsNWidgets(2));
        expect(find.text('Employer-corrected'), findsNothing);
        expect(
          find.text('Work verification does not confirm payment approval.'),
          findsOneWidget,
        );
        expect(find.text("Worker's submission note"), findsOneWidget);
        final note = tester.widget<Text>(find.text(longNote));
        expect(note.data, longNote);
        expect(note.maxLines, isNull);
        expect(find.text('Submitted by the assigned worker'), findsOneWidget);
        expect(
          find.textContaining('Submitted: Thu, 5 Nov 2026'),
          findsOneWidget,
        );
        expect(find.text('Attachments'), findsOneWidget);
        expect(find.text('Work photo.png'), findsOneWidget);
        expect(find.text('View image'), findsOneWidget);
        await tester.ensureVisible(find.text('View PDF'));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('worker evidence with an empty note still shows the attachment', (
    tester,
  ) async {
    source.evidenceRead = (_) async => [evidenceRow()..['description'] = ''];
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text("Worker's submission note"), findsNothing);
    expect(find.text('Attachments'), findsOneWidget);
    expect(find.text('file.pdf'), findsOneWidget);
    expect(find.text('View PDF'), findsOneWidget);
  });

  testWidgets(
    'loading, metadata fields, rounds and no file/mutation controls',
    (tester) async {
      final pending = Completer<List<Map<String, dynamic>>>();
      source.evidenceRead = (_) => pending.future;
      await show(tester);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete([
        evidenceRow(),
        evidenceRow()
          ..['evidence_id'] = other
          ..['submission_round'] = 1
          ..['description'] = 'Earlier description'
          ..['file_name'] = 'photo.png'
          ..['mime_type'] = 'image/png',
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Latest submission — Round 2'), findsOneWidget);
      expect(find.text('Earlier description'), findsNothing);
      await tester.ensureVisible(find.text('Earlier submissions (1)'));
      await tester.tap(find.text('Earlier submissions (1)'));
      await tester.pumpAndSettle();
      for (final text in [
        'Server job',
        'Latest submission — Round 2',
        'Submission round 1',
        'Server evidence',
        'Earlier description',
        'file.pdf',
        'photo.png',
      ]) {
        expect(find.text(text), findsWidgets);
      }
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('https://'), findsNothing);
      expect(find.text('$id/file.pdf'), findsNothing);
      expect(source.checkIns, 0);
      expect(source.checkOuts, 0);
      expect(find.text('Upload'), findsNothing);
      expect(find.text('Open file'), findsNothing);
    },
  );

  testWidgets('empty and connection error retry', (tester) async {
    source.evidenceRead = (_) async => throw Exception('offline');
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text('Unable to load evidence'), findsOneWidget);
    source.evidenceRead = (_) async => [];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No work evidence'), findsOneWidget);
  });

  testWidgets(
    'permission and expired session errors are visible without metadata',
    (tester) async {
      source.evidenceRead = (_) async =>
          throw const PostgrestException(message: 'denied', code: '42501');
      await show(tester);
      await tester.pumpAndSettle();
      expect(find.text('Evidence access denied'), findsOneWidget);
      source.evidenceRead = (_) async => throw const AuthException('expired');
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in required'), findsOneWidget);
      expect(find.text('file.pdf'), findsNothing);
    },
  );

  testWidgets(
    'account switch clears metadata and stale response; logout is isolated',
    (tester) async {
      await show(tester);
      await tester.pumpAndSettle();
      expect(find.text('file.pdf'), findsOneWidget);
      final pending = Completer<List<Map<String, dynamic>>>();
      source.evidenceRead = (_) => pending.future;
      await tester.tap(find.byTooltip('Refresh evidence'));
      await tester.pump();
      source.workerRead = () async => [];
      source.switchAccount(other);
      await tester.pumpAndSettle();
      expect(find.textContaining('Your account changed'), findsOneWidget);
      expect(find.text('file.pdf'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      pending.complete([evidenceRow()]);
      await tester.pumpAndSettle();
      expect(find.text('file.pdf'), findsNothing);
      expect(find.text('Evidence access denied'), findsOneWidget);
      source.switchAccount(null);
      await tester.pumpAndSettle();
      expect(find.text('Sign in required'), findsOneWidget);
    },
  );

  testWidgets(
    'authorized employer pre-submission state skips metadata and refreshes after submission',
    (tester) async {
      viewer.dispose();
      viewer = WorkEvidenceRepository.employer(
        attendance,
        assignmentId: id,
        companyId: other,
        loadCompanyAccess: () async =>
            const JobAccess({'company_id': other}, null),
      );
      var reads = 0;
      source.evidenceRead = (_) async {
        reads++;
        return [evidenceRow()];
      };
      await show(tester);
      await tester.pumpAndSettle();
      expect(find.text('No evidence submitted yet'), findsOneWidget);
      expect(
        find.textContaining('worker has not formally submitted evidence'),
        findsOneWidget,
      );
      expect(find.text('Evidence access denied'), findsNothing);
      expect(find.text('Server job'), findsOneWidget);
      expect(reads, 0);
      source.companyRead = (_) async => [
        assignment(company: true)..['verification_status'] = 'pending_review',
      ];
      await tester.tap(find.byTooltip('Refresh evidence'));
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(find.text('file.pdf'), findsOneWidget);
      expect(find.text('No evidence submitted yet'), findsNothing);
    },
  );

  testWidgets(
    'account and company replacement clear awaiting state and prior evidence context',
    (tester) async {
      viewer.dispose();
      viewer = WorkEvidenceRepository.employer(
        attendance,
        assignmentId: id,
        companyId: other,
        loadCompanyAccess: () async =>
            const JobAccess({'company_id': other}, null),
      );
      await show(tester);
      await tester.pumpAndSettle();
      expect(find.text('No evidence submitted yet'), findsOneWidget);
      source.switchAccount(other);
      await tester.pumpAndSettle();
      expect(find.text('No evidence submitted yet'), findsNothing);
      expect(find.textContaining('Your account changed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      viewer.dispose();
      viewer = WorkEvidenceRepository.employer(
        attendance,
        assignmentId: id,
        companyId: id,
        loadCompanyAccess: () async =>
            const JobAccess({'company_id': id}, null),
      );
      source.companyRead = (company) async {
        expect(company, id);
        return [
          assignment(company: true)..['verification_status'] = 'pending_review',
        ];
      };
      await show(tester);
      await tester.pumpAndSettle();
      expect(find.text('file.pdf'), findsOneWidget);
      expect(find.text('No evidence submitted yet'), findsNothing);
    },
  );

  testWidgets(
    'genuine employer metadata denial after submission is not an empty state',
    (tester) async {
      viewer.dispose();
      viewer = WorkEvidenceRepository.employer(
        attendance,
        assignmentId: id,
        companyId: other,
        loadCompanyAccess: () async =>
            const JobAccess({'company_id': other}, null),
      );
      source.companyRead = (_) async => [
        assignment(company: true)..['verification_status'] = 'pending_review',
      ];
      source.evidenceRead = (_) async => throw const PostgrestException(
        message: 'Not authorized to view this evidence',
        code: 'P0001',
      );
      await show(tester);
      await tester.pumpAndSettle();
      expect(find.text('Evidence access denied'), findsOneWidget);
      expect(find.text('No evidence submitted yet'), findsNothing);
      expect(find.text('No work evidence'), findsNothing);
    },
  );

  for (final width in [320.0, 840.0, 1440.0]) {
    testWidgets('metadata responsive at $width with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      source.evidenceRead = (_) async => [
        evidenceRow()
          ..['file_name'] = List.filled(16, 'long-evidence-name').join('-')
          ..['description'] = List.filled(
            20,
            'Actual submitted description.',
          ).join(' '),
      ];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: WorkEvidencePage(repository: viewer),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Latest submission — Round 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
