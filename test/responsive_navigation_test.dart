import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/auth/login_page.dart';
import 'package:jobmate/features/auth/sign_up_page.dart';
import 'package:jobmate/shared/navigation/app_page.dart';
import 'package:jobmate/shared/widgets/app_workspace.dart';
import 'package:jobmate/shared/widgets/auth_layout.dart';
import 'package:jobmate/shared/widgets/design_primitives.dart';
import 'package:jobmate/shared/widgets/mobile_back_action.dart';
import 'package:jobmate/shared/widgets/responsive_layout.dart';

void main() {
  for (final size in [
    const Size(320, 720),
    const Size(568, 320),
    const Size(1024, 768),
  ]) {
    for (final registration in [false, true]) {
      testWidgets(
        'Actual ${registration ? 'registration' : 'login'} at $size / large text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: registration ? const SignUpPage() : const LoginPage(),
            ),
          );
          await tester.pumpAndSettle();
          if (registration) {
            await tester.enterText(
              find.byType(TextField).at(2),
              'Password123!',
            );
            await tester.ensureVisible(find.text('Employer'));
            await tester.tap(find.text('Employer'));
            await tester.pumpAndSettle();
          }
          final action = registration
              ? find.text('Create account')
              : find.text('Sign In');
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          expect(action.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(568, 320),
    const Size(768, 900),
    const Size(900, 700),
    const Size(1440, 900),
  ]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('Workspace adapts to $size and text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: AppWorkspace(
              title: 'Administrator tools',
              path: '/tools',
              role: 'administrator',
              onNavigate: (_) {},
              child: WorkspaceContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PageHeading(
                      title: 'Manage administrator permissions',
                      description: 'Review invitations and company document permissions.',
                    ),
                    const Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ResponsiveFilter(
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: 'Search accounts',
                            ),
                          ),
                        ),
                        ResponsiveFilter(
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: 'Account status',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ResponsiveGrid(
                      maxColumns: 2,
                      minItemWidth: 260,
                      children: [
                        for (var i = 0; i < 3; i++)
                          const WorkspaceCard(
                            title: 'Manage administrator permissions',
                            child: Text(
                              'Control who can invite administrators and review company supporting documents. Long descriptions can wrap and grow.',
                            ),
                          ),
                      ],
                    ),
                    const ResponsivePagination(page: 1),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).first).drawer,
          size.width < 768 ? isNotNull : isNull,
        );
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -1200),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Grid height grows with text instead of constraining it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ResponsiveGrid(
              maxColumns: 2,
              minItemWidth: 240,
              children: [
                Card(child: SizedBox(height: 80, child: Text('Short card'))),
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'A long administrator permission description. '
                      'It remains completely readable as the card height expands. '
                      'This sentence repeats to exceed the previous fixed tool-card height. '
                      'There is no fixed maximum height imposed by the grid.',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final cards = find.byType(Card);
    expect(
      tester.getSize(cards.last).height,
      greaterThan(tester.getSize(cards.first).height),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Standalone return supports direct URL, dirty input and platform transition',
    (tester) async {
      Page<void>? page;
      final router = GoRouter(
        initialLocation: '/form',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Dashboard root')),
          ),
          GoRoute(
            path: '/form',
            pageBuilder: (context, state) {
              return page = appPage(
                state,
                Scaffold(
                  appBar: ResponsivePageAppBar(
                    title: const Text('Edit profile'),
                    hasUnsavedChanges: () => true,
                  ),
                  body: const AuthLayout(
                    child: TextField(
                      decoration: InputDecoration(labelText: 'Name'),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(router.canPop(), isFalse);
      expect(
        page,
        kIsWeb ? isA<NoTransitionPage<void>>() : isA<MaterialPage<void>>(),
      );
      expect(
        find.byIcon(Icons.arrow_back),
        kIsWeb ? findsNothing : findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'Unsaved name');
      final exit = kIsWeb ? find.text('Dashboard') : find.byTooltip('Back');
      await tester.tap(exit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved name'), findsOneWidget);
      await tester.tap(exit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave page'));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard root'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Responsive form stays scrollable above an open keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthLayout(
            branded: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 8; i++)
                  TextField(decoration: InputDecoration(labelText: 'Field $i')),
                FilledButton(onPressed: () {}, child: const Text('Save form')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Save form'));
    await tester.pumpAndSettle();
    expect(find.text('Save form').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
