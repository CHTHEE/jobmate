import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/applications/browse_job_card.dart';
import 'package:jobmate/features/applications/browse_jobs_page.dart';
import 'package:jobmate/features/applications/job_details_page.dart';
import 'package:jobmate/features/applications/job_details_presentation.dart';
import 'package:jobmate/features/applications/job_marketplace_format.dart';
import 'package:jobmate/features/applications/module2_repository.dart';

import 'fixtures/my_applications_source.dart';
import 'fixtures/published_jobs_source.dart';
import 'published_jobs_test.dart' show publishedRow;

void main() {
  test('salary separators, decimals, disclosure and supported periods', () {
    for (final period in {
      'hourly': 'hour',
      'daily': 'day',
      'monthly': 'month',
      'yearly': 'year',
    }.entries) {
      final row = {
        ...publishedRow('job', visible: true),
        'salary_min': 1500.5,
        'salary_max': 20000,
        'salary_period': period.key,
      };
      expect(
        marketplaceSalary(BrowseJob.published(row)),
        '1,500.5–20,000 / ${period.value}',
      );
      expect(
        marketplaceSalary(
          BrowseJob.published({...row, 'salary_visible': false}),
        ),
        'Not disclosed',
      );
      expect(
        marketplaceSalary(BrowseJob.published({...row, 'salary_max': null})),
        'Not disclosed',
      );
    }
    expect(marketplaceDate('2026-11-30'), '30 Nov 2026');
    expect(marketplaceDate(null), 'Not set');
    expect(marketplaceDate('2026-11-30T23:00:00Z'), '30 Nov 2026');
  });

  testWidgets('ordinary desktop card has three compact rows', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 880,
              child: BrowseJobCard(
                job: BrowseJob.published(publishedRow('job', visible: true)),
                logo: const Icon(Icons.business),
                saved: false,
                onSave: () {},
                onDetails: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(BrowseJobCard)).height,
      lessThanOrEqualTo(190),
    );
    expect(
      (tester
                  .getCenter(
                    find.byKey(const ValueKey('job-secondary-metadata')),
                  )
                  .dy -
              tester.getCenter(find.text('View Details')).dy)
          .abs(),
      lessThan(10),
    );
    expect(find.text('4,000–6,000 / month'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'content preserves paragraphs, structured order and explicit bullet lines',
    (tester) async {
      Future<void> render(Object content) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: JobContent(content))),
      );
      await render(['First item.', 'Second item.']);
      expect(
        tester.getTopLeft(find.text('First item.')).dy,
        lessThan(tester.getTopLeft(find.text('Second item.')).dy),
      );
      await render('A paragraph. Two sentences.\nAnother paragraph.');
      expect(
        find.text('A paragraph. Two sentences.\nAnother paragraph.'),
        findsOneWidget,
      );
      await render('• First line\n- Second line');
      expect(find.text('First line'), findsOneWidget);
      expect(find.text('Second line'), findsOneWidget);
      await render('A paragraph. Two sentences.\n• A listed item');
      expect(find.text('A paragraph. Two sentences.'), findsOneWidget);
      expect(find.text('A listed item'), findsOneWidget);
      expect(JobContent.hasContent([]), isFalse);
      expect(JobContent.hasContent('  '), isFalse);
    },
  );

  testWidgets(
    'expired job without application cannot apply and missing information stays safe',
    (tester) async {
      final jobs = TestPublishedJobsSource()
        ..rows = [
          {
            ...publishedRow('job'),
            'application_deadline': '2020-01-01',
            'employment_type': null,
            'location': null,
            'vacancies': null,
            'role_overview': '',
            'requirements': [],
            'original_description': '',
          },
        ];
      final applications = TestMyApplicationsSource();
      final module = Module2Repository(
        publishedSource: jobs,
        myApplicationsSource: applications,
      );
      addTearDown(() async {
        module.dispose();
        await jobs.changes.close();
        await applications.changes.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: JobDetailsPage(jobId: 'job', repository: module),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply Now'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Application deadline has passed.'), findsOneWidget);
      expect(find.byType(JobApplicationBanner), findsNothing);
      expect(find.text('Not disclosed'), findsOneWidget);
      expect(find.text('Not provided'), findsWidgets);
      expect(find.text('Role Overview'), findsNothing);
      expect(find.text('Job Description'), findsNothing);
      expect(find.text('Requirements'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 600.0, 880.0, 1440.0]) {
    testWidgets(
      'details hired and expired preserve values and actions at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final jobs = TestPublishedJobsSource()
          ..rows = [
            {
              ...publishedRow('job', visible: true),
              'title':
                  'A long customer service and event coordination job title',
              'company_name':
                  'Company with a long name for responsive coverage',
              'location': 'A long venue location with several districts and building names',
              'application_deadline': '2020-01-01',
              'requirements': 'An ordinary paragraph. With two sentences.',
              'responsibilities': '• Help customers\n• Coordinate events',
              'benefits': [],
            },
          ];
        final applications = TestMyApplicationsSource()
          ..rows = [
            {...applicationRow('owned', status: 'hired'), 'job_id': 'job'},
          ];
        final module = Module2Repository(
          publishedSource: jobs,
          myApplicationsSource: applications,
        );
        final router = GoRouter(
          initialLocation: '/jobs/job',
          routes: [
            GoRoute(
              path: '/jobs/:id',
              builder: (_, _) =>
                  JobDetailsPage(jobId: 'job', repository: module),
            ),
            GoRoute(
              path: '/applications/:id',
              builder: (_, state) =>
                  Scaffold(body: Text('Opened ${state.pathParameters['id']}')),
            ),
            GoRoute(
              path: '/jobs',
              builder: (_, _) => const Scaffold(body: Text('Browse root')),
            ),
          ],
        );
        addTearDown(() async {
          router.dispose();
          module.dispose();
          await jobs.changes.close();
          await applications.changes.close();
        });
        await tester.pumpWidget(
          MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(JobInformationGrid), findsOneWidget);
        expect(find.text('You were hired for this job'), findsOneWidget);
        expect(find.text('Application deadline has passed.'), findsOneWidget);
        expect(find.text('Apply Now'), findsNothing);
        expect(find.text('4,000–6,000 / month'), findsOneWidget);
        expect(find.text('1 Jan 2020'), findsOneWidget);
        expect(find.text('Help customers'), findsOneWidget);
        expect(
          find.text('An ordinary paragraph. With two sentences.'),
          findsOneWidget,
        );
        expect(find.text('Benefits'), findsNothing);
        expect(
          find.byKey(const ValueKey('view-public-company-profile')),
          findsOneWidget,
        );
        await tester.ensureVisible(find.byTooltip('Save Job (this session)'));
        await tester.tap(find.byTooltip('Save Job (this session)'));
        await tester.pump();
        expect(module.browse.saved('job'), isTrue);
        expect(find.byTooltip('Unsave Job (this session)'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('View Application'));
        await tester.tap(find.text('View Application'));
        await tester.pumpAndSettle();
        expect(find.text('Opened owned'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'search, sort, expandable filters, saved filter and details return',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final jobs = TestPublishedJobsSource()
        ..rows = [
          publishedRow('one'),
          {
            ...publishedRow('two'),
            'title': 'Accountant',
            'employment_type': 'part_time',
          },
        ];
      final module = Module2Repository(publishedSource: jobs);
      final router = GoRouter(
        initialLocation: '/jobs',
        routes: [
          GoRoute(
            path: '/jobs',
            builder: (_, _) => BrowseJobsPage(repository: module),
          ),
          GoRoute(
            path: '/jobs/:id',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () => context.pop(),
                child: Text('Return from ${state.pathParameters['id']}'),
              ),
            ),
          ),
        ],
      );
      addTearDown(() async {
        router.dispose();
        module.dispose();
        await jobs.changes.close();
      });
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('Clear filters'), findsNothing);
      expect(find.text('Saved this session'), findsNothing);
      expect(find.text('Bookmarked jobs only'), findsNothing);
      expect(find.text('2 results'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Accountant');
      await tester.pump();
      expect(find.text('1 results'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pump();
      await tester.tap(find.text('Filters'));
      await tester.pump();
      expect(find.text('Saved this session'), findsNothing);
      expect(find.text('Bookmarked jobs only'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Part-time').last);
      await tester.pumpAndSettle();
      expect(find.text('1 results'), findsOneWidget);
      await tester.tap(find.text('Filters'));
      await tester.pump();
      expect(find.text('Part-time'), findsWidgets);
      await tester.tap(find.byTooltip('Save job (this session)'));
      await tester.pump();
      await tester.tap(find.text('Clear filters'));
      await tester.pump();
      expect(find.text('2 results'), findsOneWidget);
      await tester.tap(find.text('Filters'));
      await tester.pump();
      await tester.tap(find.text('Bookmarked jobs only'));
      await tester.pump();
      expect(find.text('1 results'), findsOneWidget);
      await tester.tap(find.text('Filters'));
      await tester.pump();
      expect(find.text('Bookmarked jobs only'), findsNothing);
      expect(find.text('1 results'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pump();
      await tester.tap(find.byType(DropdownButton<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title').last);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Accountant')).dy,
        lessThan(tester.getTopLeft(find.text('Flutter Developer')).dy),
      );
      await tester.tap(find.text('View Details').first);
      await tester.pumpAndSettle();
      expect(find.text('Return from two'), findsOneWidget);
      await tester.tap(find.text('Return from two'));
      await tester.pumpAndSettle();
      expect(find.text('Title'), findsOneWidget);
      expect(module.browse.saved('two'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
