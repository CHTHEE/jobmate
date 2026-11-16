import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/applications/employer_applicant_card.dart';
import 'package:jobmate/features/applications/employer_applicants_page.dart';
import 'package:jobmate/features/applications/employer_applicants_repository.dart';
import 'package:jobmate/features/applications/employer_applicant_profile.dart';
import 'package:jobmate/features/applications/employer_resume_button.dart';
import 'package:jobmate/features/applications/employer_status_change_form.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';

import 'fixtures/employer_applicants_source.dart';

void main() {
  late TestEmployerApplicantsSource source;
  setUp(() => source = TestEmployerApplicantsSource());
  tearDown(() => source.changes.close());

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String field, String value) async {
    final dropdown = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == field,
    );
    await tap(
      tester,
      find.descendant(
        of: dropdown,
        matching: find.byType(DropdownButton<String>),
      ),
    );
    await tap(tester, find.text(value).last);
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EmployerApplicantsPage(source: source, jobId: 'real-job-id'),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> ids(WidgetTester tester) => tester
      .widgetList<EmployerApplicantCard>(find.byType(EmployerApplicantCard))
      .map((card) => card.applicant.id)
      .toList();

  testWidgets(
    'summary filters retain authoritative counts, status counts, search, sorting and reset',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      source.rows = [
        for (var i = 0; i < MyApplicationStatus.values.length; i++)
          {
            ...applicantRow(
              MyApplicationStatus.values[i].name,
              status: MyApplicationStatus.values[i].name,
            ),
            'applicant_name':
                '${MyApplicationStatus.values[i].label} applicant',
            'applied_at':
                '2026-11-${(i + 4).toString().padLeft(2, '0')}T10:00:00Z',
          },
      ];
      await show(tester);
      expect(find.text('8 matching applications'), findsOneWidget);
      expect(find.byType(EmployerApplicantCard), findsNWidgets(8));
      expect(ids(tester).first, 'withdrawn');
      final heights = [
        for (final label in ['All', 'Active', 'Completed'])
          tester
              .getSize(find.byKey(ValueKey('applicant-summary-$label')))
              .height,
      ];
      expect(heights.toSet().length, 1);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('applicant-summary-All')),
          matching: find.text('8'),
        ),
        findsOneWidget,
      );
      for (final label in ['Active', 'Completed']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('applicant-summary-$label')),
            matching: find.text('4'),
          ),
          findsOneWidget,
        );
        await tap(tester, find.byKey(ValueKey('applicant-summary-$label')));
        expect(find.text('4 matching applications'), findsOneWidget);
        expect(
          tester
              .widgetList<EmployerApplicantCard>(
                find.byType(EmployerApplicantCard),
              )
              .every(
                (card) =>
                    card.applicant.status.completed == (label == 'Completed'),
              ),
          isTrue,
        );
      }
      await tap(tester, find.byKey(const ValueKey('applicant-summary-All')));
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'shortlisted');
      await tester.pumpAndSettle();
      expect(ids(tester), ['shortlisted']);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('applicant-summary-All')),
          matching: find.text('8'),
        ),
        findsOneWidget,
      );
      await choose(tester, 'Application status', 'Hired: 1');
      expect(find.text('No matching applicants'), findsOneWidget);
      await tap(tester, find.text('Clear filters'));
      expect(find.text('8 matching applications'), findsOneWidget);
      for (final state in MyApplicationStatus.values) {
        await choose(tester, 'Application status', '${state.label}: 1');
        expect(ids(tester), [state.name]);
      }
      await tap(tester, find.text('Clear filters'));
      await choose(tester, 'Sort', 'Oldest');
      expect(ids(tester).first, 'submitted');
      await choose(tester, 'Sort', 'Name');
      final actual = tester
          .widgetList<EmployerApplicantCard>(find.byType(EmployerApplicantCard))
          .map((card) => card.applicant.name)
          .toList();
      expect(actual, [...actual]..sort());
      await tap(tester, find.text('Clear filters'));
      expect(ids(tester).first, 'withdrawn');
      expect(source.updates, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'matching result grammar handles zero, one and multiple applications',
    (tester) async {
      source.rows = [
        applicantRow('one'),
        {...applicantRow('two'), 'applicant_name': 'Other applicant'},
      ];
      await show(tester);
      expect(find.text('2 matching applications'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Alex');
      await tester.pumpAndSettle();
      expect(find.text('1 matching application'), findsOneWidget);
      expect(find.text('1 matching applications'), findsNothing);
      await tester.enterText(find.byType(TextField), 'No such applicant');
      await tester.pumpAndSettle();
      expect(find.text('0 matching applications'), findsOneWidget);
    },
  );

  testWidgets(
    'selector preserves posting query and never aggregates across jobs',
    (tester) async {
      source.fetchApplicants = (id) async => [
        {...applicantRow(id), 'applicant_name': 'Applicant for $id'},
      ];
      final router = GoRouter(
        initialLocation: '/applicants?posting=real-job-id',
        routes: [
          GoRoute(
            path: '/applicants',
            builder: (_, state) => EmployerApplicantsPage(
              source: source,
              jobId: state.uri.queryParameters['posting'],
            ),
          ),
          GoRoute(
            path: '/job-postings',
            builder: (_, _) => const Scaffold(body: Text('Posting root')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('Applicant for real-job-id'), findsOneWidget);
      expect(find.text('All Job Posts'), findsNothing);
      await choose(tester, 'Job posting', 'Closed posting (closed)');
      expect(
        router.routeInformationProvider.value.uri.queryParameters['posting'],
        'closed-job-id',
      );
      expect(find.text('Applicant for closed-job-id'), findsOneWidget);
      expect(find.text('Applicant for real-job-id'), findsNothing);
      expect(find.text('Edit Job'), findsNothing);
      await choose(tester, 'Job posting', 'Select a job');
      expect(source.requests, ['real-job-id', 'closed-job-id']);
      expect(find.text('Select a job to view applicants'), findsOneWidget);
      expect(find.byType(ApplicantSummaryFilters), findsNothing);
      await tap(tester, find.text('Back to My Job Postings'));
      expect(find.text('Posting root'), findsOneWidget);
    },
  );

  testWidgets(
    'profile and resume entry widgets keep real application identities',
    (tester) async {
      source.rows = [
        {...applicantRow('owned'), 'resume_id': 'resume'},
      ];
      await show(tester);
      expect(
        tester
            .widget<ApplicantProfileButton>(find.byType(ApplicantProfileButton))
            .applicationId,
        'owned',
      );
      expect(
        tester
            .widget<EmployerResumeButton>(find.byType(EmployerResumeButton))
            .applicant
            .resumeId,
        'resume',
      );
      await tap(tester, find.text('Shortlist'));
      final dialog = tester.widget<EmployerStatusChangeForm>(
        find.byType(EmployerStatusChangeForm),
      );
      expect(dialog.applicant.id, 'owned');
      expect(dialog.next, MyApplicationStatus.shortlisted);
      expect(source.updates, isEmpty);
      expect(source.resumeRequests, isEmpty);
    },
  );

  testWidgets(
    'card actions preserve every status without rendering internal IDs or generic explanations',
    (tester) async {
      var profiles = 0, resumes = 0, messages = 0;
      final transitions = <MyApplicationStatus>[];
      for (final status in MyApplicationStatus.values) {
        final applicant = JobApplicant({
          ...applicantRow('app', status: status.name),
          'resume_id': 'resume',
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: JobMateTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: EmployerApplicantCard(
                  applicant: applicant,
                  jobTitle: 'Selected job',
                  updating: false,
                  profileAction: TextButton(
                    onPressed: () => profiles++,
                    child: const Text('Profile callback'),
                  ),
                  resumeAction: TextButton(
                    onPressed: () => resumes++,
                    child: const Text('Resume callback'),
                  ),
                  messageAction: TextButton(
                    onPressed: () => messages++,
                    child: const Text('Message callback'),
                  ),
                  onTransition: transitions.add,
                ),
              ),
            ),
          ),
        );
        expect(find.text(status.label), findsOneWidget);
        for (final next in MyApplicationStatus.values) {
          final label = employerTransitionLabel(next);
          if (applicant.employerNext.contains(next)) {
            await tap(tester, find.text(label));
          }
        }
        expect(
          tester.widgetList<FilledButton>(find.byType(FilledButton)).length,
          applicant.employerNext
              .where((next) => next != MyApplicationStatus.rejected)
              .length,
        );
        expect(
          find.text('Reject'),
          applicant.employerNext.contains(MyApplicationStatus.rejected)
              ? findsOneWidget
              : findsNothing,
        );
        if (status.lifecycleExplanation != null) {
          expect(find.text(status.lifecycleExplanation!), findsNothing);
        }
        expect(find.textContaining('Application ID:'), findsNothing);
        expect(find.text('app'), findsNothing);
        expect(
          tester
              .widget<EmployerApplicantCard>(find.byType(EmployerApplicantCard))
              .applicant
              .id,
          'app',
        );
        await tap(tester, find.text('Profile callback'));
        await tap(tester, find.text('Resume callback'));
        await tap(tester, find.text('Message callback'));
      }
      expect(profiles, 8);
      expect(resumes, 8);
      expect(messages, 8);
      expect(transitions, [
        MyApplicationStatus.shortlisted,
        MyApplicationStatus.rejected,
        MyApplicationStatus.interview,
        MyApplicationStatus.rejected,
        MyApplicationStatus.offered,
        MyApplicationStatus.rejected,
      ]);
    },
  );

  testWidgets(
    'long identities, metadata, terminal text and filters wrap from 320 to 1920',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      source.data = EmployerPostingContext(source.data.access, [
        for (final job in source.data.jobs)
          {
            ...job,
            'title': 'A long job title for customer service, event coordination and workplace operations',
          },
      ]);
      source.rows = [
        {
          ...applicantRow('hired', status: 'hired'),
          'applicant_name':
              'An applicant with a very long name for responsive coverage',
        },
        applicantRow('applied'),
      ];
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
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: EmployerApplicantsPage(
                key: ValueKey(width),
                source: source,
                jobId: 'real-job-id',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(EmployerApplicantCard), findsNWidgets(2));
        expect(find.text('No resume attached'), findsNWidgets(2));
        expect(find.byType(EmployerResumeButton), findsNothing);
        await tester.ensureVisible(find.text('Reject'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'width $width');
      }
    },
  );
}
