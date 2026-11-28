import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jobmate/features/applications/employer_applicant_profile.dart';
import 'package:jobmate/features/applications/employer_applicants_repository.dart';
import 'package:jobmate/features/applications/employer_resume_button.dart';
import 'package:jobmate/features/applications/employer_status_change_form.dart';
import 'package:jobmate/features/applications/module2_widgets.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';
import 'package:jobmate/features/chat/chat_application_button.dart';
import 'package:jobmate/features/chat/chat_repository.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';

import 'fixtures/employer_applicants_source.dart';
import 'fixtures/chat_ui.dart';
import 'employer_resume_button_test.dart' show FakeOpener;

class ProfileFixture implements ApplicantProfileRepository {
  final requests = <String>[];
  Map<String, dynamic> data = {'profile': <String, dynamic>{}};
  Future<Map<String, dynamic>> Function()? fetch;
  @override
  Future<Map<String, dynamic>> load(String id) {
    requests.add(id);
    return fetch?.call() ?? Future.value(data);
  }
}

void main() {
  late TestEmployerApplicantsSource source;
  late EmployerApplicantsRepository repo;
  late ProfileFixture profile;
  setUp(() async {
    source = TestEmployerApplicantsSource()
      ..rows = [
        {
          ...applicantRow(chatApplication, status: 'hired'),
          'cover_note': 'My real application note.',
        },
      ];
    repo = EmployerApplicantsRepository(source, 'real-job-id');
    await repo.load();
    profile = ProfileFixture();
  });
  tearDown(() async {
    repo.dispose();
    await source.changes.close();
  });
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Widget button({FakeOpener? opener, ChatRepository Function()? chat}) =>
      ApplicantProfileButton(
        applicationId: chatApplication,
        applicant: repo.applicants.single,
        jobTitle: 'Part-Time Cafe Crew',
        applicantsRepository: repo,
        repository: profile,
        resumeOpener: opener,
        createChatRepository: chat,
      );
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: JobMateTheme.light(),
        home: Scaffold(body: button()),
      ),
    );
    await tap(tester, find.text('View applicant profile'));
  }

  testWidgets(
    'identity, application context, empty sections and status use authorized rows without identifiers',
    (tester) async {
      await open(tester);
      expect(find.text('Applicant Profile'), findsOneWidget);
      expect(find.text('Alex Thee'), findsOneWidget);
      expect(find.text('AT'), findsOneWidget);
      expect(find.text('Applied for: Part-Time Cafe Crew'), findsOneWidget);
      expect(find.text('Hired'), findsOneWidget);
      expect(find.textContaining('Applied:'), findsOneWidget);
      expect(find.text('Application note'), findsOneWidget);
      expect(find.text('My real application note.'), findsOneWidget);
      expect(
        find.text('No profile details have been provided yet.'),
        findsOneWidget,
      );
      for (final label in [
        'About',
        'Skills',
        'Education',
        'Work experience',
        'Languages',
        'Weekly availability',
        'Certifications',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byType(EmployerResumeButton), findsNothing);
      expect(find.textContaining(chatApplication), findsNothing);
      expect(find.textContaining('real-applicant-id'), findsNothing);
      expect(find.textContaining('Application ID:'), findsNothing);
      expect(profile.requests, [chatApplication]);
      await tester.tap(find.byTooltip('Close applicant profile'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  Map<String, dynamic> populated() => {
    'profile': {
      'headline': 'Customer service professional',
      'bio': 'First paragraph.\nSecond paragraph.',
    },
    'skills': [
      {'skill_name': 'Teamwork', 'proficiency': 'Advanced'},
      {
        'skill_name':
            'A long skill name with detailed customer service context',
        'proficiency': 'Intermediate',
      },
    ],
    'education': [
      {
        'institution': 'College',
        'qualification': 'Diploma',
        'field_of_study': 'Business',
        'started_on': '2020-01-01',
        'completed_on': '2022-12-31',
        'description': 'Education detail',
      },
      {'institution': 'University'},
    ],
    'work_experiences': [
      {
        'job_title': 'Assistant',
        'employer_name': 'Previous employer',
        'location': 'Kuala Lumpur',
        'is_current': true,
        'description': 'Work detail',
      },
    ],
    'languages': [
      {'language_name': 'Malay', 'proficiency': 'Fluent'},
    ],
    'availability': [
      {
        'iso_weekday': 1,
        'start_time': '09:00:00',
        'end_time': '17:00:00',
        'timezone_name': 'Asia/Kuala_Lumpur',
      },
    ],
    'certifications': [
      {
        'certification_name': 'Certificate',
        'issuer': 'Issuer',
        'document_attached': true,
        'independently_verified': false,
      },
    ],
  };

  testWidgets(
    'populated sections preserve structured content and proficiency without fake reputation',
    (tester) async {
      profile.data = populated();
      await open(tester);
      for (final text in [
        'Customer service professional',
        'First paragraph.\nSecond paragraph.',
        'Teamwork - Advanced',
        'College',
        'Diploma · Business',
        'Education detail',
        'University',
        'Assistant',
        'Previous employer',
        'Currently working',
        'Work detail',
        'Malay',
        'Fluent',
        'Monday',
        '09:00 – 17:00',
        'Asia/Kuala_Lumpur',
        'Certificate',
        'Issuer',
        'Self-declared; not independently verified',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(
        find.text('No profile details have been provided yet.'),
        findsNothing,
      );
      expect(find.textContaining('Trust score'), findsNothing);
      expect(find.textContaining('reviews'), findsNothing);
      expect(source.updates, isEmpty);
    },
  );

  testWidgets(
    'loading, denied profile and retry are distinct from empty; stale reads never restore data',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      profile.fetch = () => pending.future;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: button())));
      await tester.tap(find.text('View applicant profile'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.text('No profile details have been provided yet.'),
        findsNothing,
      );
      pending.completeError(
        const PostgrestException(message: 'Denied', code: '42501'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Applicant profile unavailable or you no longer have access.',
        ),
        findsOneWidget,
      );
      expect(find.byType(ChatApplicationButton), findsNothing);
      profile.fetch = null;
      await tap(tester, find.text('Retry'));
      expect(
        find.text('No profile details have been provided yet.'),
        findsOneWidget,
      );
      source.switchAccount(null);
      await tester.pumpAndSettle();
      expect(find.text('Alex Thee'), findsNothing);
      expect(find.text('My real application note.'), findsNothing);
      expect(find.byType(ChatApplicationButton), findsNothing);
    },
  );

  testWidgets('pending profile result is discarded after account change', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    profile.fetch = () => pending.future;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: button())));
    await tester.tap(find.text('View applicant profile'));
    await tester.pump();
    source.switchAccount(null);
    await tester.pump();
    pending.complete({
      'profile': {'bio': 'Private late bio'},
    });
    await tester.pumpAndSettle();
    expect(find.text('Private late bio'), findsNothing);
    expect(find.text('Alex Thee'), findsNothing);
  });

  testWidgets(
    'resume reuses browser tab opener and messaging dismisses modal before navigation',
    (tester) async {
      source.rows = [
        {
          ...applicantRow(chatApplication, status: 'hired'),
          'resume_id': 'resume',
        },
      ];
      await repo.load();
      final opener = FakeOpener(isWeb: true);
      final chat = ChatFixtureSource();
      addTearDown(chat.accounts.close);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: button(
                opener: opener,
                chat: () => ChatRepository(
                  source: chat,
                  pendingStore: ChatFixturePendingStore(ChatFixtureStorage()),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/employer-messages/:id',
            builder: (_, _) =>
                const Scaffold(body: Text('Opened conversation')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tap(tester, find.text('View applicant profile'));
      expect(chat.creates, 0);
      await tap(tester, find.text('View Resume'));
      expect(source.resumeRequests, [chatApplication]);
      expect(opener.events.first, 'reserve');
      expect(opener.windows.single.navigated, isNotNull);
      expect(find.textContaining('https://'), findsNothing);
      await tap(tester, find.text('Message Applicant'));
      expect(chat.creates, 1);
      expect(find.text('Opened conversation'), findsOneWidget);
      expect(find.text('Applicant Profile'), findsNothing);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('View applicant profile'), findsOneWidget);
      expect(find.text('Applicant Profile'), findsNothing);
    },
  );

  testWidgets(
    'long profiles and skill chips scroll at 320–1920 widths, 1.6 scale and short heights',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      profile.data = populated();
      profile.data['profile'] = {
        'bio': List.filled(
          20,
          'Long profile paragraphs remain readable.',
        ).join('\n'),
      };
      source.rows = [
        {
          ...applicantRow(chatApplication, status: 'hired'),
          'applicant_name':
              'A very long applicant name for responsive profile coverage',
        },
      ];
      await repo.load();
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
        await tester.pumpWidget(
          MaterialApp(
            theme: JobMateTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(body: button()),
          ),
        );
        await tap(tester, find.text('View applicant profile'));
        final bar = tester.widget<Scrollbar>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollbar),
          ),
        );
        expect(bar.thumbVisibility, isTrue);
        bar.controller!.jumpTo(bar.controller!.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'width $width');
        await tester.tap(find.byTooltip('Close applicant profile'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'recruitment forms scroll with long notes, increased text and short viewports',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      source.rows = [
        {
          ...applicantRow(chatApplication, status: 'interview'),
          'applicant_name':
              'A very long applicant name for recruitment dialog coverage',
        },
      ];
      await repo.load();
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
        await tester.pumpWidget(
          MaterialApp(
            theme: JobMateTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => moduleModal<void>(
                    context,
                    EmployerStatusChangeForm(
                      repository: repo,
                      applicant: repo.applicants.single,
                      next: MyApplicationStatus.offered,
                    ),
                  ),
                  child: const Text('Recruit'),
                ),
              ),
            ),
          ),
        );
        await tap(tester, find.text('Recruit'));
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(
          find.byType(TextField),
          List.filled(20, 'A detailed recruitment note.').join('\n'),
        );
        await tap(tester, find.text('Cancel'));
        expect(find.text('Discard status note?'), findsOneWidget);
        await tap(tester, find.text('Keep editing'));
        await tap(tester, find.byTooltip('Close recruitment dialog'));
        await tap(tester, find.text('Discard'));
        expect(find.byType(EmployerStatusChangeForm), findsNothing);
        expect(source.updates, isEmpty);
        expect(
          tester.takeException(),
          isNull,
          reason: 'recruitment width $width',
        );
      }
    },
  );

  testWidgets(
    'each supported recruitment action keeps confirmation, context, note validation and cancel',
    (tester) async {
      source.data = EmployerPostingContext(source.data.access, [
        for (final job in source.data.jobs)
          {...job, 'employment_type': 'full_time', 'salary_period': 'monthly'},
      ]);
      for (final pair in [
        (MyApplicationStatus.submitted, MyApplicationStatus.shortlisted),
        (MyApplicationStatus.shortlisted, MyApplicationStatus.interview),
        (MyApplicationStatus.interview, MyApplicationStatus.offered),
        (MyApplicationStatus.submitted, MyApplicationStatus.rejected),
      ]) {
        source.rows = [applicantRow(chatApplication, status: pair.$1.name)];
        await repo.load();
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => moduleModal<void>(
                    context,
                    EmployerStatusChangeForm(
                      repository: repo,
                      applicant: repo.applicants.single,
                      next: pair.$2,
                    ),
                  ),
                  child: const Text('Recruit'),
                ),
              ),
            ),
          ),
        );
        await tap(tester, find.text('Recruit'));
        expect(
          find.text('${employerTransitionLabel(pair.$2)} applicant?'),
          findsOneWidget,
        );
        expect(find.text('Alex Thee'), findsOneWidget);
        expect(find.text('Part-Time Cafe Crew'), findsOneWidget);
        if (pair.$2 == MyApplicationStatus.offered) {
          expect(
            find.text(
              'The worker must accept the offer before this application becomes Hired.',
            ),
            findsOneWidget,
          );
        }
        tester.widget<TextField>(find.byType(TextField)).controller!.text =
            'x' * 2001;
        await tap(
          tester,
          find.text('Confirm ${employerTransitionLabel(pair.$2)}'),
        );
        expect(
          tester
              .widget<TextField>(find.byType(TextField))
              .decoration!
              .errorText,
          'Keep the note within 2,000 characters.',
        );
        expect(source.updates, isEmpty);
        tester.widget<TextField>(find.byType(TextField)).controller!.clear();
        await tap(tester, find.text('Cancel'));
        expect(find.byType(EmployerStatusChangeForm), findsNothing);
        expect(source.updates, isEmpty);
      }
    },
  );
}
