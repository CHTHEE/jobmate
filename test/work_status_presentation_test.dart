import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';
import 'package:jobmate/features/work_attendance/work_status_presentation.dart';

void main() {
  test('saved check-in timing uses the exact inclusive 15-minute boundary', () {
    final start = DateTime.parse('2026-11-10T09:00:00+08:00');
    expect(workCheckInTimingLabel(start, null), isNull);
    expect(
      workCheckInTimingLabel(
        start,
        start.subtract(const Duration(minutes: 30)),
      ),
      'On Time',
    );
    expect(
      workCheckInTimingLabel(start, DateTime.parse('2026-11-10T01:15:00Z')),
      'On Time',
    );
    expect(
      workCheckInTimingLabel(start, DateTime.parse('2026-11-10T01:15:01Z')),
      'Late',
    );
  });
  test('server states determine stage and contextual actions', () {
    WorkStage stage(String assignment, String verification) =>
        WorkStage.fromStatuses(
          WorkAssignmentStatus.parse(assignment),
          WorkVerificationStatus.parse(verification),
        );
    expect(stage('scheduled', 'not_submitted'), WorkStage.scheduled);
    expect(stage('active', 'not_submitted'), WorkStage.checkedIn);
    expect(
      stage('awaiting_verification', 'not_submitted'),
      WorkStage.awaitingEvidence,
    );
    expect(
      stage('awaiting_verification', 'pending_review'),
      WorkStage.pendingReview,
    );
    expect(
      stage('awaiting_verification', 'more_evidence_required'),
      WorkStage.moreEvidence,
    );
    expect(stage('completed', 'verified'), WorkStage.verified);
    expect(stage('cancelled', 'pending_review'), WorkStage.cancelled);
    expect(WorkStage.pendingReview.evidenceAction(true), 'Review Evidence');
    expect(
      WorkStage.moreEvidence.evidenceAction(false),
      'Review Feedback & Resubmit',
    );
  });

  for (final employer in [false, true]) {
    testWidgets(
      'all status banners fit narrow screens with large text ($employer)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final stage in WorkStage.values) {
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(1.6)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: WorkStatusBanner(stage: stage, employer: employer),
                ),
              ),
            ),
          );
          expect(find.text(stage.label), findsOneWidget);
          expect(find.text(stage.heading(employer)), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
