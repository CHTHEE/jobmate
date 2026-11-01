import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/home/dashboard_content.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:jobmate/shared/widgets/app_workspace.dart';

void main() {
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
    for (final module in upcomingModules) {
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, module.$1),
      );
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
    }
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Personal profile'))
          .selected,
      isTrue,
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
    await tester.tap(find.widgetWithText(ListTile, 'Company profile'));
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
        expect(find.text('Profile completion: 50%'), findsOneWidget);
        expect(
          find.text('Set up company'),
          role == 'employer' ? findsOneWidget : findsNothing,
        );
        if (width < 1024) {
          await tester.tap(find.byTooltip('Open navigation menu'));
          await tester.pumpAndSettle();
        }
        expect(
          find.text('Company profile'),
          role == 'employer' ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.widgetWithText(ListTile, 'Personal profile'));
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
