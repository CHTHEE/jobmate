import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/applications/applicant_notification_repository.dart';
import 'package:jobmate/features/applications/applicant_unseen_controller.dart';
import 'package:jobmate/features/jobs/job_postings_page.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:jobmate/shared/widgets/app_workspace.dart';

import 'employer_job_postings_refinement_test.dart' show posting;
import 'job_postings_test.dart' show TestJobs;

const first = '00000000-0000-4000-8000-000000000021';
const second = '00000000-0000-4000-8000-000000000022';
const third = '00000000-0000-4000-8000-000000000023';
const dot = ValueKey('unseen-applicants-dot');

void main() {
  for (final width in [320.0, 768.0, 1200.0]) {
    testWidgets('applicant indicators react and fit at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final semantics = tester.ensureSemantics();
      final accountChanges = StreamController<String?>.broadcast(sync: true);
      String? actor = 'employer-a';
      var reads = 0;
      var rows = <Map<String, Object>>[];
      final unseen = ApplicantUnseenController(
        ApplicantNotificationRepository.withRpc((name, _) async {
          expect(name, 'list_unseen_applicant_counts');
          reads++;
          return rows;
        }),
        currentUserId: () => actor,
        accountChanges: accountChanges.stream,
      );
      addTearDown(() async {
        unseen.dispose();
        await accountChanges.close();
      });
      final repo = TestJobs()
        ..records = [
          posting(first, 'published'),
          posting(second, 'closed'),
          posting(third, 'draft'),
        ];
      final router = GoRouter(
        initialLocation: AppRoutes.jobPostings,
        routes: [
          GoRoute(
            path: AppRoutes.jobPostings,
            builder: (_, _) =>
                JobPostingsPage(repository: repo, applicantUnseen: unseen),
          ),
          GoRoute(
            path: AppRoutes.applicants,
            builder: (_, state) => AppWorkspace(
              title: 'Applicants target',
              path: AppRoutes.applicants,
              role: 'employer',
              applicantUnseen: unseen,
              child: Text(
                state.uri.queryParameters['posting'] ?? 'All applicants',
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      unseen.enterWorkspace(accountId: actor, companyId: 'company');
      await tester.pumpAndSettle();

      Finder inCard(String id, String text) => find.descendant(
        of: find.byKey(ValueKey('employer-job-$id')),
        matching: find.text(text),
      );
      final nav = find.byKey(const ValueKey('workspace-navigation'));
      Finder menuText(String label) =>
          find.descendant(of: nav, matching: find.text(label));
      Future<void> openMenu() async {
        if (nav.evaluate().isNotEmpty) return;
        await tester.tap(
          kIsWeb ? find.byTooltip('Open navigation menu') : find.text('More'),
        );
        await tester.pumpAndSettle();
      }

      await openMenu();
      expect(menuText('View Applicants'), findsOneWidget);
      expect(find.byKey(dot), findsNothing);
      expect(inCard(first, '1 new'), findsNothing);

      rows = [
        {'job_id': first, 'unseen_count': 1},
        {'job_id': second, 'unseen_count': 1500},
        {'job_id': third, 'unseen_count': 0},
      ];
      await unseen.refresh();
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.byKey(dot), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('View Applicants, new applications')),
        findsOneWidget,
      );
      if (!kIsWeb || width < 1000) {
        router.routerDelegate.navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
      }
      expect(inCard(first, '1 new'), findsOneWidget);
      expect(inCard(second, '999+ new'), findsOneWidget);
      expect(find.bySemanticsLabel('1500 new applications'), findsOneWidget);
      expect(inCard(third, '0 new'), findsNothing);

      final button = inCard(second, 'View Applicants');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text(second), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();

      actor = 'employer-b';
      accountChanges.add(actor);
      await tester.pumpAndSettle();
      expect(inCard(first, '1 new'), findsNothing);
      expect(inCard(second, '999+ new'), findsNothing);
      await openMenu();
      expect(find.byKey(dot), findsNothing);
      final destination = menuText('View Applicants');
      await tester.ensureVisible(destination);
      await tester.tap(destination);
      await tester.pumpAndSettle();
      expect(find.text('All applicants'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
