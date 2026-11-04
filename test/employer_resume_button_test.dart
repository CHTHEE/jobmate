import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/employer_applicants_repository.dart';
import 'package:jobmate/features/applications/employer_resume_button.dart';
import 'package:jobmate/features/applications/resume_pdf_opener.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/employer_applicants_source.dart';

class FakeWindow implements ResumePdfWindow {
  Uri? navigated;
  int closes = 0;
  bool allowed = true;
  @override
  bool navigate(Uri uri) {
    navigated = uri;
    return allowed;
  }

  @override
  void close() {
    closes++;
  }
}

class FakeOpener implements ResumePdfOpener {
  FakeOpener({required this.isWeb});
  @override
  final bool isWeb;
  final events = <String>[];
  final windows = <FakeWindow>[];
  bool blocked = false, launchAllowed = true;
  final opened = <Uri>[];
  @override
  ResumePdfWindow? reserve() {
    events.add('reserve');
    if (blocked) return null;
    final window = FakeWindow();
    windows.add(window);
    return window;
  }

  @override
  Future<bool> open(Uri uri) async {
    events.add('open');
    opened.add(uri);
    return launchAllowed;
  }
}

void main() {
  late TestEmployerApplicantsSource source;
  late EmployerApplicantsRepository repo;
  late DateTime clock;
  FunctionResponse response({
    String url = 'https://storage.example.test/resume.pdf?token=private',
    dynamic expiry = 60,
  }) => FunctionResponse(
    status: 200,
    data: {'signed_url': url, 'expires_in': expiry},
  );
  setUp(() async {
    clock = DateTime(2026, 11, 4);
    source = TestEmployerApplicantsSource()
      ..rows = [
        {...applicantRow('mock-application'), 'resume_id': 'mock-resume'},
      ];
    repo = EmployerApplicantsRepository(source, 'real-job-id');
    await repo.load();
  });
  tearDown(() async {
    repo.dispose();
    await source.changes.close();
  });
  Future<void> mount(WidgetTester tester, FakeOpener opener) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmployerResumeButton(
              repository: repo,
              applicant: repo.applicants.single,
              opener: opener,
              now: () => clock,
            ),
          ),
        ),
      );

  test(
    'Only absolute HTTPS URLs and positive integral expiry are accepted',
    () {
      for (final url in [
        '/relative.pdf',
        'http://example.test/x',
        'javascript:alert(1)',
        'https://',
        'https://user:secret@example.test/x',
      ]) {
        expect(
          () => ApplicationResumeLink(response(url: url), clock),
          throwsFormatException,
        );
      }
      for (final expiry in <dynamic>[null, '60', 0, -1, 1.5, double.infinity]) {
        expect(
          () => ApplicationResumeLink(response(expiry: expiry), clock),
          throwsFormatException,
        );
      }
      final link = ApplicationResumeLink(response(), clock);
      expect(link.uri.scheme, 'https');
      expect(link.expiresAt, clock.add(const Duration(seconds: 60)));
    },
  );
  testWidgets(
    'Web reserves before request and opens automatically on one click',
    (tester) async {
      final opener = FakeOpener(isWeb: true);
      final pending = Completer<FunctionResponse>();
      source.fetchResume = () {
        opener.events.add('request');
        return pending.future;
      };
      await mount(tester, opener);
      await tester.tap(find.text('View Resume'));
      await tester.pump();
      expect(opener.events, ['reserve', 'request']);
      expect(source.resumeRequests, ['mock-application']);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete(response());
      await tester.pumpAndSettle();
      expect(opener.windows.single.navigated!.scheme, 'https');
      expect(find.text('Open PDF'), findsNothing);
      expect(opener.opened, isEmpty);
      expect(find.textContaining('private'), findsNothing);
    },
  );
  testWidgets(
    'Native requests then launches automatically, without fallback action',
    (tester) async {
      final opener = FakeOpener(isWeb: false);
      source.fetchResume = () async {
        opener.events.add('request');
        return response();
      };
      await mount(tester, opener);
      await tester.tap(find.text('View Resume'));
      await tester.pumpAndSettle();
      expect(opener.events, ['request', 'open']);
      expect(opener.opened.length, 1);
      expect(source.resumeRequests.length, 1);
      expect(find.text('Open PDF'), findsNothing);
    },
  );
  testWidgets(
    'Only a blocked Web opening offers Open PDF and reuses valid link',
    (tester) async {
      final opener = FakeOpener(isWeb: true)..blocked = true;
      source.fetchResume = () async => response();
      await mount(tester, opener);
      await tester.tap(find.text('View Resume'));
      await tester.pumpAndSettle();
      expect(find.text('Open PDF'), findsOneWidget);
      await tester.tap(find.text('Open PDF'));
      await tester.pumpAndSettle();
      expect(opener.opened.length, 1);
      expect(source.resumeRequests.length, 1);
      expect(find.text('Open PDF'), findsNothing);
    },
  );
  testWidgets('Expired fallback renews link via the same one-click Web flow', (
    tester,
  ) async {
    final opener = FakeOpener(isWeb: true)..blocked = true;
    source.fetchResume = () async => response();
    await mount(tester, opener);
    await tester.tap(find.text('View Resume'));
    await tester.pumpAndSettle();
    clock = clock.add(const Duration(seconds: 61));
    opener.blocked = false;
    await tester.tap(find.text('Open PDF'));
    await tester.pumpAndSettle();
    expect(source.resumeRequests.length, 2);
    expect(opener.windows.single.navigated, isNotNull);
    expect(find.text('Open PDF'), findsNothing);
  });
  for (final status in [400, 401, 403, 404, 500]) {
    testWidgets('HTTP $status closes reserved tab and shows safe error', (
      tester,
    ) async {
      final opener = FakeOpener(isWeb: true);
      source.fetchResume = () => Future.error(
        FunctionException(
          status: status,
          details: 'https://secret.invalid/?token=private',
        ),
      );
      await mount(tester, opener);
      await tester.tap(find.text('View Resume'));
      await tester.pumpAndSettle();
      expect(opener.windows.single.closes, greaterThan(0));
      expect(opener.windows.single.navigated, isNull);
      expect(find.textContaining('private'), findsNothing);
      expect(find.text('Open PDF'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Malformed response never navigates a reserved window', (
    tester,
  ) async {
    final opener = FakeOpener(isWeb: true);
    source.fetchResume = () async => response(url: '/relative.pdf');
    await mount(tester, opener);
    await tester.tap(find.text('View Resume'));
    await tester.pumpAndSettle();
    expect(opener.windows.single.navigated, isNull);
    expect(opener.windows.single.closes, greaterThan(0));
    expect(find.textContaining('invalid or expired'), findsOneWidget);
  });
  testWidgets('Logout closes pending tab and discards late signed URL', (
    tester,
  ) async {
    final opener = FakeOpener(isWeb: true);
    final pending = Completer<FunctionResponse>();
    source.fetchResume = () => pending.future;
    await mount(tester, opener);
    await tester.tap(find.text('View Resume'));
    await tester.pump();
    source.switchAccount(null);
    pending.complete(response());
    await tester.pumpAndSettle();
    expect(opener.windows.single.closes, greaterThan(0));
    expect(opener.windows.single.navigated, isNull);
    expect(find.text('Open PDF'), findsNothing);
  });
  testWidgets(
    'Disposal during request closes pending tab and ignores completion',
    (tester) async {
      final opener = FakeOpener(isWeb: true);
      final pending = Completer<FunctionResponse>();
      source.fetchResume = () => pending.future;
      await mount(tester, opener);
      await tester.tap(find.text('View Resume'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      pending.complete(response());
      await tester.pumpAndSettle();
      expect(opener.windows.single.closes, greaterThan(0));
      expect(opener.windows.single.navigated, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('A timed-out request closes its tab and can retry', (
    tester,
  ) async {
    final opener = FakeOpener(isWeb: true);
    final pending = Completer<FunctionResponse>();
    source.fetchResume = () => pending.future;
    await mount(tester, opener);
    await tester.tap(find.text('View Resume'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(opener.windows.single.closes, greaterThan(0));
    expect(opener.windows.single.navigated, isNull);
    source.fetchResume = () async => response();
    await tester.tap(find.text('View Resume'));
    await tester.pumpAndSettle();
    expect(opener.windows.last.navigated, isNotNull);
    pending.complete(response());
    await tester.pumpAndSettle();
    expect(opener.windows.first.navigated, isNull);
  });
}
