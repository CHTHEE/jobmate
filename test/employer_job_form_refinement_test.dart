import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_form_page.dart';
import 'package:jobmate/features/jobs/job_form_widgets.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/jobs/job_preview.dart';

import 'job_postings_test.dart'
    show TestJobs, completeJob, field, inputLabel, testRouter;

void main() {
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder input(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && inputLabel(widget) == label,
  );

  testWidgets(
    'external labels and real verification; employment chips persist incomplete draft',
    (tester) async {
      final repo = TestJobs()
        ..access = const JobAccess({
          'company_id': 'company',
          'company_name': 'Hiring Co',
          'verification_status': 'verified',
        }, null);
      final router = testRouter(repo, initial: '/job-postings/create');
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('Verified company'), findsOneWidget);
      expect(find.text('Basic Information'), findsOneWidget);
      expect(find.byType(JobLabeledField), findsWidgets);
      expect(
        tester.widget<TextField>(input('Job title')).decoration!.label,
        isNull,
      );
      expect(find.text('Job title *', findRichText: true), findsOneWidget);
      for (final label in [
        'Full-time',
        'Part-time',
        'Contract',
        'Internship',
        'Temporary',
      ]) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
      field(tester, 'Job title').text = 'An incomplete internship draft';
      await tap(tester, find.widgetWithText(ChoiceChip, 'Internship'));
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Internship'))
            .selected,
        isTrue,
      );
      await tap(tester, find.text('Save Draft'));
      expect(repo.saved?['employment_type'], 'internship');
      expect(repo.saved?['title'], 'An incomplete internship draft');
      expect(repo.saved?['status'], 'draft');
      expect(repo.formats, 0);
      expect(repo.saves, 1);
    },
  );

  testWidgets(
    'live compensation preview respects edits, period and hidden salary',
    (tester) async {
      final repo = TestJobs();
      await tester.pumpWidget(MaterialApp(home: JobFormPage(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text('Verified company'), findsNothing);
      await tester.ensureVisible(input('Minimum salary'));
      await tester.enterText(input('Minimum salary'), '1500');
      await tester.enterText(input('Maximum salary'), '1600');
      await tester.pump();
      expect(find.text('Salary preview: 1,500–1,600 / month'), findsOneWidget);
      await tap(
        tester,
        find.descendant(
          of: find.byType(DropdownButtonFormField<String>).first,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      await tap(tester, find.text('Hourly').last);
      expect(find.text('Salary preview: 1,500–1,600 / hour'), findsOneWidget);
      await tap(tester, find.byType(SwitchListTile));
      expect(find.text('Salary preview: Not disclosed'), findsOneWidget);
      expect(repo.saves, 0);
      expect(repo.formats, 0);
      final vacancies = find.ancestor(
        of: input('Vacancies'),
        matching: find.byType(JobFormSection),
      );
      expect(
        find.descendant(of: vacancies, matching: find.text('Compensation')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'published edit prepopulates and preview reads unsaved values without side effects',
    (tester) async {
      final repo = TestJobs()
        ..records = [
          {
            ...completeJob(),
            'job_id': 'live',
            'status': 'published',
            'employment_type': 'internship',
          },
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: JobFormPage(jobId: 'live', repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(field(tester, 'Job title').text, 'Complete role');
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Internship'))
            .selected,
        isTrue,
      );
      expect(find.text('Save Draft'), findsNothing);
      expect(find.text('Publish Job'), findsNothing);
      expect(find.text('Save Changes'), findsOneWidget);
      expect(
        find.text('Review your posting and use Save Changes to update it.'),
        findsOneWidget,
      );
      field(tester, 'Job title').text = 'Unsaved changed title';
      field(tester, 'Original description').text =
          'Original text remains distinct from generated details.';
      await tap(tester, find.byType(SwitchListTile));
      await tap(tester, find.text('Preview'));
      final preview = find.byType(JobPreview);
      expect(
        find.descendant(of: preview, matching: find.text('Not disclosed')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.textContaining('12–18')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: preview,
          matching: find.text('Unsaved changed title'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: preview,
          matching: find.text('Employer Original description'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: preview,
          matching: find.text(
            'Original text remains distinct from generated details.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.text('Help customers')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.text('Apply Now')),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Close preview'));
      await tester.pumpAndSettle();
      expect(find.byType(JobPreview), findsNothing);
      expect(field(tester, 'Job title').text, 'Unsaved changed title');
      expect(repo.saves, 0);
      expect(repo.formats, 0);
    },
  );

  testWidgets(
    'form and preview remain usable with scaled text, narrow widths and short heights',
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
        tester.view.physicalSize = Size(width, width == 768 ? 400 : 700);
        tester.view.devicePixelRatio = 1;
        final repo = TestJobs()
          ..records = [
            {
              ...completeJob(),
              'job_id': 'draft',
              'status': 'draft',
              'title': 'A longer employer title for customer service and event coordination',
              'original_description': List.filled(
                20,
                'Long original paragraphs remain available for review.',
              ).join('\n'),
            },
          ];
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: JobFormPage(
                key: ValueKey(width),
                jobId: 'draft',
                repository: repo,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'form width $width');
        await tap(tester, find.text('Preview'));
        expect(find.byType(JobPreview), findsOneWidget);
        final scrollbar = tester.widget<Scrollbar>(
          find.descendant(
            of: find.byType(JobPreview),
            matching: find.byType(Scrollbar),
          ),
        );
        expect(scrollbar.thumbVisibility, isTrue);
        expect(scrollbar.controller!.position.maxScrollExtent, greaterThan(0));
        scrollbar.controller!.jumpTo(
          scrollbar.controller!.position.maxScrollExtent,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'preview width $width');
        await tester.tap(find.byTooltip('Close preview'));
        await tester.pumpAndSettle();
        expect(repo.saves, 0);
        expect(repo.formats, 0);
      }
    },
  );
}
