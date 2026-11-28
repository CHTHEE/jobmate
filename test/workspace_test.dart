import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// Supabase's injectable HTTP client lets this fixture run on Web and native.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:jobmate/features/home/dashboard_content.dart';
import 'package:jobmate/features/home/employer_dashboard.dart';
import 'package:jobmate/features/jobs/job_form_page.dart';
import 'package:jobmate/features/jobs/job_form_result.dart';
import 'package:jobmate/features/jobs/job_form_route.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/payments/payment_feature_gate.dart';
import 'package:jobmate/features/profile/profile_page.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:jobmate/shared/navigation/workspace_destinations.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';
import 'package:jobmate/shared/widgets/app_workspace.dart';
import 'package:jobmate/shared/widgets/responsive_layout.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/workspace_navigation_test_helper.dart';
import 'job_postings_test.dart' show TestJobs, field;
import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, id, other;

void _myAccountSectionTests() {
  group('My Account settings', () {
    var role = 'job_seeker';
    setUpAll(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/shared_preferences'),
            (call) async => call.method == 'getAll' ? <String, Object>{} : true,
          );
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'fixture-key',
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          persistSession: false,
          detectSessionInUri: false,
          localStorage: EmptyLocalStorage(),
        ),
        httpClient: MockClient((request) async {
          if (request.url.path ==
              '/rest/v1/rpc/list_my_payment_recipient_methods_v1') {
            expect(role, 'job_seeker');
            return http.Response(
              '[]',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          expect(request.url.path, '/rest/v1/users');
          expect(request.url.queryParameters['user_id'], 'eq.account-id');
          return http.Response(
            jsonEncode({'name': 'Alex Tan', 'role': role, 'status': 'active'}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      await Supabase.instance.client.auth.setInitialSession(
        jsonEncode({
          'access_token':
              'eyJhbGciOiJub25lIn0.eyJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.',
          'token_type': 'bearer',
          'user': {'id': 'account-id', 'email': 'fixture@example.com'},
        }),
      );
    });
    tearDownAll(() async {
      await Supabase.instance.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/shared_preferences'),
            null,
          );
    });

    for (final accountRole in ['job_seeker', 'employer']) {
      // The section selector uses the compact layout below 760 logical pixels.
      for (final width in [320.0, 600.0, 1440.0]) {
        testWidgets('$accountRole can reach settings at $width', (
          tester,
        ) async {
          role = accountRole;
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final router = GoRouter(
            initialLocation: AppRoutes.profile,
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (_, _) => const ProfilePage(),
              ),
              GoRoute(
                path: AppRoutes.verifyPassword,
                builder: (_, _) =>
                    const Scaffold(body: Text('Verify password')),
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            MaterialApp.router(
              routerConfig: router,
              theme: JobMateTheme.light(),
            ),
          );
          await tester.pumpAndSettle();

          final dropdown = find.byKey(
            const ValueKey('my-account-mobile-section-navigation'),
          );
          final hasPayment =
              accountRole == 'job_seeker' && paymentRecipientSimulationEnabled;
          if (width < 760) {
            expect(
              tester
                  .widget<DropdownButtonFormField<MyAccountSection>>(dropdown)
                  .initialValue,
              MyAccountSection.profile,
            );
            await tester.ensureVisible(dropdown);
            await tester.tap(dropdown);
            await tester.pumpAndSettle();
            expect(
              find.text('Payment details'),
              hasPayment ? findsOneWidget : findsNothing,
            );
            await tester.tap(find.text('Account & security').last);
          } else {
            expect(
              find.byKey(const ValueKey('my-account-nav-profile')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('my-account-nav-payment')),
              hasPayment ? findsOneWidget : findsNothing,
            );
            await tester.tap(
              find.byKey(const ValueKey('my-account-nav-security')),
            );
          }
          await tester.pumpAndSettle();
          final changePassword = find.text('Change password');
          await tester.ensureVisible(changePassword);
          await tester.tap(changePassword);
          await tester.pumpAndSettle();
          expect(find.text('Verify password'), findsOneWidget);
          router.pop();
          await tester.pumpAndSettle();

          if (width < 760) {
            await tester.ensureVisible(dropdown);
            await tester.tap(dropdown);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Notifications').last);
          } else {
            await tester.tap(
              find.byKey(const ValueKey('my-account-nav-notifications')),
            );
          }
          await tester.pumpAndSettle();
          expect(find.text('Notification preferences'), findsOneWidget);
          expect(
            find.widgetWithText(SwitchListTile, 'Application updates'),
            findsOneWidget,
          );
          if (hasPayment) {
            if (width < 760) {
              await tester.ensureVisible(dropdown);
              await tester.tap(dropdown);
              await tester.pumpAndSettle();
              await tester.tap(find.text('Payment details').last);
            } else {
              await tester.tap(
                find.byKey(const ValueKey('my-account-nav-payment')),
              );
            }
            await tester.pumpAndSettle();
            expect(find.text('Payment Details'), findsOneWidget);
            expect(find.text('Could not load payment details.'), findsNothing);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}

void main() {
  _employerDashboardTests();
  _myAccountSectionTests();
  test('Job Seekers have one primary browse destination', () {
    final paths = workspaceDestinations('job_seeker').values
        .expand((items) => items)
        .map((item) => item.$1);
    expect(paths.where((path) => path == AppRoutes.browseJobs), hasLength(1));
    expect(paths, isNot(contains(AppRoutes.search)));
    expect(
      paths,
      containsAll([AppRoutes.recommendations, AppRoutes.applications]),
    );
  });

  test('employer keeps real verification and hides only attendance demo navigation', () {
    final paths = workspaceDestinations('employer').values
        .expand((items) => items)
        .map((item) => item.$1);
    expect(paths, contains(AppRoutes.workVerification));
    expect(paths, isNot(contains(AppRoutes.attendanceReview)));
    expect(paths, contains(AppRoutes.workers));
    expect(paths, contains(AppRoutes.employerPayments));
  });

  test('Admin destinations follow assigned permissions and hide unavailable modules', () {
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
    final paths = groups.values.expand((items) => items).map((item) => item.$1);

    expect(paths, contains(AppRoutes.adminUsers));
    expect(paths, contains(AppRoutes.adminReports));
    expect(paths, isNot(contains(AppRoutes.inviteAdmin)));
    expect(paths, contains(AppRoutes.adminCompanies));
    expect(paths, isNot(contains(AppRoutes.adminJobModeration)));
    expect(paths, isNot(contains(AppRoutes.adminDisputes)));
    expect(paths, isNot(contains(AppRoutes.companyReviews)));
    expect(paths, contains(AppRoutes.adminPermissions));
  });

  test('Superadmin gets the User Management destination by role', () {
    final groups = adminWorkspaceDestinations({
      'can_manage_admin_permissions': true,
      'can_manage_user_accounts': false,
    });
    final paths = groups.values.expand((items) => items).map((item) => item.$1);

    expect(paths, contains(AppRoutes.adminUsers));
  });

  test(
    'Administrator primary tabs are stable and nested company routes match',
    () {
      expect(
        workspacePrimaryDestinations('administrator').map((item) => item.$1),
        [AppRoutes.home, AppRoutes.adminUsers, AppRoutes.adminPayments],
      );
      final destinations = adminWorkspaceDestinations({}).values
          .expand((items) => items);
      expect(
        selectedWorkspacePath(
          '${AppRoutes.adminCompanies}/synthetic-company',
          destinations,
        ),
        AppRoutes.adminCompanies,
      );
    },
  );

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
        fail(
          'Expected NavigationDestination, found ${destination.runtimeType}.',
        );
      }
      return destination.label;
    }).toList();
    expect(labels, ['Home', 'Users', 'Payments', 'Account', 'More']);
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
      expect(find.text('My Account'), findsOneWidget);
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
      await scrollWorkspaceMenuTo(tester, 'Payments');
      expect(find.widgetWithText(ListTile, 'Payments'), findsOneWidget);
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
        expect(find.text('Account settings'), findsNothing);
        await tester.tap(find.text('My Account'));
        await tester.pumpAndSettle();
        expect(destination, AppRoutes.profile);

        if (role == 'employer') {
          await tester.tap(
            kIsWeb
                ? find.byKey(const ValueKey('workspace-account-menu'))
                : find.text('Account'),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Company Reputation'));
          await tester.pumpAndSettle();
          expect(destination, AppRoutes.employerReputation);
        }

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
          expect(find.text('Applied companies'), findsNothing);
          expect(find.text('Evaluations from others'), findsNothing);
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
        await tester.tap(find.text('My Account'));
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

class _DashboardFormRepository extends TestJobs {
  final accessCheck = Completer<JobAccess>();

  @override
  Future<JobAccess> loadAccess({bool includeLogo = true}) => accessCheck.future;
}

void _employerDashboardTests() {
  const profile = {
    'role': 'employer',
    'status': 'active',
    'name': 'Real Employer',
    'verification_status': 'rejected',
  };
  Map<String, dynamic> company(String key) => {
    'company_id': key,
    'company_name': key == id ? 'Current Company' : 'Other Company',
    'verification_status': 'verified',
    'industry': 'Retail',
    'location': 'Selangor',
  };

  testWidgets(
    'Dashboard Post Job uses one existing form and refreshes only created results',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _DashboardFormRepository();
      final work = FakeSource()..companyRead = (_) async => [];
      addTearDown(work.changes.close);
      var reads = 0;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: WorkspaceContent(
                maxWidth: double.infinity,
                child: EmployerDashboard(
                  profile: profile,
                  email: 'employer@example.invalid',
                  company: company(id),
                  companyError: null,
                  memberRole: 'owner',
                  onProfile: () {},
                  onCompany: () {},
                  onVerification: () {},
                  createData: () => EmployerDashboardData(
                    loadAccess: () async => JobAccess(company(id), null),
                    listPostings: (_) async {
                      reads++;
                      return [];
                    },
                    work: WorkAttendanceRepository(work),
                  ),
                ),
              ),
            ),
          ),
          jobFormRoute(AppRoutes.createJob, repository: repository),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final header = find.widgetWithText(FilledButton, 'Post Job');
      final open = tester.widget<FilledButton>(header).onPressed!;
      open();
      open();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final form = find.byType(JobFormPage);
      expect(form, findsOneWidget);
      expect(tester.widget<JobFormPage>(form).dialog, isTrue);
      expect(find.text('Verifying company...'), findsOneWidget);
      expect(find.text('Current Company'), findsWidgets);
      expect(reads, 1);
      repository.accessCheck.complete(JobAccess(company(id), null));
      await tester.pumpAndSettle();
      field(tester, 'Job title').text = 'Unsaved fixture title';
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(form, findsOneWidget);
      await tester.tap(find.byTooltip('Close job form'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(form, findsNothing);
      expect(header, findsOneWidget);
      expect(reads, 1);

      Future<void> openQuickAction() async {
        final quick = find.text('Post New Job');
        await tester.ensureVisible(quick);
        await tester.tap(quick);
        await tester.pumpAndSettle();
        expect(tester.widget<JobFormPage>(form).dialog, isTrue);
      }

      await openQuickAction();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(reads, 1);
      await openQuickAction();
      field(tester, 'Job title').text = 'Draft fixture title';
      await tester.tap(find.text('Save Draft'));
      await tester.pumpAndSettle();
      expect(repository.saved?['status'], 'draft');
      expect(form, findsNothing);
      expect(reads, 2);
      await openQuickAction();
      router.pop(
        JobFormResult(JobFormChange.created, {
          'job_id': 'published-fixture',
          'status': 'published',
        }),
      );
      await tester.pumpAndSettle();
      expect(reads, 3);
      expect(header, findsOneWidget);
      router.go(AppRoutes.createJob);
      await tester.pumpAndSettle();
      expect(tester.widget<JobFormPage>(form).dialog, isFalse);
    },
  );
  Map<String, dynamic> posting(
    String key,
    String title, {
    String status = 'published',
    String deadline = '2026-12-10',
    String published = '2026-11-23T09:00:00Z',
  }) => {
    'company_id': id,
    'job_id': key,
    'title': title,
    'status': status,
    'application_deadline': deadline,
    'published_at': published,
    'employment_type': 'part_time',
    'location': 'Kuala Lumpur',
  };

  testWidgets(
    'Employer dashboard uses independently loaded postings and work, real routes and centered layout',
    (tester) async {
      const longTitle = 'Customer operations and community support coordinator';
      const longLocation =
          'Kuala Lumpur city centre and surrounding neighbourhoods';
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1700, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pendingPosts = Completer<List<Map<String, dynamic>>>();
      final work = FakeSource();
      addTearDown(work.changes.close);
      work.companyRead = (scope) async {
        expect(scope, id);
        return [
          {
            ...assignment(company: true),
            'job_title': 'Verified upcoming fixture',
            'attendance_as_of': '2026-11-04T09:00:00Z',
          },
          {
            ...assignment(company: true),
            'assignment_id': other,
            'assignment_status': 'awaiting_verification',
            'verification_status': 'pending_review',
            'attendance_as_of': '2026-11-06T09:00:00Z',
          },
        ];
      };
      final dashboard = EmployerDashboard(
        profile: profile,
        email: 'employer@example.invalid',
        company: company(id),
        companyError: null,
        memberRole: 'owner',
        onProfile: () {},
        onCompany: () {},
        onVerification: () {},
        now: () => DateTime(2026, 11, 26),
        createData: () => EmployerDashboardData(
          loadAccess: () async => JobAccess(company(id), null),
          listPostings: (scope) {
            expect(scope, id);
            return pendingPosts.future;
          },
          work: WorkAttendanceRepository(work),
        ),
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Row(
                children: [
                  if (MediaQuery.sizeOf(context).width >= 768)
                    const SizedBox(width: 240),
                  Expanded(
                    child: WorkspaceContent(
                      maxWidth: double.infinity,
                      child: dashboard,
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final route in [
            AppRoutes.createJob,
            AppRoutes.applicants,
            AppRoutes.workers,
            AppRoutes.workVerification,
          ])
            GoRoute(
              path: route,
              builder: (_, _) => Scaffold(body: Text(route)),
            ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                MediaQuery.sizeOf(context).width < 600 ? 1.6 : 1,
              ),
            ),
            child: child!,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Loading company postings...'), findsOneWidget);
      expect(find.text('Verified upcoming fixture'), findsOneWidget);
      expect(find.text('Shifts needing action'), findsOneWidget);
      expect(
        find.text('Workers with upcoming or in-progress shifts'),
        findsOneWidget,
      );
      expect(
        find.text('Counts reflect available company postings.'),
        findsNothing,
      );
      pendingPosts.complete([
        posting('d', 'Fourth posting', published: '2026-11-21T09:00:00Z'),
        posting('b', 'Second posting'),
        posting('a', 'First posting'),
        {
          ...posting('c', longTitle, published: '2026-11-22T09:00:00Z'),
          'location': longLocation,
        },
        posting('expired', 'Expired posting', deadline: '2026-11-01'),
        posting('closed', 'Closed posting', status: 'closed'),
        posting('draft', 'Draft posting', status: 'draft'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('7'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('First posting'), findsOneWidget);
      expect(find.text('Second posting'), findsOneWidget);
      expect(find.text(longTitle), findsOneWidget);
      expect(find.text('Fourth posting'), findsNothing);
      expect(find.text('Expired posting'), findsNothing);
      expect(find.text('Closed posting'), findsNothing);
      expect(find.text('Sample applicants'), findsNothing);
      expect(find.text('Your hiring workspace, connected'), findsNothing);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      final rect = tester.getRect(find.byWidget(dashboard));
      final section = tester.getRect(
        find
            .ancestor(
              of: find.text('Total Jobs'),
              matching: find.byType(ResponsiveGrid),
            )
            .first,
      );
      expect(section.width, closeTo(1200, 1));
      expect(section.left - rect.left, closeTo(rect.right - section.right, 1));
      expect(
        tester.getTopLeft(find.text('First posting')).dx,
        lessThan(tester.getTopLeft(find.text('Second posting')).dx),
      );
      Finder card(String heading) => find
          .ancestor(of: find.text(heading), matching: find.byType(Card))
          .first;
      final first = tester.getRect(card('First posting'));
      final second = tester.getRect(card('Second posting'));
      final third = tester.getRect(card(longTitle));
      expect(second.top, closeTo(first.top, 1));
      expect(third.top, closeTo(first.top, 1));
      expect(third.size, first.size);
      final footers = find.text('View Job');
      expect(
        tester.getRect(footers.first).bottom,
        closeTo(tester.getRect(footers.last).bottom, 1),
      );
      for (final (left, right) in [
        ('Work Management', 'Worker Overview'),
        ('Company Overview', 'Your Account'),
      ]) {
        expect(
          tester.getRect(card(left)).top,
          closeTo(tester.getRect(card(right)).top, 1),
        );
        expect(
          tester.getRect(card(left)).bottom,
          closeTo(tester.getRect(card(right)).bottom, 1),
        );
      }
      expect(
        find.descendant(
          of: card('Company Overview'),
          matching: find.byIcon(Icons.business_outlined),
        ),
        findsOneWidget,
      );
      for (final (label, route) in [
        ('Review Applicants', AppRoutes.applicants),
        ('Manage Workers', AppRoutes.workers),
        ('Manage Work', AppRoutes.workVerification),
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        final destination = find.text(route);
        expect(destination, findsOneWidget);
        tester.element(destination).pop();
        await tester.pumpAndSettle();
      }
      tester.view.physicalSize = const Size(1120, 900);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(card('Second posting')).top,
        closeTo(tester.getRect(card('First posting')).top, 1),
      );
      expect(
        tester.getRect(card(longTitle)).top,
        greaterThan(tester.getRect(card('First posting')).bottom),
      );
      tester.view.physicalSize = const Size(320, 900);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(card('Second posting')).top,
        greaterThan(tester.getRect(card('First posting')).bottom),
      );
      expect(find.text(longLocation), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Work Management')).dy,
        lessThan(tester.getTopLeft(find.text('Worker Overview')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Company Overview presents available authorized logo bytes and keeps the fallback',
    (tester) async {
      final work = FakeSource()..companyRead = (_) async => [];
      addTearDown(work.changes.close);
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jBz0AAAAASUVORK5CYII=',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceContent(
              maxWidth: double.infinity,
              child: EmployerDashboard(
                profile: profile,
                email: 'employer@example.invalid',
                company: company(id),
                companyError: null,
                memberRole: 'owner',
                onProfile: () {},
                onCompany: () {},
                onVerification: () {},
                createData: () => EmployerDashboardData(
                  loadAccess: () async =>
                      JobAccess(company(id), null, logo: bytes),
                  listPostings: (_) async => [],
                  work: WorkAttendanceRepository(work),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final logo = find.byWidgetPredicate(
        (widget) =>
            widget is Image && widget.semanticLabel == 'Current Company logo',
      );
      final image = tester.widget<Image>(logo);
      expect(image.width, 44);
      final fallback = image.errorBuilder!(
        tester.element(logo),
        StateError('Bad image'),
        null,
      );
      await tester.pumpWidget(MaterialApp(home: fallback));
      expect(find.byIcon(Icons.business_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'Employer rejects wrong company access and stale results after switching',
    (tester) async {
      final work = FakeSource();
      addTearDown(work.changes.close);
      final first = Completer<List<Map<String, dynamic>>>();
      var checks = 0;
      final data = EmployerDashboardData(
        loadAccess: () async =>
            JobAccess(company(++checks == 1 ? id : other), null),
        listPostings: (scope) => scope == id ? first.future : Future.value([]),
        work: WorkAttendanceRepository(work..companyRead = (_) async => []),
      );
      Widget page(String scope) => MaterialApp(
        home: Scaffold(
          body: WorkspaceContent(
            maxWidth: double.infinity,
            child: EmployerDashboard(
              profile: profile,
              email: 'employer@example.invalid',
              company: company(scope),
              companyError: null,
              memberRole: 'owner',
              onProfile: () {},
              onCompany: () {},
              onVerification: () {},
              createData: () => data,
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(id));
      await tester.pump();
      expect(find.text('Post Job'), findsOneWidget);
      await tester.pumpWidget(page(other));
      await tester.pumpAndSettle();
      first.complete([posting('late', 'Previous company posting')]);
      await tester.pumpAndSettle();
      expect(find.text('Previous company posting'), findsNothing);
      expect(find.text('Current Company'), findsNothing);
      work.switchAccount(null);
      await tester.pumpAndSettle();
      expect(find.text('Other Company'), findsNothing);
      expect(find.text('Review Applicants'), findsNothing);
    },
  );

  testWidgets(
    'Employer posting retry stays scoped and leaves the work section usable',
    (tester) async {
      final work = FakeSource()..companyRead = (_) async => [];
      addTearDown(work.changes.close);
      final retry = Completer<List<Map<String, dynamic>>>();
      var requests = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceContent(
              maxWidth: double.infinity,
              child: EmployerDashboard(
                profile: profile,
                email: 'employer@example.invalid',
                company: company(id),
                companyError: null,
                memberRole: 'owner',
                onProfile: () {},
                onCompany: () {},
                onVerification: () {},
                createData: () => EmployerDashboardData(
                  loadAccess: () async => JobAccess(company(id), null),
                  listPostings: (scope) async {
                    expect(scope, id);
                    if (++requests == 1) throw StateError('Offline');
                    return retry.future;
                  },
                  work: WorkAttendanceRepository(work),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Company postings could not be loaded.'),
        findsOneWidget,
      );
      expect(
        find.text('No upcoming shifts in loaded assignments.'),
        findsOneWidget,
      );
      final retryButton = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Retry'))
          .onPressed!;
      retryButton();
      retryButton();
      await tester.pump();
      expect(requests, 2);
      expect(
        find.text('Counts reflect available company postings.'),
        findsNothing,
      );
      retry.complete([]);
      await tester.pumpAndSettle();
      expect(
        find.text('No loaded postings are open for applications.'),
        findsOneWidget,
      );
      expect(
        find.text('Counts reflect available company postings.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Employer company mismatch gates requests and narrow large text remains usable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final work = FakeSource();
      addTearDown(work.changes.close);
      var postingCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: WorkspaceContent(
              maxWidth: double.infinity,
              child: EmployerDashboard(
                profile: profile,
                email: 'employer@example.invalid',
                company: company(id),
                companyError: null,
                memberRole: 'owner',
                onProfile: () {},
                onCompany: () {},
                onVerification: () {},
                createData: () => EmployerDashboardData(
                  loadAccess: () async => JobAccess(company(other), null),
                  listPostings: (_) async {
                    postingCalls++;
                    return [];
                  },
                  work: WorkAttendanceRepository(work),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(postingCalls, 0);
      expect(
        find.text(
          'The hiring company changed. Check for updates before continuing.',
        ),
        findsOneWidget,
      );
      expect(find.text('Post Job'), findsNothing);
      expect(find.text('Manage Workers'), findsNothing);
      expect(find.text('Company Overview'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Company Overview')).dy,
        lessThan(tester.getTopLeft(find.text('Your Account')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
