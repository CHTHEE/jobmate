import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_form_page.dart';
import 'package:jobmate/features/jobs/job_form_widgets.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/jobs/job_preview.dart';

import 'job_postings_test.dart'
    show TestJobs, completeForm, completeJob, field, inputLabel, testRouter;

Finder selectField(String label) => find.descendant(
  of: find.ancestor(
    of: find.text('$label *', findRichText: true),
    matching: find.byType(JobLabeledField),
  ),
  matching: find.byType(DropdownButton<String>),
);

class PendingCreateAccess extends TestJobs {
  var check = Completer<JobAccess>();
  final logo = Completer<Uint8List?>();
  final accessCalls = <bool>[];
  int logoCalls = 0;
  final postings = Completer<List<Map<String, dynamic>>>();

  @override
  Future<JobAccess> loadAccess({bool includeLogo = true}) {
    accessCalls.add(includeLogo);
    return check.future;
  }

  @override
  Future<Uint8List?> loadAccessLogo(JobAccess access) {
    logoCalls++;
    return logo.future;
  }

  @override
  Future<List<Map<String, dynamic>>> list(String companyId) => postings.future;
}

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

  testWidgets('salary preview and maximum validation react to either field', (
    tester,
  ) async {
    final repo = TestJobs();
    await tester.pumpWidget(MaterialApp(home: JobFormPage(repository: repo)));
    await tester.pumpAndSettle();
    final minimum = field(tester, 'Minimum salary (RM)');
    final maximum = field(tester, 'Maximum salary (RM)');
    final rangeError = find.text(
      'Maximum salary must be equal to or greater than minimum salary.',
    );
    final invalid = find.text(
      'Salary preview: Please enter a valid salary range.',
    );
    final incomplete = find.text('Salary preview: Enter both salary amounts.');
    expect(incomplete, findsOneWidget);
    expect(
      tester.widget<TextField>(input('Maximum salary (RM)')).enabled,
      isTrue,
    );
    maximum.text = '4500';
    await tester.pump();
    expect(incomplete, findsOneWidget);
    expect(rangeError, findsNothing);

    minimum.text = '3000';
    await tester.pump();
    expect(find.text('Salary preview: RM 3,000–4,500 / month'), findsOneWidget);
    minimum.text = '5000';
    await tester.pump();
    final maxField = find.ancestor(
      of: input('Maximum salary (RM)'),
      matching: find.byType(TextFormField),
    );
    expect(find.descendant(of: maxField, matching: rangeError), findsOneWidget);
    expect(invalid, findsOneWidget);
    expect(find.text('Salary preview: RM 5,000–4,500 / month'), findsNothing);

    maximum.text = '5500';
    await tester.pump();
    expect(rangeError, findsNothing);
    expect(find.text('Salary preview: RM 5,000–5,500 / month'), findsOneWidget);
    maximum.text = '3000';
    await tester.pump();
    expect(rangeError, findsOneWidget);
    minimum.text = '3000';
    await tester.pump();
    expect(rangeError, findsNothing);
    expect(find.text('Salary preview: RM 3,000 / month'), findsOneWidget);

    for (final bad in ['invalid', '-1', 'Infinity', 'NaN']) {
      minimum.text = bad;
      await tester.pump();
      expect(invalid, findsOneWidget);
      expect(rangeError, findsNothing);
    }
    minimum.clear();
    await tester.pump();
    expect(incomplete, findsOneWidget);
  });

  testWidgets(
    'hidden reversed salary cannot save, publish or render in job preview',
    (tester) async {
      final repo = TestJobs();
      await tester.pumpWidget(MaterialApp(home: JobFormPage(repository: repo)));
      await tester.pumpAndSettle();
      completeForm(tester);
      final state = tester.state<JobFormPageState>(find.byType(JobFormPage));
      state.selected['work_arrangement'] = 'remote';
      field(tester, 'Minimum salary (RM)').text = '5000';
      field(tester, 'Maximum salary (RM)').text = '4500';
      await tap(tester, find.byType(SwitchListTile));
      expect(
        find.text('Salary preview: Please enter a valid salary range.'),
        findsOneWidget,
      );
      await tap(tester, find.text('Save Draft'));
      await tap(tester, find.text('Publish Job'));
      expect(repo.saves, 0);
      await tap(tester, find.byType(SwitchListTile));
      await tap(tester, find.text('Preview unsaved changes'));
      final preview = find.byType(JobPreview);
      expect(
        find.descendant(
          of: preview,
          matching: find.text('Salary not disclosed'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('RM 5,000–4,500'), findsNothing);
      expect(field(tester, 'Minimum salary (RM)').text, '5000');
      expect(field(tester, 'Maximum salary (RM)').text, '4500');
    },
  );

  testWidgets('published edits cannot submit a newly reversed salary range', (
    tester,
  ) async {
    final repo = TestJobs()
      ..records = [
        {...completeJob(), 'job_id': 'live', 'status': 'published'},
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: JobFormPage(jobId: 'live', repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    field(tester, 'Minimum salary (RM)').text = '20';
    await tap(tester, find.text('Save Changes'));
    expect(
      find.text(
        'Maximum salary must be equal to or greater than minimum salary.',
      ),
      findsOneWidget,
    );
    expect(repo.saves, 0);
  });

  DropdownButton<String> dropdown(WidgetTester tester, String label) =>
      tester.widget<DropdownButton<String>>(selectField(label));

  Future<void> choose(WidgetTester tester, String label, String option) async {
    await tap(tester, selectField(label));
    await tap(tester, find.text(option).last);
  }

  testWidgets(
    'employment types expose only compatible periods and keep compatible defaults',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: JobFormPage(repository: TestJobs())),
      );
      await tester.pumpAndSettle();
      void expectPeriod(String value, List<String> options) {
        final period = dropdown(tester, 'Salary period');
        expect(period.value, value);
        expect(period.items!.map((item) => item.value), options);
      }

      expect(dropdown(tester, 'Employment type').value, 'full_time');
      expectPeriod('monthly', ['monthly']);
      expect(
        tester
            .widget<TextField>(input('Minimum salary (RM)'))
            .decoration!
            .hintText,
        'e.g. 3000',
      );
      await choose(tester, 'Employment type', 'Part-time');
      expectPeriod('hourly', ['hourly', 'daily']);
      expect(
        find.text('Part-time jobs support hourly or daily pay.'),
        findsOneWidget,
      );
      await choose(tester, 'Employment type', 'Temporary');
      expectPeriod('hourly', ['hourly', 'daily']);
      await choose(tester, 'Employment type', 'Full-time');
      await choose(tester, 'Employment type', 'Temporary');
      expectPeriod('daily', ['hourly', 'daily']);
      expect(
        tester
            .widget<TextField>(input('Minimum salary (RM)'))
            .decoration!
            .hintText,
        'e.g. 100',
      );
      await choose(tester, 'Employment type', 'Contract');
      expectPeriod('monthly', ['monthly']);
      await choose(tester, 'Employment type', 'Internship');
      expectPeriod('monthly', ['monthly']);
      expect(dropdown(tester, 'Salary period').onChanged, isNull);
      expect(
        tester
            .widget<TextField>(input('Minimum salary (RM)'))
            .decoration!
            .hintText,
        'e.g. 800',
      );
      expect(
        tester
            .widget<TextField>(input('Maximum salary (RM)'))
            .decoration!
            .hintText,
        'e.g. 1200',
      );
      expect(find.text('Change salary period?'), findsNothing);
    },
  );

  testWidgets(
    'type changes protect amounts and cancel or dismiss keeps the original terms',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: JobFormPage(repository: TestJobs())),
      );
      await tester.pumpAndSettle();
      field(tester, 'Job title').text = 'Keep this title';
      field(tester, 'Minimum salary (RM)').text = '3000';
      field(tester, 'Maximum salary (RM)').text = '4500';
      await choose(tester, 'Employment type', 'Contract');
      expect(find.text('Change salary period?'), findsNothing);
      expect(field(tester, 'Maximum salary (RM)').text, '4500');

      await choose(tester, 'Employment type', 'Temporary');
      expect(
        find.textContaining('Changing from Monthly to Daily'),
        findsOneWidget,
      );
      await tap(tester, find.widgetWithText(TextButton, 'Cancel').last);
      expect(dropdown(tester, 'Employment type').value, 'contract');
      expect(dropdown(tester, 'Salary period').value, 'monthly');
      expect(field(tester, 'Minimum salary (RM)').text, '3000');

      await choose(tester, 'Employment type', 'Temporary');
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.text('Change salary period?'), findsNothing);
      expect(dropdown(tester, 'Salary period').value, 'monthly');
      expect(field(tester, 'Maximum salary (RM)').text, '4500');

      await choose(tester, 'Employment type', 'Temporary');
      await tap(tester, find.text('Change & reset salary'));
      expect(dropdown(tester, 'Employment type').value, 'temporary');
      expect(dropdown(tester, 'Salary period').value, 'daily');
      expect(field(tester, 'Minimum salary (RM)').text, isEmpty);
      expect(field(tester, 'Maximum salary (RM)').text, isEmpty);
      expect(field(tester, 'Job title').text, 'Keep this title');
      field(tester, 'Minimum salary (RM)').text = '100';
      field(tester, 'Maximum salary (RM)').text = '150';
      await tester.pump();
      expect(find.text('Salary preview: RM 100–150 / day'), findsOneWidget);
      await choose(tester, 'Salary period', 'Hourly');
      await tap(tester, find.text('Change & reset salary'));
      field(tester, 'Minimum salary (RM)').text = '12';
      field(tester, 'Maximum salary (RM)').text = '18';
      await tester.pump();
      expect(find.text('Salary preview: RM 12–18 / hour'), findsOneWidget);
    },
  );

  testWidgets(
    'draft save rejects an incompatible pair even when selection is bypassed',
    (tester) async {
      final repo = TestJobs();
      final key = GlobalKey<JobFormPageState>();
      await tester.pumpWidget(
        MaterialApp(
          home: JobFormPage(key: key, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      field(tester, 'Job title').text = 'Fixture title';
      key.currentState!.selected['salary_period'] = 'hourly';
      final save = key.currentState!.save(false);
      await tester.pumpAndSettle();
      await save;
      expect(
        find.textContaining('Choose a compatible salary period'),
        findsOneWidget,
      );
      expect(repo.saves, 0);
    },
  );

  testWidgets(
    'expired published deadline can be extended through Save Changes',
    (tester) async {
      final repo = TestJobs()
        ..records = [
          {
            ...completeJob(),
            'job_id': 'expired',
            'status': 'published',
            'application_deadline': '2020-11-27',
          },
        ];
      final router = testRouter(repo, initial: '/job-postings/expired/edit');
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.textContaining('Deadline Passed.'), findsOneWidget);
      expect(field(tester, 'Application deadline').text, '2020-11-27');
      await tap(tester, find.text('Save Changes'));
      expect(
        find.textContaining('after today (Malaysia time)'),
        findsOneWidget,
      );
      expect(repo.saves, 0);
      field(tester, 'Application deadline').text = '2099-12-31';
      await tap(tester, find.text('Save Changes'));
      expect(repo.saves, 1);
      expect(repo.records.single['application_deadline'], '2099-12-31');
      expect(repo.records.single['status'], 'published');
      expect(repo.records.single['salary_min'], completeJob()['salary_min']);
    },
  );

  for (final status in ['draft', 'published', 'closed']) {
    testWidgets(
      'legacy $status shows stored compensation and applies status-specific safeguards',
      (tester) async {
        final repo = TestJobs()
          ..records = [
            {
              ...completeJob(),
              'job_id': 'legacy',
              'status': status,
              'employment_type': 'internship',
              'work_arrangement': 'remote',
            },
          ];
        final router = testRouter(repo, initial: '/job-postings/legacy/edit');
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        expect(dropdown(tester, 'Salary period').value, 'hourly');
        expect(field(tester, 'Minimum salary (RM)').text, '12');
        if (status == 'closed') {
          expect(dropdown(tester, 'Employment type').onChanged, isNull);
          expect(
            tester.widget<TextField>(input('Minimum salary (RM)')).enabled,
            isFalse,
          );
          expect(find.text('Save Changes'), findsNothing);
          return;
        }
        field(tester, 'Job title').text = 'Unrelated edit';
        if (status == 'draft') {
          expect(
            find.textContaining('This saved salary period is incompatible'),
            findsOneWidget,
          );
          await tap(tester, find.text('Publish Job'));
          expect(
            find.textContaining('Choose a compatible salary period'),
            findsOneWidget,
          );
          expect(repo.saves, 0);
          await tap(tester, find.text('Save Draft'));
        } else {
          expect(
            find.textContaining(
              'This published job uses a legacy salary period',
            ),
            findsOneWidget,
          );
          expect(dropdown(tester, 'Employment type').onChanged, isNull);
          expect(
            tester.widget<TextField>(input('Minimum salary (RM)')).enabled,
            isFalse,
          );
          await tap(tester, find.text('Save Changes'));
        }
        expect(repo.saves, 1);
        expect(repo.saved?['title'], 'Unrelated edit');
        expect(repo.saved?['employment_type'], 'internship');
        expect(repo.saved?['salary_period'], 'hourly');
        expect(repo.saved?['salary_min'], 12);
        expect(repo.saved?['salary_max'], 18);
      },
    );
  }

  for (final dialog in [false, true]) {
    testWidgets(
      'Create Job keeps local input available while verifying (dialog: $dialog)',
      (tester) async {
        await tester.binding.setSurfaceSize(
          dialog ? const Size(390, 800) : const Size(1200, 900),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repo = PendingCreateAccess();
        await tester.pumpWidget(
          MaterialApp(
            home: JobFormPage(repository: repo, dialog: dialog),
          ),
        );
        expect(find.text('Verifying company...'), findsOneWidget);
        expect(find.text('Hiring Co'), findsNothing);
        expect(tester.widget<TextField>(input('Job title')).enabled, isTrue);
        expect(field(tester, 'Vacancies').text, '1');
        field(tester, 'Job title').text = 'Draft during verification';
        field(tester, 'Vacancies').text = '3';
        final publish = find.widgetWithText(FilledButton, 'Publish Job');
        final draft = find.widgetWithText(OutlinedButton, 'Save Draft');
        final preview = find.widgetWithText(
          TextButton,
          'Preview unsaved changes',
        );
        expect(tester.widget<FilledButton>(publish).onPressed, isNull);
        expect(tester.widget<OutlinedButton>(draft).onPressed, isNull);
        expect(tester.widget<TextButton>(preview).onPressed, isNull);
        expect(repo.accessCalls, [false]);
        expect(repo.logoCalls, 0);

        repo.check.complete(repo.access);
        await tester.pumpAndSettle();
        expect(repo.logoCalls, 1);
        expect(find.text('Hiring Co'), findsOneWidget);
        expect(find.byType(CircleAvatar), findsWidgets);
        expect(tester.widget<FilledButton>(publish).onPressed, isNotNull);
        expect(tester.widget<OutlinedButton>(draft).onPressed, isNotNull);
        expect(tester.widget<TextButton>(preview).onPressed, isNotNull);
        expect(field(tester, 'Job title').text, 'Draft during verification');
        expect(field(tester, 'Vacancies').text, '3');
        if (dialog) {
          repo.logo.complete(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jBz0AAAAASUVORK5CYII=',
            ),
          );
        } else {
          repo.logo.completeError(StateError('Optional logo unavailable'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Hiring Co'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Image && widget.semanticLabel == 'Hiring Co logo',
          ),
          dialog ? findsOneWidget : findsNothing,
        );
        expect(tester.widget<FilledButton>(publish).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'retry preserves a dirty draft and a late result after discard is ignored',
    (tester) async {
      final repo = PendingCreateAccess();
      final router = testRouter(repo, initial: '/job-postings/create');
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      field(tester, 'Job title').text = 'Preserve my draft';
      repo.check.completeError(Exception('Offline'));
      await tester.pumpAndSettle();
      expect(find.text('Unable to connect. Please try again.'), findsOneWidget);
      repo.check = Completer<JobAccess>();
      final retry = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Retry'))
          .onPressed!;
      retry();
      retry();
      await tester.pump();
      expect(repo.accessCalls, [false, false]);
      expect(field(tester, 'Job title').text, 'Preserve my draft');
      await tester.tap(find.text('Back to Job Postings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Discard changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(JobFormPage), findsNothing);
      repo.check.complete(repo.access);
      repo.postings.complete([]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repo.logoCalls, 0);
    },
  );

  testWidgets('denied Create Job hides draft and retains the access message', (
    tester,
  ) async {
    final repo = PendingCreateAccess();
    await tester.pumpWidget(MaterialApp(home: JobFormPage(repository: repo)));
    repo.check.complete(
      const JobAccess(null, 'Company verification required.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Company verification required.'), findsOneWidget);
    expect(input('Job title'), findsNothing);
    expect(find.text('Publish Job'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(repo.logoCalls, 0);
  });

  testWidgets(
    'account change hides authorized details and drops the pending logo',
    (tester) async {
      final repo = PendingCreateAccess();
      Future<void> setActor(String id) => repo.client.auth.setInitialSession(
        jsonEncode({
          'access_token':
              'eyJhbGciOiJub25lIn0.eyJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.',
          'token_type': 'bearer',
          'user': {'id': id, 'aud': 'authenticated'},
        }),
      );
      await setActor('first-employer');
      await tester.pumpWidget(MaterialApp(home: JobFormPage(repository: repo)));
      repo.check.complete(repo.access);
      await tester.pumpAndSettle();
      expect(find.text('Hiring Co'), findsOneWidget);
      expect(repo.logoCalls, 1);
      await setActor('second-employer');
      await tester.pumpAndSettle();
      repo.logo.complete(Uint8List.fromList([1]));
      await tester.pumpAndSettle();
      expect(
        find.text('Your account changed. Reopen the job form.'),
        findsOneWidget,
      );
      expect(find.text('Hiring Co'), findsNothing);
      expect(find.text('Publish Job'), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Edit Job waits for access and the authoritative posting', (
    tester,
  ) async {
    final repo = PendingCreateAccess();
    await tester.pumpWidget(
      MaterialApp(
        home: JobFormPage(repository: repo, jobId: 'existing'),
      ),
    );
    expect(repo.accessCalls, [true]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(input('Job title'), findsNothing);
    repo.check.complete(repo.access);
    await tester.pump();
    expect(input('Job title'), findsNothing);
    repo.postings.complete([
      {...completeJob(), 'job_id': 'existing', 'status': 'draft'},
    ]);
    await tester.pumpAndSettle();
    expect(field(tester, 'Job title').text, completeJob()['title']);
    expect(repo.logoCalls, 0);
  });

  testWidgets(
    'external labels and real verification; employment dropdown persists incomplete draft',
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
      final employment = selectField('Employment type');
      expect(
        tester
            .widget<DropdownButton<String>>(employment)
            .items!
            .map((item) => (item.child as Text).data),
        ['Full-time', 'Part-time', 'Contract', 'Internship', 'Temporary'],
      );
      field(tester, 'Job title').text = 'An incomplete internship draft';
      await tap(tester, employment);
      await tap(
        tester,
        find.widgetWithText(DropdownMenuItem<String>, 'Internship').last,
      );
      expect(
        tester
            .widget<DropdownButton<String>>(selectField('Employment type'))
            .value,
        'internship',
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
      expect(
        find.textContaining('Minimum salary (RM)', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Maximum salary (RM)', findRichText: true),
        findsOneWidget,
      );
      await tester.ensureVisible(input('Minimum salary (RM)'));
      await tester.enterText(input('Minimum salary (RM)'), '1500');
      await tester.enterText(input('Maximum salary (RM)'), '1600');
      await tester.pump();
      expect(
        find.text('Salary preview: RM 1,500–1,600 / month'),
        findsOneWidget,
      );
      await choose(tester, 'Employment type', 'Part-time');
      expect(find.text('Change salary period?'), findsOneWidget);
      await tap(tester, find.text('Change & reset salary'));
      expect(field(tester, 'Minimum salary (RM)').text, isEmpty);
      expect(field(tester, 'Maximum salary (RM)').text, isEmpty);
      await tester.enterText(input('Minimum salary (RM)'), '12');
      await tester.enterText(input('Maximum salary (RM)'), '18');
      await tester.pump();
      expect(find.text('Salary preview: RM 12–18 / hour'), findsOneWidget);
      await tap(tester, find.byType(SwitchListTile));
      expect(find.text('Salary preview: Salary not disclosed'), findsOneWidget);
      expect(repo.saves, 0);
      expect(repo.formats, 0);
      final vacancies = find.ancestor(
        of: input('Vacancies'),
        matching: find.byType(JobFormSection),
      );
      expect(
        find.descendant(
          of: vacancies,
          matching: find.text('Schedule & Location'),
        ),
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
            .widget<DropdownButton<String>>(selectField('Employment type'))
            .value,
        'internship',
      );
      expect(find.text('Save Draft'), findsNothing);
      expect(find.text('Publish Job'), findsNothing);
      expect(find.text('Save Changes'), findsOneWidget);
      expect(
        find.text('Preview your edits, then choose Save Changes.'),
        findsOneWidget,
      );
      field(tester, 'Job title').text = 'Unsaved changed title';
      field(tester, 'Original description').text =
          'Original text remains distinct from generated details.';
      await tap(tester, find.byType(SwitchListTile));
      await tap(tester, find.text('Preview unsaved changes'));
      final preview = find.byType(JobPreview);
      expect(
        find.descendant(
          of: preview,
          matching: find.text('Salary not disclosed'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.textContaining('RM 12–18')),
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
        await tap(tester, find.text('Preview unsaved changes'));
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
