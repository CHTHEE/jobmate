import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_pages.dart';
import 'package:jobmate/features/work_attendance/work_evidence_qa_page.dart';
import 'package:jobmate/features/work_attendance/work_evidence_qa_review.dart';
import 'package:jobmate/features/work_attendance/work_evidence_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, evidenceRow, id, other;

class _LoopbackHttpOverrides extends HttpOverrides {}

class FakeQaReview implements WorkEvidenceQaReviewSource {
  FakeQaReview(this.attendance);
  final FakeSource attendance;
  @override
  String? get userId => attendance.userId;
  @override
  Stream<String?> get accountChanges => attendance.accountChanges;
  final calls = <(bool, String, String?)>[];
  late Future<void> Function(bool, String?) response;
  @override
  Future<void> verify(String assignmentId) {
    calls.add((true, assignmentId, null));
    return response(true, null);
  }

  @override
  Future<void> requestMore(String assignmentId, String reason) {
    calls.add((false, assignmentId, reason));
    return response(false, reason);
  }
}

void main() {
  late FakeSource source;
  late WorkAttendanceRepository attendance;
  late WorkEvidenceRepository viewer;
  late FakeQaReview review;
  late WorkEvidenceQaReviewSession session;
  late Map<String, dynamic> row, file;
  late Future<JobAccess> Function() access;
  setUp(() {
    source = FakeSource();
    row = assignment(company: true)
      ..['assignment_id'] = supervisedWorkEvidenceQaAssignment
      ..['assignment_status'] = 'awaiting_verification'
      ..['verification_status'] = 'pending_review'
      ..['check_in_at'] = '2026-11-05T01:00:00Z'
      ..['check_out_at'] = '2026-11-05T09:00:00Z';
    file = evidenceRow()
      ..['submission_round'] = 1
      ..['storage_path'] = '$supervisedWorkEvidenceQaAssignment/test.pdf';
    source.companyRead = (_) async => [row];
    source.evidenceRead = (_) async => [file];
    access = () async => const JobAccess({'company_id': id}, null);
    attendance = WorkAttendanceRepository(source);
    viewer = WorkEvidenceRepository.employer(
      attendance,
      assignmentId: supervisedWorkEvidenceQaAssignment,
      companyId: id,
      loadCompanyAccess: () => access(),
    );
    session = WorkEvidenceQaReviewSession();
    review = FakeQaReview(source);
    review.response = (verify, _) async {
      row['verification_status'] = verify
          ? 'verified'
          : 'more_evidence_required';
      if (verify) {
        row['assignment_status'] = 'completed';
        row['verified_at'] = '2026-11-05T10:00:00Z';
      }
    };
  });
  tearDown(() async {
    viewer.dispose();
    attendance.dispose();
    await source.changes.close();
  });
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorkEvidencePage(
          repository: viewer,
          createQaReviewSource: () => review,
          qaReviewSession: session,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(
    WidgetTester tester,
    String text, {
    bool settle = true,
  }) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> open(WidgetTester tester) =>
      press(tester, 'Review work (QA only)');
  bool enabled(WidgetTester tester, String text) =>
      tester
          .widget<ButtonStyleButton>(
            find
                .ancestor(
                  of: find.text(text),
                  matching: find.bySubtype<ButtonStyleButton>(),
                )
                .first,
          )
          .onPressed !=
      null;

  testWidgets(
    'verify requires confirmation and refreshes authoritative status, with honest history notice',
    (tester) async {
      await show(tester);
      await open(tester);
      expect(
        find.text('Authoritative verification status: pending_review'),
        findsOneWidget,
      );
      expect(
        find.text('Verification history isn’t available here yet.'),
        findsOneWidget,
      );
      await press(tester, 'Verify Work');
      expect(review.calls, isEmpty);
      await press(tester, 'Cancel');
      expect(review.calls, isEmpty);
      await press(tester, 'Verify Work');
      await press(tester, 'Confirm review');
      expect(review.calls.single, (
        true,
        supervisedWorkEvidenceQaAssignment,
        null,
      ));
      expect(
        find.text('Authoritative verification status: verified'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Work verified successfully!'),
        findsOneWidget,
      );
      expect(enabled(tester, 'Verify Work'), isFalse);
      expect(viewer.evidence, hasLength(1));
    },
  );
  testWidgets(
    'request-more validates trimmed reason and refreshes actual status',
    (tester) async {
      await show(tester);
      await open(tester);
      expect(enabled(tester, 'Request More Evidence'), isFalse);
      await tester.enterText(find.byType(TextField), ' ' * 3);
      await tester.pump();
      expect(enabled(tester, 'Request More Evidence'), isFalse);
      await tester.enterText(find.byType(TextField), 'x' * 1001);
      await tester.pump();
      expect(find.text('Use at most 1,000 characters.'), findsOneWidget);
      expect(enabled(tester, 'Request More Evidence'), isFalse);
      await tester.enterText(
        find.byType(TextField),
        '  Add the missing detail.  ',
      );
      await tester.pump();
      await press(tester, 'Request More Evidence');
      expect(review.calls, isEmpty);
      await press(tester, 'Confirm review');
      expect(review.calls.single, (
        false,
        supervisedWorkEvidenceQaAssignment,
        'Add the missing detail.',
      ));
      expect(
        find.text('Authoritative verification status: more_evidence_required'),
        findsOneWidget,
      );
      expect(enabled(tester, 'Request More Evidence'), isFalse);
    },
  );
  testWidgets(
    'duplicate clicks blocked while real-interface fake operation is pending',
    (tester) async {
      final pending = Completer<void>();
      review.response = (_, _) => pending.future;
      await show(tester);
      await open(tester);
      await press(tester, 'Verify Work');
      await press(tester, 'Confirm review', settle: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(review.calls, hasLength(1));
      expect(enabled(tester, 'Verify Work'), isFalse);
      expect(enabled(tester, 'Request More Evidence'), isFalse);
      pending.complete();
      await tester.pumpAndSettle();
      expect(review.calls, hasLength(1));
    },
  );
  testWidgets(
    'uncertain RPC and failed read reconciliation remain blocked across dialog reopening',
    (tester) async {
      review.response = (_, _) async {
        source.companyRead = (_) async => throw StateError('read unavailable');
        throw TimeoutException('lost response');
      };
      await show(tester);
      await open(tester);
      await press(tester, 'Verify Work');
      await press(tester, 'Confirm review');
      expect(
        find.textContaining('ask for help to check what happened'),
        findsOneWidget,
      );
      expect(enabled(tester, 'Verify Work'), isFalse);
      await press(tester, 'Close');
      source.companyRead = (_) async => [row];
      await viewer.load();
      await tester.pumpAndSettle();
      await open(tester);
      expect(
        find.textContaining('Further QA review actions are blocked'),
        findsOneWidget,
      );
      expect(enabled(tester, 'Verify Work'), isFalse);
      expect(review.calls, hasLength(1));
    },
  );
  testWidgets(
    'lost response can show verified state but never claims request reconciliation or unlocks',
    (tester) async {
      final commit = review.response;
      review.response = (action, reason) async {
        await commit(action, reason);
        throw TimeoutException('lost');
      };
      await show(tester);
      await open(tester);
      await press(tester, 'Verify Work');
      await press(tester, 'Confirm review');
      expect(
        find.text('Authoritative verification status: verified'),
        findsOneWidget,
      );
      expect(
        find.textContaining('We could not confirm your review'),
        findsOneWidget,
      );
      expect(find.textContaining('Your review was recorded'), findsNothing);
      expect(enabled(tester, 'Verify Work'), isFalse);
      expect(review.calls, hasLength(1));
    },
  );
  testWidgets(
    'revoked company authorization after confirmation prevents writes',
    (tester) async {
      await show(tester);
      await open(tester);
      await press(tester, 'Verify Work');
      access = () async => const JobAccess(null, 'denied');
      await press(tester, 'Confirm review');
      expect(review.calls, isEmpty);
      expect(find.textContaining('No review was sent.'), findsOneWidget);
    },
  );
  testWidgets(
    'new submission round after confirmation prevents reviewing unseen evidence',
    (tester) async {
      await show(tester);
      await open(tester);
      await press(tester, 'Verify Work');
      file['submission_round'] = 2;
      await press(tester, 'Confirm review');
      expect(review.calls, isEmpty);
      expect(find.textContaining('No review was sent.'), findsOneWidget);
    },
  );
  testWidgets(
    'account switch away and back during confirmation invalidates action',
    (tester) async {
      await show(tester);
      await open(tester);
      await press(tester, 'Verify Work');
      source.userId = other;
      source.changes.add(other);
      source.userId = id;
      source.changes.add(id);
      await tester.pump();
      await press(tester, 'Confirm review');
      expect(review.calls, isEmpty);
      expect(
        find.text('Account or company context changed. Close this dialog.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('other assignments retain read-only production review', (
    tester,
  ) async {
    viewer.dispose();
    row['assignment_id'] = id;
    viewer = WorkEvidenceRepository.employer(
      attendance,
      assignmentId: id,
      companyId: id,
      loadCompanyAccess: () => access(),
    );
    await show(tester);
    expect(find.text('Review work (QA only)'), findsNothing);
    expect(review.calls, isEmpty);
  });
  testWidgets('narrow enlarged-text confirmation remains accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await viewer.load();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: WorkEvidenceQaReviewDialog(
          viewer: viewer,
          source: review,
          session: session,
        ),
      ),
    );
    await press(tester, 'Verify Work');
    await press(tester, 'Cancel');
    expect(tester.takeException(), isNull);
    expect(review.calls, isEmpty);
  });

  test('Supabase adapter exact deployed RPCs, QA scope and no POST retries (loopback only)', () async {
    // Remove Flutter's blanket HTTP-400 override only inside this loopback test.
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <(String, Map<String, dynamic>)>[];
      var fail = false;
      server.listen((request) async {
        expect(request.method, 'POST');
        requests.add((
          request.uri.path,
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        ));
        request.response.statusCode = fail ? 503 : 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            fail ? {'code': '503', 'message': 'fake unavailable'} : null,
          ),
        );
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'fake-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      final adapter = SupabaseWorkEvidenceQaReviewSource(client);
      await expectLater(
        adapter.verify(supervisedWorkEvidenceQaAssignment),
        throwsA(isA<AuthException>()),
      );
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'fake-token',
          'token_type': 'bearer',
          'user': {'id': id},
        }),
      );
      await adapter.verify(supervisedWorkEvidenceQaAssignment);
      await adapter.requestMore(
        supervisedWorkEvidenceQaAssignment,
        '  Detail  ',
      );
      expect(requests.map((r) => r.$1), [
        '/rest/v1/rpc/verify_work_assignment',
        '/rest/v1/rpc/request_more_work_evidence',
      ]);
      expect(requests.first.$2, {
        'p_assignment_id': supervisedWorkEvidenceQaAssignment,
      });
      expect(requests.last.$2, {
        'p_assignment_id': supervisedWorkEvidenceQaAssignment,
        'p_reason': 'Detail',
      });
      await expectLater(adapter.verify(id), throwsFormatException);
      expect(
        () => adapter.requestMore(supervisedWorkEvidenceQaAssignment, ' '),
        throwsFormatException,
      );
      expect(
        () =>
            adapter.requestMore(supervisedWorkEvidenceQaAssignment, 'x' * 1001),
        throwsFormatException,
      );
      fail = true;
      await expectLater(
        adapter.verify(supervisedWorkEvidenceQaAssignment),
        throwsA(isA<PostgrestException>()),
      );
      expect(requests, hasLength(3));
    }, _LoopbackHttpOverrides());
  });
}
