import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/admin/admin_dashboard_page.dart';
import 'package:jobmate/features/phase4/admin_preview_pages.dart';
import 'package:jobmate/features/phase4/phase4_store.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/workspace_navigation_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : true,
        );
    // No saved session and no network requests: only render the real shell.
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'fixture-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets('Admin dashboard has one shared account control', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AdminDashboardPage(email: 'fixture@example.com')),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Notifications'), findsOneWidget);
    expect(find.byTooltip('Refresh dashboard'), findsOneWidget);
    expect(find.textContaining('Admin - '), findsNothing);
    if (kIsWeb) {
      expect(
        find.byKey(const ValueKey('workspace-account-menu')),
        findsOneWidget,
      );
    } else {
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      final accountDestinations = bar.destinations.where((destination) {
        if (destination is! NavigationDestination) {
          fail(
            'Unexpected workspace navigation widget: ${destination.runtimeType}.',
          );
        }
        return destination.label == 'Account';
      });
      expect(accountDestinations.length, 1);
      expect(
        find.byKey(const ValueKey('workspace-account-menu')),
        findsNothing,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Admin sidebar ink remains visible when moderation is pushed and removed',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = Phase4Store();
      addTearDown(store.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const AdminDashboardPage(email: 'fixture@example.com'),
          ),
          GoRoute(
            path: AppRoutes.adminDemoJobs,
            builder: (_, _) => AdminPreviewPage(section: 'Jobs', store: store),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump(const Duration(milliseconds: 300));
      await openWorkspaceMenu(tester);
      // Read-only directories are shared with all active Admins.
      expect(find.widgetWithText(ListTile, 'Users'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Companies'), findsOneWidget);
      if (!kIsWeb) {
        Navigator.of(
          tester.element(find.byKey(const ValueKey('workspace-navigation'))),
        ).pop();
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      router.push(AppRoutes.adminDemoJobs);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AdminPreviewPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      router.pop();
      await tester.pump(const Duration(seconds: 1));
      await openWorkspaceMenu(tester);
      expect(find.widgetWithText(ListTile, 'Users'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Companies'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Signed out view'))),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
