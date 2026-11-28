import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/applications/browse_job_card.dart';
import 'package:jobmate/features/applications/job_details_page.dart';
import 'package:jobmate/features/applications/job_discovery_distance.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/features/location/nearby_job_results.dart';
import 'package:jobmate/features/location/nearby_jobs_page.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:jobmate/shared/widgets/app_workspace.dart';

import 'fixtures/my_applications_source.dart';
import 'fixtures/published_jobs_source.dart';
import 'published_jobs_test.dart' show publishedRow;
import 'support/workspace_navigation_test_helper.dart';

const origin = (latitude: 3.15, longitude: 101.7);

Map<String, dynamic> posting(
  String id,
  double? latitude, {
  String arrangement = 'on_site',
  String type = 'full_time',
}) => {
  ...publishedRow(id),
  'title': id,
  'latitude': latitude,
  'longitude': origin.longitude,
  'work_arrangement': arrangement,
  'employment_type': type,
};

void main() {
  test(
    'nearby projection uses valid physical pins, distance, and stable ties',
    () {
      final jobs = [
        posting('z-tie', 3.151),
        posting('a-tie', 3.151),
        posting('closest', 3.15),
        posting('hybrid', 3.22, arrangement: 'hybrid', type: 'part_time'),
        posting('far', 3.28),
        posting('outside', 3.5),
        posting('remote', 3.15, arrangement: 'remote'),
        posting('missing', null),
        posting('invalid', 91),
      ].map(BrowseJob.published).toList();
      Iterable<String> ids(num radius, [String type = '']) => nearbyJobResults(
        jobs,
        origin: origin,
        radiusKm: radius,
        employmentType: type,
      ).map((result) => result.job.id);
      expect(ids(5), ['closest', 'a-tie', 'z-tie']);
      expect(ids(10), ['closest', 'a-tie', 'z-tie', 'hybrid']);
      expect(ids(20), ['closest', 'a-tie', 'z-tie', 'hybrid', 'far']);
      expect(ids(20, 'part_time'), ['hybrid']);
      final boundary = jobDiscoveryDistanceKm(origin, jobs[3].workplace!)!;
      expect(ids(boundary), contains('hybrid'));
      expect(ids(boundary - 0.000001), isNot(contains('hybrid')));
    },
  );

  test(
    'nearby results exclude expired and invalid deadlines after MYT midnight',
    () {
      final jobs = [
        for (final (id, deadline) in [
          ('today', '2026-11-27'),
          ('future', '2026-11-29'),
          ('expired', '2026-11-26'),
          ('invalid', '2026-02-30'),
          ('missing', null),
        ])
          BrowseJob.published({
            ...posting(id, 3.15),
            'application_deadline': deadline,
          }),
      ];
      Iterable<String> ids(DateTime now) => nearbyJobResults(
        jobs,
        origin: origin,
        radiusKm: 5,
        now: now,
      ).map((row) => row.job.id);
      expect(ids(DateTime.utc(2026, 11, 27, 15, 59, 59)), ['future', 'today']);
      expect(ids(DateTime.utc(2026, 11, 27, 16)), ['future']);
    },
  );

  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'Nearby list keeps place and filters on details return at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final source = TestPublishedJobsSource()
          ..rows = [
            posting('Mid Valley Developer', 3.15),
            {
              ...posting('Expired listing', 3.15),
              'application_deadline': '2026-11-26',
            },
            posting('Hybrid Engineer', 3.22, arrangement: 'hybrid'),
            posting(
              'Hybrid Designer',
              3.22,
              arrangement: 'hybrid',
              type: 'part_time',
            ),
          ];
        final module = Module2Repository(
          publishedSource: source,
          publishedClock: () => DateTime.utc(2026, 11, 27, 16),
          myApplicationsSource: TestMyApplicationsSource(),
        );
        addTearDown(source.changes.close);
        addTearDown(module.dispose);
        var failSearch = true;
        var checks = 0;
        final router = GoRouter(
          initialLocation: AppRoutes.nearbyJobs,
          routes: [
            ...nearbyJobsRoutes(
              page: NearbyJobsListPage(
                repository: module.browse,
                checkAccess: () async {
                  checks++;
                  return source.userId != null;
                },
                searchPlaces: (query) async {
                  expect(query, 'Mid Valley');
                  if (failSearch) throw StateError('Unavailable');
                  return [
                    (
                      name: 'Mid Valley Megamall',
                      address: 'Lingkaran Syed Putra, Kuala Lumpur',
                      coordinates: origin,
                    ),
                  ];
                },
                mapBuilder: (_, point, radius, results, select, showList) =>
                    Column(
                      children: [
                        Text('Map radius $radius'),
                        for (final result in results)
                          TextButton(
                            onPressed: () => select(result.job.id),
                            child: Text('Marker ${result.job.id}'),
                          ),
                        TextButton(
                          onPressed: showList,
                          child: const Text('View list'),
                        ),
                      ],
                    ),
              ),
            ),
            GoRoute(
              path: '/jobs/:jobId',
              builder: (_, state) => JobDetailsPage(
                repository: module,
                jobId: state.pathParameters['jobId']!,
              ),
            ),
            GoRoute(
              path: '/jobs',
              builder: (_, _) => const Text('Browse destination'),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, AppRoutes.nearbyJobs);
        Future<void> tap(Finder target) async {
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pumpAndSettle();
        }

        expect(find.text('No location selected'), findsOneWidget);
        expect(find.text('Search location'), findsOneWidget);
        expect(find.text('Search radius'), findsNothing);
        expect(find.byType(SegmentedButton<bool>), findsNothing);
        expect(find.byType(BrowseJobCard), findsNothing);
        await tap(find.text('Choose a location'));
        await tester.enterText(find.byType(TextField), 'Mid Valley');
        await tap(find.text('Search'));
        expect(
          find.textContaining('Location search is unavailable'),
          findsOneWidget,
        );
        failSearch = false;
        await tap(find.text('Search'));
        await tap(find.text('Mid Valley Megamall'));
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('1 nearby job'), findsOneWidget);
        expect(find.text('Within 5 km of Mid Valley Megamall'), findsOneWidget);
        expect(find.text('Lingkaran Syed Putra, Kuala Lumpur'), findsOneWidget);
        await tap(find.byKey(const ValueKey('workspace-filters-toggle')));
        expect(find.text('Search radius'), findsOneWidget);
        final summary = tester.getRect(find.text('1 nearby job'));
        final toggle = tester.getRect(find.byType(SegmentedButton<bool>));
        if (width == 320) {
          expect(toggle.top, greaterThanOrEqualTo(summary.bottom));
        } else {
          expect(toggle.left, greaterThan(summary.right));
          expect(toggle.overlaps(summary), isFalse);
          expect(toggle.top, lessThan(summary.bottom));
        }
        await tap(find.text('Change location'));
        await tester.enterText(find.byType(TextField), 'Penang');
        await tap(find.text('Cancel'));
        expect(find.text('Mid Valley Megamall'), findsOneWidget);
        expect(find.text('1 nearby job'), findsOneWidget);
        expect(find.textContaining('0.0 km straight-line'), findsOneWidget);
        await tap(find.text('10 km'));
        expect(find.text('3 nearby jobs'), findsOneWidget);
        expect(
          find.text('Within 10 km of Mid Valley Megamall'),
          findsOneWidget,
        );
        final listIds = tester
            .widgetList<BrowseJobCard>(find.byType(BrowseJobCard))
            .map((card) => card.job.id)
            .toList();
        await tap(find.text('Map'));
        expect(find.text('Map radius 10'), findsOneWidget);
        expect(find.textContaining('Marker '), findsNWidgets(listIds.length));
        for (final id in listIds) {
          expect(find.text('Marker $id'), findsOneWidget);
        }
        await tap(find.text('Marker Mid Valley Developer'));
        expect(
          tester.widget<BrowseJobCard>(find.byType(BrowseJobCard)).job.id,
          'Mid Valley Developer',
        );
        expect(find.text('Jobs at this marker'), findsNothing);
        await tap(find.text('Marker Hybrid Engineer'));
        expect(find.text('Jobs at this marker'), findsOneWidget);
        await tap(
          find.byKey(const ValueKey('nearby-marker-job-Hybrid Designer')),
        );
        expect(
          tester.widget<BrowseJobCard>(find.byType(BrowseJobCard)).job.id,
          'Hybrid Designer',
        );
        await tap(
          find.byKey(const ValueKey('nearby-marker-job-Hybrid Engineer')),
        );
        expect(
          tester.widget<BrowseJobCard>(find.byType(BrowseJobCard)).job.id,
          'Hybrid Engineer',
        );
        await tap(
          find.byKey(const ValueKey('nearby-marker-job-Hybrid Designer')),
        );
        await tap(find.text('View list'));
        expect(find.byType(BrowseJobCard), findsNWidgets(3));
        await tap(find.text('Map'));
        expect(
          tester.widget<BrowseJobCard>(find.byType(BrowseJobCard)).job.id,
          'Hybrid Designer',
        );
        await tap(find.text('20 km'));
        expect(find.text('Map radius 20'), findsOneWidget);
        await tap(find.byType(DropdownButtonFormField<String>));
        await tap(find.text('Part-time').last);
        expect(find.text('1 nearby job'), findsOneWidget);
        expect(
          find.text('Within 20 km of Mid Valley Megamall'),
          findsOneWidget,
        );
        await tap(find.byTooltip('Save job (this session)'));
        expect(module.browse.saved('Hybrid Designer'), isTrue);
        await tap(find.text('View Details'));
        expect(router.state.pathParameters['jobId'], 'Hybrid Designer');
        expect(find.byType(JobDetailsPage), findsOneWidget);
        router.pop();
        await tester.pumpAndSettle();
        expect(router.state.uri.path, AppRoutes.nearbyJobs);
        expect(find.text('Map radius 20'), findsOneWidget);
        expect(find.text('1 nearby job'), findsOneWidget);
        expect(
          find.text('Within 20 km of Mid Valley Megamall'),
          findsOneWidget,
        );
        expect(find.text('Mid Valley Megamall'), findsOneWidget);
        expect(find.byTooltip('Unsave job (this session)'), findsOneWidget);

        source.reportedTotal = 7;
        await module.browse.load();
        await tester.pumpAndSettle();
        expect(find.text('Nearby results unavailable'), findsOneWidget);
        expect(find.text('1 nearby job'), findsNothing);
        expect(find.textContaining('Within 20 km of'), findsNothing);
        expect(find.byType(SegmentedButton<bool>), findsNothing);
        expect(find.byType(BrowseJobCard), findsNothing);
        expect(find.textContaining('Marker '), findsNothing);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Browse Jobs'), findsOneWidget);
        source.reportedTotal = null;
        await tap(find.text('Retry'));
        expect(find.text('1 nearby job'), findsOneWidget);

        source.switchAccount('seeker-b');
        await tester.pumpAndSettle();
        expect(checks, 2);
        expect(find.text('No location selected'), findsOneWidget);
        expect(find.text('Mid Valley Megamall'), findsNothing);
        expect(find.text('20 km'), findsNothing);
        expect(module.browse.saved('Hybrid Designer'), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Nearby workspace destination and legacy links use the real page',
    (tester) async {
      final source = TestPublishedJobsSource();
      final repo = PublishedJobsRepository(source);
      addTearDown(source.changes.close);
      addTearDown(repo.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (_, _) => const AppWorkspace(
              title: 'Dashboard',
              path: AppRoutes.home,
              role: 'job_seeker',
              child: SizedBox.shrink(),
            ),
          ),
          ...nearbyJobsRoutes(
            page: NearbyJobsListPage(
              repository: repo,
              checkAccess: () async => true,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await openWorkspaceMenu(tester);
      await scrollWorkspaceMenuTo(tester, 'Nearby Jobs');
      expect(find.text('Nearby Jobs (demo)'), findsNothing);
      await tester.tap(find.widgetWithText(ListTile, 'Nearby Jobs'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, AppRoutes.nearbyJobs);
      expect(find.byType(NearbyJobsListPage), findsOneWidget);
      expect(find.text('No location selected'), findsOneWidget);
      router.go('${AppRoutes.nearbyJobs}/demo-job-1');
      await tester.pumpAndSettle();
      expect(router.state.uri.path, AppRoutes.nearbyJobs);
      expect(find.byType(NearbyJobsListPage), findsOneWidget);
      expect(find.byType(BrowseJobCard), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Nearby legacy route still denies a non-Job-Seeker', (
    tester,
  ) async {
    final source = TestPublishedJobsSource();
    final repo = PublishedJobsRepository(source);
    addTearDown(source.changes.close);
    addTearDown(repo.dispose);
    final router = GoRouter(
      initialLocation: '${AppRoutes.nearbyJobs}/demo-job-1',
      routes: nearbyJobsRoutes(
        page: NearbyJobsListPage(
          repository: repo,
          checkAccess: () async => false,
        ),
      ),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, AppRoutes.nearbyJobs);
    expect(find.text('Page unavailable'), findsOneWidget);
    expect(find.text('Choose a location'), findsNothing);
    expect(source.calls, 0);
  });
}
