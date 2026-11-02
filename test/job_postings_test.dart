import 'dart:async';

import 'package:jobmate/features/jobs/job_ai_formatter.dart';

import 'package:jobmate/features/jobs/job_validation.dart';

import 'dart:convert';

import 'package:jobmate/features/company/company_logo.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:jobmate/features/jobs/job_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_form_page.dart';
import 'package:jobmate/features/jobs/job_postings_page.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TestJobs extends JobPostingsRepository {
  TestJobs()
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  JobAccess access = const JobAccess({
    'company_id': 'company',
    'company_name': 'Hiring Co',
  }, null);
  List<Map<String, dynamic>> records = [];
  Map<String, dynamic>? saved;
  Object? saveError;
  Completer<void>? pending;
  int saves = 0;
  bool authenticated = true;
  int formats = 0;
  String? formattedDescription;
  Object? formatError;
  Completer<void>? formatPending;
  @override
  bool get signedIn => authenticated;
  @override
  Future<Map<String, String>> formatDescription(String description) async {
    formats++;
    formattedDescription = description;
    if (formatPending != null) await formatPending!.future;
    if (formatError != null) throw formatError!;
    return {
      'role_overview': 'Generated overview\nSecond paragraph',
      'responsibilities': 'Help customers\nOrganise products',
      'requirements': 'Communicate clearly',
      'benefits': 'Flexible hours',
    };
  }

  @override
  Future<JobAccess> loadAccess() async => access;
  @override
  Future<List<Map<String, dynamic>>> list(String companyId) async => records;
  @override
  Future<Map<String, dynamic>> save(
    Map<String, dynamic> values, {
    String? jobId,
    String expectedStatus = 'draft',
  }) async {
    saves++;
    if (pending != null) await pending!.future;
    if (saveError != null) throw saveError!;
    saved = values;
    final existing =
        records.where((j) => j['job_id'] == jobId).firstOrNull ??
        <String, dynamic>{};
    records.removeWhere((j) => j['job_id'] == jobId);
    records.add({...existing, ...values, 'job_id': jobId ?? 'new-job'});
    return {...existing, ...values, 'job_id': jobId ?? 'new-job'};
  }

  @override
  Future<void> close(String jobId) async {
    records.firstWhere((j) => j['job_id'] == jobId)['status'] = 'closed';
  }
}

TextEditingController field(WidgetTester tester, String label) => tester
    .widgetList<TextField>(find.byType(TextField))
    .firstWhere((f) => inputLabel(f) == label)
    .controller!;

GoRouter testRouter(TestJobs repo, {bool dashboard = false, String? initial}) =>
    GoRouter(
      initialLocation: initial ?? (dashboard ? '/' : AppRoutes.jobPostings),
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Dashboard root')),
        ),
        GoRoute(
          path: AppRoutes.jobPostings,
          builder: (_, state) => JobPostingsPage(
            repository: repo,
            initialStatus: state.uri.queryParameters['status'] ?? 'draft',
          ),
        ),
        GoRoute(
          path: AppRoutes.createJob,
          builder: (_, _) => JobFormPage(repository: repo),
        ),
        GoRoute(
          path: '${AppRoutes.jobPostings}/:jobId/edit',
          builder: (_, state) => JobFormPage(
            repository: repo,
            jobId: state.pathParameters['jobId'],
          ),
        ),
      ],
    );
String? inputLabel(TextField field) =>
    field.decoration?.labelText ??
    (field.decoration?.label is Text
        ? ((field.decoration!.label as Text).textSpan?.toPlainText().replaceAll(
            ' *',
            '',
          ))
        : null);

Map<String, dynamic> completeJob() => {
  'title': 'Complete role',
  'department': 'Retail',
  'employment_type': 'part_time',
  'work_arrangement': 'on_site',
  'location': 'Shah Alam',
  'salary_min': 12,
  'salary_max': 18,
  'salary_period': 'hourly',
  'salary_visible': true,
  'vacancies': 3,
  'application_deadline': '${DateTime.now().year + 1}-12-31',
  'original_description': 'First paragraph.\nSecond paragraph.',
  'role_overview': 'A useful role.',
  'responsibilities': ['Help customers'],
  'requirements': ['Communicate clearly'],
  'benefits': ['Flexible hours'],
};
void completeForm(WidgetTester tester) {
  final job = completeJob();
  for (final input in tester.widgetList<TextField>(find.byType(TextField))) {
    final label = inputLabel(input);
    const keys = {
      'Job title': 'title',
      'Department': 'department',
      'Job location': 'location',
      'Minimum salary': 'salary_min',
      'Maximum salary': 'salary_max',
      'Vacancies': 'vacancies',
      'Application deadline': 'application_deadline',
      'Original description': 'original_description',
      'Role overview': 'role_overview',
      'Responsibilities': 'responsibilities',
      'Requirements': 'requirements',
      'Benefits': 'benefits',
    };
    final value = job[keys[label]];
    if (value != null) {
      input.controller!.text = value is List ? value.join('\n') : '$value';
    }
  }
}

void main() {
  test('AI response parsing is strict and preserves structured lines', () {
    expect(
      parseJobFormatting({
        'role_overview': ' Summary\nParagraph ',
        'responsibilities': [' Help customers ', '', 'Organise products'],
        'requirements': ['Communicate'],
        'benefits': ['Flexibility'],
      })['responsibilities'],
      'Help customers\nOrganise products',
    );
    expect(
      () => parseJobFormatting({
        'role_overview': 'Summary',
        'responsibilities': ['Valid'],
        'requirements': [42],
        'benefits': [],
      }),
      throwsFormatException,
    );
    expect(
      () => parseJobFormatting({'role_overview': 'Summary'}),
      throwsFormatException,
    );
  });
  testWidgets(
    'AI requires sign-in and 30 characters without changing manual text',
    (tester) async {
      final repo = TestJobs()..authenticated = false;
      await tester.pumpWidget(MaterialApp(home: JobFormPage(repository: repo)));
      await tester.pumpAndSettle();
      final ai = find.widgetWithText(OutlinedButton, 'Format with AI ✨');
      await tester.ensureVisible(ai);
      await tester.tap(ai);
      await tester.pumpAndSettle();
      expect(find.text('Sign in to use AI formatting.'), findsOneWidget);
      repo.authenticated = true;
      field(tester, 'Original description').text = 'Too short';
      await tester.tap(ai);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Enter at least 30 characters'),
        findsOneWidget,
      );
      expect(repo.formats, 0);
      expect(field(tester, 'Original description').text, 'Too short');
    },
  );
  testWidgets(
    'AI applies editable text, blocks duplicates and persists its applied flag',
    (tester) async {
      final repo = TestJobs()..formatPending = Completer<void>();
      final router = testRouter(repo, initial: AppRoutes.createJob);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      field(tester, 'Job title').text = 'AI role';
      const original =
          '  We need a helpful retail assistant to support customers every weekend.  ';
      field(tester, 'Original description').text = original;
      final ai = find.widgetWithText(OutlinedButton, 'Format with AI ✨');
      await tester.ensureVisible(ai);
      await tester.tap(ai);
      await tester.pump();
      expect(repo.formats, 1);
      expect(find.text('Formatting…'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Formatting…'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Save Draft'),
            )
            .onPressed,
        isNull,
      );
      repo.formatPending!.complete();
      await tester.pumpAndSettle();
      expect(repo.formattedDescription, original.trim());
      expect(field(tester, 'Original description').text, original);
      expect(
        field(tester, 'Role overview').text,
        'Generated overview\nSecond paragraph',
      );
      expect(
        field(tester, 'Responsibilities').text,
        'Help customers\nOrganise products',
      );
      field(tester, 'Benefits').text = 'My reviewed benefit';
      final save = find.widgetWithText(OutlinedButton, 'Save Draft');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.saved?['ai_assisted'], true);
      expect(repo.saved?['benefits'], ['My reviewed benefit']);
      expect(repo.saved?['responsibilities'], [
        'Help customers',
        'Organise products',
      ]);
    },
  );
  for (final status in [401, 403, 429, 502]) {
    testWidgets(
      'AI $status failure preserves manual fields and allows saving',
      (tester) async {
        final repo = TestJobs()
          ..formatError = FunctionException(status: status);
        final router = testRouter(repo, initial: AppRoutes.createJob);
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        completeForm(tester);
        final before = field(tester, 'Role overview').text;
        final ai = find.widgetWithText(OutlinedButton, 'Format with AI ✨');
        await tester.ensureVisible(ai);
        await tester.tap(ai);
        await tester.pumpAndSettle();
        expect(find.text('Replace existing content?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(repo.formats, 0);
        await tester.tap(ai);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Replace with AI'));
        await tester.pumpAndSettle();
        expect(
          find.text(jobFormattingError(FunctionException(status: status))),
          findsOneWidget,
        );
        expect(field(tester, 'Role overview').text, before);
        expect(field(tester, 'Responsibilities').text, 'Help customers');
        final save = find.widgetWithText(OutlinedButton, 'Save Draft');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(repo.saved?['ai_assisted'], false);
        expect(repo.saved?['role_overview'], before);
      },
    );
  }
  testWidgets(
    'Validation refreshes immediately after corrections and clearing without another submission',
    (tester) async {
      final repo = TestJobs();
      await tester.pumpWidget(MaterialApp(home: JobFormPage(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text('Enter department.'), findsNothing);
      final publish = find.widgetWithText(FilledButton, 'Publish');
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await tester.pumpAndSettle();
      expect(find.text('Enter department.'), findsOneWidget);
      expect(find.text('Enter job title.'), findsOneWidget);
      final title = find.byWidgetPredicate(
        (w) => w is TextField && inputLabel(w) == 'Job title',
      );
      await tester.ensureVisible(title);
      await tester.enterText(title, 'Retail assistant');
      await tester.pumpAndSettle();
      expect(find.text('Enter job title.'), findsNothing);
      expect(find.text('Enter department.'), findsOneWidget);
      final titleInput = tester.widget<TextField>(title);
      expect(titleInput.decoration!.errorText, isNull);
      expect(
        (titleInput.decoration!.label as Text).textSpan!.toPlainText(),
        'Job title *',
      );
      await tester.enterText(title, '   ');
      await tester.pumpAndSettle();
      expect(find.text('Enter job title.'), findsOneWidget);
      completeForm(tester);
      await tester.pumpAndSettle();
      for (final input in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(input.decoration?.errorText, isNull, reason: inputLabel(input));
      }
      field(tester, 'Minimum salary').text = '30';
      await tester.pumpAndSettle();
      expect(
        find.text('Maximum salary must be at least the minimum.'),
        findsOneWidget,
      );
      field(tester, 'Minimum salary').text = '12';
      await tester.pumpAndSettle();
      expect(
        find.text('Maximum salary must be at least the minimum.'),
        findsNothing,
      );
      field(tester, 'Responsibilities').text = ' \n  ';
      await tester.pumpAndSettle();
      expect(
        find.text('Add at least one responsibilities bullet point.'),
        findsOneWidget,
      );
      field(tester, 'Responsibilities').text = '\n Assist customers \n';
      await tester.pumpAndSettle();
      expect(
        find.text('Add at least one responsibilities bullet point.'),
        findsNothing,
      );
      field(tester, 'Application deadline').clear();
      await tester.pumpAndSettle();
      expect(find.text('Enter application deadline.'), findsOneWidget);
      final picker = find.byTooltip('Choose application deadline');
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Enter application deadline.'), findsNothing);
      expect(repo.saves, 0);
      expect(find.byType(JobFormPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Draft validation refresh stays under draft rules', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: JobFormPage(repository: TestJobs())),
    );
    await tester.pumpAndSettle();
    final save = find.widgetWithText(OutlinedButton, 'Save Draft');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Enter job title.'), findsOneWidget);
    expect(find.text('Enter department.'), findsNothing);
    field(tester, 'Job title').text = 'Draft role';
    await tester.pumpAndSettle();
    expect(find.text('Enter job title.'), findsNothing);
    expect(find.text('Enter department.'), findsNothing);
  });
  test('Every publication field is required and numeric/deadline constraints apply', () {
    expect(jobPublicationErrors(completeJob()), isEmpty);
    for (final key in jobRequiredFields) {
      final invalid = {
        ...completeJob(),
        key: jobBulletFields.contains(key) ? [' ', '\n'] : '   ',
      };
      expect(jobPublicationErrors(invalid).containsKey(key), true, reason: key);
    }
    for (final entry in {
      'salary_min': -1,
      'salary_max': 1,
      'vacancies': 0,
      'application_deadline': '2026-02-30',
    }.entries) {
      expect(
        jobPublicationErrors({...completeJob(), entry.key: entry.value})
            .containsKey(entry.key),
        true,
      );
    }
    final today = DateTime.now().toIso8601String().substring(0, 10);
    expect(
      jobPublicationErrors({...completeJob(), 'application_deadline': today})
          .containsKey('application_deadline'),
      true,
    );
    expect(
      jobPublicationErrors({...completeJob(), 'salary_visible': null})
          .containsKey('salary_visible'),
      true,
    );
    expect(
      jobPublicationErrors({
        ...completeJob(),
        'work_arrangement': 'remote',
        'location': 'Malaysia',
      }),
      isEmpty,
    );
  });
  testWidgets(
    'Published edits validate all fields, retain status and timestamp, and return to Published',
    (tester) async {
      const publishedAt = '2026-11-01T10:00:00Z';
      final repo = TestJobs()
        ..records = [
          {
            ...completeJob(),
            'job_id': 'live',
            'status': 'published',
            'published_at': publishedAt,
          },
        ];
      final router = testRouter(
        repo,
        initial: '${AppRoutes.jobPostings}?status=published',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final edit = find.widgetWithText(FilledButton, 'Edit');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.text('Save Draft'), findsNothing);
      expect(find.text('Publish'), findsNothing);
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
        true,
      );
      field(tester, 'Department').text = '  ';
      final save = find.widgetWithText(FilledButton, 'Save Changes');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
      expect(find.text('Enter department.'), findsOneWidget);
      field(tester, 'Department').text = 'Updated department';
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.saved?['status'], 'published');
      expect(repo.saved!.containsKey('published_at'), false);
      expect(repo.saved!.containsKey('company_id'), false);
      expect(repo.saved!.containsKey('created_by'), false);
      expect(repo.records.single['published_at'], publishedAt);
      expect(find.text('Job updated successfully'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'published (1)'),
            )
            .selected,
        true,
      );
    },
  );
  testWidgets(
    'Description Enter actions retain focus and multiline content round trips',
    (tester) async {
      final repo = TestJobs();
      final router = testRouter(repo, initial: AppRoutes.createJob);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      field(tester, 'Job title').text = 'Multiline role';
      for (final label in [
        'Original description',
        'Role overview',
        'Responsibilities',
        'Requirements',
        'Benefits',
      ]) {
        final input = find.byWidgetPredicate(
          (w) => w is TextField && inputLabel(w) == label,
        );
        final widget = tester.widget<TextField>(input);
        expect(widget.keyboardType, TextInputType.multiline);
        expect(widget.textInputAction, TextInputAction.newline);
        expect(widget.maxLines, greaterThan(1));
        await tester.ensureVisible(input);
        await tester.tap(input);
        await tester.pump();
        final focus = FocusManager.instance.primaryFocus;
        await tester.enterText(input, 'First line\nSecond line');
        await tester.testTextInput.receiveAction(TextInputAction.newline);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(focus));
        expect(field(tester, label).text, 'First line\nSecond line');
        expect(repo.saves, 0);
      }
      final save = find.widgetWithText(OutlinedButton, 'Save Draft');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.saved?['original_description'], 'First line\nSecond line');
      expect(repo.saved?['role_overview'], 'First line\nSecond line');
      for (final key in ['responsibilities', 'requirements', 'benefits']) {
        expect(repo.saved?[key], ['First line', 'Second line']);
      }
      await tester.ensureVisible(find.text('Edit Draft'));
      await tester.tap(find.text('Edit Draft'));
      await tester.pumpAndSettle();
      for (final label in [
        'Original description',
        'Role overview',
        'Responsibilities',
        'Requirements',
        'Benefits',
      ]) {
        expect(field(tester, label).text, 'First line\nSecond line');
      }
      final preview = find.widgetWithText(OutlinedButton, 'Preview');
      await tester.ensureVisible(preview);
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(JobPreview),
          matching: find.text('First line\nSecond line'),
        ),
        findsNWidgets(2),
      );
      expect(find.text('First line'), findsNWidgets(3));
      expect(find.text('Second line'), findsNWidgets(3));
    },
  );
  testWidgets(
    'Company logo appears on cards and preview and disappears on refresh when removed',
    (tester) async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jBz0AAAAASUVORK5CYII=',
      );
      final repo = TestJobs()
        ..access = JobAccess(
          {'company_id': 'company', 'company_name': 'Hiring Co'},
          null,
          logo: bytes,
        )
        ..records = [
          {
            'job_id': 'draft',
            'company_id': 'company',
            'title': 'Logo role',
            'status': 'draft',
          },
        ];
      await tester.pumpWidget(
        MaterialApp(home: JobPostingsPage(repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CompanyIdentity), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      final preview = find.widgetWithText(OutlinedButton, 'Preview');
      await tester.ensureVisible(preview);
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(JobPreview),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.byType(JobPreview))).pop();
      await tester.pumpAndSettle();
      repo.access = const JobAccess({
        'company_id': 'company',
        'company_name': 'New company name',
      }, null);
      final refresh = find.widgetWithText(OutlinedButton, 'Refresh');
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.text('New company name'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
  test('Description lines become trimmed JSON string arrays', () {
    expect(jobLines(' Build apps\n\n Test apps \n'), [
      'Build apps',
      'Test apps',
    ]);
  });
  for (final width in [320.0, 1440.0]) {
    for (final publish in [false, true]) {
      testWidgets(
        'Save returns to refreshed ${publish ? 'published' : 'draft'} list at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repo = TestJobs();
          final router = testRouter(repo);
          addTearDown(router.dispose);
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(FilledButton, 'Create Job').first,
          );
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextFormField).first, 'Engineer');
          final action = publish
              ? find.widgetWithText(FilledButton, 'Publish')
              : find.widgetWithText(OutlinedButton, 'Save Draft');
          if (publish) {
            await tester.ensureVisible(action);
            await tester.tap(action);
            await tester.pumpAndSettle();
            expect(repo.saved, isNull);
            expect(find.text('Enter role overview.'), findsOneWidget);
            completeForm(tester);
            field(tester, 'Job title').text = 'Engineer';
            field(tester, 'Job location').text = 'Kuala Lumpur';
            field(tester, 'Role overview').text = 'Build useful software.';
            field(tester, 'Responsibilities').text = 'Build apps\n\n Test apps';
          }
          await tester.ensureVisible(action);
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(repo.saved?['status'], publish ? 'published' : 'draft');
          expect(
            repo.saved?['responsibilities'],
            publish ? ['Build apps', 'Test apps'] : <String>[],
          );
          expect(repo.saved!.containsKey('company_id'), false);
          expect(find.byType(JobFormPage), findsNothing);
          expect(find.text('Engineer'), findsOneWidget);
          expect(
            find.text(
              publish ? 'Job published successfully' : 'Job saved as draft',
            ),
            findsOneWidget,
          );
          expect(
            tester
                .widget<ChoiceChip>(
                  find.widgetWithText(
                    ChoiceChip,
                    '${publish ? 'published' : 'draft'} (1)',
                  ),
                )
                .selected,
            true,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'Existing draft saves and returns to its list without losing dashboard back navigation',
    (tester) async {
      final repo = TestJobs()
        ..records = [
          {
            'job_id': 'draft',
            'title': 'Existing role',
            'status': 'draft',
            'vacancies': 1,
          },
        ];
      final router = testRouter(repo, dashboard: true);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.push(AppRoutes.jobPostings);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Draft'));
      await tester.pumpAndSettle();
      field(tester, 'Job title').text = 'Updated role';
      final action = find.widgetWithText(OutlinedButton, 'Save Draft');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Updated role'), findsOneWidget);
      expect(router.canPop(), true);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Dashboard root'), findsOneWidget);
    },
  );
  testWidgets(
    'Failed save stays on form and duplicate submissions are blocked',
    (tester) async {
      final repo = TestJobs()
        ..saveError = StateError('Save rejected')
        ..pending = Completer<void>();
      final router = testRouter(repo, initial: AppRoutes.createJob);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      field(tester, 'Job title').text = 'Engineer';
      final save = find.widgetWithText(OutlinedButton, 'Save Draft');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      expect(tester.widget<OutlinedButton>(save).onPressed, isNull);
      expect(repo.saves, 1);
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(JobFormPage), findsOneWidget);
      expect(find.text('Save rejected'), findsOneWidget);
      expect(field(tester, 'Job title').text, 'Engineer');
      repo.saveError = null;
      repo.pending = null;
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(JobFormPage), findsNothing);
      expect(find.text('Engineer'), findsOneWidget);
    },
  );
  testWidgets('Every field has guidance and deadline has a picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: JobFormPage(repository: TestJobs())),
    );
    await tester.pumpAndSettle();
    for (final input in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(input.decoration!.hintText, isNotEmpty);
    }
    final picker = find.byTooltip('Choose application deadline');
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      field(tester, 'Application deadline').text,
      matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
    );
  });
  testWidgets('Saved preview includes sections and hides private salary', (
    tester,
  ) async {
    final job = <String, dynamic>{
      'title': 'Retail assistant',
      'department': 'Retail',
      'employment_type': 'part_time',
      'work_arrangement': 'hybrid',
      'salary_visible': true,
      'salary_min': 12,
      'salary_max': 18,
      'salary_period': 'hourly',
      'original_description': 'Original text',
      'role_overview': 'Overview text',
      'responsibilities': ['Help customers'],
      'requirements': ['Communication'],
      'benefits': ['Flexible hours'],
      'published_at': '2026-11-01T10:00:00Z',
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobPreview(job: job, company: 'Hiring Co'),
        ),
      ),
    );
    expect(find.text('Original text'), findsOneWidget);
    expect(find.text('Help customers'), findsOneWidget);
    expect(find.text('Communication'), findsOneWidget);
    expect(find.text('Flexible hours'), findsOneWidget);
    expect(find.text('Part-time'), findsOneWidget);
    expect(find.text('2026-11-01'), findsOneWidget);
    expect(find.textContaining('12'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobPreview(
            job: {...job, 'salary_visible': false},
            company: 'Hiring Co',
          ),
        ),
      ),
    );
    expect(find.text('Salary'), findsNothing);
    expect(find.textContaining('12'), findsNothing);
  });
  testWidgets('Draft card publishes saved data and selects Published', (
    tester,
  ) async {
    final repo = TestJobs()
      ..records = [
        {
          ...completeJob(),
          'job_id': 'draft',
          'title': 'Ready role',
          'status': 'draft',
          'work_arrangement': 'remote',
          'role_overview': 'A useful role',
          'vacancies': 2,
          'salary_visible': false,
          'salary_min': 12345,
          'salary_max': 20000,
          'created_at': '2026-11-01T10:00:00Z',
        },
      ];
    await tester.pumpWidget(
      MaterialApp(home: JobPostingsPage(repository: repo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Work arrangement: Remote'), findsOneWidget);
    expect(find.text('Vacancies: 2'), findsOneWidget);
    expect(find.text('Created: 2026-11-01'), findsOneWidget);
    expect(find.textContaining('12345'), findsNothing);
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Publish'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Publish'));
    await tester.pumpAndSettle();
    expect(repo.saves, 1);
    expect(repo.records.single['status'], 'published');
    expect(find.text('Ready role'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'published (1)'))
          .selected,
      true,
    );
    expect(find.text('Close Job'), findsOneWidget);
  });
  testWidgets('Draft card does not publish incomplete saved data', (
    tester,
  ) async {
    final repo = TestJobs()
      ..records = [
        {'job_id': 'draft', 'title': 'Incomplete role', 'status': 'draft'},
      ];
    await tester.pumpWidget(
      MaterialApp(home: JobPostingsPage(repository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Publish'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Publish'));
    await tester.pumpAndSettle();
    expect(repo.saves, 0);
    expect(find.textContaining('Use Edit Draft'), findsOneWidget);
  });
  testWidgets('Unverified company disables creation', (tester) async {
    final repo = TestJobs()
      ..access = const JobAccess(null, 'Company pending verification.');
    await tester.pumpWidget(
      MaterialApp(home: JobPostingsPage(repository: repo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Company pending verification.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Create Job'))
          .onPressed,
      isNull,
    );
  });
  testWidgets('Filters show jobs and closing requires confirmation', (
    tester,
  ) async {
    final repo = TestJobs()
      ..records = [
        {'job_id': 'draft', 'title': 'Draft role', 'status': 'draft'},
        {'job_id': 'live', 'title': 'Live role', 'status': 'published'},
        {'job_id': 'closed', 'title': 'Closed role', 'status': 'closed'},
      ];
    await tester.pumpWidget(
      MaterialApp(home: JobPostingsPage(repository: repo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit Draft'), findsOneWidget);
    await tester.tap(find.text('published (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Live role'), findsOneWidget);
    await tester.ensureVisible(find.text('Close Job'));
    await tester.tap(find.text('Close Job'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Close Job'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('closed (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Live role'), findsOneWidget);
    expect(find.text('Edit Draft'), findsNothing);
    expect(find.text('Close Job'), findsNothing);
  });
  testWidgets('Closed job form is read-only', (tester) async {
    final repo = TestJobs()
      ..records = [
        {'job_id': 'closed', 'title': 'Closed role', 'status': 'closed'},
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: JobFormPage(jobId: 'closed', repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Save Draft'), findsNothing);
    expect(find.text('Publish'), findsNothing);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
      false,
    );
  });
}
