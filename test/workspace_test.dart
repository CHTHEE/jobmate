import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/home/dashboard_content.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:jobmate/shared/navigation/workspace_destinations.dart';
import 'package:jobmate/shared/widgets/app_workspace.dart';

import 'support/workspace_navigation_test_helper.dart';

void main() {
  test(
    'Admin destinations follow assigned permissions and hide unavailable modules',
    () {
      final groups = adminWorkspaceDestinations({
        'can_manage_user_accounts': true,
        'can_manage_company_restrictions': false,
        'can_manage_user_reports': true,
        'can_manage_job_moderation': false,
        'can_manage_disputes': false,
        'can_review_companies': false,
        'can_invite_admins': true,
        'can_manage_admin_permissions': false,
      });
      final paths = groups.values
          .expand((items) => items)
          .map((item) => item.$1);

      expect(paths, contains(AppRoutes.adminUsers));
      expect(paths, contains(AppRoutes.adminReports));
      expect(paths, contains(AppRoutes.inviteAdmin));
      expect(paths, contains(AppRoutes.adminCompanies));
      expect(paths, isNot(contains(AppRoutes.adminJobModeration)));
      expect(paths, isNot(contains(AppRoutes.adminDisputes)));
      expect(paths, isNot(contains(AppRoutes.companyReviews)));
      expect(paths, isNot(contains(AppRoutes.adminPermissions)));
    },
  );

  test('Superadmin gets the User Management destination by role', () {
    final groups = adminWorkspaceDestinations({
      'can_manage_admin_permissions': true,
      'can_manage_user_accounts': false,
    });
    final paths = groups.values.expand((items) => items).map((item) => item.$1);

    expect(paths, contains(AppRoutes.adminUsers));
  });

  test('Administrator primary tabs are stable and nested company routes match', () {
    expect(
      workspacePrimaryDestinations('administrator').map((item) => item.$1),
      [AppRoutes.home, AppRoutes.adminUsers, AppRoutes.adminPayments],
    );
    final destinations = adminWorkspaceDestinations({})
        .values
        .expand((items) => items);
    expect(
      selectedWorkspacePath(
        '${AppRoutes.adminCompanies}/synthetic-company',
        destinations,
      ),
      AppRoutes.adminCompanies,
    );
  });

  testWidgets('Admin detail routes retain the same bottom navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AppWorkspace(
          title: 'Example company',
          path: '${AppRoutes.adminCompanies}/synthetic-company',
          role: 'administrator',
          focused: true,
          backFallback: AppRoutes.adminCompanies,
          child: const Text('Company detail'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    final labels = bar.destinations.map((destination) {
      if (destination is! NavigationDestination) {
        fail('Expected NavigationDestination, found ${destination.runtimeType}.');
      }
      return destination.label;
    }).toList();
    expect(
      labels,
      ['Home', 'Users', 'Payments', 'Account', 'More'],
    );
    expect(bar.selectedIndex, 4);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Company directory'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Short native layout keeps Account separate from More', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selectedPath;
    await tester.pumpWidget(
      MaterialApp(
        home: AppWorkspace(
          title: 'Dashboard',
          path: AppRoutes.home,
          role: 'job_seeker',
          onNavigate: (path) => selectedPath = path,
          child: const SizedBox(),
        ),
      ),
    );
    if (!kIsWeb) {
      final bottomBar = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(bottomBar.destinations.length, 5);
      expect(
        (bottomBar.destinations[1] as NavigationDestination).label,
        'Jobs',
      );
      await tester.tap(find.text('Jobs'));
      expect(selectedPath, AppRoutes.browseJobs);
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      expect(find.text('My profile'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Dashboard'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Search'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Browse Jobs'), findsNothing);
      await tester.drag(
        find.byKey(const ValueKey('workspace-navigation')),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign out'), findsOneWidget);
      final moreList = tester.widget<ListView>(
        find.byKey(const ValueKey('workspace-navigation')),
      );
      final moreChildren =
          (moreList.childrenDelegate as SliverChildListDelegate).children;
      expect(
        find.descendant(
          of: find.byWidget(moreChildren.last),
          matching: find.text('Sign out'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  for (final role in ['job_seeker', 'employer']) {
    testWidgets('$role keeps Payments in navigation without section headings', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: AppWorkspace(
            title: 'Dashboard',
            path: AppRoutes.home,
            role: role,
            child: const SizedBox(),
          ),
        ),
      );
      await openWorkspaceMenu(tester);
      await scrollWorkspaceMenuTo(tester, 'Payments (sandbox)');
      expect(
        find.widgetWithText(ListTile, 'Payments (sandbox)'),
        findsOneWidget,
      );
      for (final heading in ['COMMUNICATION', 'PROFILE', 'WORKERS']) {
        expect(find.text(heading), findsNothing);
      }
      expect(find.widgetWithText(ListTile, 'Personal profile'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Account Settings'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final role in ['job_seeker', 'employer']) {
    for (final width in [320.0, 1440.0]) {
      testWidgets('$role account menu routes correctly at $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? destination;
        var signedOut = false;
        await tester.pumpWidget(
          MaterialApp(
            home: AppWorkspace(
              title: 'My Applications',
              path: AppRoutes.applications,
              role: role,
              accountName: 'Alex Tan',
              onNavigate: (path) => destination = path,
              onSignOut: () async => signedOut = true,
              child: const SizedBox(),
            ),
          ),
        );
        expect(
          find.byKey(const ValueKey('workspace-account-menu')),
          kIsWeb ? findsOneWidget : findsNothing,
        );
        if (!kIsWeb) expect(find.text('Account'), findsOneWidget);
        expect(
          find.text('Alex Tan'),
          kIsWeb && width == 1440 ? findsOneWidget : findsNothing,
        );

        await tester.tap(
          kIsWeb
              ? find.byKey(const ValueKey('workspace-account-menu'))
              : find.text('Account'),
        );
        await tester.pumpAndSettle();
        if (!kIsWeb) expect(find.text('Sign out'), findsNothing);
        await tester.tap(find.text('My profile'));
        await tester.pumpAndSettle();
        expect(destination, AppRoutes.profile);

        if (role == 'employer') {
          await tester.tap(
            kIsWeb
                ? find.byKey(const ValueKey('workspace-account-menu'))
                : find.text('Account'),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Reputation (demo)'));
          await tester.pumpAndSettle();
          expect(destination, AppRoutes.employerReputation);
        }

        await tester.tap(
          kIsWeb
              ? find.byKey(const ValueKey('workspace-account-menu'))
              : find.text('Account'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Account settings'));
        await tester.pumpAndSettle();
        expect(
          destination,
          role == 'employer' ? AppRoutes.employerSettings : AppRoutes.settings,
        );

        await tester.tap(
          kIsWeb
              ? find.byKey(const ValueKey('workspace-account-menu'))
              : find.byIcon(Icons.more_horiz),
        );
        await tester.pumpAndSettle();
        if (!kIsWeb) {
          expect(
            find.byKey(const ValueKey('workspace-navigation')),
            findsOneWidget,
          );
          await scrollWorkspaceMenuTo(tester, 'Sign out');
        }
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
        expect(signedOut, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [320.0, 1440.0]) {
    for (final destination in [
      (AppRoutes.profile, 'Personal profile'),
      (AppRoutes.company, 'Company profile'),
      (AppRoutes.jobPostings, 'My Job Postings'),
    ]) {
      testWidgets(
        '${destination.$2} platform leading and direct navigation at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final router = GoRouter(
            initialLocation: destination.$1,
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const Scaffold(body: Text('Dashboard root')),
              ),
              GoRoute(
                path: destination.$1,
                builder: (_, _) => AppWorkspace(
                  title: destination.$2,
                  path: destination.$1,
                  role: 'employer',
                  child: const Text('Page content'),
                ),
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          expect(router.canPop(), false);
          expect(
            tester
                .widget<AppBar>(find.byType(AppBar))
                .automaticallyImplyLeading,
            false,
          );
          expect(find.byType(BackButton), findsNothing);
          await openWorkspaceMenu(tester);
          if (kIsWeb) {
            await tester.tap(find.widgetWithText(ListTile, 'Dashboard'));
          } else {
            expect(find.widgetWithText(ListTile, 'Dashboard'), findsNothing);
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            await tester.tap(find.text('Home'));
          }
          await tester.pumpAndSettle();
          expect(find.text('Dashboard root'), findsOneWidget);
          router.push(destination.$1);
          await tester.pumpAndSettle();
          expect(router.canPop(), true);
          expect(find.byType(BackButton), findsNothing);
          expect(find.text('Page content'), findsOneWidget);
          // Back remains routed even when Web omits the visual arrow.
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.text('Dashboard root'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('Planned modules have no navigation actions', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: AppWorkspace(
          title: 'Personal profile',
          path: AppRoutes.profile,
          role: 'job_seeker',
          child: SizedBox(),
        ),
      ),
    );
    await openWorkspaceMenu(tester);
    for (final module in upcomingModules) {
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, module.$1),
      );
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
    }
    expect(find.widgetWithText(ListTile, 'Personal profile'), findsNothing);
    expect(
      find.byKey(const ValueKey('workspace-account-menu')),
      kIsWeb ? findsOneWidget : findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Navigation remains disabled during a profile operation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var navigated = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AppWorkspace(
          title: 'Personal profile',
          path: AppRoutes.profile,
          role: 'employer',
          navigationLocked: true,
          onNavigate: (_) => navigated = true,
          child: const SizedBox(),
        ),
      ),
    );
    if (kIsWeb) {
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Company profile'))
            .enabled,
        isFalse,
      );
    } else {
      expect(
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .onDestinationSelected,
        isNull,
      );
    }
    expect(navigated, isFalse);
  });
  for (final width in [320.0, 768.0, 1024.0, 1440.0]) {
    for (final role in ['job_seeker', 'employer']) {
      testWidgets('$role navigation and dashboard at $width', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? destination;
        await tester.pumpWidget(
          MaterialApp(
            home: AppWorkspace(
              title: 'Dashboard',
              path: AppRoutes.home,
              role: role,
              onNavigate: (value) => destination = value,
              child: WorkspaceContent(
                child: DashboardContent(
                  profile: {
                    'role': role,
                    'name': 'Test User',
                    'status': 'active',
                    'verification_status': 'pending',
                  },
                  email: 'test@example.com',
                  onProfile: () {},
                  onCompany: () {},
                  onVerification: () {},
                ),
              ),
            ),
          ),
        );
        if (role == 'job_seeker') {
          expect(find.text('Complete your profile'), findsOneWidget);
          expect(find.text('50%'), findsOneWidget);
          expect(find.text('Applied companies'), findsOneWidget);
          expect(find.text('Evaluations from others'), findsOneWidget);
          expect(find.text('Personal profile'), findsNothing);
        } else {
          expect(find.text('Profile completion: 50%'), findsOneWidget);
        }
        expect(
          find.text('Set up company'),
          role == 'employer' ? findsOneWidget : findsNothing,
        );
        await openWorkspaceMenu(tester);
        if (role == 'employer') {
          await scrollWorkspaceMenuTo(tester, 'Company profile');
        }
        expect(
          find.text('Company profile'),
          role == 'employer' ? findsOneWidget : findsNothing,
        );
        expect(find.widgetWithText(ListTile, 'Personal profile'), findsNothing);
        if (find
            .byKey(const ValueKey('workspace-sidebar'))
            .evaluate()
            .isEmpty) {
          await tester.tapAt(Offset(width - 2, 100));
          await tester.pumpAndSettle();
        }
        await tester.tap(
          kIsWeb
              ? find.byKey(const ValueKey('workspace-account-menu'))
              : find.text('Account'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('My profile'));
        await tester.pumpAndSettle();
        expect(destination, AppRoutes.profile);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final status in ['pending', 'verified', 'rejected']) {
    testWidgets(
      '$status company shows membership without granting management',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var opened = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WorkspaceContent(
                child: DashboardContent(
                  profile: const {'role': 'employer'},
                  email: 'test@example.com',
                  company: {
                    'company_name': 'Company under test',
                    'verification_status': status,
                  },
                  memberRole: 'member',
                  onProfile: () {},
                  onVerification: () {},
                  onCompany: () => opened = true,
                ),
              ),
            ),
          ),
        );
        expect(find.text('Membership: member'), findsOneWidget);
        expect(find.text('Set up company'), findsNothing);
        await tester.ensureVisible(find.text('View company profile'));
        await tester.tap(find.text('View company profile'));
        expect(opened, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Company error is not treated as missing membership', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceContent(
            child: DashboardContent(
              profile: const {'role': 'employer'},
              email: 'test@example.com',
              companyError: 'Unavailable',
              onProfile: () {},
              onVerification: () {},
              onCompany: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Company unavailable'), findsOneWidget);
    expect(find.text('Set up company'), findsNothing);
  });
}
