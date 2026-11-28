import 'dart:async';

import 'package:jobmate/features/work_attendance/employer_work_evidence_summary.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/resume_pdf_opener.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_action_indicators.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';
import 'package:jobmate/features/work_attendance/work_attendance_lifecycle.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_pages.dart';
import 'package:jobmate/features/work_attendance/work_verification_pages.dart';
import 'package:jobmate/features/work_attendance/work_evidence_preview.dart';
import 'package:jobmate/features/work_attendance/work_evidence_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_pages.dart';
import 'package:jobmate/features/work_attendance/engagement_closure_controls.dart';
import 'package:jobmate/shared/widgets/app_workspace.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';

import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, evidenceRow, id, other;
import 'work_attendance_resolution_test.dart' show resolutionContext, auditFor;
import 'work_evidence_preview_test.dart' show PreviewSource;
import 'work_assignment_creation_dialog_test.dart'
    show FakeEngagementClosureGateway;

class ReservedEvidenceWindow implements ResumePdfWindow {
  Uri? uri;
  bool closed = false;
  @override
  bool navigate(Uri value) {
    uri = value;
    return true;
  }

  @override
  void close() {
    closed = true;
  }
}

class EvidenceBrowser implements ResumePdfOpener {
  bool blocked = false;
  final windows = <ReservedEvidenceWindow>[];
  @override
  bool get isWeb => true;
  @override
  ResumePdfWindow? reserve() {
    if (blocked) return null;
    final window = ReservedEvidenceWindow();
    windows.add(window);
    return window;
  }

  @override
  Future<bool> open(Uri uri) =>
      throw StateError('Use the reserved gesture tab');
}

Map<String, dynamic> correctedRow() => {
  ...assignment(),
  'assignment_status': 'awaiting_verification',
  'check_in_at': '2026-11-05T01:00:00Z',
  'attendance_as_of': '2026-11-07T12:00:00Z',
  'attendance_resolution':
      resolutionContext(
          resolution: auditFor({
            'p_request_id': other,
            'p_decision': 'corrected',
            'p_reason': 'Authorized actual-time correction',
            'p_check_in_at': '2026-11-05T01:10:00Z',
            'p_check_out_at': '2026-11-05T08:00:00Z',
          }),
        )
        ..['original_location'] = {
          'check_in_status': 'denied',
          'check_out_status': null,
        },
};

void main() {
  test('loaded action predicates exclude review, verified, resolved and unavailable actions', () {
    WorkerWorkAssignment worker(Map<String, dynamic> changes) =>
        WorkerWorkAssignment.fromJson({...correctedRow(), ...changes});
    expect(workerShiftNeedsAction(worker({})), isTrue);
    expect(
      workerShiftNeedsAction(
        worker({'verification_status': 'more_evidence_required'}),
      ),
      isTrue,
    );
    expect(
      workerShiftNeedsAction(worker({'verification_status': 'pending_review'})),
      isFalse,
    );
    expect(
      workerShiftNeedsAction(
        worker({
          'assignment_status': 'completed',
          'verification_status': 'verified',
        }),
      ),
      isFalse,
    );
    expect(
      workerShiftNeedsAction(worker({'assignment_status': 'cancelled'})),
      isFalse,
    );
    final ended = WorkerWorkAssignment.fromJson({
      ...assignment(),
      'assignment_status': 'active',
      'check_in_at': '2026-11-05T01:00:00Z',
      'attendance_as_of': '2026-11-07T12:00:00Z',
      'attendance_resolution': resolutionContext(),
    });
    expect(workerShiftNeedsAction(ended), isFalse);
    expect(employerShiftNeedsAction(ended), isTrue);
    expect(employerShiftNeedsAction(worker({})), isFalse);
    expect(
      employerShiftNeedsAction(
        worker({'verification_status': 'pending_review'}),
      ),
      isTrue,
    );
    expect(
      employerShiftNeedsAction(
        worker({
          'verification_status': 'verified',
          'assignment_status': 'completed',
        }),
      ),
      isFalse,
    );
  });

  testWidgets(
    'green success, amber pending, informative correction and neutral absence are distinct',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        attendanceTone(AttendanceLifecycle.corrected),
        AttendanceTone.information,
      );
      expect(
        attendanceTone(AttendanceLifecycle.confirmedAbsent),
        AttendanceTone.neutral,
      );
      expect(
        attendanceTone(AttendanceLifecycle.incomplete),
        AttendanceTone.issue,
      );
      final success = attendanceToneColors(context, AttendanceTone.positive);
      expect(success.$1.g, greaterThan(success.$1.r));
      expect(
        success,
        isNot(attendanceToneColors(context, AttendanceTone.information)),
      );
      expect(
        attendanceToneColors(context, AttendanceTone.pending),
        isNot(attendanceToneColors(context, AttendanceTone.issue)),
      );
    },
  );

  testWidgets(
    'worker loaded counts update without extra fetching and clear on account change',
    (tester) async {
      final source = FakeSource()..workerRead = () async => [correctedRow()];
      final repo = WorkAttendanceRepository(source);
      addTearDown(() async {
        repo.dispose();
        await source.changes.close();
      });
      await tester.pumpWidget(
        MaterialApp(home: WorkAttendancePage(repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppWorkspace>(find.byType(AppWorkspace))
            .navigationActionCounts,
        {AppRoutes.workAttendance: 1},
      );
      expect(source.calls, 1);
      source.workerRead = () async => [
        {...correctedRow(), 'verification_status': 'pending_review'},
      ];
      await repo.loadWorkerAssignments();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppWorkspace>(find.byType(AppWorkspace))
            .navigationActionCounts,
        {AppRoutes.workAttendance: 0},
      );
      source.userId = null;
      source.changes.add(null);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppWorkspace>(find.byType(AppWorkspace))
            .navigationActionCounts
            .values
            .every((count) => count == 0),
        isTrue,
      );
    },
  );

  testWidgets(
    'employer count is company scoped and never reuses worker badges',
    (tester) async {
      final source = FakeSource()
        ..companyRead = (_) async => [
          {
            ...assignment(company: true),
            'assignment_status': 'awaiting_verification',
            'verification_status': 'pending_review',
          },
        ];
      final repo = WorkAttendanceRepository(source);
      addTearDown(() async {
        repo.dispose();
        await source.changes.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: WorkVerificationPage(
            repository: repo,
            companyId: other,
            loadAccess: () async =>
                const JobAccess({'company_id': other}, null),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppWorkspace>(find.byType(AppWorkspace))
            .navigationActionCounts,
        {AppRoutes.workVerification: 1},
      );
      expect(source.calls, 1);
      source.userId = null;
      source.changes.add(null);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppWorkspace>(find.byType(AppWorkspace))
            .navigationActionCounts,
        isEmpty,
      );
    },
  );

  testWidgets(
    'corrected summary distinguishes original timestamps, GPS and reason without technical identifiers',
    (tester) async {
      final data = correctedRow(),
          row = WorkerWorkAssignment.fromJson(correctedRow());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AttendanceLifecycleNotice(assignment: row),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Corrected effective checkout:'),
        findsOneWidget,
      );
      expect(find.text('Attendance correction'), findsOneWidget);
      expect(find.textContaining('Original check-in:'), findsOneWidget);
      expect(find.textContaining('not approved payable time'), findsOneWidget);
      expect(find.text('Original checkout: Not recorded'), findsOneWidget);
      expect(find.text('Authorized actual-time correction'), findsOneWidget);
      expect(
        find.textContaining('check-in denied; checkout not recorded'),
        findsOneWidget,
      );
      expect(find.textContaining('Assignment:'), findsNothing);
      expect(find.text('Technical details'), findsNothing);
      expect(find.textContaining(id), findsNothing);
      expect(find.textContaining('Resolved by employer:'), findsOneWidget);
      expect(row.checkOutAt, isNull);
      expect(data['check_out_at'], isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'worker and employer correction summaries wrap at narrow widths',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [320.0, 840.0]) {
        for (final employer in [false, true]) {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          final row = WorkerWorkAssignment.fromJson(correctedRow());
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(width == 320 ? 2 : 1.6),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: employer
                      ? EmployerWorkEvidenceSummary(
                          key: UniqueKey(),
                          assignment: row,
                        )
                      : AttendanceLifecycleNotice(
                          key: UniqueKey(),
                          assignment: row,
                        ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            employer
                ? find.text('Corrected check-in')
                : find.textContaining('Corrected effective check-in:'),
            findsOneWidget,
          );
          expect(find.textContaining('approved payable time'), findsOneWidget);
          expect(find.textContaining('Original checkout:'), findsOneWidget);
          expect(find.textContaining('Assignment:'), findsNothing);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  for (final launchBlocked in [false, true]) {
    testWidgets(
      'View PDF dismisses after successful web launch, blocked=$launchBlocked',
      (tester) async {
        final source = FakeSource();
        source.workerRead = () async => [assignment()];
        source.evidenceRead = (_) async => [
          evidenceRow()..['storage_path'] = '$id/file.pdf',
        ];
        final attendance = WorkAttendanceRepository(source);
        final viewer = WorkEvidenceRepository.worker(
          attendance,
          assignmentId: id,
        );
        final signing = PreviewSource(source),
            browser = EvidenceBrowser()..blocked = launchBlocked;
        addTearDown(() async {
          viewer.dispose();
          attendance.dispose();
          await source.changes.close();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: WorkEvidencePage(
              repository: viewer,
              previewOpener: browser,
              createPreviewRepository: () =>
                  WorkEvidencePreviewRepository(signing),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('View PDF'));
        await tester.tap(find.text('View PDF'));
        expect(browser.windows.length, launchBlocked ? 0 : 1);
        expect(signing.signed, isEmpty);
        await tester.pumpAndSettle();
        if (launchBlocked) {
          expect(find.byType(WorkEvidencePreviewDialog), findsOneWidget);
          expect(find.textContaining('browser blocked'), findsOneWidget);
          browser.blocked = false;
          await tester.tap(find.text('Open PDF'));
          await tester.pumpAndSettle();
        }
        expect(browser.windows.last.uri, isNotNull);
        expect(signing.signed.length, 1);
        expect(find.textContaining('token='), findsNothing);
        expect(find.byType(WorkEvidencePreviewDialog), findsNothing);
        expect(browser.windows.last.closed, isFalse);
      },
    );
  }

  for (final blocked in [false, true]) {
    testWidgets(
      'automatic PDF uses gesture tab and private authorization, blocked=$blocked',
      (tester) async {
        final source = FakeSource();
        source.workerRead = () async => [assignment()];
        source.evidenceRead = (_) async => [
          evidenceRow()..['storage_path'] = '$id/file.pdf',
        ];
        final attendance = WorkAttendanceRepository(source);
        final viewer = WorkEvidenceRepository.worker(
          attendance,
          assignmentId: id,
        );
        final signing = PreviewSource(source);
        final preview = WorkEvidencePreviewRepository(signing);
        final browser = EvidenceBrowser()..blocked = blocked;
        addTearDown(() async {
          preview.dispose();
          viewer.dispose();
          attendance.dispose();
          await source.changes.close();
        });
        final window = browser
            .reserve(); // Same synchronous reservation used by View PDF.
        await tester.pumpWidget(
          MaterialApp(
            home: WorkEvidencePreviewDialog(
              viewer: viewer,
              evidenceId: id,
              repository: preview,
              opener: browser,
              autoOpen: true,
              reservedWindow: window,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(signing.checks, ['$id/file.pdf']);
        expect(signing.signed.single.$2, 90);
        expect(find.textContaining('token='), findsNothing);
        if (blocked) {
          expect(find.textContaining('browser blocked'), findsOneWidget);
          browser.blocked = false;
          await tester.tap(find.text('Open PDF'));
          await tester.pumpAndSettle();
        }
        expect(browser.windows.last.uri, isNotNull);
        await tester.pump(const Duration(seconds: 91));
        await tester.pumpAndSettle();
        expect(find.text('Check access again'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'closure reason remains bounded and scrollable with long text and enlarged fonts',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [320.0, 840.0, 1920.0]) {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: EngagementClosureControls(
                key: ValueKey(width),
                applicationId: id,
                worker: false,
                gateway: FakeEngagementClosureGateway(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Close Engagement'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          List.filled(30, 'A long reason for closure.').join('\n'),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .getSize(
                find
                    .descendant(
                      of: find.byType(AlertDialog),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .width,
          lessThanOrEqualTo(560),
        );
        expect(
          find.textContaining('does not approve or process payment'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'account change closes pending PDF tab and suppresses late signing',
    (tester) async {
      final source = FakeSource();
      source.workerRead = () async => [assignment()];
      source.evidenceRead = (_) async => [
        evidenceRow()..['storage_path'] = '$id/file.pdf',
      ];
      final attendance = WorkAttendanceRepository(source),
          signing = PreviewSource(source);
      final viewer = WorkEvidenceRepository.worker(
            attendance,
            assignmentId: id,
          ),
          preview = WorkEvidencePreviewRepository(signing);
      final pending = Completer<Uri>();
      signing.response = () => pending.future;
      final browser = EvidenceBrowser(), window = ReservedEvidenceWindow();
      addTearDown(() async {
        preview.dispose();
        viewer.dispose();
        attendance.dispose();
        await source.changes.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: WorkEvidencePreviewDialog(
            viewer: viewer,
            evidenceId: id,
            repository: preview,
            opener: browser,
            autoOpen: true,
            reservedWindow: window,
          ),
        ),
      );
      await tester.pump();
      source.userId = null;
      source.changes.add(null);
      await tester.pump();
      pending.complete(Uri.parse('https://private.invalid/?token=fake'));
      await tester.pumpAndSettle();
      expect(window.closed, isTrue);
      expect(window.uri, isNull);
      expect(preview.link, isNull);
    },
  );
}
