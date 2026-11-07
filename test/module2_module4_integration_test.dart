import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/employer_applicants_repository.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_assignment_creation_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';
import 'package:jobmate/features/work_attendance/work_attendance_pages.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_deadline.dart';
import 'package:jobmate/features/work_attendance/work_evidence_draft_controller.dart';
import 'package:jobmate/features/work_attendance/work_evidence_upload_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_workflow.dart';
import 'package:jobmate/features/work_attendance/work_verification_pages.dart';

import 'fixtures/employer_applicants_source.dart';
import 'fixtures/my_applications_source.dart';
import 'work_assignment_creation_repository_test.dart'
    show CandidateSource, complete, uid;
import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, id, other;
import 'work_evidence_workflow_test.dart'
    show EvidenceServer, WorkflowSource, UploadSource;
import 'work_evidence_draft_controller_test.dart' show file, pdf;

// Connect existing local fakes at their adapter boundaries. This verifies Flutter
// integration, not deployed SQL authorization, overlap races or Storage behavior.
void main() {
  late TestEmployerApplicantsSource employerSource;
  late TestMyApplicationsSource workerSource;
  late CandidateSource candidates;
  late EmployerApplicantsRepository employer;
  late MyApplicationDetailsRepository worker;
  late WorkAssignmentCreationRepository creation;
  late List<Map<String, dynamic>> shifts;

  setUp(() {
    shifts = [];
    employerSource = TestEmployerApplicantsSource()
      ..actor = other
      ..rows = [applicantRow(uid(4))..['applicant_id'] = id]
      ..data = EmployerPostingContext(
        JobAccess({
          'company_id': uid(2),
          'company_name': 'Authorized company',
        }, null),
        [
          {
            'job_id': uid(3),
            'company_id': uid(2),
            'title': 'QA Assistant',
            'status': 'published',
          },
        ],
      );
    workerSource = TestMyApplicationsSource()..actor = id;
    workerSource.fetch = () async => [
      applicationRow(
          uid(4),
          status: employerSource.rows.single['status'] as String,
        )
        ..['job_id'] = uid(3)
        ..['job_title'] = 'QA Assistant'
        ..['company_name'] = 'Authorized company',
    ];
    workerSource.sendResponse = (_, action) async {
      final choice = ApplicationResponseAction.values.singleWhere(
        (a) => a.wireName == action,
      );
      employerSource.rows = [
        {...employerSource.rows.single, 'status': choice.result.name},
      ];
      workerSource.historyRows.add(
        historyRow(
          'worker-${workerSource.historyRows.length}',
          status: choice.result.name,
        ),
      );
      return 'Confirmed';
    };
    candidates = CandidateSource()..userId = other;
    candidates.access = () async => employerSource.data.access;
    candidates.jobs = (_) async => complete(employerSource.data.jobs);
    candidates.applicants = (_) async => complete(employerSource.rows);
    candidates.assignments = (_) async => complete(shifts);
    var request = 80;
    candidates.reserve = (_) async => uid(request++);
    candidates.create = (parameters) async {
      final shiftId = shifts.isEmpty ? id : uid(90 + shifts.length);
      shifts.add(
        assignment()
          ..['assignment_id'] = shiftId
          ..['application_id'] = parameters['p_application_id']
          ..['job_id'] = uid(3)
          ..['worker_id'] = id
          ..['company_id'] = uid(2)
          ..['company_name'] = 'Authorized company'
          ..['job_title'] = 'QA Assistant'
          ..['scheduled_start'] = parameters['p_scheduled_start']
          ..['scheduled_end'] = parameters['p_scheduled_end']
          ..['workplace_location'] = parameters['p_workplace_location'],
      );
      return shiftId;
    };
    employer = EmployerApplicantsRepository(employerSource, uid(3));
    worker = MyApplicationDetailsRepository(workerSource, uid(4));
    creation = WorkAssignmentCreationRepository(
      candidates,
      ledger: WorkAssignmentCreationLedger(),
    );
  });

  tearDown(() async {
    employer.dispose();
    worker.dispose();
    creation.dispose();
    await employerSource.changes.close();
    await workerSource.changes.close();
    await candidates.changes.close();
  });

  Future<void> offer() async {
    await employer.load();
    await worker.load();
    for (final next in [
      MyApplicationStatus.shortlisted,
      MyApplicationStatus.interview,
      MyApplicationStatus.offered,
    ]) {
      if (worker.application!.status != MyApplicationStatus.offered) {
        await expectLater(
          worker.respond(worker.application!, 'accept_offer'),
          throwsStateError,
        );
      }
      await expectLater(
        employer.updateStatus(
          employer.applicants.single,
          MyApplicationStatus.hired,
          '',
        ),
        throwsStateError,
      );
      await employer.updateStatus(
        employer.applicants.single,
        next,
        'Agreed next step',
      );
      await worker.load();
      expect(worker.application!.status, next);
      await creation.load(companyId: candidates.company);
      expect(creation.state.candidates, isEmpty);
      expect(candidates.creates, 0);
    }
  }

  test('hiring connects to repeat/overnight shifts, independent attendance, late evidence and verification', () async {
    await offer();
    await worker.respond(worker.application!, 'accept_offer');
    await employer.load();
    expect(worker.application!.status, MyApplicationStatus.hired);
    expect(employer.applicants.single.status, MyApplicationStatus.hired);
    await expectLater(
      worker.respond(worker.application!, 'withdraw'),
      throwsStateError,
    );
    await expectLater(
      worker.respond(worker.application!, 'decline_offer'),
      throwsStateError,
    );
    await creation.load(companyId: candidates.company);
    expect(creation.state.candidates.single.applicationId, uid(4));

    for (final (startDate, startTime, endDate, endTime) in [
      ('2026-11-10', '22:30', '2026-11-11', '02:15'),
      ('2026-11-09', '09:00', '2026-11-09', '17:00'),
    ]) {
      final result = await creation.create(
        candidate: creation.state.candidates.single,
        start: workAssignmentMalaysiaUtc(startDate, startTime)!,
        end: workAssignmentMalaysiaUtc(endDate, endTime)!,
        location: 'Agreed workplace',
      );
      expect(result.status, WorkAssignmentCreateStatus.success);
    }
    expect(shifts.map((row) => row['application_id']), [uid(4), uid(4)]);
    expect(shifts.first['scheduled_start'], '2026-11-10T14:30:00.000Z');
    expect(shifts.first['scheduled_end'], '2026-11-10T18:15:00.000Z');
    final overlap = await creation.create(
      candidate: creation.state.candidates.single,
      start: DateTime.utc(2026, 11, 10, 15),
      end: DateTime.utc(2026, 11, 10, 16),
      location: 'Agreed workplace',
    );
    expect(overlap.status, WorkAssignmentCreateStatus.rejected);
    expect(candidates.creates, 2);
    final untouched = Map<String, dynamic>.of(shifts.last);

    final attendanceSource = FakeSource()..workerRead = (() async => shifts);
    attendanceSource.onCheckIn = (shiftId) async {
      expect(shiftId, id);
      shifts.first['assignment_status'] = 'active';
      shifts.first['check_in_at'] = '2026-11-10T14:35:00Z';
      return DateTime.utc(2026, 11, 10, 14, 35);
    };
    attendanceSource.onCheckOut = (shiftId) async {
      expect(shiftId, id);
      shifts.first['assignment_status'] = 'awaiting_verification';
      shifts.first['check_out_at'] = '2026-11-10T18:20:00Z';
      return DateTime.utc(2026, 11, 10, 18, 20);
    };
    final attendance = WorkAttendanceRepository(attendanceSource);
    addTearDown(() async {
      attendance.dispose();
      await attendanceSource.changes.close();
    });
    await attendance.loadWorkerAssignments();
    await attendance.checkIn(
      id,
      location: const WorkAttendanceLocation.denied(),
    );
    expect(
      attendance.worker.rows.first.attendanceState,
      WorkAttendanceState.checkedIn,
    );
    await attendance.checkOut(
      id,
      location: WorkAttendanceLocation.granted(
        latitude: 3.139,
        longitude: 101.687,
      ),
    );
    final checkedOut = attendance.worker.rows.first;
    expect(checkedOut.attendanceState, WorkAttendanceState.checkedOut);
    final lateNow = checkedOut.checkOutAt!.add(const Duration(days: 2));
    expect(
      EvidenceDeadline.fromAssignment(checkedOut, now: lateNow).state,
      EvidenceDeadlineState.overdue,
    );
    expect(
      EvidenceDeadline.fromAssignment(
        attendance.worker.rows.last,
        now: lateNow,
      ).state,
      EvidenceDeadlineState.notStarted,
    );

    final server = EvidenceServer();
    final workerWorkflow = WorkflowSource(server, id);
    final employerWorkflow = WorkflowSource(server, other);
    for (final source in [workerWorkflow, employerWorkflow]) {
      source.intercept = (rpc, parameters) async {
        final result = server.call(source.userId!, rpc, parameters);
        shifts.first['verification_status'] = server.status;
        if (server.status == 'verified') {
          shifts.first['assignment_status'] = 'completed';
          shifts.first['verified_at'] = '2026-11-13T01:00:00Z';
        }
        return result;
      };
    }
    final ledger = WorkEvidenceWorkflowLedger();
    final wc = WorkEvidenceWorkflowController(
      workerWorkflow,
      assignmentId: id,
      employer: false,
      ledger: ledger,
    );
    final ec = WorkEvidenceWorkflowController(
      employerWorkflow,
      assignmentId: id,
      employer: true,
      ledger: ledger,
    );
    addTearDown(() async {
      wc.dispose();
      ec.dispose();
      await workerWorkflow.changes.close();
      await employerWorkflow.changes.close();
    });
    for (final round in [1, 2]) {
      final draft = WorkEvidenceDraftController(
        session: workerWorkflow,
        assignmentId: id,
      )..setDescription('Work report $round');
      final uploads = WorkEvidenceUploadRepository(
        UploadSource(workerWorkflow),
        assignmentId: id,
      );
      try {
        await draft.addFiles([file(pdf(round))]);
        await wc.load();
        expect(wc.snapshot!.canSubmit, isTrue);
        expect(await wc.submit(draft, uploads), isTrue);
      } finally {
        draft.dispose();
        uploads.dispose();
      }
      await attendance.loadWorkerAssignments();
      expect(
        EvidenceDeadline.fromAssignment(
          attendance.worker.rows.first,
          now: lateNow,
        ).state,
        EvidenceDeadlineState.submitted,
      );
      await ec.load();
      expect(
        await ec.review(
          round == 1 ? 'more_evidence_requested' : 'verified',
          round == 1 ? 'Include closing tasks.' : null,
        ),
        isTrue,
      );
      await attendance.loadWorkerAssignments();
      expect(
        EvidenceDeadline.fromAssignment(
          attendance.worker.rows.first,
          now: lateNow,
        ).state,
        round == 1
            ? EvidenceDeadlineState.moreEvidenceRequired
            : EvidenceDeadlineState.verified,
      );
    }
    await wc.load();
    expect(wc.snapshot!.history.map((event) => event.action), [
      'evidence_submitted',
      'more_evidence_requested',
      'evidence_resubmitted',
      'verified',
    ]);
    expect(server.evidence, hasLength(2));
    expect(shifts.last, untouched);
    expect(employerSource.rows.single['status'], 'hired');
    expect(attendanceSource.checkIns, 1);
    expect(attendanceSource.checkOuts, 1);
  });

  for (final action in [
    ApplicationResponseAction.declineOffer,
    ApplicationResponseAction.withdraw,
  ]) {
    test(
      '${action.label} remains distinct and never creates a work assignment',
      () async {
        await offer();
        await worker.respond(worker.application!, action.wireName);
        await employer.load();
        await creation.load(companyId: candidates.company);
        expect(worker.application!.status, action.result);
        expect(employer.applicants.single.status, action.result);
        expect(creation.state.candidates, isEmpty);
        expect(shifts, isEmpty);
        expect(candidates.creates, 0);
        expect(candidates.reservations, 0);
        expect(employer.applicants.single.employerNext, isEmpty);
      },
    );
  }

  for (final employerView in [false, true]) {
    for (final width in [320.0, 840.0, 1440.0]) {
      testWidgets(
        'overnight order and identical-title application isolation: employer=$employerView width=$width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          Map<String, dynamic> row(String shiftId, String applicationId) =>
              assignment()
                ..['assignment_id'] = shiftId
                ..['application_id'] = applicationId
                ..['worker_id'] = id;
          final rows = [
            row(id, uid(4))
              ..['scheduled_start'] = '2026-11-06T22:30:00+08:00'
              ..['scheduled_end'] = '2026-11-07T02:15:00+08:00',
            row(uid(92), uid(6)),
            row(other, uid(4)),
          ];
          final source = FakeSource()
            ..userId = employerView ? other : id
            ..workerRead = (() async => rows)
            ..companyRead = ((_) async => rows);
          final attendance = WorkAttendanceRepository(source);
          addTearDown(() async {
            attendance.dispose();
            await source.changes.close();
          });
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: employerView
                  ? WorkVerificationPage(
                      repository: attendance,
                      companyId: candidates.company,
                      loadAccess: candidates.access,
                      loadWorkerName: (_, _) async => 'Same worker',
                    )
                  : WorkAttendancePage(repository: attendance),
            ),
          );
          await tester.pumpAndSettle();
          final group = find.byKey(ValueKey('application-${uid(4)}'));
          expect(find.text('Server job'), findsNWidgets(2));
          expect(find.text('2 shifts'), findsOneWidget);
          expect(find.text('1 shift'), findsOneWidget);
          expect(find.byKey(ValueKey('application-${uid(6)}')), findsOneWidget);
          final cards = find.descendant(of: group, matching: find.byType(Card));
          expect(tester.widgetList<Card>(cards).map((card) => card.key), [
            const ValueKey(other),
            const ValueKey(id),
          ]);
          expect(
            find.text('Scheduled end: 07/11/2026 02:15 MYT'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          expect(candidates.creates, 0);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
