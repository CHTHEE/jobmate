import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_pages.dart';
import 'package:jobmate/features/work_attendance/work_evidence_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, evidenceRow, id, other;

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
      for (final text in [
        'Server job',
        'Submission round 2',
        'Submission round 1',
        'Server evidence',
        'Earlier description',
        'file.pdf',
        'photo.png',
        'File type: application/pdf',
        'File type: image/png',
        'Submitted by the assigned worker',
        'Submitted at: 05/11/2026 10:00 MYT',
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
      expect(find.text('Submission round 2'), findsOneWidget);
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
