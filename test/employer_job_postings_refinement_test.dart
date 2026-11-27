import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/jobs/employer_job_card.dart';
import 'package:jobmate/features/jobs/job_form_route.dart';
import 'package:jobmate/features/jobs/job_form_page.dart';
import 'package:jobmate/features/jobs/job_postings_page.dart';
import 'package:jobmate/features/jobs/job_preview.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';

import 'job_postings_test.dart'
    show TestJobs, completeJob, field, openPostingFilters;

Map<String, dynamic> posting(String id, String status) => {
  ...completeJob(),
  'job_id': id,
  'status': status,
  'title': '$status role',
  'published_at': status == 'draft' ? null : '2026-11-15',
  'created_at': '2026-11-01',
};

class LoadingJobs extends TestJobs {
  Future<List<Map<String, dynamic>>>? response;
  int reads = 0;
  @override
  Future<List<Map<String, dynamic>>> list(String companyId) {
    reads++;
    return response ?? Future.value(records);
  }
}

void main() {
  Future<void> select(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, label));
    await tester.tap(find.widgetWithText(ChoiceChip, label));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'fresh All view, scoped counts, equal summary heights and combined search filters',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = TestJobs()
        ..records = [
          posting('draft', 'draft'),
          posting('live', 'published'),
          posting('closed', 'closed'),
        ];
      await tester.pumpWidget(
        MaterialApp(home: JobPostingsPage(repository: repo)),
      );
      await tester.pumpAndSettle();
      await openPostingFilters(tester);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All (3)'))
            .selected,
        isTrue,
      );
      expect(find.byType(EmployerJobCard), findsNWidgets(3));
      expect(find.text('Hiring Co'), findsOneWidget);
      final sizes = [
        for (final key in ['all', 'published', 'draft', 'closed'])
          tester.getSize(find.byKey(ValueKey('posting-stat-$key'))).height,
      ];
      expect(sizes.toSet().length, 1);
      for (final key in ['published', 'draft', 'closed']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('posting-stat-$key')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('posting-stat-all')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byType(TextField)).dy,
        lessThan(
          tester.getTopLeft(find.widgetWithText(ChoiceChip, 'All (3)')).dy,
        ),
      );
      for (final status in ['Published', 'Draft', 'Closed']) {
        await select(tester, '$status (1)');
        expect(find.byType(EmployerJobCard), findsOneWidget);
        expect(find.text('${status.toLowerCase()} role'), findsOneWidget);
      }
      await tester.enterText(find.byType(TextField), 'published');
      await tester.pumpAndSettle();
      expect(find.text('No matching jobs'), findsOneWidget);
      expect(find.text('No job postings yet'), findsNothing);
      await select(tester, 'Published (1)');
      expect(find.text('published role'), findsOneWidget);
      await select(tester, 'All (3)');
      expect(find.byType(EmployerJobCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Deadline Passed counts only expired published jobs and updates after edit',
    (tester) async {
      final repo = LoadingJobs()
        ..records = [
          for (final (id, status, deadline) in [
            ('expired', 'published', '2026-11-26'),
            ('today', 'published', '2026-11-27'),
            ('missing', 'published', null),
            ('invalid', 'published', '2026-02-30'),
            ('draft', 'draft', '2026-11-26'),
            ('closed', 'closed', '2026-11-26'),
          ])
            {
              ...posting(id, status),
              'title': '$id role',
              'application_deadline': deadline,
            },
        ];
      final router = GoRouter(
        initialLocation: '/job-postings',
        routes: [
          GoRoute(
            path: '/job-postings',
            builder: (_, _) => JobPostingsPage(
              repository: repo,
              now: () => DateTime.utc(2026, 11, 26, 16),
            ),
          ),
          jobFormRoute('/job-postings/:jobId/edit', repository: repo),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await openPostingFilters(tester);
      await select(tester, 'Deadline Passed (1)');
      expect(find.byType(EmployerJobCard), findsOneWidget);
      expect(find.text('expired role'), findsOneWidget);
      expect(find.text('View Applicants'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('posting-stat-published')),
          matching: find.text('4'),
        ),
        findsOneWidget,
      );

      final search = find.byType(TextField);
      await tester.enterText(search, 'today');
      await tester.pumpAndSettle();
      expect(find.text('No matching jobs'), findsOneWidget);
      expect(
        find.widgetWithText(ChoiceChip, 'Deadline Passed (1)'),
        findsOneWidget,
      );
      final clear = find.text('Clear filters');
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(find.text('today role'), findsOneWidget);
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
      await select(tester, 'Published (4)');
      expect(find.byType(EmployerJobCard), findsNWidgets(4));
      await select(tester, 'Deadline Passed (1)');
      expect(repo.reads, 1);

      await tester.ensureVisible(find.text('Edit'));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      field(tester, 'Application deadline').text = '2099-12-31';
      final save = find.text('Save Changes');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.saves, 1);
      expect(
        repo.records.singleWhere((job) => job['job_id'] == 'expired')['status'],
        'published',
      );
      final refresh = find.text('Check for updates');
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(find.text('No postings with a passed deadline'), findsOneWidget);
      expect(
        find.widgetWithText(ChoiceChip, 'Deadline Passed (0)'),
        findsOneWidget,
      );
      await select(tester, 'Published (4)');
      expect(find.text('expired role'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit initial filter survives and status-empty differs from no postings',
    (tester) async {
      final repo = TestJobs()..records = [posting('draft', 'draft')];
      await tester.pumpWidget(
        MaterialApp(
          home: JobPostingsPage(repository: repo, initialStatus: 'published'),
        ),
      );
      await tester.pumpAndSettle();
      await openPostingFilters(tester);
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Published (0)'),
            )
            .selected,
        isTrue,
      );
      expect(find.text('No published jobs'), findsOneWidget);
      expect(find.text('No job postings yet'), findsNothing);
      await select(tester, 'All (1)');
      expect(find.text('draft role'), findsOneWidget);
    },
  );

  testWidgets(
    'loading and failed fetch never show misleading empty states; retry works',
    (tester) async {
      final pending = Completer<List<Map<String, dynamic>>>();
      final repo = LoadingJobs()..response = pending.future;
      await tester.pumpWidget(
        MaterialApp(home: JobPostingsPage(repository: repo)),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(PostingSummary), findsNothing);
      expect(find.text('No job postings yet'), findsNothing);
      pending.completeError(StateError('Fetch failed'));
      await tester.pumpAndSettle();
      expect(find.text('Fetch failed'), findsOneWidget);
      expect(find.text('No job postings yet'), findsNothing);
      repo.response = Future.value([]);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No job postings yet'), findsOneWidget);
      expect(find.text('Post your first job'), findsOneWidget);
      repo.response = Future.value([posting('draft', 'draft')]);
      await tester.ensureVisible(find.text('Check for updates'));
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('draft role'), findsOneWidget);
      expect(repo.reads, 3);
    },
  );

  testWidgets(
    'posting routes, preview and Close cancellation preserve identifiers and records',
    (tester) async {
      final repo = TestJobs()..records = [posting('live', 'published')];
      final router = GoRouter(
        initialLocation: '/job-postings',
        routes: [
          GoRoute(
            path: '/job-postings',
            builder: (_, _) => JobPostingsPage(repository: repo),
          ),
          GoRoute(
            path: '/applicants',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () => context.pop(),
                child: Text(
                  'Applicants ${state.uri.queryParameters['posting']}',
                ),
              ),
            ),
          ),
          jobFormRoute('/job-postings/:jobId/edit', repository: repo),
          GoRoute(
            path: '/job-postings/create',
            builder: (_, _) => const Scaffold(body: Text('Create destination')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View Applicants'));
      await tester.tap(find.text('View Applicants'));
      await tester.pumpAndSettle();
      expect(find.text('Applicants live'), findsOneWidget);
      await tester.tap(find.text('Applicants live'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Edit'));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<JobFormPage>(find.byType(JobFormPage)).jobId,
        'live',
      );
      await tester.ensureVisible(find.text('Preview unsaved changes'));
      await tester.tap(find.text('Preview unsaved changes'));
      await tester.pumpAndSettle();
      expect(find.byType(JobPreview), findsOneWidget);
      await tester.tap(find.byTooltip('Close preview'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Close Job'));
      await tester.tap(find.text('Close Job'));
      await tester.pumpAndSettle();
      expect(
        find.text('Closed jobs cannot be edited or reopened.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Keep Job Open'));
      await tester.pumpAndSettle();
      expect(repo.records.single['status'], 'published');
      await tester.tap(find.byTooltip('Close job form'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Post Job'));
      await tester.tap(find.text('Post Job'));
      await tester.pumpAndSettle();
      expect(find.text('Create destination'), findsOneWidget);
    },
  );

  testWidgets(
    'card actions, formats, expired status and busy locking for every persisted status',
    (tester) async {
      final calls = <String>[];
      for (final status in ['draft', 'published', 'closed']) {
        await tester.pumpWidget(
          MaterialApp(
            theme: JobMateTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: EmployerJobCard(
                  job: {
                    ...posting('job', status),
                    'application_deadline': '2020-11-15',
                    'salary_min': 1500,
                    'salary_max': 1600,
                    'salary_period': 'monthly',
                  },
                  busy: false,
                  onEdit: () => calls.add('edit'),
                  onApplicants: () => calls.add('applicants'),
                ),
              ),
            ),
          ),
        );
        expect(
          find.text(postingStatusLabel(status)),
          status == 'published' ? findsNothing : findsOneWidget,
        );
        expect(find.text('RM 1,500–1,600 / month'), findsOneWidget);
        expect(find.text('Deadline: 15 Nov 2020'), findsOneWidget);
        expect(
          find.text('Deadline Passed'),
          status == 'published' ? findsOneWidget : findsNothing,
        );
        expect(
          find.textContaining('You can still review existing applicants.'),
          status == 'published' ? findsOneWidget : findsNothing,
        );
        for (final label in [
          'View Applicants',
          status == 'closed' ? 'View' : 'Edit',
        ]) {
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
        }
      }
      expect(calls.where((value) => value == 'applicants').length, 3);
      expect(calls.where((value) => value == 'edit').length, 3);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmployerJobCard(
              job: {
                ...posting('hidden', 'published'),
                'salary_visible': false,
                'salary_min': 98765,
              },
              busy: true,
              onEdit: () {},
              onApplicants: () {},
            ),
          ),
        ),
      );
      expect(find.text('Salary not disclosed'), findsOneWidget);
      expect(find.textContaining('98765'), findsNothing);
      for (final button in tester.widgetList<ButtonStyleButton>(
        find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
      )) {
        expect(button.onPressed, isNull);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'page wraps long content and actions across phone, tablet and desktop widths',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [
        320.0,
        360.0,
        390.0,
        430.0,
        600.0,
        768.0,
        840.0,
        1024.0,
        1280.0,
        1440.0,
        1920.0,
      ]) {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        final repo = TestJobs()
          ..records = [
            for (final status in ['draft', 'published', 'closed'])
              {
                ...posting(status, status),
                'title':
                    'A long title for customer service and event coordination',
                'location': 'A long location including several districts and a detailed building address',
              },
          ];
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: JobPostingsPage(key: ValueKey(width), repository: repo),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(EmployerJobCard), findsNWidgets(3));
        await tester.ensureVisible(find.text('View Applicants').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'width $width');
      }
    },
  );
}
