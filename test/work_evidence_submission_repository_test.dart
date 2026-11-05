import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_evidence_draft_controller.dart';
import 'package:jobmate/features/work_attendance/work_evidence_submission_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_upload_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_evidence_draft_controller_test.dart'
    show FakeDraftSession, assignmentA, assignmentB, file, pdf, png;
import 'work_evidence_upload_repository_test.dart' show FakeUploadSource;
import 'work_attendance_repository_test.dart' show assignment;

class FakeSubmissionReads implements WorkEvidenceSubmissionReadSource {
  FakeSubmissionReads(this.source);
  final FakeSubmissionSource source;
  String? accountOverride;
  @override
  String? get userId => accountOverride ?? source.userId;
  @override
  Stream<String?> get accountChanges => source.accountChanges;
  final calls = <String>[];
  late Future<WorkEvidenceReconciliationRead> Function() assignments;
  late Future<WorkEvidenceReconciliationRead> Function(String) evidence;
  @override
  Future<WorkEvidenceReconciliationRead> listMyAssignments() {
    calls.add('assignments');
    return assignments();
  }

  @override
  Future<WorkEvidenceReconciliationRead> listEvidence(String id) {
    calls.add(id);
    return evidence(id);
  }
}

class FakeSubmissionSource implements WorkEvidenceSubmissionSource {
  @override
  String? userId = 'worker-a';
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get accountChanges => changes.stream;
  final calls = <(String, String, List<String>)>[];
  Future<int> Function() response = () async => 3;
  @override
  Future<int> submit(String id, String description, List<String> paths) {
    calls.add((id, description, List.of(paths)));
    return response();
  }

  void account(String? value) {
    userId = value;
    changes.add(value);
  }
}

void main() {
  late FakeDraftSession session;
  late FakeUploadSource storage;
  late FakeSubmissionSource source;
  late WorkEvidenceDraftController draft;
  late WorkEvidenceUploadRepository uploads;
  late WorkEvidenceSubmissionRepository repo;
  late WorkEvidenceSubmissionLedger ledger;
  late WorkEvidenceConfirmedBatch receipt;
  setUp(() async {
    session = FakeDraftSession();
    storage = FakeUploadSource();
    source = FakeSubmissionSource();
    draft = WorkEvidenceDraftController(
      session: session,
      assignmentId: assignmentA,
    );
    draft.setDescription('  Completed the shift.  ');
    await draft.addFiles([file(pdf()), file(png(), name: 'photo.png')]);
    uploads = WorkEvidenceUploadRepository(storage, assignmentId: assignmentA);
    final uploaded = await uploads.upload(draft.files);
    receipt = uploads.validateConfirmedBatch(result: uploaded, draft: draft)!;
    ledger = WorkEvidenceSubmissionLedger();
    repo = WorkEvidenceSubmissionRepository(
      source,
      uploads: uploads,
      ledger: ledger,
    );
  });
  tearDown(() async {
    repo.dispose();
    uploads.dispose();
    draft.dispose();
    await source.changes.close();
    await storage.changes.close();
    await session.changes.close();
  });

  group('read-only reconciliation', () {
    const worker = '33333333-3333-4333-8333-333333333333';
    late FakeSubmissionReads reader;
    late Map<String, dynamic> shift;
    late List<Map<String, dynamic>> evidence;
    WorkEvidenceReconciliationRead read(List<Map<String, dynamic>> rows) =>
        WorkEvidenceReconciliationRead(rows, total: rows.length);
    Map<String, dynamic> evidenceRow(int index, {int round = 3}) => {
      'evidence_id':
          '00000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}',
      'submission_round': round,
      'description': 'Completed the shift.',
      'storage_path': receipt.uploadedPaths[index],
      'file_name': receipt.uploadedPaths[index].split('/').last,
      'mime_type': index == 0 ? 'application/pdf' : 'image/png',
      'submitted_by': worker,
      'submitted_at': '2026-11-05T15:50:00Z',
    };
    Future<WorkEvidenceReconciliationResult> reconcile() =>
        repo.reconcile(assignmentId: assignmentA);
    Future<void> expectLocked([bool confirmed = false]) async {
      expect(
        (await repo.submit(draft: draft, receipt: receipt)).error,
        confirmed
            ? WorkEvidenceSubmissionError.alreadySubmitted
            : WorkEvidenceSubmissionError.reconciliationRequired,
      );
      expect(source.calls, hasLength(1));
      expect(storage.uploads, hasLength(2));
    }

    setUp(() async {
      repo.dispose();
      uploads.dispose();
      draft.dispose();
      source.userId = worker;
      storage.userId = worker;
      session.userId = worker;
      draft = WorkEvidenceDraftController(
        session: session,
        assignmentId: assignmentA,
      );
      draft.setDescription('  Completed the shift.  ');
      await draft.addFiles([file(pdf()), file(png(), name: 'photo.png')]);
      uploads = WorkEvidenceUploadRepository(
        storage,
        assignmentId: assignmentA,
      );
      receipt = uploads.validateConfirmedBatch(
        result: await uploads.upload(draft.files),
        draft: draft,
      )!;
      storage.uploads.removeRange(
        0,
        2,
      ); // Remove the outer fixture's fake upload history.
      shift = assignment()
        ..['assignment_status'] = 'awaiting_verification'
        ..['verification_status'] = 'pending_review'
        ..['check_in_at'] = '2026-11-05T01:00:00Z'
        ..['check_out_at'] = '2026-11-05T09:00:00Z';
      evidence = [evidenceRow(0), evidenceRow(1)];
      reader = FakeSubmissionReads(source);
      reader.assignments = () async => read([shift]);
      reader.evidence = (_) async => read(evidence);
      repo = WorkEvidenceSubmissionRepository(
        source,
        uploads: uploads,
        ledger: ledger,
        reads: reader,
      );
      source.response = () async => throw TimeoutException('unknown');
      expect(
        (await repo.submit(
          draft: draft,
          receipt: receipt,
        )).requiresReconciliation,
        isTrue,
      );
    });
    test('complete match confirms authoritative round, not a retry', () async {
      final result = await reconcile();
      expect(result.status, WorkEvidenceReconciliationStatus.committed);
      expect(result.submissionRound, 3);
      expect(repo.isReconciliationCurrent(result), isTrue);
      expect(reader.calls, ['assignments', assignmentA, 'assignments']);
      await expectLocked(true);
    });
    test(
      'read order is not upload order; unique paths establish the same batch',
      () async {
        evidence = evidence.reversed.toList();
        expect(
          (await reconcile()).status,
          WorkEvidenceReconciliationStatus.committed,
        );
        await expectLocked(true);
      },
    );
    test(
      'later verified status still permits positive reconciliation',
      () async {
        shift['verification_status'] = 'verified';
        shift['assignment_status'] = 'completed';
        shift['verified_at'] = '2026-11-06T01:00:00Z';
        expect(
          (await reconcile()).status,
          WorkEvidenceReconciliationStatus.committed,
        );
        await expectLocked(true);
      },
    );
    test('absent evidence and not_submitted remain uncertain', () async {
      shift['verification_status'] = 'not_submitted';
      evidence = [];
      expect(
        (await reconcile()).status,
        WorkEvidenceReconciliationStatus.uncertain,
      );
      await expectLocked();
    });
    test(
      'even an ineligible assignment with no evidence remains uncertain',
      () async {
        evidence = [];
        expect(
          (await reconcile()).status,
          WorkEvidenceReconciliationStatus.uncertain,
        );
        await expectLocked();
      },
    );
    test('different read-session account fails closed without reads', () async {
      reader.accountOverride = assignmentB;
      expect(
        (await reconcile()).status,
        WorkEvidenceReconciliationStatus.uncertain,
      );
      expect(reader.calls, isEmpty);
      await expectLocked();
    });
    test('duplicate assignment and nonpositive round fail closed', () async {
      reader.assignments = () async => read([shift, shift]);
      expect(
        (await reconcile()).status,
        WorkEvidenceReconciliationStatus.uncertain,
      );
      reader.assignments = () async => read([shift]);
      evidence[0]['submission_round'] = 0;
      expect(
        (await reconcile()).status,
        WorkEvidenceReconciliationStatus.uncertain,
      );
      await expectLocked();
    });
    test(
      'final assignment read failure cannot publish a positive match',
      () async {
        var count = 0;
        reader.assignments = () async {
          if (++count == 2) throw const SocketException('offline');
          return read([shift]);
        };
        expect(
          (await reconcile()).status,
          WorkEvidenceReconciliationStatus.uncertain,
        );
        await expectLocked();
      },
    );
    test('missing assignment never grants evidence access', () async {
      reader.assignments = () async => read([]);
      expect(
        (await reconcile()).status,
        WorkEvidenceReconciliationStatus.uncertain,
      );
      expect(reader.calls, ['assignments']);
      await expectLocked();
    });
    test('another committed batch confirms changed eligibility, never retry permission', () async {
      evidence = [evidenceRow(0)..['storage_path'] = '$assignmentA/other.pdf'];
      expect(
        (await reconcile()).status,
        WorkEvidenceReconciliationStatus.notEligibleOrChanged,
      );
      await expectLocked();
    });
    for (final key in [
      'description',
      'submitted_by',
      'submission_round',
      'storage_path',
    ]) {
      test('conflicting $key cannot confirm the original attempt', () async {
        evidence[0][key] = switch (key) {
          'description' => 'Other work',
          'submitted_by' => assignmentB,
          'submission_round' => 4,
          _ => '$assignmentB/file.pdf',
        };
        expect(
          (await reconcile()).status,
          WorkEvidenceReconciliationStatus.uncertain,
        );
        await expectLocked();
      });
    }
    test('partial matching evidence is uncertain', () async {
      evidence.removeLast();
      expect(
        (await reconcile()).status,
        WorkEvidenceReconciliationStatus.uncertain,
      );
      await expectLocked();
    });
    test(
      'an extra file in the same round makes the payload ambiguous',
      () async {
        evidence.add({
          ...evidenceRow(0),
          'evidence_id': assignmentB,
          'storage_path': '$assignmentA/extra.pdf',
        });
        expect(
          (await reconcile()).status,
          WorkEvidenceReconciliationStatus.uncertain,
        );
        await expectLocked();
      },
    );
    for (final target in ['assignment', 'evidence']) {
      for (final total in <int?>[null, 99]) {
        test('$target incomplete exact count $total cannot confirm', () async {
          if (target == 'assignment') {
            reader.assignments = () async =>
                WorkEvidenceReconciliationRead([shift], total: total);
          } else {
            reader.evidence = (_) async =>
                WorkEvidenceReconciliationRead(evidence, total: total);
          }
          expect(
            (await reconcile()).status,
            WorkEvidenceReconciliationStatus.uncertain,
          );
          await expectLocked();
        });
      }
      test(
        '$target read failure retains the lock and hides backend internals',
        () async {
          if (target == 'assignment') {
            reader.assignments = () async => throw const PostgrestException(
              message: 'secret path',
              code: '42501',
            );
          } else {
            reader.evidence = (_) async =>
                throw const SocketException('secret token');
          }
          final result = await reconcile();
          expect(result.status, WorkEvidenceReconciliationStatus.uncertain);
          expect(result.message, isNot(contains('secret')));
          await expectLocked();
        },
      );
      test('malformed $target fails closed', () async {
        if (target == 'assignment') {
          shift.remove('application_id');
        } else {
          evidence[0].remove('submitted_at');
        }
        expect(
          (await reconcile()).status,
          WorkEvidenceReconciliationStatus.uncertain,
        );
        await expectLocked();
      });
    }
    test('duplicate rows and contradictory status never confirm', () async {
      evidence.add(Map.of(evidence.first));
      expect(
        (await reconcile()).status,
        WorkEvidenceReconciliationStatus.uncertain,
      );
      evidence.removeLast();
      shift['verification_status'] = 'not_submitted';
      expect(
        (await reconcile()).status,
        WorkEvidenceReconciliationStatus.uncertain,
      );
      await expectLocked();
    });
    test(
      'recorded successful round must match the authoritative round',
      () async {
        // First confirm round 3; a later contradictory round cannot replace it.
        await reconcile();
        for (final row in evidence) {
          row['submission_round'] = 4;
        }
        expect(
          (await reconcile()).status,
          WorkEvidenceReconciliationStatus.uncertain,
        );
        await expectLocked(true);
      },
    );
    test('account switch away and back invalidates pending reads', () async {
      final pending = Completer<WorkEvidenceReconciliationRead>();
      reader.evidence = (_) => pending.future;
      final action = reconcile();
      await Future<void>.delayed(Duration.zero);
      source.account(assignmentB);
      source.account(worker);
      pending.complete(read(evidence));
      final result = await action;
      expect(result.status, WorkEvidenceReconciliationStatus.uncertain);
      expect(repo.isReconciliationCurrent(result), isFalse);
      await expectLocked();
    });
    test(
      'other account or assignment cannot reconcile another attempt',
      () async {
        source.account(assignmentB);
        expect(
          (await reconcile()).status,
          WorkEvidenceReconciliationStatus.uncertain,
        );
        source.account(worker);
        expect(
          (await repo.reconcile(assignmentId: assignmentB)).status,
          WorkEvidenceReconciliationStatus.uncertain,
        );
        expect(reader.calls, isEmpty);
        await expectLocked();
      },
    );
    test(
      'fresh final assignment read prevents stale authorization/identity',
      () async {
        var calls = 0;
        reader.assignments = () async => read([
          Map.of(shift)
            ..['company_id'] = ++calls == 1 ? shift['company_id'] : assignmentA,
        ]);
        expect(
          (await reconcile()).status,
          WorkEvidenceReconciliationStatus.uncertain,
        );
        await expectLocked();
      },
    );
    test('recreated repository uses stored trusted payload after local draft cleanup', () async {
      draft.clear();
      repo.dispose();
      repo = WorkEvidenceSubmissionRepository(
        source,
        uploads: uploads,
        ledger: ledger,
        reads: reader,
      );
      expect(
        (await reconcile()).status,
        WorkEvidenceReconciliationStatus.committed,
      );
      await expectLocked(true);
    });
    test(
      'concurrent reconciliation and disposal do not release locks',
      () async {
        final pending = Completer<WorkEvidenceReconciliationRead>();
        reader.evidence = (_) => pending.future;
        final first = reconcile();
        await Future<void>.delayed(Duration.zero);
        expect(
          (await reconcile()).status,
          WorkEvidenceReconciliationStatus.uncertain,
        );
        repo.dispose();
        pending.complete(read(evidence));
        expect(
          (await first).status,
          WorkEvidenceReconciliationStatus.uncertain,
        );
        repo = WorkEvidenceSubmissionRepository(
          source,
          uploads: uploads,
          ledger: ledger,
          reads: reader,
        );
        await expectLocked();
      },
    );
  });

  test('confirmed round, trimmed description, trusted ordered paths and explicit refresh', () async {
    final result = await repo.submit(draft: draft, receipt: receipt);
    expect(result.error, isNull);
    expect(result.submissionRound, 3);
    expect(result.requiresRefresh, isTrue);
    expect(repo.isCurrent(result), isTrue);
    expect(source.calls.single.$1, assignmentA);
    expect(source.calls.single.$2, 'Completed the shift.');
    expect(source.calls.single.$3, receipt.uploadedPaths);
    expect(storage.uploads, hasLength(2));
  });

  for (final description in ['', '   ', List.filled(2001, 'a').join()]) {
    test(
      'invalid description length ${description.length} is local, no RPC or lock',
      () async {
        draft.setDescription(description);
        expect(
          (await repo.submit(draft: draft, receipt: receipt)).error,
          WorkEvidenceSubmissionError.invalidDraft,
        );
        expect(source.calls, isEmpty);
        draft.setDescription('Corrected');
        expect(
          (await repo.submit(draft: draft, receipt: receipt)).submissionRound,
          3,
        );
      },
    );
  }

  test(
    'SQL limit counts Unicode characters rather than UTF-16 code units',
    () async {
      draft.setDescription(List.filled(2000, '😀').join());
      expect((await repo.submit(draft: draft, receipt: receipt)).error, isNull);
    },
  );

  test(
    'description change and change-back during preparation never dispatch',
    () async {
      final pending = repo.submit(draft: draft, receipt: receipt);
      final old = draft.description;
      draft.setDescription('Edited');
      draft.setDescription(old);
      expect((await pending).error, WorkEvidenceSubmissionError.invalidated);
      expect(source.calls, isEmpty);
      expect((await repo.submit(draft: draft, receipt: receipt)).error, isNull);
    },
  );

  test('removed files invalidate trusted receipt without a request', () async {
    draft.removeFile(draft.files.first.id);
    expect(
      (await repo.submit(draft: draft, receipt: receipt)).error,
      WorkEvidenceSubmissionError.invalidDraft,
    );
    expect(source.calls, isEmpty);
  });

  test(
    'file or upload generation changes during preparation prevent dispatch',
    () async {
      final pending = repo.submit(draft: draft, receipt: receipt);
      uploads.changeAssignment(assignmentB);
      uploads.changeAssignment(assignmentA);
      expect((await pending).error, WorkEvidenceSubmissionError.invalidated);
      expect(source.calls, isEmpty);
    },
  );

  test('receipt from a different upload repository is rejected', () async {
    final other = WorkEvidenceUploadRepository(
      storage,
      assignmentId: assignmentA,
    );
    final service = WorkEvidenceSubmissionRepository(
      source,
      uploads: other,
      ledger: ledger,
    );
    expect(
      (await service.submit(draft: draft, receipt: receipt)).error,
      WorkEvidenceSubmissionError.invalidDraft,
    );
    expect(source.calls, isEmpty);
    service.dispose();
    other.dispose();
  });

  test(
    'later failed eligibility attempt invalidates previously complete receipt',
    () async {
      storage.onEligibility = () async => false;
      await uploads.upload(draft.files);
      expect(
        (await repo.submit(draft: draft, receipt: receipt)).error,
        WorkEvidenceSubmissionError.invalidDraft,
      );
      expect(source.calls, isEmpty);
    },
  );

  test(
    'concurrent calls and rebuilt services share an in-flight lock',
    () async {
      final response = Completer<int>();
      source.response = () => response.future;
      final pending = repo.submit(draft: draft, receipt: receipt);
      expect(
        (await repo.submit(draft: draft, receipt: receipt)).error,
        WorkEvidenceSubmissionError.busy,
      );
      await Future<void>.delayed(Duration.zero);
      final other = WorkEvidenceSubmissionRepository(
        source,
        uploads: uploads,
        ledger: ledger,
      );
      expect(
        (await other.submit(draft: draft, receipt: receipt)).error,
        WorkEvidenceSubmissionError.busy,
      );
      response.complete(2);
      expect((await pending).submissionRound, 2);
      expect(source.calls, hasLength(1));
      other.dispose();
    },
  );

  test(
    'confirmed submission blocks new receipt and recreated repository',
    () async {
      await repo.submit(draft: draft, receipt: receipt);
      final next = await uploads.upload(draft.files);
      final renewed = uploads.validateConfirmedBatch(
        result: next,
        draft: draft,
      )!;
      repo.dispose();
      repo = WorkEvidenceSubmissionRepository(
        source,
        uploads: uploads,
        ledger: ledger,
      );
      expect(
        (await repo.submit(draft: draft, receipt: renewed)).error,
        WorkEvidenceSubmissionError.alreadySubmitted,
      );
      expect(source.calls, hasLength(1));
    },
  );

  for (final permission in [true, false]) {
    test(
      'definite server rejection permission=$permission permits explicit corrected retry',
      () async {
        source.response = () async =>
            throw WorkEvidenceSubmissionRejected(permission);
        final result = await repo.submit(draft: draft, receipt: receipt);
        expect(
          result.error,
          permission
              ? WorkEvidenceSubmissionError.permission
              : WorkEvidenceSubmissionError.rejected,
        );
        expect(result.requiresRefresh, isFalse);
        expect(result.message, isNot(contains(assignmentA)));
        source.response = () async => 4;
        expect(
          (await repo.submit(draft: draft, receipt: receipt)).submissionRound,
          4,
        );
        expect(source.calls, hasLength(2));
      },
    );
  }

  for (final error in [
    TimeoutException('private path'),
    const SocketException('private token'),
    const AuthException('session lost'),
    const PostgrestException(message: 'gateway internals', code: '503'),
    const FormatException('lost round'),
  ]) {
    test(
      'ambiguous ${error.runtimeType} locks assignment across rebuilds and renewed receipts',
      () async {
        source.response = () async => throw error;
        final result = await repo.submit(draft: draft, receipt: receipt);
        expect(result.requiresReconciliation, isTrue);
        expect(result.submissionRound, isNull);
        expect(result.message, isNot(contains('private')));
        final next = await uploads.upload(draft.files);
        final renewed = uploads.validateConfirmedBatch(
          result: next,
          draft: draft,
        )!;
        repo.dispose();
        repo = WorkEvidenceSubmissionRepository(
          source,
          uploads: uploads,
          ledger: ledger,
        );
        expect(
          (await repo.submit(
            draft: draft,
            receipt: renewed,
          )).requiresReconciliation,
          isTrue,
        );
        expect(source.calls, hasLength(1));
      },
    );
  }

  test(
    'default ledger survives repository recreation without caller injection',
    () async {
      repo.dispose();
      repo = WorkEvidenceSubmissionRepository(source, uploads: uploads);
      source.response = () async => throw TimeoutException('unknown');
      await repo.submit(draft: draft, receipt: receipt);
      repo.dispose();
      repo = WorkEvidenceSubmissionRepository(source, uploads: uploads);
      expect(
        (await repo.submit(
          draft: draft,
          receipt: receipt,
        )).requiresReconciliation,
        isTrue,
      );
      expect(source.calls, hasLength(1));
    },
  );

  test('logout before dispatch is local and does not claim success', () async {
    final pending = repo.submit(draft: draft, receipt: receipt);
    source.account(null);
    expect((await pending).error, WorkEvidenceSubmissionError.invalidated);
    expect(source.calls, isEmpty);
    expect(
      (await repo.submit(draft: draft, receipt: receipt)).error,
      WorkEvidenceSubmissionError.authentication,
    );
  });

  for (final success in [true, false]) {
    test(
      'account change ignores stale ${success ? 'success' : 'failure'} but preserves original lock',
      () async {
        final response = Completer<int>();
        source.response = () => response.future;
        final pending = repo.submit(draft: draft, receipt: receipt);
        await Future<void>.delayed(Duration.zero);
        source.account('worker-b');
        source.account('worker-a');
        if (success) {
          response.complete(5);
        } else {
          response.completeError(TimeoutException('unknown'));
        }
        final result = await pending;
        expect(result.error, WorkEvidenceSubmissionError.invalidated);
        expect(result.submissionRound, isNull);
        expect(repo.isCurrent(result), isFalse);
        expect(
          (await repo.submit(draft: draft, receipt: receipt)).error,
          success
              ? WorkEvidenceSubmissionError.alreadySubmitted
              : WorkEvidenceSubmissionError.reconciliationRequired,
        );
        expect(source.calls, hasLength(1));
      },
    );
  }

  test('edit during dispatched request hides stale result, retains confirmed outcome', () async {
    final response = Completer<int>();
    source.response = () => response.future;
    final pending = repo.submit(draft: draft, receipt: receipt);
    await Future<void>.delayed(Duration.zero);
    draft.setDescription('Different description');
    response.complete(6);
    expect((await pending).error, WorkEvidenceSubmissionError.invalidated);
    expect(
      (await repo.submit(draft: draft, receipt: receipt)).error,
      WorkEvidenceSubmissionError.alreadySubmitted,
    );
  });

  test('disposal preserves ambiguous remote lock', () async {
    final response = Completer<int>();
    source.response = () => response.future;
    final pending = repo.submit(draft: draft, receipt: receipt);
    await Future<void>.delayed(Duration.zero);
    repo.dispose();
    response.completeError(TimeoutException('unknown'));
    expect((await pending).error, WorkEvidenceSubmissionError.invalidated);
    repo = WorkEvidenceSubmissionRepository(
      source,
      uploads: uploads,
      ledger: ledger,
    );
    expect(
      (await repo.submit(
        draft: draft,
        receipt: receipt,
      )).requiresReconciliation,
      isTrue,
    );
  });

  test(
    'different authenticated account cannot reuse the original receipt',
    () async {
      source.account('worker-b');
      expect(
        (await repo.submit(draft: draft, receipt: receipt)).error,
        WorkEvidenceSubmissionError.invalidDraft,
      );
      expect(source.calls, isEmpty);
    },
  );

  test(
    'assignment changes before dispatch cannot submit the old batch',
    () async {
      final pending = repo.submit(draft: draft, receipt: receipt);
      draft.changeAssignment(assignmentB);
      expect((await pending).error, WorkEvidenceSubmissionError.invalidated);
      expect(source.calls, isEmpty);
    },
  );

  test(
    'two repositories starting together acquire only one dispatch lock',
    () async {
      final response = Completer<int>();
      source.response = () => response.future;
      final other = WorkEvidenceSubmissionRepository(
        source,
        uploads: uploads,
        ledger: ledger,
      );
      final first = repo.submit(draft: draft, receipt: receipt);
      final second = other.submit(draft: draft, receipt: receipt);
      expect((await second).error, WorkEvidenceSubmissionError.busy);
      expect(source.calls, hasLength(1));
      response.complete(8);
      expect((await first).submissionRound, 8);
      other.dispose();
    },
  );

  test(
    'nonpositive returned round is ambiguous and blocks further attempts',
    () async {
      source.response = () async => 0;
      final result = await repo.submit(draft: draft, receipt: receipt);
      expect(result.requiresReconciliation, isTrue);
      expect(result.submissionRound, isNull);
      expect(
        (await repo.submit(
          draft: draft,
          receipt: receipt,
        )).requiresReconciliation,
        isTrue,
      );
      expect(source.calls, hasLength(1));
    },
  );

  test('Supabase reconciliation adapter uses exact read RPCs and counts only (loopback mock)', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <(String, Object?)>[];
    Object payload = [assignment()];
    var includeCount = true;
    server.listen((request) async {
      expect(request.method, 'POST'); // PostgREST read RPCs use HTTP POST.
      expect(request.headers.value('prefer'), contains('count=exact'));
      final body = await utf8.decoder.bind(request).join();
      requests.add((request.uri.path, body.isEmpty ? null : jsonDecode(body)));
      request.response.headers.contentType = ContentType.json;
      if (includeCount) request.response.headers.set('Content-Range', '0-0/1');
      request.response.write(jsonEncode(payload));
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
    final adapter = SupabaseWorkEvidenceSubmissionSource(client);
    await expectLater(
      adapter.listMyAssignments(),
      throwsA(isA<AuthException>()),
    );
    expect(requests, isEmpty);
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'fake-token',
        'token_type': 'bearer',
        'user': {'id': assignmentB},
      }),
    );
    final assignments = await adapter.listMyAssignments();
    expect(assignments.total, 1);
    expect(assignments.completeRows.single['assignment_id'], assignmentA);
    expect(() => assignments.rows.clear(), throwsUnsupportedError);
    expect(
      () => assignments.rows.single['assignment_id'] = assignmentB,
      throwsUnsupportedError,
    );
    final files = await adapter.listEvidence(assignmentA);
    expect(files.total, 1);
    expect(requests.map((r) => r.$1), [
      '/rest/v1/rpc/list_my_work_assignments',
      '/rest/v1/rpc/list_work_evidence',
    ]);
    expect(requests.first.$2, isNull);
    expect(requests.last.$2, {'p_assignment_id': assignmentA});
    payload = ['malformed'];
    await expectLater(adapter.listEvidence(assignmentA), throwsFormatException);
    payload = [];
    includeCount = false;
    // Missing HTTP count metadata fails closed (SDK may throw before decoding).
    try {
      final missing = await adapter.listMyAssignments();
      expect(() => missing.completeRows, throwsFormatException);
    } catch (error) {
      expect(error, isA<TypeError>());
    }
    expect(requests.every((r) => !r.$1.contains('submit')), isTrue);
  });

  test('Supabase adapter exact RPC and parameters; explicit SQL errors only (loopback mock)', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bodies = <Map<String, dynamic>>[];
    Object payload = 7;
    var status = 200;
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/rest/v1/rpc/submit_work_evidence');
      bodies.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(payload));
      await request.response.close();
    });
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });
    final adapter = SupabaseWorkEvidenceSubmissionSource(client);
    expect(
      await adapter.submit(assignmentA, 'Work done', receipt.uploadedPaths),
      7,
    );
    expect(bodies.single, {
      'p_assignment_id': assignmentA,
      'p_description': 'Work done',
      'p_storage_paths': receipt.uploadedPaths,
    });
    for (final code in ['P0001', '42501', '28000', '22023']) {
      status = 400;
      payload = {'code': code, 'message': 'sensitive backend internals'};
      await expectLater(
        adapter.submit(assignmentA, 'Work done', receipt.uploadedPaths),
        throwsA(isA<WorkEvidenceSubmissionRejected>()),
      );
    }
    status = 503;
    payload = {'code': '503', 'message': 'unknown'};
    await expectLater(
      adapter.submit(assignmentA, 'Work done', receipt.uploadedPaths),
      throwsA(isA<PostgrestException>()),
    );
    status = 200;
    payload = '7';
    await expectLater(
      adapter.submit(assignmentA, 'Work done', receipt.uploadedPaths),
      throwsFormatException,
    );
  });
}
