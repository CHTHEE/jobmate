import 'dart:async';

import 'fixtures/my_applications_source.dart';
import 'fixtures/published_jobs_source.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/shared/widgets/app_workspace.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';
import 'package:jobmate/features/home/dashboard_content.dart';
import 'package:jobmate/features/home/job_seeker_dashboard.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';

import 'work_attendance_repository_test.dart' show FakeSource, assignment;

void main() {
  _jobSeekerDashboardTests();
  for (final role in ['job_seeker', 'employer']) {
    testWidgets('$role presents completed profile appropriately', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardContent(
                profile: {
                  'role': role,
                  'name': 'Test User',
                  'phone_num': '0123456789',
                  'profile_image_url': 'https://example.com/photo.jpg',
                  'status': 'active',
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
      await tester.pump();
      expect(
        find.text('Complete your profile'),
        role == 'job_seeker' ? findsOneWidget : findsNothing,
      );
      if (role == 'job_seeker') expect(find.text('100%'), findsOneWidget);
      expect(find.textContaining('Profile completion:'), findsNothing);
    });
  }
}

class _SnapshotSource extends TestMyApplicationsSource
    implements CompleteMyApplicationsSource {
  bool complete = true;

  @override
  Future<MyApplicationSnapshot> listSnapshot() async =>
      (rows: await list(), complete: complete);
}

Map<String, dynamic> _job(
  String id, {
  String status = 'published',
  String deadline = '2027-01-05',
}) => {
  'job_id': id,
  'title': id,
  'company_name': 'Real Company',
  'status': status,
  'application_deadline': deadline,
  'employment_type': 'temporary',
  'work_arrangement': 'on_site',
  'location': 'Kuala Lumpur',
  'salary_visible': true,
  'salary_min': 12,
  'salary_max': 18,
  'salary_period': 'hourly',
  'published_at': '2026-11-05T09:00:00Z',
};

void _jobSeekerDashboardTests() {
  late _SnapshotSource applications;
  late TestPublishedJobsSource jobs;
  late FakeSource work;
  late Future<Map<String, dynamic>> Function() reputation;

  setUp(() {
    applications = _SnapshotSource();
    jobs = TestPublishedJobsSource();
    work = FakeSource()..workerRead = () async => [];
    reputation = () async => {
      'core_average': null,
      'rated_application_count': 0,
      'published_application_count': 0,
      'verified_completed_shift_count': 0,
    };
  });

  tearDown(() async {
    await applications.changes.close();
    await jobs.changes.close();
    await work.changes.close();
  });

  Future<void> show(
    WidgetTester tester, {
    double width = 1060,
    double scale = 1,
    double sidebarWidth = 0,
    double? narrowScale,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 920);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Row(
              children: [
                if (MediaQuery.sizeOf(context).width >= 768)
                  SizedBox(width: sidebarWidth),
                Expanded(
                  child: WorkspaceContent(
                    key: const ValueKey('dashboard-workspace'),
                    maxWidth: double.infinity,
                    child: JobSeekerDashboard(
                      name: 'Real Seeker',
                      email: 'seeker@example.invalid',
                      phone: '',
                      photo: '',
                      onProfile: () {},
                      now: () => DateTime(2026, 11, 26),
                      createData: () => JobSeekerDashboardData(
                        applications: MyApplicationsRepository(
                          applications,
                          verifyCompleteness: true,
                        ),
                        jobs: PublishedJobsRepository(
                          jobs,
                          requirePublished: true,
                        ),
                        work: WorkAttendanceRepository(work),
                        loadProfile: (_) async => const {
                          'skills': [
                            {'skill_name': 'Excel'},
                            {'skill_name': 'SQL'},
                          ],
                        },
                        loadReputation: reputation,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final path in [
          '/applications/:id',
          '/jobs/:id',
          '/recommendations',
        ])
          GoRoute(
            path: path,
            builder: (_, state) => Scaffold(body: Text(state.uri.path)),
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
              MediaQuery.sizeOf(context).width < 768
                  ? narrowScale ?? scale
                  : scale,
            ),
          ),
          child: child!,
        ),
      ),
    );
  }

  testWidgets(
    'real data, three eligible matches, stable recent rows and navigation',
    (tester) async {
      applications.rows = [
        {
          ...applicationRow('a', status: 'interview'),
          'job_title': 'Older application',
          'job_id': 'Already applied',
        },
        {
          ...applicationRow('b', status: 'shortlisted'),
          'job_title': 'First recent',
          'applied_at': '2026-11-06T09:00:00Z',
        },
        {
          ...applicationRow('c'),
          'job_title': 'Second recent',
          'applied_at': '2026-11-05T09:00:00Z',
        },
      ];
      jobs.rows = [
        for (final title in [
          'Match A',
          'Match B',
          'Match C',
          'Match D',
          'Already applied',
        ])
          _job(title),
        _job('Expired job', deadline: '2026-11-02'),
        _job('Draft job', status: 'draft'),
      ];
      jobs.reportedTotal = jobs.rows.length + 1;
      work.workerRead = () async => [
        {
          ...assignment(),
          'job_title': 'Upcoming real shift',
          'attendance_as_of': '2026-11-04T09:00:00Z',
        },
      ];
      reputation = () async => {
        'core_average': 4.25,
        'rated_application_count': 2,
        'published_application_count': 3,
        'verified_completed_shift_count': 7,
      };
      await show(tester);
      await tester.pumpAndSettle();
      expect(find.text('Real Seeker'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(applications.calls, 1);
      expect(jobs.calls, 1);
      expect(find.text('Current application statuses'), findsOneWidget);
      expect(find.text('1'), findsNWidgets(3));
      expect(find.text('View Job'), findsNWidgets(3));
      expect(find.text('Limited evidence'), findsNWidgets(3));
      expect(find.text('Match D'), findsNothing);
      expect(find.text('Already applied'), findsNothing);
      expect(find.text('Expired job'), findsNothing);
      expect(find.text('Draft job'), findsNothing);
      expect(find.textContaining('Only part of the published'), findsOneWidget);
      expect(find.text('Upcoming real shift'), findsOneWidget);
      expect(find.textContaining('4.25 / 5'), findsOneWidget);
      expect(
        find.text('7 verified completed shifts', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Applied companies'), findsNothing);
      expect(find.text('Evaluations from others'), findsNothing);
      expect(
        tester.getTopLeft(find.text('First recent')).dy,
        lessThan(tester.getTopLeft(find.text('Second recent')).dy),
      );

      await tester.ensureVisible(find.text('View Job').first);
      await tester.tap(find.text('View Job').first);
      await tester.pumpAndSettle();
      expect(find.text('/jobs/Match%20A'), findsOneWidget);
      final context = tester.element(find.text('/jobs/Match%20A'));
      context.pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('First recent'));
      await tester.tap(find.text('First recent'));
      await tester.pumpAndSettle();
      expect(find.text('/applications/b'), findsOneWidget);
    },
  );

  testWidgets(
    'dashboard centers in the main pane and cards reflow at narrow large text',
    (tester) async {
      const title = 'Customer operations and community support coordinator';
      const location =
          'Kuala Lumpur city centre and surrounding neighbourhoods';
      jobs.rows = [
        {
          ..._job(title),
          'location': location,
          'requirements': ['Skills: Excel, SQL'],
        },
        _job('Second recommendation'),
      ];
      applications.rows = [applicationRow('responsive')];
      await show(tester, width: 1760, sidebarWidth: 240, narrowScale: 1.6);
      await tester.pumpAndSettle();
      final pane = tester.getRect(
        find.byKey(const ValueKey('dashboard-workspace')),
      );
      final profile = tester.getRect(
        find
            .ancestor(
              of: find.text('Complete your profile'),
              matching: find.byType(Card),
            )
            .first,
      );
      expect(profile.width, closeTo(1200, 1));
      expect(profile.left - pane.left, closeTo(pane.right - profile.right, 1));
      final firstJob = find.text(title);
      final secondJob = find.text('Second recommendation');
      Finder jobCard(Finder title) =>
          find.ancestor(of: title, matching: find.byType(Card)).first;
      expect(
        tester.getSize(jobCard(firstJob)).width,
        closeTo(tester.getSize(jobCard(secondJob)).width, 1),
      );
      expect(
        tester.getTopLeft(firstJob).dy,
        closeTo(tester.getTopLeft(secondJob).dy, 1),
      );
      final match = find.text('Est. match');
      expect(
        tester.getRect(firstJob).right,
        lessThan(tester.getRect(match).left),
      );
      final work = find.text('My Work');
      final reputation = find.text('My Reputation');
      expect(
        tester.getTopLeft(work).dy,
        closeTo(tester.getTopLeft(reputation).dy, 1),
      );
      final company = find.text('ABC Company');
      final status = find.text('Applied').last;
      expect(
        tester.getRect(company).right,
        lessThan(tester.getRect(status).left),
      );

      tester.view.physicalSize = const Size(320, 920);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(work).dy,
        lessThan(tester.getTopLeft(reputation).dy),
      );
      expect(
        tester.getTopLeft(firstJob).dy,
        lessThan(tester.getTopLeft(secondJob).dy),
      );
      expect(
        tester.getRect(status).top,
        greaterThanOrEqualTo(tester.getRect(company).bottom),
      );
      expect(
        tester.getRect(firstJob).right,
        lessThan(tester.getRect(match).left),
      );
      expect(find.text(location), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'independent pending reads and partial history on narrow large text',
    (tester) async {
      final pending = Completer<List<Map<String, dynamic>>>();
      applications
        ..complete = false
        ..fetch = () => pending.future;
      jobs.rows = [_job('Potentially ineligible')];
      reputation = () async => throw StateError('Unavailable');
      await show(tester, width: 320, scale: 1.6);
      await tester.pump();
      expect(find.text('Loading your applications...'), findsWidgets);
      expect(find.text('No upcoming shifts.'), findsOneWidget);
      expect(find.text('Reputation summary is unavailable.'), findsOneWidget);
      pending.complete([applicationRow('partial')]);
      await tester.pumpAndSettle();
      expect(
        find.text('Current statuses from loaded applications'),
        findsOneWidget,
      );
      expect(
        find.textContaining('application history could not be verified'),
        findsOneWidget,
      );
      expect(find.text('Potentially ineligible'), findsNothing);
      expect(find.text('View all matches'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty real sections and no released ratings', (tester) async {
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text('You have no applications yet.'), findsOneWidget);
    expect(find.text('No eligible matches right now.'), findsOneWidget);
    expect(find.text('No upcoming shifts.'), findsOneWidget);
    expect(find.text('No ratings yet'), findsOneWidget);
    expect(find.text('Trust Score'), findsNothing);
  });

  testWidgets('late application results cannot populate a changed account', (
    tester,
  ) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    applications.fetch = () => pending.future;
    await show(tester);
    applications.switchAccount(null);
    await tester.pumpAndSettle();
    pending.complete([applicationRow('stale')]);
    await tester.pumpAndSettle();
    expect(find.text('Real Seeker'), findsNothing);
    expect(find.text('Part-Time Cafe Crew'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('application retry coalesces and late results survive disposal', (
    tester,
  ) async {
    applications.fetch = () async => throw StateError('Applications offline');
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text('Applications offline'), findsWidgets);
    expect(find.text('No upcoming shifts.'), findsOneWidget);
    final pending = Completer<List<Map<String, dynamic>>>();
    applications.fetch = () => pending.future;
    final retry = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Retry').first)
        .onPressed!;
    retry();
    retry();
    await tester.pump();
    expect(applications.calls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete([applicationRow('late')]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
