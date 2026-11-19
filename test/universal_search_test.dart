import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/applications/browse_jobs_page.dart';
import 'package:jobmate/features/applications/job_details_page.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/features/search/universal_search_page.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';

import 'fixtures/my_applications_source.dart';
import 'fixtures/published_jobs_source.dart';
import 'published_jobs_test.dart' show publishedRow;

class _CompanySearch implements PublicCompanySearch {
  int calls = 0;

  @override
  Future<List<PublicCompanyResult>> find(String query) async {
    calls++;
    return const [
      PublicCompanyResult(
        id: 'company-1',
        name: 'Verified Studio',
        industry: 'Design',
        location: 'Kuala Lumpur',
      ),
    ];
  }
}

void main() {
  for (final width in [320.0, 1440.0]) {
    testWidgets('dashboard search opens a light top-center dialog at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showJobMateSearchPanel(context),
                child: const Text('Open search'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open search'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      final rect = tester.getRect(find.byType(Dialog));
      expect(dialog.alignment, Alignment.topCenter);
      expect(rect.center.dx, closeTo(width / 2, 1));
      expect(rect.top, lessThan(150));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ModalBarrier && widget.color == const Color(0x29000000),
        ),
        findsOneWidget,
      );
      expect(find.text('Search JobMate'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Open search'), findsOneWidget);
    });
  }

  testWidgets('embedded search keeps a session-only recent query', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: UniversalSearchPage(embedded: true)),
      ),
    );
    expect(find.text('No recent searches in this session.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'engineer');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('engineer'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets(
    'Search retains verified companies and private people alongside Browse Jobs',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final companySearch = _CompanySearch();

      await tester.pumpWidget(
        MaterialApp(home: UniversalSearchPage(companySearch: companySearch)),
      );
      expect(find.text('Browse jobs'), findsOneWidget);
      expect(find.text('View demo job'), findsNothing);

      await tester.enterText(find.byType(TextField), 'Studio');
      await tester.tap(find.text('Companies'));
      await tester.pumpAndSettle();
      expect(companySearch.calls, 1);
      expect(find.text('Verified Studio'), findsOneWidget);
      expect(find.text('Design • Kuala Lumpur'), findsOneWidget);

      await tester.tap(find.text('People'));
      await tester.pumpAndSettle();
      expect(find.text('People search is not available yet'), findsOneWidget);
      expect(find.text('Verified Studio'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('legacy search and the panel open the real browse catalogue', (
    tester,
  ) async {
    final source = TestPublishedJobsSource()
      ..rows = [
        publishedRow('real-job'),
        {
          ...publishedRow('other-job'),
          'title': 'Designer',
          'company_name': 'Design Studio',
          'role_overview': 'Design interfaces',
        },
      ];
    final applications = TestMyApplicationsSource();
    final repository = Module2Repository(
      publishedSource: source,
      myApplicationsSource: applications,
    );
    addTearDown(repository.dispose);
    addTearDown(source.changes.close);
    final router = GoRouter(
      initialLocation: '/search?q=Actual%20Company',
      routes: [
        legacyJobSearchRoute(),
        GoRoute(
          path: AppRoutes.browseJobs,
          builder: (_, state) => BrowseJobsPage(
            repository: repository,
            initialKeyword:
                state.uri.queryParameters[AppRoutes.jobKeywordParameter] ?? '',
            keywordRequest: state.extra,
          ),
        ),
        GoRoute(
          path: '${AppRoutes.browseJobs}/:jobId',
          builder: (_, state) => JobDetailsPage(
            repository: repository,
            jobId: state.pathParameters['jobId']!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, AppRoutes.browseJobs);
    expect(find.text('Flutter Developer'), findsOneWidget);
    expect(find.text('Designer'), findsNothing);

    Future<void> handoff(String keyword) async {
      await tester.tap(find.byTooltip('Search jobs and companies'));
      await tester.pumpAndSettle();
      final dialog = find.byType(Dialog);
      expect(dialog, findsOneWidget);
      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextField)),
        keyword,
      );
      final browse = find.descendant(
        of: dialog,
        matching: find.text('Browse jobs'),
      );
      await tester.ensureVisible(browse);
      await tester.tap(browse);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
    }

    await tester.enterText(find.byType(TextField), 'Design Studio');
    await tester.pumpAndSettle();
    expect(find.text('Designer'), findsOneWidget);
    await handoff(' Actual Company ');
    expect(router.state.uri.queryParameters['q'], 'Actual Company');
    expect(find.text('Flutter Developer'), findsOneWidget);
    expect(find.text('Designer'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Design Studio');
    await tester.pumpAndSettle();
    expect(find.text('Designer'), findsOneWidget);
    await handoff('Actual Company');
    expect(find.text('Flutter Developer'), findsOneWidget);
    expect(find.text('Designer'), findsNothing);
    await handoff('');
    expect(router.state.uri.toString(), '/jobs');
    expect(find.text('Designer'), findsOneWidget);
    await handoff('Flutter');
    final details = find.text('View Details');
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(router.state.pathParameters['jobId'], 'real-job');
    expect(find.byType(JobDetailsPage), findsOneWidget);
    await handoff('Design Studio');
    expect(router.state.uri.path, AppRoutes.browseJobs);
    expect(find.text('Designer'), findsOneWidget);
    await handoff('Flutter');
    expect(find.text('Flutter Developer'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(router.state.pathParameters['jobId'], 'real-job');
    expect(tester.takeException(), isNull);
  });
}
