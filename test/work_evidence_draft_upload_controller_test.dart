import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_evidence_draft_controller.dart';
import 'package:jobmate/features/work_attendance/work_evidence_draft_upload_controller.dart';
import 'package:jobmate/features/work_attendance/work_evidence_upload_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_evidence_draft_controller_test.dart'
    show FakeDraftSession, assignmentA, assignmentB, file, pdf, png;

class MemoryUploadSource implements WorkEvidenceUploadSource {
  @override
  String? userId = 'worker-a';
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get accountChanges => changes.stream;
  final eligibility = <String>[];
  final paths = <String>[];
  Future<bool> Function() eligible = () async => true;
  Future<void> Function() send = () async {};

  @override
  Future<bool> canUpload(String assignmentId) {
    eligibility.add(assignmentId);
    return eligible();
  }

  @override
  Future<void> upload(String objectPath, Uint8List bytes, String contentType) {
    paths.add(objectPath);
    return send();
  }

  void account(String? actor) {
    userId = actor;
    changes.add(actor);
  }
}

/// Allows tests to reorder genuine validated object identities without reading
/// files or replacing the production validation contract with fake metadata.
class ReorderableDraft extends WorkEvidenceDraftController {
  ReorderableDraft(EvidenceDraftSession session)
    : super(session: session, assignmentId: assignmentA);
  bool reversed = false;
  @override
  List<EvidenceDraftFile> get files =>
      reversed ? List.unmodifiable(super.files.reversed) : super.files;
  void reorder() {
    reversed = !reversed;
    notifyListeners();
  }
}

void main() {
  late FakeDraftSession session;
  late MemoryUploadSource source;
  late ReorderableDraft draft;
  late WorkEvidenceUploadRepository uploads;
  late WorkEvidenceDraftUploadController coordinator;

  setUp(() async {
    session = FakeDraftSession();
    source = MemoryUploadSource();
    draft = ReorderableDraft(session);
    draft.setDescription('Completed the shift');
    await draft.addFiles([file(pdf()), file(png(), name: 'photo.png')]);
    uploads = WorkEvidenceUploadRepository(source, assignmentId: assignmentA);
    coordinator = WorkEvidenceDraftUploadController(
      draft: draft,
      uploads: uploads,
    );
  });
  tearDown(() async {
    coordinator.dispose();
    uploads.dispose();
    draft.dispose();
    await source.changes.close();
    await session.changes.close();
  });

  test(
    'construction and draft editing never initiate uploads automatically',
    () async {
      expect(coordinator.state.phase, WorkEvidenceDraftUploadPhase.idle);
      draft.setDescription('Changed before start');
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.state.phase, WorkEvidenceDraftUploadPhase.idle);
      expect(source.eligibility, isEmpty);
      expect(source.paths, isEmpty);
    },
  );

  test(
    'existing description validation blocks start and allows correction',
    () async {
      draft.setDescription('  ');
      final blocked = await coordinator.start();
      expect(blocked.phase, WorkEvidenceDraftUploadPhase.invalidDraft);
      expect(blocked.message, draft.descriptionError);
      expect(source.eligibility, isEmpty);
      draft.setDescription('Corrected description');
      expect(
        (await coordinator.start()).phase,
        WorkEvidenceDraftUploadPhase.confirmed,
      );
    },
  );

  test(
    'existing file validation blocks an empty selection with no requests',
    () async {
      for (final selected in draft.files) {
        draft.removeFile(selected.id);
      }
      final blocked = await coordinator.start();
      expect(blocked.phase, WorkEvidenceDraftUploadPhase.invalidDraft);
      expect(blocked.message, draft.filesError);
      expect(source.eligibility, isEmpty);
      expect(source.paths, isEmpty);
    },
  );

  test('pending local file validation blocks start', () async {
    // Even an empty addition has an asynchronous local validation lifecycle.
    final pending = draft.addFiles([]);
    expect(draft.busy, isTrue);
    expect(
      (await coordinator.start()).phase,
      WorkEvidenceDraftUploadPhase.invalidDraft,
    );
    await pending;
    expect(source.eligibility, isEmpty);
  });

  test(
    'explicit start returns immutable ordered paths and a current receipt',
    () async {
      final states = <WorkEvidenceDraftUploadPhase>[];
      coordinator.addListener(() => states.add(coordinator.state.phase));
      final result = await coordinator.start();
      expect(result.phase, WorkEvidenceDraftUploadPhase.confirmed);
      expect(states, contains(WorkEvidenceDraftUploadPhase.uploading));
      expect(result.confirmedPaths, source.paths);
      expect(() => result.confirmedPaths.clear(), throwsUnsupportedError);
      expect(
        uploads.isConfirmedBatchCurrent(result.receipt!, draft: draft),
        isTrue,
      );
      expect(result.objectsMayExist, isTrue);
      await coordinator.start();
      expect(source.eligibility, hasLength(1));
      expect(source.paths, hasLength(2));
    },
  );

  test('duplicate starts during eligibility make only one attempt', () async {
    final eligibility = Completer<bool>();
    source.eligible = () => eligibility.future;
    final pending = coordinator.start();
    expect(
      (await coordinator.start()).phase,
      WorkEvidenceDraftUploadPhase.uploading,
    );
    expect(source.eligibility, [assignmentA]);
    eligibility.complete(true);
    expect((await pending).phase, WorkEvidenceDraftUploadPhase.confirmed);
    expect(source.paths, hasLength(2));
  });

  test(
    'duplicate start during an in-flight file does not upload it again',
    () async {
      final first = Completer<void>();
      source.send = () => first.future;
      final pending = coordinator.start();
      await Future<void>.delayed(Duration.zero);
      expect(
        (await coordinator.start()).phase,
        WorkEvidenceDraftUploadPhase.uploading,
      );
      expect(source.paths, hasLength(1));
      expect(source.eligibility, hasLength(1));
      first.complete();
      expect((await pending).phase, WorkEvidenceDraftUploadPhase.confirmed);
      expect(source.paths, hasLength(2));
    },
  );

  test(
    'account change on confirmed notification cannot expose a stale receipt',
    () async {
      coordinator.addListener(() {
        if (coordinator.state.phase == WorkEvidenceDraftUploadPhase.confirmed) {
          source.account('worker-b');
        }
      });
      final result = await coordinator.start();
      expect(result.phase, WorkEvidenceDraftUploadPhase.invalidated);
      expect(result.receipt, isNull);
      expect(result.confirmedPaths, isEmpty);
      expect(result.objectsMayExist, isTrue);
    },
  );

  test('partial failure retries explicitly, preserving successes and failed object name', () async {
    source.send = () async {
      if (source.paths.length == 2) {
        throw Exception('synthetic connection failure');
      }
    };
    final partial = await coordinator.start();
    expect(partial.phase, WorkEvidenceDraftUploadPhase.partialFailure);
    expect(partial.canRetry, isTrue);
    expect(partial.confirmedPaths, [source.paths.first]);
    expect(partial.receipt, isNull);
    final failedPath = source.paths.last;
    await Future<void>.delayed(Duration.zero);
    expect(source.paths, hasLength(2)); // No automatic retry.
    source.send = () async {};
    final complete = await coordinator.start();
    expect(complete.phase, WorkEvidenceDraftUploadPhase.confirmed);
    expect(complete.confirmedPaths, [source.paths.first, failedPath]);
    expect(source.paths, [source.paths.first, failedPath, failedPath]);
    expect(source.eligibility, hasLength(2));
    expect(partial.confirmedPaths, hasLength(1)); // Snapshot stays immutable.
  });

  test(
    'connection failure without confirmed paths exposes retryable state',
    () async {
      source.eligible = () async => throw Exception('synthetic offline');
      final result = await coordinator.start();
      expect(result.phase, WorkEvidenceDraftUploadPhase.retryable);
      expect(result.canRetry, isTrue);
      expect(source.paths, isEmpty);
      source.eligible = () async => true;
      expect(
        (await coordinator.start()).phase,
        WorkEvidenceDraftUploadPhase.confirmed,
      );
    },
  );

  test('eligibility denial is blocked and never silently retried', () async {
    source.eligible = () async => false;
    final result = await coordinator.start();
    expect(result.phase, WorkEvidenceDraftUploadPhase.blocked);
    expect(result.error, WorkEvidenceUploadError.notEligible);
    expect(result.canRetry, isFalse);
    await coordinator.start();
    expect(source.eligibility, hasLength(1));
    expect(source.paths, isEmpty);
  });

  test(
    'ambiguous 409 partial failure retains confirmed paths but cannot retry',
    () async {
      source.send = () async {
        if (source.paths.length == 2) {
          throw const StorageException('synthetic conflict', statusCode: '409');
        }
      };
      final result = await coordinator.start();
      expect(result.phase, WorkEvidenceDraftUploadPhase.partialFailure);
      expect(result.error, WorkEvidenceUploadError.conflict);
      expect(result.canRetry, isFalse);
      expect(result.confirmedPaths, hasLength(1));
      await coordinator.start();
      expect(source.paths, hasLength(2));
    },
  );

  test('reordering exact file identities during eligibility invalidates before upload', () async {
    final eligible = Completer<bool>();
    source.eligible = () => eligible.future;
    final pending = coordinator.start();
    draft.reorder();
    draft
        .reorder(); // Returning to original order must not resurrect the batch.
    eligible.complete(true);
    expect((await pending).phase, WorkEvidenceDraftUploadPhase.invalidated);
    expect(source.paths, isEmpty);
    await coordinator.start();
    expect(source.eligibility, hasLength(1));
  });

  test(
    'changed selection stops remaining uploads without claiming rollback',
    () async {
      final first = Completer<void>();
      source.send = () => first.future;
      final pending = coordinator.start();
      await Future<void>.delayed(Duration.zero);
      expect(source.paths, hasLength(1));
      draft.removeFile(draft.files.last.id);
      expect(coordinator.state.phase, WorkEvidenceDraftUploadPhase.invalidated);
      first.complete();
      final result = await pending;
      expect(result.phase, WorkEvidenceDraftUploadPhase.invalidated);
      expect(result.objectsMayExist, isTrue);
      expect(result.message, contains('nothing was rolled back or deleted'));
      expect(result.confirmedPaths, isEmpty);
      expect(source.paths, hasLength(1));
    },
  );

  test(
    'description change-back cannot publish a stale successful batch',
    () async {
      final first = Completer<void>();
      source.send = () => first.future;
      final pending = coordinator.start();
      await Future<void>.delayed(Duration.zero);
      final old = draft.description;
      draft.setDescription('Edited');
      draft.setDescription(old);
      first.complete();
      expect((await pending).phase, WorkEvidenceDraftUploadPhase.invalidated);
      expect(coordinator.state.receipt, isNull);
      expect(source.paths, hasLength(1));
    },
  );

  test(
    'replacement after partial failure cannot mix old success with new files',
    () async {
      source.send = () async {
        if (source.paths.length == 2) throw Exception('synthetic offline');
      };
      await coordinator.start();
      final oldFile = draft.files.last;
      draft.removeFile(oldFile.id);
      await draft.addFiles([file(png(2), name: oldFile.name)]);
      expect(
        (await coordinator.start()).phase,
        WorkEvidenceDraftUploadPhase.invalidated,
      );
      expect(source.paths, hasLength(2));
      expect(coordinator.state.confirmedPaths, isEmpty);
      expect(coordinator.state.objectsMayExist, isTrue);
    },
  );

  for (final change in ['source account', 'draft account', 'assignment']) {
    test(
      '$change change isolates pending completions and prevents retries',
      () async {
        final first = Completer<void>();
        source.send = () => first.future;
        final pending = coordinator.start();
        await Future<void>.delayed(Duration.zero);
        switch (change) {
          case 'source account':
            source.account('worker-b');
            source.account('worker-a');
          case 'draft account':
            session.account(null);
            session.account('worker-a');
          case 'assignment':
            draft.changeAssignment(assignmentB);
            draft.changeAssignment(assignmentA);
        }
        first.complete();
        expect((await pending).phase, WorkEvidenceDraftUploadPhase.invalidated);
        expect(coordinator.state.confirmedPaths, isEmpty);
        expect(coordinator.state.receipt, isNull);
        await coordinator.start();
        expect(source.paths, hasLength(1));
      },
    );
  }

  test(
    'account mismatch without an event hides confirmed state immediately',
    () async {
      await coordinator.start();
      source.userId = 'worker-b';
      expect(coordinator.state.phase, WorkEvidenceDraftUploadPhase.invalidated);
      expect(coordinator.state.confirmedPaths, isEmpty);
      expect(coordinator.state.receipt, isNull);
      await coordinator.start();
      source.userId = 'worker-a';
      expect(coordinator.state.phase, WorkEvidenceDraftUploadPhase.invalidated);
    },
  );

  test('synchronous listener invalidation prevents dispatch', () async {
    coordinator.addListener(() {
      if (coordinator.state.phase == WorkEvidenceDraftUploadPhase.uploading) {
        draft.clear();
      }
    });
    expect(
      (await coordinator.start()).phase,
      WorkEvidenceDraftUploadPhase.invalidated,
    );
    expect(source.eligibility, isEmpty);
    expect(source.paths, isEmpty);
  });

  test(
    'dedicated repository is explicitly bound to the draft assignment',
    () async {
      uploads.changeAssignment(assignmentB);
      expect(
        (await coordinator.start()).phase,
        WorkEvidenceDraftUploadPhase.confirmed,
      );
      expect(source.eligibility, [assignmentA]);
      expect(
        source.paths.every((path) => path.startsWith('$assignmentA/')),
        isTrue,
      );
    },
  );

  test(
    'disposal ignores in-flight completion and does not clear caller draft',
    () async {
      final first = Completer<void>();
      source.send = () => first.future;
      final pending = coordinator.start();
      await Future<void>.delayed(Duration.zero);
      var notifications = 0;
      coordinator.addListener(() => notifications++);
      coordinator.dispose();
      first.complete();
      expect((await pending).phase, WorkEvidenceDraftUploadPhase.invalidated);
      expect(notifications, 0);
      expect(draft.files, hasLength(2));
      expect(source.paths, hasLength(1));
    },
  );
}
