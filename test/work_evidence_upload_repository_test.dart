import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_evidence_draft_controller.dart';
import 'package:jobmate/features/work_attendance/work_evidence_upload_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_evidence_draft_controller_test.dart'
    show FakeDraftSession, assignmentA, assignmentB, pdf, png, webp, jpeg, file;

class FakeUploadSource implements WorkEvidenceUploadSource {
  @override
  String? userId = 'worker-a';
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get accountChanges => changes.stream;
  final eligibility = <String>[];
  final uploads = <(String, Uint8List, String)>[];
  Future<bool> Function() onEligibility = () async => true;
  Future<void> Function(String, Uint8List, String) onUpload = (
    _,
    _,
    _,
  ) async {};
  void account(String? actor) {
    userId = actor;
    changes.add(actor);
  }

  @override
  Future<bool> canUpload(String assignment) {
    eligibility.add(assignment);
    return onEligibility();
  }

  @override
  Future<void> upload(String path, Uint8List bytes, String mime) {
    uploads.add((path, Uint8List.fromList(bytes), mime));
    return onUpload(path, bytes, mime);
  }
}

/// Only used to verify defensive checks against malformed external inputs.
class InvalidDraftFile extends Fake implements EvidenceDraftFile {
  InvalidDraftFile(this.data, this.mimeType);
  final Uint8List data;
  @override
  final String mimeType;
  @override
  Uint8List get bytes => data;
}

/// Selects/reorders the exact instances without weakening production validation.
class DraftSelectionView extends Fake implements WorkEvidenceDraftController {
  DraftSelectionView(this.session, this.assignmentId, this.files);
  @override
  final EvidenceDraftSession session;
  @override
  final String? assignmentId;
  @override
  final List<EvidenceDraftFile> files;
  bool selecting = false;
  @override
  bool get busy => selecting;
}

void main() {
  group('upload repository with fakes', () {
    late FakeUploadSource source;
    late FakeDraftSession session;
    late WorkEvidenceDraftController draft;
    late WorkEvidenceUploadRepository repo;
    setUp(() async {
      source = FakeUploadSource();
      session = FakeDraftSession();
      draft = WorkEvidenceDraftController(
        session: session,
        assignmentId: assignmentA,
      );
      await draft.addFiles([
        file(pdf(), name: 'private-report.pdf'),
        file(png(), name: 'private-photo.png'),
        file(webp(), name: 'private-photo.webp'),
      ]);
      repo = WorkEvidenceUploadRepository(source, assignmentId: assignmentA);
    });
    tearDown(() async {
      repo.dispose();
      draft.dispose();
      await source.changes.close();
      await session.changes.close();
    });

    test(
      'eligibility false blocks all uploads and creates no successful paths',
      () async {
        source.onEligibility = () async => false;
        final result = await repo.upload(draft.files);
        expect(source.eligibility, [assignmentA]);
        expect(source.uploads, isEmpty);
        expect(result.error, WorkEvidenceUploadError.notEligible);
        expect(result.uploadedPaths, isEmpty);
        expect(result.complete, isFalse);
        expect(result.objectsMayExist, isFalse);
      },
    );

    test('unique UUID object names, correct content types and deterministic ordered paths', () async {
      final files = draft.files;
      final result = await repo.upload(files);
      expect(result.complete, isTrue);
      expect(repo.isCurrent(result), isTrue);
      expect(result.uploadedPaths, source.uploads.map((u) => u.$1).toList());
      expect(result.uploadedPaths.toSet(), hasLength(3));
      expect(result.pendingFileIndexes, isEmpty);
      expect(source.uploads.map((u) => u.$3), [
        'application/pdf',
        'image/png',
        'image/webp',
      ]);
      for (final path in result.uploadedPaths) {
        expect(
          path,
          matches(
            '^$assignmentA/'
            r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(pdf|png|webp)$',
          ),
        );
        expect(path, isNot(contains('private')));
      }
      expect(source.uploads[0].$2, pdf());
      expect(source.uploads[1].$2, png());
      expect(() => result.uploadedPaths.clear(), throwsUnsupportedError);
      expect(() => repo.uploadedPaths.clear(), throwsUnsupportedError);
    });

    test('completed retry rechecks eligibility and never uploads confirmed files again', () async {
      final files = draft.files;
      final first = await repo.upload(files);
      final again = await repo.upload(files);
      expect(again.uploadedPaths, first.uploadedPaths);
      expect(source.uploads, hasLength(3));
      expect(source.eligibility, [assignmentA, assignmentA]);
      expect(again.complete, isTrue);
    });

    test('partial failure keeps paths, stops subsequent uploads and retries original pending names', () async {
      var calls = 0;
      source.onUpload = (_, _, _) async {
        if (++calls == 2) {
          throw const StorageException(
            '/private/path/token',
            statusCode: '500',
          );
        }
      };
      final files = draft.files;
      final partial = await repo.upload(files);
      expect(partial.complete, isFalse);
      expect(partial.uploadedPaths, [source.uploads.first.$1]);
      expect(partial.pendingFileIndexes, [1, 2]);
      expect(source.uploads, hasLength(2));
      expect(partial.message, isNot(contains('/private/path/token')));
      final failedPath = source.uploads[1].$1;
      source.onUpload = (_, _, _) async {};
      final complete = await repo.upload(files);
      expect(complete.complete, isTrue);
      expect(source.uploads, hasLength(4));
      expect(source.uploads[2].$1, failedPath);
      expect(complete.uploadedPaths, [
        source.uploads[0].$1,
        failedPath,
        source.uploads[3].$1,
      ]);
      expect(
        source.uploads.where((u) => u.$1 == complete.uploadedPaths.first),
        hasLength(1),
      );
    });

    test(
      'retry must pass fresh eligibility even after partial success',
      () async {
        var calls = 0;
        source.onUpload = (_, _, _) async {
          if (++calls == 2) throw Exception('network');
        };
        final partial = await repo.upload(draft.files);
        source.onEligibility = () async => false;
        final result = await repo.upload(draft.files);
        expect(result.error, WorkEvidenceUploadError.notEligible);
        expect(result.uploadedPaths, partial.uploadedPaths);
        expect(source.uploads, hasLength(2));
      },
    );

    test(
      '409 conflict is unconfirmed, never overwritten or treated as success',
      () async {
        source.onUpload = (_, _, _) async =>
            throw const StorageException('Duplicate', statusCode: '409');
        final first = await repo.upload(draft.files);
        final retry = await repo.upload(draft.files);
        expect(retry.error, WorkEvidenceUploadError.conflict);
        expect(first.complete, isFalse);
        expect(retry.complete, isFalse);
        expect(retry.uploadedPaths, isEmpty);
        expect(source.uploads[0].$1, source.uploads[1].$1);
        expect(retry.objectsMayExist, isTrue);
        expect(retry.message, contains('Reconciliation'));
      },
    );

    test('reordered, removed and replacement files cannot mix with a previous batch', () async {
      var calls = 0;
      source.onUpload = (_, _, _) async {
        if (++calls == 2) throw Exception('offline');
      };
      final files = draft.files;
      await repo.upload(files);
      final count = source.uploads.length;
      for (final changed in [files.reversed.toList(), files.sublist(1)]) {
        expect(
          (await repo.upload(changed)).error,
          WorkEvidenceUploadError.selectionChanged,
        );
      }
      final otherDraft = WorkEvidenceDraftController(
        session: session,
        assignmentId: assignmentA,
      );
      await otherDraft.addFiles([
        file(pdf()),
        file(png(), name: 'image.png'),
        file(webp(), name: 'image.webp'),
      ]);
      expect(otherDraft.files.first.id, files.first.id);
      expect(
        (await repo.upload(otherDraft.files)).error,
        WorkEvidenceUploadError.selectionChanged,
      );
      otherDraft.dispose();
      expect(source.uploads, hasLength(count));
    });

    test(
      'defensive MIME, empty, size and count checks happen before eligibility',
      () async {
        for (final files in <List<EvidenceDraftFile>>[
          [],
          List.filled(6, draft.files.first),
          [draft.files.first, draft.files.first],
          [InvalidDraftFile(Uint8List(0), 'application/pdf')],
          [InvalidDraftFile(pdf(), 'application/octet-stream')],
          [
            InvalidDraftFile(
              Uint8List(WorkEvidenceDraftController.maxFileBytes + 1),
              'image/png',
            ),
          ],
        ]) {
          final result = await repo.upload(files);
          expect(result.error, WorkEvidenceUploadError.invalidFiles);
        }
        expect(source.eligibility, isEmpty);
        expect(source.uploads, isEmpty);
      },
    );

    test('cleared validated files cannot upload and JPEG maps to permitted jpg extension', () async {
      final released = draft.files;
      draft.clear();
      expect(
        (await repo.upload(released)).error,
        WorkEvidenceUploadError.invalidFiles,
      );
      await draft.addFiles([file(jpeg(), name: 'photo.jpeg')]);
      final result = await repo.upload(draft.files);
      expect(result.complete, isTrue);
      expect(result.uploadedPaths.single, endsWith('.jpg'));
      expect(source.uploads.single.$3, 'image/jpeg');
    });

    test(
      'an in-flight upload owns a stable snapshot until its source completes',
      () async {
        final pending = Completer<void>();
        Uint8List? sent;
        source.onUpload = (_, bytes, _) {
          sent = bytes;
          return pending.future;
        };
        final original = draft.files;
        final operation = repo.upload([original.first]);
        await Future<void>.delayed(Duration.zero);
        draft.clear();
        expect(sent, pdf());
        pending.complete();
        final result = await operation;
        expect(result.complete, isTrue);
        expect(sent!.every((b) => b == 0), isTrue);
      },
    );

    test('duplicate calls while eligibility/upload is pending do not start another batch', () async {
      final gate = Completer<bool>();
      source.onEligibility = () => gate.future;
      final operation = repo.upload(draft.files);
      expect(repo.busy, isTrue);
      expect(
        (await repo.upload(draft.files)).error,
        WorkEvidenceUploadError.busy,
      );
      expect(source.eligibility, hasLength(1));
      gate.complete(true);
      await operation;
      expect(source.uploads, hasLength(3));
      expect(repo.busy, isFalse);
    });

    test('assignment change invalidates pending eligibility and clears retry context', () async {
      final eligibility = Completer<bool>();
      source.onEligibility = () => eligibility.future;
      final old = repo.upload(draft.files);
      repo.changeAssignment(assignmentB);
      eligibility.complete(true);
      final result = await old;
      expect(result.error, WorkEvidenceUploadError.invalidated);
      expect(repo.isCurrent(result), isFalse);
      expect(source.uploads, isEmpty);
      source.onEligibility = () async => true;
      expect(
        (await repo.upload(draft.files)).error,
        WorkEvidenceUploadError.selectionChanged,
      );
      draft.changeAssignment(assignmentB);
      await draft.addFiles([file(pdf())]);
      final current = await repo.upload(draft.files);
      expect(current.complete, isTrue);
      expect(
        current.uploadedPaths.every((p) => p.startsWith('$assignmentB/')),
        isTrue,
      );
    });

    for (final fail in [false, true]) {
      test(
        'account changes discard stale upload completion/error ($fail) without rollback claims',
        () async {
          final pending = Completer<void>();
          source.onUpload = (_, _, _) => pending.future;
          final old = repo.upload(draft.files);
          await Future<void>.delayed(Duration.zero);
          source.account('worker-b');
          expect(repo.uploadedPaths, isEmpty);
          expect(repo.busy, isFalse);
          if (fail) {
            pending.completeError(Exception('old-account private error'));
          } else {
            pending.complete();
          }
          final result = await old;
          expect(result.error, WorkEvidenceUploadError.invalidated);
          expect(result.uploadedPaths, isEmpty);
          expect(result.objectsMayExist, isTrue);
          expect(result.message, contains('nothing was rolled back'));
          expect(source.uploads, hasLength(1));
        },
      );
    }

    test(
      'logout and a rapid sign-out/sign-in cannot resurrect old batch paths',
      () async {
        final result = await repo.upload(draft.files);
        source.account(null);
        expect(repo.isCurrent(result), isFalse);
        expect(repo.uploadedPaths, isEmpty);
        final guest = await repo.upload(draft.files);
        expect(guest.error, WorkEvidenceUploadError.authentication);
        source.account('worker-a');
        expect(repo.uploadedPaths, isEmpty);
      },
    );

    test('same assignment preserves confirmed paths; a different assignment cannot reuse them', () async {
      final files = draft.files;
      final original = await repo.upload(files);
      repo.changeAssignment(assignmentA);
      expect(repo.isCurrent(original), isTrue);
      expect((await repo.upload(files)).uploadedPaths, original.uploadedPaths);
      repo.changeAssignment(assignmentB);
      expect(repo.isCurrent(original), isFalse);
      expect(
        (await repo.upload(files)).error,
        WorkEvidenceUploadError.selectionChanged,
      );
      draft.changeAssignment(assignmentB);
      await draft.addFiles([file(pdf())]);
      final next = await repo.upload(draft.files);
      expect(next.complete, isTrue);
      expect(
        next.uploadedPaths.toSet().intersection(original.uploadedPaths.toSet()),
        isEmpty,
      );
      expect(
        next.uploadedPaths.every((p) => p.startsWith('$assignmentB/')),
        isTrue,
      );
    });

    test('account change on final progress notification cannot return a current success', () async {
      repo.addListener(() {
        if (repo.uploadedPaths.length == 3) source.account(null);
      });
      final result = await repo.upload(draft.files);
      expect(result.error, WorkEvidenceUploadError.invalidated);
      expect(result.uploadedPaths, isEmpty);
      expect(repo.uploadedPaths, isEmpty);
    });

    test(
      'a new account cannot retry file instances bound to the previous account',
      () async {
        final previousFiles = draft.files;
        final previous = await repo.upload(previousFiles);
        source.account('worker-b');
        final count = source.uploads.length;
        expect(
          (await repo.upload(previousFiles)).error,
          WorkEvidenceUploadError.selectionChanged,
        );
        expect(source.uploads, hasLength(count));
        session.account('worker-b');
        draft.changeAssignment(assignmentA);
        await draft.addFiles([file(pdf(9))]);
        final current = await repo.upload(draft.files);
        expect(current.complete, isTrue);
        expect(repo.isCurrent(previous), isFalse);
        expect(
          current.uploadedPaths.toSet().intersection(
            previous.uploadedPaths.toSet(),
          ),
          isEmpty,
        );
      },
    );

    test('eligibility authentication/permission errors and malformed responses remain failures', () async {
      for (final (failure, kind) in <(Object, WorkEvidenceUploadError)>[
        (
          const AuthException('expired'),
          WorkEvidenceUploadError.authentication,
        ),
        (
          const PostgrestException(message: 'denied', code: '42501'),
          WorkEvidenceUploadError.permission,
        ),
        (
          const FormatException('wrong boolean'),
          WorkEvidenceUploadError.invalidResponse,
        ),
      ]) {
        source.onEligibility = () async => throw failure;
        final result = await repo.upload(draft.files);
        expect(result.error, kind);
        expect(result.complete, isFalse);
      }
      expect(source.uploads, isEmpty);
    });

    test('confirmed batch validation returns immutable ordered paths with zero side effects', () async {
      final result = await repo.upload(draft.files);
      final calls = source.eligibility.length, writes = source.uploads.length;
      var notifications = 0;
      repo.addListener(() => notifications++);
      source.onEligibility = () async =>
          throw StateError('Validation must not call an RPC');
      source.onUpload = (_, _, _) async =>
          throw StateError('Validation must not upload');
      final receipt = repo.validateConfirmedBatch(
        result: result,
        draft: draft,
      )!;
      expect(receipt.assignmentId, assignmentA);
      expect(receipt.uploadedPaths, result.uploadedPaths);
      expect(receipt.uploadedPaths.toSet(), hasLength(draft.files.length));
      expect(
        receipt.uploadedPaths.every((p) => p.startsWith('$assignmentA/')),
        isTrue,
      );
      expect(() => receipt.uploadedPaths.clear(), throwsUnsupportedError);
      expect(repo.isConfirmedBatchCurrent(receipt, draft: draft), isTrue);
      expect(
        repo.validateConfirmedBatch(result: result, draft: draft),
        isNotNull,
      );
      expect(source.eligibility, hasLength(calls));
      expect(source.uploads, hasLength(writes));
      expect(notifications, 0);
    });

    test('read-only validation rejects reordered added removed and duplicate selected identities', () async {
      final result = await repo.upload(draft.files);
      final files = draft.files;
      final calls = source.eligibility.length, writes = source.uploads.length;
      for (final selection in [
        files.reversed.toList(),
        files.sublist(1),
        [...files, files.first],
        [files.first, files.first, files.last],
        <EvidenceDraftFile>[],
      ]) {
        final view = DraftSelectionView(session, assignmentA, selection);
        expect(
          repo.validateConfirmedBatch(result: result, draft: view),
          isNull,
        );
      }
      expect(source.eligibility, hasLength(calls));
      expect(source.uploads, hasLength(writes));
    });

    test('same filenames MIME sizes and local IDs in a new draft cannot prove identity', () async {
      final result = await repo.upload(draft.files);
      final receipt = repo.validateConfirmedBatch(
        result: result,
        draft: draft,
      )!;
      final replacement = WorkEvidenceDraftController(
        session: session,
        assignmentId: assignmentA,
      );
      await replacement.addFiles([
        file(pdf(), name: 'private-report.pdf'),
        file(png(), name: 'private-photo.png'),
        file(webp(), name: 'private-photo.webp'),
      ]);
      expect(replacement.files.first.id, draft.files.first.id);
      expect(replacement.files.first.sizeBytes, draft.files.first.sizeBytes);
      expect(
        repo.validateConfirmedBatch(result: result, draft: replacement),
        isNull,
      );
      expect(
        repo.isConfirmedBatchCurrent(receipt, draft: replacement),
        isFalse,
      );
      replacement.dispose();
    });

    test('removing/replacing or clearing files invalidates issued receipt without network calls', () async {
      final result = await repo.upload(draft.files);
      final receipt = repo.validateConfirmedBatch(
        result: result,
        draft: draft,
      )!;
      final calls = source.eligibility.length, writes = source.uploads.length;
      draft.removeFile(draft.files.last.id);
      await draft.addFiles([file(webp(), name: 'private-photo.webp')]);
      expect(repo.validateConfirmedBatch(result: result, draft: draft), isNull);
      expect(repo.isConfirmedBatchCurrent(receipt, draft: draft), isFalse);
      draft.clear();
      expect(repo.validateConfirmedBatch(result: result, draft: draft), isNull);
      expect(source.eligibility, hasLength(calls));
      expect(source.uploads, hasLength(writes));
    });

    test(
      'incomplete and conflicting batches never produce a confirmed receipt',
      () async {
        final pending = Completer<void>();
        source.onUpload = (_, _, _) => pending.future;
        final operation = repo.upload(draft.files);
        await Future<void>.delayed(Duration.zero);
        final busyResult = await repo.upload(draft.files);
        expect(
          repo.validateConfirmedBatch(result: busyResult, draft: draft),
          isNull,
        );
        pending.completeError(
          const StorageException('Conflict', statusCode: '409'),
        );
        final conflict = await operation;
        final calls = source.eligibility.length, writes = source.uploads.length;
        expect(conflict.error, WorkEvidenceUploadError.conflict);
        expect(
          repo.validateConfirmedBatch(result: conflict, draft: draft),
          isNull,
        );
        expect(source.eligibility, hasLength(calls));
        expect(source.uploads, hasLength(writes));
      },
    );

    test('partial successes require a fully confirmed new attempt before issuing receipt', () async {
      var count = 0;
      source.onUpload = (_, _, _) async {
        if (++count == 2) throw Exception('Unconfirmed request');
      };
      final partial = await repo.upload(draft.files);
      expect(partial.uploadedPaths, hasLength(1));
      final calls = source.eligibility.length, writes = source.uploads.length;
      expect(
        repo.validateConfirmedBatch(result: partial, draft: draft),
        isNull,
      );
      expect(source.eligibility, hasLength(calls));
      expect(source.uploads, hasLength(writes));
      source.onUpload = (_, _, _) async {};
      final complete = await repo.upload(draft.files);
      expect(
        repo.validateConfirmedBatch(result: complete, draft: draft),
        isNotNull,
      );
      expect(
        repo.validateConfirmedBatch(result: partial, draft: draft),
        isNull,
      );
      expect(
        source.uploads.where((u) => u.$1 == partial.uploadedPaths.first),
        hasLength(1),
      );
    });

    test('failed eligibility invalidates an earlier success despite retained paths', () async {
      final old = await repo.upload(draft.files);
      final receipt = repo.validateConfirmedBatch(result: old, draft: draft)!;
      source.onEligibility = () async => false;
      final denied = await repo.upload(draft.files);
      expect(
        repo.isCurrent(old),
        isTrue,
      ); // Existing context-only API is unchanged.
      expect(repo.uploadedPaths, old.uploadedPaths);
      expect(repo.validateConfirmedBatch(result: old, draft: draft), isNull);
      expect(repo.validateConfirmedBatch(result: denied, draft: draft), isNull);
      expect(repo.isConfirmedBatchCurrent(receipt, draft: draft), isFalse);
      source.onEligibility = () async => true;
      final current = await repo.upload(draft.files);
      expect(
        repo.validateConfirmedBatch(result: current, draft: draft),
        isNotNull,
      );
      expect(repo.validateConfirmedBatch(result: old, draft: draft), isNull);
    });

    test(
      'new completed attempts invalidate old receipts despite identical paths',
      () async {
        final first = await repo.upload(draft.files);
        final receipt = repo.validateConfirmedBatch(
          result: first,
          draft: draft,
        )!;
        final second = await repo.upload(draft.files);
        expect(second.uploadedPaths, first.uploadedPaths);
        expect(
          repo.validateConfirmedBatch(result: first, draft: draft),
          isNull,
        );
        expect(repo.isConfirmedBatchCurrent(receipt, draft: draft), isFalse);
        expect(
          repo.validateConfirmedBatch(result: second, draft: draft),
          isNotNull,
        );
        expect(source.uploads, hasLength(3));
      },
    );

    test('active retries and pending draft selections block validation without side effects', () async {
      final result = await repo.upload(draft.files);
      final receipt = repo.validateConfirmedBatch(
        result: result,
        draft: draft,
      )!;
      final gate = Completer<bool>();
      source.onEligibility = () => gate.future;
      final retry = repo.upload(draft.files);
      final calls = source.eligibility.length;
      expect(repo.validateConfirmedBatch(result: result, draft: draft), isNull);
      expect(repo.isConfirmedBatchCurrent(receipt, draft: draft), isFalse);
      expect(source.eligibility, hasLength(calls));
      gate.complete(true);
      final latest = await retry;
      final view = DraftSelectionView(session, assignmentA, draft.files);
      final confirmed = repo.validateConfirmedBatch(
        result: latest,
        draft: view,
      )!;
      view.selecting = true;
      expect(repo.validateConfirmedBatch(result: latest, draft: view), isNull);
      expect(repo.isConfirmedBatchCurrent(confirmed, draft: view), isFalse);
      view.selecting = false;
      expect(repo.isConfirmedBatchCurrent(confirmed, draft: view), isTrue);
      expect(source.uploads, hasLength(3));
    });

    test('account/assignment changes invalidate receipts and stale generations without RPCs', () async {
      final result = await repo.upload(draft.files);
      final receipt = repo.validateConfirmedBatch(
        result: result,
        draft: draft,
      )!;
      final calls = source.eligibility.length, writes = source.uploads.length;
      source.userId = 'worker-b'; // No event delivered yet.
      expect(repo.validateConfirmedBatch(result: result, draft: draft), isNull);
      expect(repo.isConfirmedBatchCurrent(receipt, draft: draft), isFalse);
      source.account('worker-b');
      source.account('worker-a');
      expect(repo.validateConfirmedBatch(result: result, draft: draft), isNull);
      repo.changeAssignment(assignmentB);
      expect(repo.isConfirmedBatchCurrent(receipt, draft: draft), isFalse);
      repo.changeAssignment(assignmentA);
      expect(repo.validateConfirmedBatch(result: result, draft: draft), isNull);
      expect(source.eligibility, hasLength(calls));
      expect(source.uploads, hasLength(writes));
    });

    test('foreign repositories or mismatched draft account/assignment cannot issue receipts', () async {
      final result = await repo.upload(draft.files);
      final otherRepo = WorkEvidenceUploadRepository(
        source,
        assignmentId: assignmentA,
      );
      expect(
        otherRepo.validateConfirmedBatch(result: result, draft: draft),
        isNull,
      );
      final wrongAssignment = DraftSelectionView(
        session,
        assignmentB,
        draft.files,
      );
      expect(
        repo.validateConfirmedBatch(result: result, draft: wrongAssignment),
        isNull,
      );
      final otherSession = FakeDraftSession()..userId = 'worker-b';
      final wrongAccount = DraftSelectionView(
        otherSession,
        assignmentA,
        draft.files,
      );
      expect(
        repo.validateConfirmedBatch(result: result, draft: wrongAccount),
        isNull,
      );
      otherRepo.dispose();
      await otherSession.changes.close();
    });

    test(
      'disposed drafts/repositories cannot validate existing receipts',
      () async {
        final result = await repo.upload(draft.files);
        final receipt = repo.validateConfirmedBatch(
          result: result,
          draft: draft,
        )!;
        draft.dispose();
        expect(
          repo.validateConfirmedBatch(result: result, draft: draft),
          isNull,
        );
        expect(repo.isConfirmedBatchCurrent(receipt, draft: draft), isFalse);
        repo.dispose();
        expect(
          repo.validateConfirmedBatch(result: result, draft: draft),
          isNull,
        );
        draft = WorkEvidenceDraftController(
          session: session,
          assignmentId: assignmentA,
        );
        repo = WorkEvidenceUploadRepository(source, assignmentId: assignmentA);
      },
    );

    test(
      'exact 10 MiB validated draft is accepted by the upload service',
      () async {
        draft.clear();
        final bytes = Uint8List(WorkEvidenceDraftController.maxFileBytes);
        bytes.setRange(0, 5, ascii.encode('%PDF-'));
        await draft.addFiles([file(bytes)]);
        final result = await repo.upload(draft.files);
        expect(result.complete, isTrue);
        expect(
          source.uploads.single.$2.length,
          WorkEvidenceDraftController.maxFileBytes,
        );
      },
    );

    test('assignment change during upload invalidates completion without claiming rollback', () async {
      final pending = Completer<void>();
      source.onUpload = (_, _, _) => pending.future;
      final old = repo.upload(draft.files);
      await Future<void>.delayed(Duration.zero);
      repo.changeAssignment(assignmentB);
      pending.complete();
      final result = await old;
      expect(result.error, WorkEvidenceUploadError.invalidated);
      expect(result.uploadedPaths, isEmpty);
      expect(result.objectsMayExist, isTrue);
      expect(repo.uploadedPaths, isEmpty);
      expect(source.uploads, hasLength(1));
    });

    test(
      'disposal invalidates an in-flight request and cancels account listener',
      () async {
        final pending = Completer<void>();
        source.onUpload = (_, _, _) => pending.future;
        final old = repo.upload(draft.files);
        await Future<void>.delayed(Duration.zero);
        repo.dispose();
        expect(source.changes.hasListener, isFalse);
        pending.complete();
        final result = await old;
        expect(result.error, WorkEvidenceUploadError.invalidated);
        expect(result.uploadedPaths, isEmpty);
        // Replace disposed fixture for tearDown.
        repo = WorkEvidenceUploadRepository(source, assignmentId: assignmentB);
      },
    );
  });

  test('Supabase adapter uses exact eligibility RPC and private append-only upload (loopback mock only)', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <(String, String, Uint8List, String?)>[];
    Object eligible = true;
    var wrongKey = false;
    server.listen((request) async {
      final body = await request.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      requests.add((
        request.method,
        request.uri.path,
        Uint8List.fromList(body),
        request.headers.value('x-upsert'),
      ));
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.startsWith('/rest/v1/rpc/')) {
        request.response.write(jsonEncode(eligible));
      } else {
        request.response.write(
          jsonEncode({
            'Key': wrongKey
                ? 'wrong-object'
                : request.uri.path.substring('/storage/v1/object/'.length),
          }),
        );
      }
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
    final source = SupabaseWorkEvidenceUploadSource(client);
    await expectLater(
      source.canUpload(assignmentA),
      throwsA(isA<AuthException>()),
    );
    expect(requests, isEmpty);
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'test-token',
        'token_type': 'bearer',
        'user': {'id': 'worker-a'},
      }),
    );
    expect(await source.canUpload(assignmentA), isTrue);
    expect(requests.last.$1, 'POST');
    expect(requests.last.$2, '/rest/v1/rpc/can_upload_work_evidence');
    expect(jsonDecode(utf8.decode(requests.last.$3)), {
      'p_assignment_id': assignmentA,
    });
    eligible = false;
    expect(await source.canUpload(assignmentA), isFalse);
    eligible = 'true';
    await expectLater(source.canUpload(assignmentA), throwsFormatException);
    final path = '$assignmentA/12345678-1234-4234-8234-123456789abc.pdf';
    await source.upload(path, pdf(), 'application/pdf');
    expect(requests.last.$1, 'POST');
    expect(requests.last.$2, '/storage/v1/object/work-evidence/$path');
    expect(requests.last.$4, 'false');
    final body = latin1.decode(requests.last.$3);
    expect(body.toLowerCase(), contains('content-type: application/pdf'));
    expect(body, contains('%PDF-1.7'));
    expect(
      requests.any((r) => ['DELETE', 'PUT', 'GET'].contains(r.$1)),
      isFalse,
    );
    wrongKey = true;
    await expectLater(
      source.upload(path, pdf(), 'application/pdf'),
      throwsFormatException,
    );
    final before = requests.length;
    await expectLater(
      source.upload('$assignmentA/sub/file.pdf', pdf(), 'application/pdf'),
      throwsFormatException,
    );
    await expectLater(
      source.upload(path, Uint8List(0), 'application/pdf'),
      throwsA(isA<Exception>()),
    );
    expect(requests, hasLength(before));
  });
}
