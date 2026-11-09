import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_evidence_workflow.dart';
import 'package:jobmate/features/work_attendance/work_evidence_workflow_panel.dart';
import 'package:jobmate/features/work_attendance/work_evidence_draft_controller.dart';
import 'package:jobmate/features/work_attendance/work_evidence_upload_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_preview.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_repository_test.dart'
    show id, other, FakeSource, assignment;
import 'work_evidence_draft_controller_test.dart' show file, pdf;
import 'work_evidence_preview_test.dart' show PreviewSource, PreviewOpener;

String uid(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
Object? clone(Object? value) => jsonDecode(jsonEncode(value));

/// Local domain fake; it does not validate PostgreSQL, RLS or Storage policies.
class EvidenceServer {
  int round = 0, counter = 1;
  String status = 'not_submitted';
  final attempts = <Map<String, dynamic>>[];
  final reviews = <Map<String, dynamic>>[];
  final history = <Map<String, dynamic>>[];
  final stored = <String>[];
  final evidence = <Map<String, dynamic>>[];
  bool attendanceComplete = true;
  Map<String, dynamic> context(String actor) => {
    'contract_version': 1,
    'assignment_id': id,
    'viewer_role': actor == id ? 'worker' : 'employer',
    'latest_round': round,
    'assignment_status': status == 'verified'
        ? 'completed'
        : 'awaiting_verification',
    'verification_status': status,
    'attendance_complete': attendanceComplete,
    'attempts': actor == id ? attempts : [],
    'review': actor == other
        ? reviews.where((r) => r['submission_round'] == round).firstOrNull
        : null,
    'history': history,
  };
  void event(String action, String actor, String? note) => history.add({
    'verification_id': uid(counter++),
    'assignment_id': id,
    'submission_round': round,
    'performed_by': actor,
    'action': action,
    'note': note,
    'created_at': '2026-11-06T01:${counter.toString().padLeft(2, '0')}:00Z',
  });
  Object? call(String actor, String rpc, Map<String, dynamic> p) {
    if (![id, other].contains(actor)) {
      throw const PostgrestException(message: 'denied', code: '42501');
    }
    if (rpc == 'work_evidence_workflow_context') return clone(context(actor));
    if (rpc == 'prepare_my_work_evidence_submission') {
      if (actor != id || p['p_expected_previous_round'] != round) {
        throw StateError('stale/forbidden');
      }
      final old = attempts
          .where((a) => a['target_round'] == round + 1)
          .firstOrNull;
      if (old != null) {
        if (old['description'] != p['p_description'] ||
            jsonEncode(old['storage_paths']) !=
                jsonEncode(p['p_storage_paths'])) {
          throw StateError('payload conflict');
        }
        return clone(old);
      }
      if (!['not_submitted', 'more_evidence_required'].contains(status)) {
        throw StateError('not eligible');
      }
      final a = <String, dynamic>{
        'request_id': uid(counter++),
        'assignment_id': id,
        'worker_id': id,
        'target_round': round + 1,
        'state': 'prepared',
        'description': p['p_description'],
        'storage_paths': p['p_storage_paths'],
        'submission_id': null,
      };
      attempts.add(a);
      return clone(a);
    }
    if (rpc == 'submit_work_evidence_idempotent') {
      if (actor != id) throw StateError('forbidden');
      final a = attempts.singleWhere(
        (a) => a['request_id'] == p['p_request_id'],
      );
      if (a['state'] == 'committed' || a['state'] == 'blocked') return clone(a);
      if (a['target_round'] != round + 1) throw StateError('stale');
      round++;
      status = 'pending_review';
      a['state'] = 'committed';
      a['submission_id'] = uid(counter++);
      for (final path in a['storage_paths'] as List) {
        expect(stored, contains(path));
        evidence.add({'round': round, 'path': path});
      }
      event(
        round == 1 ? 'evidence_submitted' : 'evidence_resubmitted',
        actor,
        null,
      );
      return clone(a);
    }
    if (rpc == 'prepare_work_evidence_review') {
      if (actor != other || p['p_expected_round'] != round) {
        throw StateError('stale/forbidden');
      }
      final old = reviews
          .where((r) => r['submission_round'] == round)
          .firstOrNull;
      if (old != null) {
        if (old['decision'] != p['p_decision'] ||
            old['reason'] != p['p_reason']) {
          throw StateError('payload conflict');
        }
        return clone(old);
      }
      if (status != 'pending_review') throw StateError('not eligible');
      final r = <String, dynamic>{
        'request_id': uid(counter++),
        'assignment_id': id,
        'actor_id': actor,
        'submission_round': round,
        'decision': p['p_decision'],
        'reason': p['p_reason'],
        'state': 'prepared',
        'history_id': null,
      };
      reviews.add(r);
      return clone(r);
    }
    if (rpc == 'commit_work_evidence_review') {
      if (actor != other) throw StateError('forbidden');
      final r = reviews.singleWhere(
        (r) => r['request_id'] == p['p_request_id'],
      );
      if (r['state'] == 'committed') return clone(r);
      if (r['submission_round'] != round || status != 'pending_review') {
        throw StateError('stale');
      }
      status = r['decision'] == 'verified'
          ? 'verified'
          : 'more_evidence_required';
      event(r['decision'] as String, actor, r['reason'] as String?);
      r['state'] = 'committed';
      r['history_id'] = history.last['verification_id'];
      return clone(r);
    }
    throw StateError('Unexpected RPC $rpc');
  }
}

class WorkflowSource
    implements WorkEvidenceWorkflowSource, EvidenceDraftSession {
  WorkflowSource(this.server, this.userId);
  final EvidenceServer server;
  @override
  String? userId;
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get accountChanges => changes.stream;
  final calls = <String>[];
  Future<Object?> Function(String, Map<String, dynamic>)? intercept;
  @override
  Future<Object?> call(String rpc, Map<String, dynamic> p) async {
    calls.add(rpc);
    return intercept?.call(rpc, p) ?? server.call(userId!, rpc, p);
  }

  void account(String? actor) {
    userId = actor;
    changes.add(actor);
  }
}

class UploadSource implements WorkEvidenceUploadSource {
  UploadSource(this.source);
  final WorkflowSource source;
  Future<void> Function()? intercept;
  int uploads = 0;
  bool eligible = true;
  @override
  String? get userId => source.userId;
  @override
  Stream<String?> get accountChanges => source.accountChanges;
  @override
  Future<bool> canUpload(String assignmentId) async =>
      eligible && source.userId == id && source.server.attendanceComplete;
  @override
  Future<void> upload(String path, Uint8List bytes, String type) async {
    uploads++;
    expect(type, 'application/pdf');
    expect(bytes, isNotEmpty);
    source.server.stored.add(path);
    await intercept?.call();
  }
}

class _LocalHttpOverrides extends HttpOverrides {}

void main() {
  late EvidenceServer server;
  late WorkflowSource worker, employer;
  late WorkEvidenceWorkflowController wc, ec;
  late WorkEvidenceWorkflowLedger ledger;
  setUp(() {
    server = EvidenceServer();
    worker = WorkflowSource(server, id);
    employer = WorkflowSource(server, other);
    ledger = WorkEvidenceWorkflowLedger();
    wc = WorkEvidenceWorkflowController(
      worker,
      assignmentId: id,
      employer: false,
      ledger: ledger,
    );
    ec = WorkEvidenceWorkflowController(
      employer,
      assignmentId: id,
      employer: true,
      ledger: ledger,
    );
  });
  tearDown(() async {
    wc.dispose();
    ec.dispose();
    await worker.changes.close();
    await employer.changes.close();
  });
  Future<
    (WorkEvidenceDraftController, WorkEvidenceUploadRepository, UploadSource)
  >
  draft([int marker = 1]) async {
    final d = WorkEvidenceDraftController(session: worker, assignmentId: id)
      ..setDescription('Work report $marker');
    await d.addFiles([file(pdf(marker))]);
    final s = UploadSource(worker);
    final u = WorkEvidenceUploadRepository(s, assignmentId: id);
    addTearDown(() {
      d.dispose();
      u.dispose();
    });
    return (d, u, s);
  }

  Future<void> submit([int marker = 1]) async {
    await wc.load();
    final d = await draft(marker);
    await wc.submit(d.$1, d.$2);
  }

  test('PDF submission, request reason, changed PDF resubmission and final verification preserve all history', () async {
    await submit();
    expect(server.round, 1);
    expect(server.evidence.length, 1);
    await ec.load();
    await ec.review(
      'more_evidence_requested',
      'Please include the closing tasks.',
    );
    await wc.load();
    expect(wc.snapshot!.canSubmit, isTrue);
    expect(wc.snapshot!.history.last.note, 'Please include the closing tasks.');
    await submit(2);
    expect(server.round, 2);
    expect(server.evidence.length, 2);
    expect(server.evidence.first['path'], isNot(server.evidence.last['path']));
    await ec.load();
    await ec.review('verified', null);
    await wc.load();
    expect(wc.snapshot!.verificationStatus.name, 'verified');
    expect(wc.snapshot!.history.map((h) => h.action), [
      'evidence_submitted',
      'more_evidence_requested',
      'evidence_resubmitted',
      'verified',
    ]);
    expect(wc.snapshot!.history.map((h) => h.round), [1, 1, 2, 2]);
    expect(ec.snapshot!.history.length, 4);
  });
  test('check-out is required before any upload', () async {
    server.attendanceComplete = false;
    await wc.load();
    final d = await draft();
    await wc.submit(d.$1, d.$2);
    expect(d.$3.uploads, 0);
    expect(server.attempts, isEmpty);
  });
  test(
    'double submission and concurrent controllers dispatch one batch',
    () async {
      await wc.load();
      final d = await draft();
      final pending = Completer<void>();
      d.$3.intercept = () => pending.future;
      final otherController = WorkEvidenceWorkflowController(
        worker,
        assignmentId: id,
        employer: false,
        ledger: ledger,
      );
      addTearDown(otherController.dispose);
      await otherController.load();
      final first = wc.submit(d.$1, d.$2);
      await Future<void>.delayed(Duration.zero);
      await wc.submit(d.$1, d.$2);
      await otherController.submit(d.$1, d.$2);
      expect(d.$3.uploads, 1);
      pending.complete();
      await first;
      expect(server.round, 1);
    },
  );
  test(
    'fresh empty server state does not release an uncertain upload gate',
    () async {
      await wc.load();
      final d = await draft();
      d.$3.intercept = () async => throw TimeoutException('lost upload');
      await wc.submit(d.$1, d.$2);
      expect(server.attempts, isEmpty);
      expect(wc.newWriteBlocked, isTrue);
      expect(d.$3.uploads, 1);
      for (var i = 0; i < 3; i++) {
        await wc.load();
        expect(wc.newWriteBlocked, isTrue);
        expect(await wc.submit(d.$1, d.$2), isFalse);
      }
      final reopened = WorkEvidenceWorkflowController(
        worker,
        assignmentId: id,
        employer: false,
        ledger: ledger,
      );
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.newWriteBlocked, isTrue);
      await reopened.submit(d.$1, d.$2);
      expect(d.$3.uploads, 1);
      expect(
        worker.calls,
        isNot(contains('prepare_my_work_evidence_submission')),
      );
      // A replacement upload repository/draft cannot bypass the shared gate.
      final replacement = await draft(2);
      expect(await reopened.submit(replacement.$1, replacement.$2), isFalse);
      expect(replacement.$3.uploads, 0);
      expect(
        worker.calls,
        isNot(contains('prepare_my_work_evidence_submission')),
      );
    },
  );
  test(
    'failed workflow preflight releases gate and allows a safe retry',
    () async {
      await wc.load();
      final d = await draft();
      var reads = 0;
      worker.intercept = (rpc, p) async {
        if (rpc == 'work_evidence_workflow_context' && ++reads == 1) {
          throw StateError('preflight unavailable');
        }
        return server.call(id, rpc, p);
      };
      expect(await wc.submit(d.$1, d.$2), isFalse);
      expect(wc.newWriteBlocked, isFalse);
      expect(d.$3.uploads, 0);
      expect(server.attempts, isEmpty);
      worker.intercept = null;
      expect(await wc.submit(d.$1, d.$2), isTrue);
      expect(d.$3.uploads, 1);
      expect(server.round, 1);
    },
  );
  test('confirmed upload eligibility rejection permits retry without stored objects', () async {
    await wc.load();
    final d = await draft();
    d.$3.eligible = false;
    expect(await wc.submit(d.$1, d.$2), isFalse);
    expect(wc.newWriteBlocked, isFalse);
    expect(d.$3.uploads, 0);
    expect(server.attempts, isEmpty);
    d.$3.eligible = true;
    expect(await wc.submit(d.$1, d.$2), isTrue);
    expect(d.$3.uploads, 1);
    expect(server.round, 1);
  });
  test('lost preparation response recovers and explicitly commits same server request after restart', () async {
    worker.intercept = (rpc, p) async {
      final value = server.call(id, rpc, p);
      if (rpc == 'prepare_my_work_evidence_submission') {
        throw TimeoutException('lost preparation');
      }
      return value;
    };
    await submit();
    expect(server.round, 0);
    expect(wc.snapshot!.pendingAttempt!['state'], 'prepared');
    expect(wc.newWriteBlocked, isTrue);
    worker.intercept = null;
    final restarted = WorkEvidenceWorkflowController(
      worker,
      assignmentId: id,
      employer: false,
      ledger: WorkEvidenceWorkflowLedger(),
    );
    addTearDown(restarted.dispose);
    await restarted.load();
    await restarted.resume();
    expect(server.round, 1);
    expect(server.attempts.length, 1);
    expect(server.history.length, 1);
  });
  test('lost committed submission is read as committed without creating another round', () async {
    worker.intercept = (rpc, p) async {
      final value = server.call(id, rpc, p);
      if (rpc == 'submit_work_evidence_idempotent') {
        throw TimeoutException('lost committed response');
      }
      return value;
    };
    await submit();
    await wc.resume();
    expect(server.round, 1);
    expect(server.history.length, 1);
    expect(wc.snapshot!.attempts.single['state'], 'committed');
  });
  test(
    'lost review preparation cannot be replaced and resumes original reason',
    () async {
      await submit();
      await ec.load();
      employer.intercept = (rpc, p) async {
        final value = server.call(other, rpc, p);
        if (rpc == 'prepare_work_evidence_review') {
          throw TimeoutException('lost preparation');
        }
        return value;
      };
      await ec.review('more_evidence_requested', 'Need a clearer PDF');
      await ec.review('verified', null);
      expect(server.status, 'pending_review');
      employer.intercept = null;
      await ec.resume();
      expect(server.history.last['note'], 'Need a clearer PDF');
      expect(server.status, 'more_evidence_required');
    },
  );
  test(
    'lost committed review and stale review replay never change a later round',
    () async {
      await submit();
      await ec.load();
      employer.intercept = (rpc, p) async {
        final value = server.call(other, rpc, p);
        if (rpc == 'commit_work_evidence_review') {
          throw TimeoutException('lost decision');
        }
        return value;
      };
      await ec.review('more_evidence_requested', 'Updated report needed');
      employer.intercept = null;
      final old = server.reviews.single['request_id'];
      await submit(2);
      server.call(other, 'commit_work_evidence_review', {'p_request_id': old});
      expect(server.status, 'pending_review');
      expect(server.history.length, 3);
    },
  );
  test(
    'changed preparation payload and missing contract fail closed',
    () async {
      await submit();
      final a = server.attempts.single;
      expect(
        () => server.call(id, 'prepare_my_work_evidence_submission', {
          'p_expected_previous_round': 0,
          'p_description': 'Changed',
          'p_storage_paths': a['storage_paths'],
        }),
        throwsStateError,
      );
      worker.intercept = (_, _) async =>
          throw const PostgrestException(message: 'missing', code: 'PGRST202');
      await wc.load();
      final d = await draft(2);
      await wc.submit(d.$1, d.$2);
      expect(d.$3.uploads, 0);
      expect(wc.snapshot, isNull);
    },
  );
  test(
    'account switch during upload prevents reservation or stale success',
    () async {
      await wc.load();
      final d = await draft();
      final pending = Completer<void>();
      d.$3.intercept = () => pending.future;
      final action = wc.submit(d.$1, d.$2);
      await Future<void>.delayed(Duration.zero);
      worker.account(other);
      worker.account(id);
      pending.complete();
      await action;
      expect(wc.snapshot, isNull);
      expect(server.attempts, isEmpty);
    },
  );
  test('account switch during employer preparation prevents commit', () async {
    await submit();
    await ec.load();
    final pending = Completer<Object?>();
    employer.intercept = (rpc, p) => rpc == 'prepare_work_evidence_review'
        ? pending.future
        : Future.value(server.call(other, rpc, p));
    final action = ec.review('verified', null);
    await Future<void>.delayed(Duration.zero);
    employer.account(id);
    pending.complete({'request_id': uid(9)});
    await action;
    expect(ec.snapshot, isNull);
    expect(server.status, 'pending_review');
  });
  test('foreign role, truncated history, invalid and blocked attempts cannot enable writes', () async {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (s) => s['viewer_role'] = 'employer',
      (s) => s['contract_version'] = 0,
      (s) => s['assignment_id'] = other,
      (s) => s['history'] = null,
    ]) {
      worker.intercept = (_, _) async {
        final s = _copy(server.context(id));
        mutate(s);
        return s;
      };
      await wc.load();
      expect(wc.snapshot, isNull);
    }
    worker.intercept = null;
    await wc.load();
    final d = await draft();
    worker.intercept = (rpc, p) async {
      final result = server.call(id, rpc, p);
      if (rpc == 'prepare_my_work_evidence_submission') {
        server.attempts.single['state'] = 'blocked';
        return clone(server.attempts.single);
      }
      return result;
    };
    await wc.submit(d.$1, d.$2);
    expect(server.round, 0);
    await wc.resume();
    expect(server.round, 0);
    expect(wc.snapshot!.pendingAttempt!['state'], 'blocked');
  });
  test(
    'workflow adapter authenticates, uses exact keyed parameters and never retries writes',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var calls = 0;
      server.listen((request) async {
        calls++;
        expect(
          request.uri.path,
          '/rest/v1/rpc/submit_work_evidence_idempotent',
        );
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'p_assignment_id': id,
          'p_request_id': other,
        });
        request.response.statusCode = 503;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'message': 'gateway', 'code': '503'}),
        );
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'fake',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      final source = SupabaseWorkEvidenceWorkflowSource(client);
      await expectLater(
        source.call('submit_work_evidence_idempotent', {}),
        throwsA(isA<AuthException>()),
      );
      expect(calls, 0);
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'fake-token',
          'token_type': 'bearer',
          'user': {'id': id},
        }),
      );
      await expectLater(
        source.call('submit_work_evidence_idempotent', {
          'p_assignment_id': id,
          'p_request_id': other,
        }),
        throwsA(isA<PostgrestException>()),
      );
      expect(calls, 1);
    }, _LocalHttpOverrides()),
  );

  testWidgets(
    'employer opens the original and resubmitted PDF through private signed access',
    (tester) async {
      await submit();
      await ec.load();
      await ec.review('more_evidence_requested', 'Update PDF');
      await submit(2);
      final source = FakeSource()..userId = other;
      source.companyRead = (_) async => [
        assignment(company: true)
          ..['assignment_status'] = 'awaiting_verification'
          ..['verification_status'] = 'pending_review',
      ];
      source.evidenceRead = (_) async => [
        for (var i = 0; i < server.evidence.length; i++)
          {
            'evidence_id': uid(300 + i),
            'submission_round': server.evidence[i]['round'],
            'description': 'PDF report',
            'storage_path': server.evidence[i]['path'],
            'file_name': 'report-$i.pdf',
            'mime_type': 'application/pdf',
            'submitted_by': id,
            'submitted_at': '2026-11-06T01:00:00Z',
          },
      ];
      final attendance = WorkAttendanceRepository(source);
      final viewer = WorkEvidenceRepository.employer(
        attendance,
        assignmentId: id,
        companyId: other,
        loadCompanyAccess: () async =>
            const JobAccess({'company_id': other}, null),
      );
      addTearDown(() async {
        viewer.dispose();
        attendance.dispose();
        await source.changes.close();
      });
      final private = PreviewSource(source);
      private.response = () async => Uri.parse(
        'https://private.invalid/object/sign/work-evidence/${private.signed.last.$1}?token=fake',
      );
      final opener = PreviewOpener();
      for (var i = 0; i < 2; i++) {
        final preview = WorkEvidencePreviewRepository(private);
        addTearDown(preview.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: WorkEvidencePreviewDialog(
              key: ValueKey(i),
              viewer: viewer,
              evidenceId: uid(300 + i),
              repository: preview,
              opener: opener,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Open PDF'), findsOneWidget);
        expect(find.textContaining('token='), findsNothing);
        await tester.tap(find.text('Open PDF'));
        await tester.pumpAndSettle();
        expect(opener.opened.last.path, contains(server.evidence[i]['path']));
        await tester.pumpWidget(const SizedBox());
        preview.dispose();
      }
      expect(opener.opened[0], isNot(opener.opened[1]));
      expect(private.checks, server.evidence.map((e) => e['path']).toList());
    },
  );

  for (final (additional, uncertain) in [
    (false, false),
    (true, false),
    (false, true),
  ]) {
    testWidgets(
      'confirmed submission closes draft without discard warning (additional=$additional, uncertain=$uncertain)',
      (tester) async {
        if (additional) {
          await submit();
          await ec.load();
          await ec.review('more_evidence_requested', 'Add closing tasks');
        }
        if (uncertain) {
          worker.intercept = (rpc, p) async {
            final result = server.call(id, rpc, p);
            if (rpc == 'submit_work_evidence_idempotent') {
              throw TimeoutException('lost response');
            }
            return result;
          };
        }
        final attendanceSource = FakeSource();
        final attendance = WorkAttendanceRepository(attendanceSource);
        final viewer = WorkEvidenceRepository.worker(
          attendance,
          assignmentId: id,
        );
        addTearDown(() async {
          viewer.dispose();
          attendance.dispose();
          await attendanceSource.changes.close();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: WorkEvidenceWorkflowPanel(
                  viewer: viewer,
                  source: worker,
                  ledger: WorkEvidenceWorkflowLedger(),
                  pickFiles: () async => [file(pdf(7))],
                  createUploads: (_) => WorkEvidenceUploadRepository(
                    UploadSource(worker),
                    assignmentId: id,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(
            additional ? 'Resubmit work evidence' : 'Submit work evidence',
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('evidence-draft-description')),
          'Completed the closing tasks.',
        );
        await tester.ensureVisible(find.text('Choose evidence files'));
        await tester.tap(find.text('Choose evidence files'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Submit Evidence'));
        await tester.tap(find.text('Submit Evidence'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
        await tester.pumpAndSettle();
        expect(server.round, additional ? 2 : 1);
        expect(find.byType(Dialog), uncertain ? findsOneWidget : findsNothing);
        expect(find.text('Your unsaved input will be lost.'), findsNothing);
        expect(find.textContaining('Discard'), findsNothing);
        expect(
          find.text(
            additional
                ? 'Additional evidence submitted successfully'
                : 'Evidence submitted successfully',
          ),
          uncertain ? findsNothing : findsOneWidget,
        );
        if (uncertain) {
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Submit Evidence'),
                )
                .onPressed,
            isNull,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [320.0, 1200.0]) {
    testWidgets(
      'employer review at $width validates reason and records a confirmed decision',
      (tester) async {
        await submit();
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final source = FakeSource()..userId = other;
        final attendance = WorkAttendanceRepository(source);
        final viewer = WorkEvidenceRepository.employer(
          attendance,
          assignmentId: id,
          companyId: other,
        );
        addTearDown(() async {
          viewer.dispose();
          attendance.dispose();
          await source.changes.close();
        });
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: WorkEvidenceWorkflowPanel(
                  viewer: viewer,
                  source: employer,
                  ledger: WorkEvidenceWorkflowLedger(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review submitted evidence'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Request more evidence'),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Enter a reason of 1–1,000 characters.'),
          findsOneWidget,
        );
        await tester.enterText(
          find.byType(TextField),
          'Please add the closing PDF page.',
        );
        await tester.ensureVisible(
          find.widgetWithText(OutlinedButton, 'Request more evidence'),
        );
        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Request more evidence'),
        );
        await tester.pumpAndSettle();
        expect(server.status, 'pending_review');
        await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
        await tester.pumpAndSettle();
        expect(server.status, 'more_evidence_required');
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          find.text('More evidence requested successfully'),
          findsOneWidget,
        );
        expect(server.history.last['note'], 'Please add the closing PDF page.');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final uncertain in [false, true]) {
    testWidgets(
      'verification closes only after a confirmed response (uncertain=$uncertain)',
      (tester) async {
        await submit();
        if (uncertain) {
          employer.intercept = (rpc, p) async {
            final result = server.call(other, rpc, p);
            if (rpc == 'commit_work_evidence_review') {
              throw TimeoutException('lost response');
            }
            return result;
          };
        }
        final attendanceSource = FakeSource()..userId = other;
        final attendance = WorkAttendanceRepository(attendanceSource);
        final viewer = WorkEvidenceRepository.employer(
          attendance,
          assignmentId: id,
          companyId: other,
        );
        addTearDown(() async {
          viewer.dispose();
          attendance.dispose();
          await attendanceSource.changes.close();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: WorkEvidenceWorkflowPanel(
                  viewer: viewer,
                  source: employer,
                  ledger: WorkEvidenceWorkflowLedger(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review submitted evidence'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Verify work'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
        await tester.pumpAndSettle();
        expect(server.status, 'verified');
        expect(
          find.byType(AlertDialog),
          uncertain ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Work verified successfully!'),
          uncertain ? findsNothing : findsOneWidget,
        );
        expect(find.text('Your unsaved input will be lost.'), findsNothing);
        if (uncertain) {
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Verify work'),
                )
                .onPressed,
            isNull,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'account switching hides the employer reason even inside confirmation',
    (tester) async {
      await submit();
      final attendanceSource = FakeSource()..userId = other;
      final attendance = WorkAttendanceRepository(attendanceSource);
      final viewer = WorkEvidenceRepository.employer(
        attendance,
        assignmentId: id,
        companyId: other,
      );
      addTearDown(() async {
        viewer.dispose();
        attendance.dispose();
        await attendanceSource.changes.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WorkEvidenceWorkflowPanel(
                viewer: viewer,
                source: employer,
                ledger: WorkEvidenceWorkflowLedger(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review submitted evidence'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Private employer reason');
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Request more evidence'),
      );
      await tester.pumpAndSettle();
      employer.account(id);
      employer.account(other);
      await tester.pumpAndSettle();
      expect(find.text('Private employer reason'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
            .onPressed,
        isNull,
      );
      expect(server.status, 'pending_review');
    },
  );

  testWidgets(
    'worker sees request reason/history and can open guarded PDF resubmission form',
    (tester) async {
      await submit();
      await ec.load();
      await ec.review('more_evidence_requested', 'Add closing tasks');
      final attendanceSource = FakeSource();
      attendanceSource.workerRead = () async => [
        assignment()
          ..['assignment_status'] = 'awaiting_verification'
          ..['verification_status'] = 'more_evidence_required',
      ];
      final attendance = WorkAttendanceRepository(attendanceSource);
      final viewer = WorkEvidenceRepository.worker(
        attendance,
        assignmentId: id,
      );
      addTearDown(() async {
        viewer.dispose();
        attendance.dispose();
        await attendanceSource.changes.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WorkEvidenceWorkflowPanel(
                viewer: viewer,
                source: worker,
                createUploads: (d) => WorkEvidenceUploadRepository(
                  UploadSource(worker),
                  assignmentId: id,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add closing tasks'), findsOneWidget);
      await tester.tap(find.text('Resubmit work evidence'));
      await tester.pumpAndSettle();
      expect(find.text('Submit work evidence'), findsOneWidget);
      expect(find.text('Choose evidence files'), findsOneWidget);
      expect(find.text('Submission is not enabled yet.'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('evidence-draft-description')),
        'Unsaved report',
      );
      await tester.ensureVisible(find.text('Close draft'));
      await tester.tap(find.text('Close draft'));
      await tester.pumpAndSettle();
      expect(find.text('Your unsaved input will be lost.'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved report'), findsOneWidget);
    },
  );
}

Map<String, dynamic> _copy(Object? value) =>
    Map<String, dynamic>.from(clone(value) as Map);
