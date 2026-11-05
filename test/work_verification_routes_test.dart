import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_verification_pages.dart';
import 'package:jobmate/features/work_attendance/work_verification_routes.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:jobmate/shared/navigation/workspace_destinations.dart';
import 'package:jobmate/shared/widgets/app_workspace.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/workspace_navigation_test_helper.dart';
import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, id, other;

void main() {
  late FakeSource source;
  late Future<bool> Function() roleCheck;
  late Future<JobAccess> Function() companyAccess;
  late List<String> companies;
  late GoRouter router;
  GoRouter createRouter({String initial = AppRoutes.workVerification}) =>
      GoRouter(
        initialLocation: initial,
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const AppWorkspace(
              title: 'Dashboard',
              path: '/',
              role: 'employer',
              showAccountMenu: false,
              child: Text('Employer dashboard'),
            ),
          ),
          workVerificationRoute(
            source: source,
            checkAccess: () => roleCheck(),
            loadCompanyAccess: () => companyAccess(),
          ),
        ],
      );
  setUp(() {
    source = FakeSource();
    companies = [];
    source.companyRead = (company) async {
      companies.add(company);
      return [assignment(company: true)];
    };
    source.workerRead = () =>
        throw StateError('Must not read worker assignments');
    source.evidenceRead = (_) => throw StateError('Must not read evidence');
    roleCheck = () async => true;
    companyAccess = () async => const JobAccess({'company_id': id}, null);
  });
  tearDown(() async {
    router.dispose();
    await source.changes.close();
  });

  test('employer destination is distinct; other roles do not see it', () {
    final destinations = workspaceDestinations('employer').values
        .expand((v) => v);
    expect(
      destinations.where((v) => v.$1 == AppRoutes.workVerification).single.$2,
      'Work Verification',
    );
    expect(
      destinations.where((v) => v.$1 == AppRoutes.attendanceReview).single.$2,
      'Attendance Review (demo)',
    );
    expect(AppRoutes.workVerification, '/work-verification');
    expect(isWorkspaceRootPath(AppRoutes.workVerification), isTrue);
    expect(
      selectedWorkspacePath(AppRoutes.workVerification, destinations),
      AppRoutes.workVerification,
    );
    for (final role in ['job_seeker', 'administrator', 'guest']) {
      expect(
        workspaceDestinations(role).values
            .expand((v) => v)
            .where((v) => v.$1 == AppRoutes.workVerification),
        isEmpty,
      );
    }
    router = createRouter();
  });

  testWidgets(
    'direct URL uses resolved company, ignoring untrusted query UUID',
    (tester) async {
      router = createRouter(
        initial: '${AppRoutes.workVerification}?company_id=$other',
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(companies, [id]);
      expect(find.byType(WorkVerificationPage), findsOneWidget);
      expect(find.text('Server job'), findsOneWidget);
      expect(
        tester.widget<AppWorkspace>(find.byType(AppWorkspace)).path,
        AppRoutes.workVerification,
      );
            if (find.byKey(const ValueKey('workspace-bottom-navigation'))
          .evaluate()
          .isNotEmpty) {
        // Native layout: Home is in the bottom navigation bar.
        final home = find.descendant(
          of: find.byKey(const ValueKey('workspace-bottom-navigation')),
          matching: find.widgetWithText(NavigationDestination, 'Home'),
        );
        expect(home, findsOneWidget);
        await tester.tap(home);
      } else {
        // Web layout: the workspace menu provides a dashboard shortcut.
        await openWorkspaceMenu(tester);
        final dashboard = find.byTooltip('Go to dashboard');
        expect(dashboard, findsOneWidget);
        await tester.tap(dashboard);
      }
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(source.changes.hasListener, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final role in ['job_seeker', 'inactive employer']) {
    testWidgets('$role denied before company lookup or assignment reads', (
      tester,
    ) async {
      roleCheck = () async => false;
      companyAccess = () async => throw StateError('Must not resolve company');
      router = createRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('Page unavailable'), findsOneWidget);
      expect(source.calls, 0);
      final dashboardAction = find.byTooltip('Go to dashboard');
      final backAction = find.byTooltip('Back');

      if (dashboardAction.evaluate().isNotEmpty) {
        await tester.tap(dashboardAction);
      } else {
        expect(backAction, findsOneWidget);
        await tester.tap(backAction);
      }
      await tester.pumpAndSettle();
      expect(find.text('Employer dashboard'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('signed-out direct entry never calls checks or RPCs', (
    tester,
  ) async {
    source.userId = null;
    roleCheck = () async => throw StateError('Must not run');
    companyAccess = () async => throw StateError('Must not run');
    router = createRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Page unavailable'), findsOneWidget);
    expect(source.calls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (name, failure) in <(String, Object)>[
    (
      'ambiguous membership',
      const PostgrestException(message: 'Multiple rows', code: 'PGRST116'),
    ),
    ('connection', Exception('offline')),
  ]) {
    testWidgets(
      '$name blocks company resolution with retry and no arbitrary choice',
      (tester) async {
        companyAccess = () async => throw failure;
        router = createRouter();
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        expect(find.text('Company access unavailable'), findsOneWidget);
        if (name == 'ambiguous membership') {
          expect(
            find.textContaining('could not be resolved uniquely'),
            findsOneWidget,
          );
        }
        expect(companies, isEmpty);
        companyAccess = () async =>
            const JobAccess({'company_id': other}, null);
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(companies, [other]);
        expect(find.text('Server job'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'missing onboarding or verification and malformed company IDs fail closed',
    (tester) async {
      router = createRouter();
      for (final access in [
        const JobAccess(null, 'Complete company onboarding.'),
        const JobAccess({'company_id': id}, 'Company verification pending.'),
        const JobAccess({'company_id': 'invalid'}, null),
      ]) {
        companyAccess = () async => access;
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        expect(find.text('Company access unavailable'), findsOneWidget);
        expect(source.calls, 0);
        router.go('/');
        await tester.pumpAndSettle();
        router.go(AppRoutes.workVerification);
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account switch resolves new company, rejects stale assignments, logout clears',
    (tester) async {
      final old = Completer<List<Map<String, dynamic>>>();
      source.companyRead = (company) {
        companies.add(company);
        return company == id
            ? old.future
            : Future.value([
                assignment(company: true)..['job_title'] = 'New company shift',
              ]);
      };
      companyAccess = () async =>
          JobAccess({'company_id': source.userId}, null);
      router = createRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      await tester.pump();
      expect(companies, [id]);
      source.switchAccount(other);
      await tester.pumpAndSettle();
      expect(companies, [id, other]);
      expect(find.text('New company shift'), findsOneWidget);
      old.complete([assignment(company: true)]);
      await tester.pumpAndSettle();
      expect(find.text('Server job'), findsNothing);
      source.switchAccount(null);
      await tester.pumpAndSettle();
      expect(find.text('New company shift'), findsNothing);
      expect(find.text('Page unavailable'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(source.changes.hasListener, isFalse);
    },
  );

  testWidgets('pending old company resolution cannot cross an account change', (
    tester,
  ) async {
    final pending = Completer<JobAccess>();
    companyAccess = () => pending.future;
    router = createRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    companyAccess = () async => const JobAccess({'company_id': other}, null);
    source.switchAccount(other);
    await tester.pumpAndSettle();
    pending.complete(const JobAccess({'company_id': id}, null));
    await tester.pumpAndSettle();
    expect(companies, [other]);
    expect(
      tester
          .widget<WorkVerificationPage>(find.byType(WorkVerificationPage))
          .companyId,
      other,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'menu entry, fresh URL reload and router Back preserve list access',
    (tester) async {
      router = createRouter(initial: '/');
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await openWorkspaceMenu(tester);
      await scrollWorkspaceMenuTo(tester, 'Work Verification');
      await tester.tap(find.widgetWithText(ListTile, 'Work Verification'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutes.workVerification,
      );
      expect(find.text('Server job'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      router = createRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(companies, [id, id]);
      router.push('/');
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Server job'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(source.changes.hasListener, isFalse);
    },
  );
}
