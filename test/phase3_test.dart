import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/recommendations/recommendations_page.dart';
import 'package:jobmate/features/attendance/attendance_pages.dart';
import 'package:jobmate/features/chat/chat_page.dart';
import 'package:jobmate/features/location/location_pages.dart';
import 'package:jobmate/features/demo_work/local_attachment.dart';
import 'package:jobmate/features/demo_work/phase3_store.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';
import 'package:jobmate/shared/widgets/app_workspace.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';

import 'support/workspace_navigation_test_helper.dart';

void main() {
  for (final width in [320.0, 1440.0]) {
    for (final role in ['job_seeker', 'employer']) {
      testWidgets('$role Phase 3 destinations remain reachable at $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? destination;
        final entries = role == 'job_seeker'
            ? {
                'For You (demo)': AppRoutes.recommendations,
                'Nearby Jobs (demo)': AppRoutes.nearbyJobs,
                'Attendance (demo)': AppRoutes.attendance,
                'Messages (demo)': AppRoutes.messages,
              }
            : {
                'Attendance Review (demo)': AppRoutes.attendanceReview,
                'Messages (demo)': AppRoutes.employerMessages,
                'Location Picker (demo)': AppRoutes.jobLocationDemo,
              };
        await tester.pumpWidget(
          MaterialApp(
            home: AppWorkspace(
              title: 'Dashboard',
              path: AppRoutes.home,
              role: role,
              onNavigate: (value) => destination = value,
              child: const SizedBox(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final entry in entries.entries) {
          await openWorkspaceMenu(tester);
          final tile = find.widgetWithText(ListTile, entry.key);
          await scrollWorkspaceMenuTo(tester, entry.key);
          await tester.tap(tile);
          await tester.pumpAndSettle();
          expect(destination, entry.value);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  test(
    'Recommendations use deterministic sample skills and documented weights',
    () {
      final repo = Module2Repository();
      addTearDown(repo.dispose);
      final retail = DemoMatch(repo.job('demo-job-1')!);
      expect(retail.score, 100);
      expect(retail.label, 'Excellent');
      expect(retail.missing, isEmpty);
      final intern = DemoMatch(repo.job('demo-job-2')!);
      expect(intern.score, 35);
      expect(intern.label, 'Fair');
      expect(intern.missing, containsAll(['dart', 'flutter']));
      expect(DemoMatch(repo.job('demo-job-2')!).score, intern.score);
      expect(repo.job('demo-job-2')!.fields.containsKey('salary_min'), isFalse);
    },
  );
  test(
    'Attendance guards, evidence and employer review share the same records',
    () {
      final store = Phase3Store();
      addTearDown(store.dispose);
      final r = store.record('today')!, time = DateTime(2026, 11, 3, 9);
      expect(
        () => store.clock(r.id, checkingIn: true, now: time),
        throwsStateError,
      );
      store.simulateLocation(r.id);
      store.clock(r.id, checkingIn: true, now: time);
      expect(() => store.clock(r.id, checkingIn: true), throwsStateError);
      expect(() => store.submitEvidence(r.id), throwsStateError);
      expect(
        () => store.clock(
          r.id,
          checkingIn: false,
          now: time.subtract(const Duration(seconds: 1)),
        ),
        throwsStateError,
      );
      store.clock(
        r.id,
        checkingIn: false,
        now: time.add(const Duration(hours: 8)),
      );
      expect(r.elapsed(time), const Duration(hours: 8));
      expect(() => store.review(r.id, verify: true), throwsStateError);
      final draft = store.evidenceDraft(r.id)
        ..description = 'Completed sample tasks';
      expect(() => store.submitEvidence(r.id), throwsStateError);
      draft.files.add(
        LocalAttachment(
          'demo.pdf',
          Uint8List.fromList('%PDF-'.codeUnits),
          'application/pdf',
        ),
      );
      store.submitEvidence(r.id);
      expect(r.evidence.length, 1);
      expect(r.description, 'Completed sample tasks');
      store.review(r.id, verify: true);
      expect(r.review, 'Verified');
      expect(
        () => store.review(r.id, verify: false, reason: 'another decision'),
        throwsStateError,
      );
      expect(() => store.submitEvidence(r.id), throwsStateError);
    },
  );
  test('Flag reasons are required and retained in the sample report', () {
    final store = Phase3Store();
    addTearDown(store.dispose);
    expect(() => store.review('shift-1', verify: false), throwsStateError);
    store.review(
      'shift-1',
      verify: false,
      reason: 'Missing completion details',
    );
    expect(store.record('shift-1')!.flagReason, 'Missing completion details');
    final html = attendanceReportHtml({
      'Worker': '<script>alert(1)</script>',
      'Review': 'Flagged',
    });
    expect(html, contains('&lt;script&gt;'));
    expect(html, isNot(contains('<script>')));
    expect(html, contains('DEMO REPORT'));
  });
  test(
    'Chat drafts, messages, unread counts and simulated receipts are coherent',
    () {
      final store = Phase3Store();
      addTearDown(store.dispose);
      final c = store.conversation('chat-3')!;
      expect(() => store.send(c.id, 'job_seeker'), throwsStateError);
      c.drafts['job_seeker'] = 'Hello demo employer';
      store.send(c.id, 'job_seeker');
      expect(c.messages.single.text, 'Hello demo employer');
      expect(c.drafts['job_seeker'], isNull);
      expect(c.unread['employer'], 1);
      store.simulateReceipts(c.id, 'job_seeker');
      expect(c.messages.single.receipt, 'Delivered');
      store.read(c.id, 'employer');
      expect(c.messages.single.receipt, 'Read');
      expect(c.unread['employer'], 0);
      c.attachmentDrafts['employer'] = [
        LocalAttachment('sample.pdf', Uint8List(0), 'application/pdf'),
      ];
      store.send(c.id, 'employer');
      expect(c.messages.last.attachments.length, 1);
      expect(c.unread['job_seeker'], 1);
      expect(() => store.send(c.id, 'administrator'), throwsStateError);
    },
  );
  test(
    'Location grid never becomes real coordinates and reset clears all drafts',
    () {
      final store = Phase3Store();
      addTearDown(store.dispose);
      final repo = Module2Repository();
      addTearDown(repo.dispose);
      expect(DemoPlace(repo.job('demo-job-2')!).distance, 5);
      expect(() => store.confirmLocation(''), throwsStateError);
      store.moveMarker(-1, 2);
      expect(store.markerX, .05);
      expect(store.markerY, .95);
      store.confirmLocation('Demo workplace');
      expect(store.locationConfirmed, isTrue);
      store.moveMarker(.2, .3);
      expect(store.locationConfirmed, isFalse);
      store.evidenceDraft('today').description = 'Unsubmitted work';
      store.flagDrafts['shift-1'] = 'Draft reason';
      store.conversation('chat-3')!.drafts['job_seeker'] = 'Draft chat';
      final generation = store.generation;
      store.reset();
      expect(store.generation, generation + 1);
      expect(store.locationAddress, isEmpty);
      expect(store.flagDrafts, isEmpty);
      expect(store.evidenceDraft('today').description, isEmpty);
      expect(store.conversation('chat-3')!.drafts, isEmpty);
    },
  );
  for (final width in [320.0, 768.0, 1440.0]) {
    for (final page in [
      'Recommendations',
      'Today',
      'Evidence',
      'History',
      'Review',
      'Worker Details',
      'Report',
      'Messages',
      'Conversation',
      'Employer Conversation',
      'Nearby',
      'Workplace',
      'Location Picker',
    ]) {
      testWidgets('$page at $width has responsive demo content', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = Phase3Store(), jobs = Module2Repository();
        addTearDown(store.dispose);
        addTearDown(jobs.dispose);
        final child = switch (page) {
          'Recommendations' => RecommendationsPage(repository: jobs),
          'Today' => AttendancePage(store: store),
          'Evidence' => EvidencePage(store: store),
          'History' => AttendanceListPage(store: store),
          'Review' => AttendanceListPage(employer: true, store: store),
          'Worker Details' => AttendanceDetailPage(
            recordId: 'shift-1',
            employer: true,
            store: store,
          ),
          'Report' => AttendanceDetailPage(
            recordId: 'shift-1',
            report: true,
            store: store,
          ),
          'Messages' => ChatPage(store: store),
          'Conversation' => ChatPage(conversationId: 'chat-3', store: store),
          'Employer Conversation' => ChatPage(
            employer: true,
            conversationId: 'chat-1',
            store: store,
          ),
          'Nearby' => NearbyJobsPage(repository: jobs),
          'Workplace' => NearbyDetailPage(
            jobId: 'demo-job-2',
            repository: jobs,
          ),
          _ => JobLocationDemoPage(store: store),
        };
        final router = GoRouter(
          routes: [GoRoute(path: '/', builder: (_, _) => child)],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(theme: JobMateTheme.light(), routerConfig: router),
        );
        await tester.pumpAndSettle();
        expect(find.text('DEMO / PREVIEW'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (page == 'Conversation') {
          await tester.ensureVisible(find.byType(TextField).last);
          await tester.enterText(
            find.byType(TextField).last,
            'Hello local demo',
          );
          await tester.pumpAndSettle();
          expect(
            store.conversation('chat-3')!.drafts['job_seeker'],
            'Hello local demo',
          );
          await tester.ensureVisible(find.text('Send (demo)'));
          await tester.tap(find.text('Send (demo)'));
          await tester.pumpAndSettle();
          expect(
            store.conversation('chat-3')!.messages.last.text,
            'Hello local demo',
          );
          expect(tester.takeException(), isNull);
        }
        if (page == 'Location Picker') {
          await tester.enterText(
            find.byType(TextField).first,
            'My sample address',
          );
          expect(store.locationDraft, 'My sample address');
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets(
    'Check-in confirmation and evidence validation are meaningful demo actions',
    (tester) async {
      final store = Phase3Store();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: JobMateTheme.light(),
          home: AttendancePage(store: store),
        ),
      );
      await tester.ensureVisible(find.text('Simulate location check (demo)'));
      await tester.tap(find.text('Simulate location check (demo)'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Check In (demo)'));
      await tester.tap(find.text('Check In (demo)'));
      await tester.pumpAndSettle();
      expect(store.record('today')!.checkIn, isNull);
      await tester.tap(find.text('Confirm demo action'));
      await tester.pumpAndSettle();
      expect(store.record('today')!.checkIn, isNotNull);
      store.clock('today', checkingIn: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: JobMateTheme.light(),
          home: EvidencePage(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Submit Evidence (demo)'));
      await tester.tap(find.text('Submit Evidence (demo)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Add 1–5 files'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
