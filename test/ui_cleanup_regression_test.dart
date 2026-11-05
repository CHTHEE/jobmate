import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/applications/employer_applicants_repository.dart';
import 'package:jobmate/features/applications/employer_status_change_form.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';
import 'package:jobmate/features/jobs/job_form_page.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:jobmate/shared/widgets/app_workspace.dart';

import 'fixtures/employer_applicants_source.dart';
import 'job_postings_test.dart' show TestJobs;
import 'support/workspace_navigation_test_helper.dart';

void main() {
  for (final entry in [
    ('employer', '/job-postings'),
    ('employer', '/applicants/job/applicant'),
    ('job_seeker', '/applications/application'),
    ('job_seeker', '/jobs/job'),
  ]) {
    testWidgets(
      '${entry.$1} sign-out replaces nested routes and ignores late errors: ${entry.$2}',
      (tester) async {
        final pending = Completer<void>();
        final router = GoRouter(
          initialLocation: entry.$2,
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('Login screen')),
            ),
            GoRoute(
              path: entry.$2,
              builder: (context, _) => AppWorkspace(
                title: 'Protected nested page',
                role: entry.$1,
                path: entry.$2,
                onNavigate: (path) =>
                    context.push(path), // The old callback could stack Login.
                onSignOut: () async {},
                accountName: 'Test account',
                child: FutureBuilder<void>(
                  future: pending.future,
                  builder: (_, snapshot) => Text(
                    snapshot.hasError
                        ? 'Unable to load application'
                        : 'Protected content',
                  ),
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('workspace-account-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/');
        expect(find.text('Login screen'), findsOneWidget);
        expect(find.text('Protected content'), findsNothing);
        pending.completeError(StateError('late session change'));
        await tester.pumpAndSettle();
        expect(find.text('Unable to load application'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final (from, next, title, phrase) in [
    (
      'submitted',
      MyApplicationStatus.shortlisted,
      'Application shortlisted',
      'has been shortlisted successfully. You can continue reviewing this application.',
    ),
    (
      'shortlisted',
      MyApplicationStatus.interview,
      'Interview stage updated',
      'has been moved to the interview stage successfully.',
    ),
    (
      'interview',
      MyApplicationStatus.offered,
      'Offer sent',
      'has been sent a job offer successfully.',
    ),
    (
      'submitted',
      MyApplicationStatus.rejected,
      'Application rejected',
      'has been marked as rejected.',
    ),
  ]) {
    testWidgets('friendly $next confirmation uses actual applicant name', (
      tester,
    ) async {
      final source = TestEmployerApplicantsSource()
        ..rows = [
          applicantRow('application', status: from)
            ..['applicant_name'] = 'Pat Example',
        ];
      final repo = EmployerApplicantsRepository(source, 'real-job-id');
      await repo.load();
      addTearDown(() async {
        repo.dispose();
        await source.changes.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmployerStatusChangeForm(
              repository: repo,
              applicant: repo.applicants.single,
              next: next,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Confirm ${employerTransitionLabel(next)}'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.text('Pat Example $phrase'), findsOneWidget);
      expect(find.textContaining('server confirmed'), findsNothing);
      expect(source.updates.single.$2, next);
    });
  }
  testWidgets('dirty job form cannot block completed sign-out', (tester) async {
    final repo = TestJobs();
    final key = GlobalKey<JobFormPageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: JobFormPage(key: key, repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    key.currentState!.fields['title']!.text = 'Unsaved job title';
    repo.authenticated = false;
    expect(await key.currentState!.confirmExit(), isTrue);
    expect(find.text('Discard unsaved changes?'), findsNothing);
    expect(repo.saves, 0);
  });
  for (final role in ['employer', 'job_seeker']) {
    testWidgets(
      '$role navigation expands active category and retains all destinations',
      (tester) async {
        final path = role == 'employer'
            ? AppRoutes.workVerification
            : AppRoutes.workAttendance;
        final label = role == 'employer'
            ? 'Work Verification'
            : 'My Work Shifts';
        await tester.pumpWidget(
          MaterialApp(
            home: AppWorkspace(
              title: 'Work',
              path: path,
              role: role,
              onNavigate: (_) {},
              showAccountMenu: false,
              child: const SizedBox(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await openWorkspaceMenu(tester);
        expect(find.widgetWithText(ListTile, label), findsOneWidget);
        expect(
          tester
              .widget<ListTile>(find.widgetWithText(ListTile, label))
              .selected,
          isTrue,
        );
        await scrollWorkspaceMenuTo(
          tester,
          role == 'employer' ? 'View Applicants' : 'Browse Jobs',
        );
        expect(
          find.text(role == 'employer' ? 'View Applicants' : 'Browse Jobs'),
          findsOneWidget,
        );
        await scrollWorkspaceMenuTo(tester, 'Dashboard');
        expect(find.text('Dashboard'), findsWidgets);
      },
    );
  }
}
