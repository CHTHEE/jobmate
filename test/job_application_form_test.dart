import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/job_application_form.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/features/applications/module2_widgets.dart';
import 'package:jobmate/features/profile/resume_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/job_application_gateway.dart';

void main() {
  late Module2Repository repository;
  late TestApplicationGateway gateway;
  late BrowseJob job;
  String? destination;
  setUp(() {
    destination = null;
    repository = Module2Repository();
    gateway = TestApplicationGateway();
    job = BrowseJob.published({
      'job_id': 'real-job',
      'title': 'Cafe Crew',
      'company_name': 'ABC Company',
      'application_deadline': '2099-12-31',
    });
  });
  tearDown(() async {
    repository.dispose();
    await gateway.changes.close();
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => moduleModal<String>(
                context,
                JobApplicationForm(
                  job: job,
                  repository: repository,
                  gateway: gateway,
                ),
              ).then((route) => destination = route),
              child: const Text('Open Apply'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Apply'));
    await tester.pumpAndSettle();
  }

  const resume = ResumeFile(
    id: 'resume-id',
    path: 'owner/document.pdf',
    name: 'My original CV.pdf',
    size: 42,
    bucket: 'jobmate-resumes',
    uploadedAt: null,
  );

  for (final width in [320.0, 1440.0]) {
    testWidgets('Resume selection and confirmed submission at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      gateway.files = [resume];
      await open(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(resume.name).last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'My cover note');
      final pending = Completer<String>();
      gateway.send = () => pending.future;
      await tester.ensureVisible(find.text('Submit application'));
      await tester.tap(find.text('Submit application'));
      await tester.pump();
      expect(gateway.submissions, 1);
      expect(gateway.sentJob, 'real-job');
      expect(gateway.sentResume, 'resume-id');
      expect(gateway.sentNote, 'My cover note');
      expect(find.text('Application submitted'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Submitting…'),
            )
            .onPressed,
        isNull,
      );
      pending.complete('returned-application-id');
      await tester.pumpAndSettle();
      expect(find.text('Application submitted'), findsOneWidget);
      expect(
        find.text('Application ID: returned-application-id'),
        findsNothing,
      );
      expect(find.text('My Applications'), findsOneWidget);
      expect(repository.applied('real-job'), isFalse);
      await tester.ensureVisible(find.text('My Applications'));
      await tester.tap(find.text('My Applications'));
      await tester.pumpAndSettle();
      expect(destination, '/applications');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('No resume is optional; server errors retain cover note', (
    tester,
  ) async {
    await open(tester);
    expect(find.textContaining('No uploaded resumes'), findsOneWidget);
    expect(find.text('Visit My Resume'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Keep this note');
    gateway.send = () => Future.error(
      const PostgrestException(
        message: 'Application deadline has passed',
        code: 'P0001',
      ),
    );
    await tester.ensureVisible(find.text('Submit application'));
    await tester.tap(find.text('Submit application'));
    await tester.pumpAndSettle();
    expect(gateway.sentResume, isNull);
    expect(find.text('Application deadline has passed'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep this note',
    );
    gateway.send = () => Future.error(
      const PostgrestException(message: 'duplicate', code: '23505'),
    );
    await tester.tap(find.text('Submit application'));
    await tester.pumpAndSettle();
    expect(find.text('You have already applied for this job.'), findsOneWidget);
    expect(find.text('Application submitted'), findsNothing);
    expect(repository.applications.length, 7);
  });

  testWidgets('Resume errors offer retry and prevent accidental submission', (
    tester,
  ) async {
    gateway.load = () => Future.error(StateError('Resume service unavailable'));
    await open(tester);
    expect(find.textContaining('Resume service unavailable'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Submit application'),
          )
          .onPressed,
      isNull,
    );
    gateway.load = () async => [resume];
    await tester.tap(find.text('Retry resumes'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
  });

  testWidgets('Visiting My Resume keeps the draft for reopening Apply', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byType(TextField),
      'Preserve for resume upload',
    );
    await tester.ensureVisible(find.text('Visit My Resume'));
    await tester.tap(find.text('Visit My Resume'));
    await tester.pumpAndSettle();
    expect(destination, '/document-submission');
    expect(
      repository.noteDraft('application:seeker-a:real-job'),
      'Preserve for resume upload',
    );
    await tester.tap(find.text('Open Apply'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Preserve for resume upload',
    );
  });

  testWidgets('Dirty cancel confirms and unexpected disposal retains note', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Draft');
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard application draft?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await open(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Draft',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(repository.noteDraft('application:seeker-a:real-job'), isEmpty);
  });

  testWidgets(
    'Account change ignores pending resume and submission responses',
    (tester) async {
      final pending = Completer<List<ResumeFile>>();
      gateway.load = () => pending.future;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JobApplicationForm(
              job: job,
              repository: repository,
              gateway: gateway,
            ),
          ),
        ),
      );
      await tester.pump();
      gateway.switchAccount('seeker-b');
      pending.complete([resume]);
      await tester.pumpAndSettle();
      expect(find.text('Session changed'), findsOneWidget);
      expect(find.text(resume.name), findsNothing);
      expect(find.text('Submit application'), findsNothing);
      expect(gateway.submissions, 0);
    },
  );

  testWidgets(
    'Account switch during submission hides stale success and draft',
    (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Private draft');
      final pending = Completer<String>();
      gateway.send = () => pending.future;
      await tester.ensureVisible(find.text('Submit application'));
      await tester.tap(find.text('Submit application'));
      await tester.pump();
      gateway.switchAccount(null);
      pending.complete('old-account-application');
      await tester.pumpAndSettle();
      expect(find.text('Session changed'), findsOneWidget);
      expect(find.textContaining('old-account-application'), findsNothing);
      expect(find.text('Private draft'), findsNothing);
      expect(repository.noteDraft('application:seeker-a:real-job'), isEmpty);
    },
  );
}
