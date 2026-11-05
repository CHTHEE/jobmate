import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:jobmate/shared/navigation/app_page.dart';
import 'package:jobmate/shared/navigation/workspace_destinations.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';
import 'package:jobmate/shared/widgets/app_workspace.dart';
import 'package:jobmate/shared/widgets/responsive_layout.dart';

import 'support/workspace_navigation_test_helper.dart';

void main() {
  const widths = [
    320.0,
    360.0,
    390.0,
    430.0,
    599.0,
    600.0,
    768.0,
    839.0,
    840.0,
    1024.0,
    1280.0,
    1440.0,
    1920.0,
  ];
  for (final role in ['job_seeker', 'employer', 'administrator']) {
    for (final width in widths) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
          '$role shell $width / $scale on ${kIsWeb ? 'Web' : 'native'}',
          (tester) async {
            tester.view.physicalSize = Size(width, 720);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            String? destination;
            await tester.pumpWidget(
              MaterialApp(
                theme: JobMateTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: AppWorkspace(
                  title: 'Your workspace',
                  path: AppRoutes.profile,
                  role: role,
                  onNavigate: (value) => destination = value,
                  child: WorkspaceContent(
                    maxWidth: 1280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Your personal profile and account information',
                        ),
                        ResponsiveGrid(
                          children: const [
                            WorkspaceCard(
                              title: 'Review company supporting documents',
                              child: Text(
                                'Long descriptions grow naturally without a fixed card height.',
                              ),
                            ),
                            WorkspaceCard(
                              title: 'Payment history',
                              child: Text(
                                'Sandbox payments do not confirm worker receipt or payout.',
                              ),
                            ),
                          ],
                        ),
                        const TextField(
                          decoration: InputDecoration(labelText: 'Full name'),
                        ),
                        FilledButton(
                          onPressed: () {},
                          child: const Text('Save changes'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final scaffold = tester.widget<Scaffold>(
              find.byType(Scaffold).first,
            );
            expect(scaffold.drawer != null, kIsWeb && width < 840);
            expect(
              find.byKey(const ValueKey('workspace-sidebar')),
              kIsWeb && width >= 840 ? findsOneWidget : findsNothing,
            );
            expect(
              find.byType(NavigationBar),
              kIsWeb ? findsNothing : findsOneWidget,
            );
            expect(find.byType(BackButton), findsNothing);
            await openWorkspaceMenu(tester);
            expect(
              find.widgetWithText(ListTile, 'Personal profile'),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('workspace-account-menu')),
              kIsWeb ? findsOneWidget : findsNothing,
            );
            if (!kIsWeb) expect(find.text('Account'), findsOneWidget);
            if (kIsWeb) {
              final home = find.widgetWithText(ListTile, 'Dashboard');
              await tester.scrollUntilVisible(
                home,
                -180,
                scrollable: find.descendant(
                  of: find.byKey(const ValueKey('workspace-navigation')),
                  matching: find.byType(Scrollable),
                ),
              );
              await tester.pumpAndSettle();
              await tester.tap(home);
            } else {
              expect(find.widgetWithText(ListTile, 'Dashboard'), findsNothing);
              await tester.binding.handlePopRoute();
              await tester.pumpAndSettle();
              await tester.tap(find.text('Home'));
            }
            await tester.pumpAndSettle();
            expect(destination, AppRoutes.home);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  test('Nested selection is unique and ignores query strings', () {
    final all = workspaceDestinations('employer').values
        .expand((items) => items);
    expect(
      selectedWorkspacePath('/job-postings/create?status=draft', all),
      AppRoutes.createJob,
    );
    expect(
      selectedWorkspacePath('/job-postings/abc/edit', all),
      AppRoutes.jobPostings,
    );
    expect(selectedWorkspacePath('/company', all), AppRoutes.company);
  });

  testWidgets(
    'Tab roots have no slide; native focused routes keep Material transitions',
    (tester) async {
      Page<void>? rootPage;
      Page<void>? detailPage;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, state) =>
                rootPage = appPage(state, const Scaffold(body: Text('Home'))),
          ),
          GoRoute(
            path: '/focused-detail',
            pageBuilder: (_, state) => detailPage = appPage(
              state,
              const Scaffold(body: Text('Detail')),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(rootPage, isA<NoTransitionPage<void>>());
      router.push('/focused-detail');
      await tester.pumpAndSettle();
      expect(
        detailPage,
        kIsWeb ? isA<NoTransitionPage<void>>() : isA<MaterialPage<void>>(),
      );
    },
  );

  testWidgets(
    'Short landscape form stays reachable above keyboard and system insets',
    (tester) async {
      tester.view.physicalSize = const Size(568, 320);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      tester.view.padding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(
        MaterialApp(
          home: AppWorkspace(
            title: 'Personal profile',
            path: AppRoutes.profile,
            role: 'job_seeker',
            child: WorkspaceContent(
              child: Column(
                children: [
                  for (var i = 0; i < 4; i++)
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Profile field $i',
                      ),
                    ),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Save changes'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      await tester.ensureVisible(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Save changes').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Root switches do not stack duplicates; direct details have a safe Back',
    (tester) async {
      final router = GoRouter(
        routes: [
          for (final path in ['/', '/jobs', '/applications'])
            GoRoute(
              path: path,
              builder: (_, _) => AppWorkspace(
                title: path,
                path: path,
                role: 'job_seeker',
                child: const Text('Root content'),
              ),
            ),
          GoRoute(
            path: '/detail',
            builder: (_, _) => const AppWorkspace(
              title: 'Detail',
              path: '/jobs',
              role: 'job_seeker',
              focused: true,
              child: Text('Details'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      for (final path in ['/jobs', '/applications', '/', '/jobs']) {
        openWorkspaceDestination(
          tester.element(find.byType(AppWorkspace)),
          path,
        );
        await tester.pumpAndSettle();
        expect(router.canPop(), false);
        expect(router.routeInformationProvider.value.uri.path, path);
      }
      router.go('/detail');
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      if (!kIsWeb) {
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/');
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Root navigation is locked during a mutation', (tester) async {
    var moved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AppWorkspace(
          title: 'Saving',
          path: '/',
          role: 'employer',
          navigationLocked: true,
          onNavigate: (_) => moved = true,
          child: const Text('Saving your changes...'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (!kIsWeb) {
      expect(
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .onDestinationSelected,
        isNull,
      );
    }
    expect(moved, false);
  });
}
