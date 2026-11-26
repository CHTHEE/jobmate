import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/browse_jobs_page.dart';
import 'package:jobmate/features/applications/job_discovery_distance.dart';
import 'package:jobmate/features/applications/module2_repository.dart';

import 'fixtures/published_jobs_source.dart';
import 'published_jobs_test.dart' show publishedRow;

void main() {
  const centre = (latitude: 3.15, longitude: 101.7);
  test('Haversine handles identical, boundary and invalid coordinates', () {
    expect(jobDiscoveryDistanceKm(centre, centre), 0);
    expect(
      jobDiscoveryDistanceKm(centre, (latitude: 3.19496, longitude: 101.7)),
      lessThan(5),
    );
    expect(
      jobDiscoveryDistanceKm(centre, (latitude: 3.19497, longitude: 101.7)),
      greaterThan(5),
    );
    expect(
      jobDiscoveryDistanceKm(centre, (latitude: double.nan, longitude: 101.7)),
      isNull,
    );
  });

  test('BrowseJob validates only paired posting coordinates', () {
    for (final pair in [(null, 101.7), (3.15, 181), (double.infinity, 101.7)]) {
      expect(
        BrowseJob.published({
          ...publishedRow('job'),
          'latitude': pair.$1,
          'longitude': pair.$2,
          'company_latitude': 3.15,
          'company_longitude': 101.7,
        }).workplace,
        isNull,
      );
    }
    expect(
      BrowseJob.published({
        ...publishedRow('job'),
        'latitude': 3.15,
        'longitude': 101.7,
      }).workplace,
      centre,
    );
  });

  for (final width in [320.0, 1440.0]) {
    testWidgets('Browse uses city or state text filtering at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = TestPublishedJobsSource()
        ..rows = [
          {
            ...publishedRow('physical'),
            'title': 'On-site Designer',
            'location': 'Petaling Jaya, Selangor',
            'work_arrangement': 'on_site',
            'latitude': centre.latitude,
            'longitude': centre.longitude,
          },
          {
            ...publishedRow('legacy'),
            'title': 'Legacy Designer',
            'location': 'Shah Alam, Selangor',
          },
          {
            ...publishedRow('remote'),
            'title': 'Remote Designer',
            'location': 'Penang',
            'work_arrangement': 'remote',
          },
          {
            ...publishedRow('other'),
            'title': 'Accountant',
            'location': 'Shah Alam, Selangor',
          },
        ];
      final repo = Module2Repository(publishedSource: source);
      addTearDown(repo.dispose);
      addTearDown(source.changes.close);
      await tester.pumpWidget(
        MaterialApp(
          home: BrowseJobsPage(repository: repo, initialKeyword: 'Designer'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3 results'), findsOneWidget);
      expect(find.text('Search location'), findsNothing);
      expect(find.text('Change location'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.textContaining('straight-line'), findsNothing);

      final filters = find.byKey(const ValueKey('workspace-filters-toggle'));
      await tester.ensureVisible(filters);
      await tester.tap(filters);
      await tester.pumpAndSettle();
      final city = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'City or state',
      );
      expect(city, findsOneWidget);
      expect(
        tester.widget<TextField>(city).decoration?.hintText,
        'City or state',
      );
      await tester.ensureVisible(city);
      await tester.enterText(city, 'selangor');
      await tester.pumpAndSettle();
      expect(find.text('2 results'), findsOneWidget);
      expect(find.text('On-site Designer'), findsOneWidget);
      expect(find.text('Legacy Designer'), findsOneWidget);
      expect(find.text('Remote Designer'), findsNothing);
      expect(find.text('Accountant'), findsNothing);

      await tester.enterText(city, 'Penang');
      await tester.pumpAndSettle();
      expect(find.text('1 results'), findsOneWidget);
      expect(find.text('Remote Designer'), findsOneWidget);

      final clear = find.text('Clear filters');
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(find.text('4 results'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
