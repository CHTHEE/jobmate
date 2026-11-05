import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, evidenceRow, id, other;

void main() {
  late FakeSource source;
  late WorkAttendanceRepository attendance;
  late WorkEvidenceRepository viewer;
  late int metadataReads;
  setUp(() {
    source = FakeSource();
    attendance = WorkAttendanceRepository(source);
    viewer = WorkEvidenceRepository.worker(attendance, assignmentId: id);
    metadataReads = 0;
    source.evidenceRead = (assignmentId) async {
      expect(assignmentId, id);
      metadataReads++;
      return [evidenceRow()];
    };
  });
  tearDown(() async {
    viewer.dispose();
    attendance.dispose();
    await source.changes.close();
  });

  test('worker resolves fresh owned assignment before metadata and parses exact evidence fields', () async {
    var listed = false;
    source.workerRead = () async {
      listed = true;
      return [assignment()];
    };
    source.evidenceRead = (_) async {
      expect(listed, isTrue);
      return [evidenceRow()];
    };
    await viewer.load();
    expect(viewer.assignment!.assignmentId, id);
    final file = viewer.evidence.single;
    expect(file.evidenceId, id);
    expect(file.submissionRound, 2);
    expect(file.description, 'Server evidence');
    expect(file.fileName, 'file.pdf');
    expect(file.mimeType, 'application/pdf');
    expect(file.storagePath, '$id/file.pdf');
    expect(file.submittedBy, other);
    expect(file.submittedAt, DateTime.utc(2026, 11, 5, 2));
    expect(() => viewer.evidence.clear(), throwsUnsupportedError);
    expect(source.checkIns, 0);
    expect(source.checkOuts, 0);
  });

  test(
    'UUID alone and cached evidence cannot authorize metadata access',
    () async {
      await attendance.loadEvidence(id);
      metadataReads = 0;
      source.workerRead = () async => [];
      await viewer.load();
      expect(viewer.errorKind, WorkAttendanceError.permission);
      expect(viewer.assignment, isNull);
      expect(viewer.evidence, isEmpty);
      expect(metadataReads, 0);
    },
  );

  test(
    'employer resolves explicit authorized company and its assignment first',
    () async {
      viewer.dispose();
      viewer = WorkEvidenceRepository.employer(
        attendance,
        assignmentId: id,
        companyId: other,
        loadCompanyAccess: () async =>
            const JobAccess({'company_id': other}, null),
      );
      var companyListed = false;
      source.workerRead = () => throw StateError('Wrong list');
      source.companyRead = (company) async {
        expect(company, other);
        companyListed = true;
        return [
          assignment(company: true)..['verification_status'] = 'pending_review',
        ];
      };
      source.evidenceRead = (_) async {
        expect(companyListed, isTrue);
        metadataReads++;
        return [evidenceRow()];
      };
      await viewer.load();
      expect(viewer.error, isNull);
      expect(viewer.evidence, hasLength(1));
      expect(metadataReads, 1);
    },
  );

  test('employer mismatch, denied membership and missing assignment prevent evidence reads', () async {
    for (final access in [
      const JobAccess({'company_id': id}, null),
      const JobAccess({'company_id': other}, 'Verification pending'),
      const JobAccess({'company_id': other}, null),
    ]) {
      viewer.dispose();
      viewer = WorkEvidenceRepository.employer(
        attendance,
        assignmentId: id,
        companyId: other,
        loadCompanyAccess: () async => access,
      );
      source.companyRead = (_) async => [];
      await viewer.load();
      expect(viewer.errorKind, WorkAttendanceError.permission);
      expect(viewer.evidence, isEmpty);
      expect(metadataReads, 0);
      expect(viewer.awaitingFirstSubmission, isFalse);
    }
  });

  test(
    'RPC independently denies evidence even with visible company assignment',
    () async {
      viewer.dispose();
      viewer = WorkEvidenceRepository.employer(
        attendance,
        assignmentId: id,
        companyId: other,
        loadCompanyAccess: () async =>
            const JobAccess({'company_id': other}, null),
      );
      source.companyRead = (_) async => [
        assignment(company: true)..['verification_status'] = 'pending_review',
      ];
      source.evidenceRead = (_) async => throw const PostgrestException(
        message: 'Not authorized to view this evidence',
        code: 'P0001',
      );
      await viewer.load();
      expect(viewer.errorKind, WorkAttendanceError.permission);
      expect(viewer.evidence, isEmpty);
    },
  );

  test('empty evidence, load errors, malformed response and retry', () async {
    source.evidenceRead = (_) async => [];
    await viewer.load();
    expect(viewer.error, isNull);
    expect(viewer.evidence, isEmpty);
    for (final failure in [
      const AuthException('expired'),
      const PostgrestException(message: 'denied', code: '42501'),
      Exception('offline'),
    ]) {
      source.evidenceRead = (_) async => throw failure;
      await viewer.load();
      expect(viewer.error, isNotNull);
      expect(viewer.loading, isFalse);
      expect(viewer.evidence, isEmpty);
    }
    source.evidenceRead = (_) async => [evidenceRow()..['submitted_at'] = null];
    await viewer.load();
    expect(viewer.errorKind, WorkAttendanceError.invalidData);
    source.evidenceRead = (_) async => [evidenceRow()];
    await viewer.load();
    expect(viewer.error, isNull);
    expect(viewer.evidence, hasLength(1));
  });

  test(
    'assignment list failure and invalid IDs do not fall through to evidence',
    () async {
      source.workerRead = () async => throw Exception('offline');
      await viewer.load();
      expect(viewer.errorKind, WorkAttendanceError.connection);
      expect(metadataReads, 0);
      viewer.dispose();
      viewer = WorkEvidenceRepository.worker(
        attendance,
        assignmentId: 'invalid',
      );
      await viewer.load();
      expect(viewer.errorKind, WorkAttendanceError.invalidData);
      expect(metadataReads, 0);
      source.switchAccount(null);
      final calls = source.calls;
      await viewer.load();
      expect(viewer.errorKind, WorkAttendanceError.authentication);
      expect(source.calls, calls);
    },
  );

  test(
    'account switch clears data immediately and rejects stale metadata success',
    () async {
      await viewer.load();
      final pending = Completer<List<Map<String, dynamic>>>();
      source.evidenceRead = (_) => pending.future;
      final oldLoad = viewer.load();
      await Future<void>.delayed(Duration.zero);
      source.workerRead = () async => [];
      source.switchAccount(other);
      expect(viewer.evidence, isEmpty);
      expect(viewer.assignment, isNull);
      expect(viewer.error, contains('Your account changed'));
      await viewer.load();
      pending.complete([evidenceRow()]);
      await oldLoad;
      expect(viewer.evidence, isEmpty);
      expect(viewer.errorKind, WorkAttendanceError.permission);
      source.switchAccount(null);
      expect(viewer.errorKind, WorkAttendanceError.authentication);
    },
  );

  test('stale assignment failure cannot overwrite new session state', () async {
    final pending = Completer<List<Map<String, dynamic>>>();
    source.workerRead = () => pending.future;
    final old = viewer.load();
    source.workerRead = () async => [];
    source.switchAccount(other);
    await viewer.load();
    pending.completeError(Exception('old account'));
    await old;
    expect(viewer.errorKind, WorkAttendanceError.permission);
    expect(metadataReads, 0);
  });

  test('newer refresh supersedes pending evidence errors', () async {
    final pending = Completer<List<Map<String, dynamic>>>();
    source.evidenceRead = (_) => pending.future;
    final old = viewer.load();
    await Future<void>.delayed(Duration.zero);
    source.evidenceRead = (_) async => [evidenceRow()];
    await viewer.load();
    pending.completeError(Exception('stale'));
    await old;
    expect(viewer.error, isNull);
    expect(viewer.evidence, hasLength(1));
  });

  test('disposed viewer ignores pending reads and leaves injected repository usable', () async {
    final pending = Completer<List<Map<String, dynamic>>>();
    source.workerRead = () => pending.future;
    final old = viewer.load();
    viewer.dispose();
    // Replace the disposed fixture so tearDown owns a live controller.
    viewer = WorkEvidenceRepository.worker(attendance, assignmentId: other);
    pending.complete([assignment()]);
    await old;
    expect(metadataReads, 0);
    source.workerRead = () async => [assignment()];
    await attendance.loadWorkerAssignments();
    expect(attendance.worker.rows, hasLength(1));
  });

  test('authorized employer not_submitted skips metadata even when cached evidence exists', () async {
    await attendance.loadEvidence(id);
    metadataReads = 0;
    viewer.dispose();
    viewer = WorkEvidenceRepository.employer(
      attendance,
      assignmentId: id,
      companyId: other,
      loadCompanyAccess: () async =>
          const JobAccess({'company_id': other}, null),
    );
    source.evidenceRead = (_) async {
      metadataReads++;
      throw StateError('Pre-submission metadata must not be requested');
    };
    await viewer.load();
    expect(viewer.awaitingFirstSubmission, isTrue);
    expect(viewer.assignment!.assignmentId, id);
    expect(viewer.error, isNull);
    expect(viewer.loading, isFalse);
    expect(viewer.evidence, isEmpty);
    expect(metadataReads, 0);
  });

  test('all other employer verification statuses retain metadata RPC authorization', () async {
    viewer.dispose();
    viewer = WorkEvidenceRepository.employer(
      attendance,
      assignmentId: id,
      companyId: other,
      loadCompanyAccess: () async =>
          const JobAccess({'company_id': other}, null),
    );
    for (final status in [
      'pending_review',
      'more_evidence_required',
      'verified',
      'disputed',
    ]) {
      source.companyRead = (_) async => [
        assignment(company: true)..['verification_status'] = status,
      ];
      await viewer.load();
      expect(viewer.awaitingFirstSubmission, isFalse);
      expect(viewer.evidence, hasLength(1));
      expect(viewer.error, isNull);
    }
    expect(metadataReads, 4);
  });

  test(
    'worker not_submitted still calls evidence RPC and uses normal empty state',
    () async {
      source.evidenceRead = (_) async {
        metadataReads++;
        return [];
      };
      await viewer.load();
      expect(metadataReads, 1);
      expect(viewer.awaitingFirstSubmission, isFalse);
      expect(viewer.evidence, isEmpty);
      expect(viewer.error, isNull);
    },
  );

  test('refresh clears awaiting state; genuine submitted RPC denial remains denied', () async {
    viewer.dispose();
    viewer = WorkEvidenceRepository.employer(
      attendance,
      assignmentId: id,
      companyId: other,
      loadCompanyAccess: () async =>
          const JobAccess({'company_id': other}, null),
    );
    await viewer.load();
    expect(viewer.awaitingFirstSubmission, isTrue);
    final pending = Completer<List<Map<String, dynamic>>>();
    source.companyRead = (_) => pending.future;
    source.evidenceRead = (_) async {
      metadataReads++;
      throw const PostgrestException(
        message: 'Not authorized to view this evidence',
        code: 'P0001',
      );
    };
    final refresh = viewer.load();
    expect(viewer.awaitingFirstSubmission, isFalse);
    await Future<void>.delayed(Duration.zero);
    pending.complete([
      assignment(company: true)..['verification_status'] = 'pending_review',
    ]);
    await refresh;
    expect(metadataReads, 1);
    expect(viewer.errorKind, WorkAttendanceError.permission);
    expect(viewer.awaitingFirstSubmission, isFalse);
    expect(viewer.assignment, isNull);
  });

  test(
    'account switch invalidates both existing and pending awaiting states',
    () async {
      viewer.dispose();
      viewer = WorkEvidenceRepository.employer(
        attendance,
        assignmentId: id,
        companyId: other,
        loadCompanyAccess: () async =>
            const JobAccess({'company_id': other}, null),
      );
      await viewer.load();
      expect(viewer.awaitingFirstSubmission, isTrue);
      final oldRows = Completer<List<Map<String, dynamic>>>();
      source.companyRead = (_) => oldRows.future;
      final oldLoad = viewer.load();
      await Future<void>.delayed(Duration.zero);
      source.switchAccount(other);
      expect(viewer.awaitingFirstSubmission, isFalse);
      expect(viewer.assignment, isNull);
      source.companyRead = (_) async => [
        assignment(company: true)..['verification_status'] = 'pending_review',
      ];
      await viewer.load();
      oldRows.complete([assignment(company: true)]);
      await oldLoad;
      expect(viewer.awaitingFirstSubmission, isFalse);
      expect(viewer.evidence, hasLength(1));
      source.switchAccount(null);
      expect(viewer.awaitingFirstSubmission, isFalse);
      expect(viewer.evidence, isEmpty);
    },
  );
}
