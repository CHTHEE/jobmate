import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/resume_pdf_opener.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_evidence_preview.dart';
import 'package:jobmate/features/work_attendance/work_evidence_repository.dart';

import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, evidenceRow, id, other;

class PreviewSource implements WorkEvidencePreviewSource {
  PreviewSource(this.attendance);
  final FakeSource attendance;
  @override
  String? get userId => attendance.userId;
  @override
  Stream<String?> get accountChanges => attendance.accountChanges;
  final checks = <String>[];
  final signed = <(String, int)>[];
  bool allowed = true;
  Future<Uri> Function()? response;
  @override
  Future<bool> canRead(String path) async {
    checks.add(path);
    return allowed;
  }

  @override
  Future<Uri> sign(String path, int seconds) async {
    signed.add((path, seconds));
    return response?.call() ??
        Future.value(
          Uri.parse(
            'https://private.invalid/object/sign/work-evidence/file?token=fake',
          ),
        );
  }
}

class PreviewOpener implements ResumePdfOpener {
  final opened = <Uri>[];
  @override
  bool get isWeb => false;
  @override
  ResumePdfWindow? reserve() => null;
  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

void main() {
  late FakeSource attendanceSource;
  late WorkAttendanceRepository attendance;
  late WorkEvidenceRepository viewer;
  late PreviewSource source;
  late WorkEvidencePreviewRepository repo;
  late Map<String, dynamic> row;
  setUp(() async {
    attendanceSource = FakeSource();
    attendanceSource.workerRead = () async => [assignment()];
    row = evidenceRow()
      ..['storage_path'] = '$id/file.pdf'
      ..['mime_type'] = 'application/pdf';
    attendanceSource.evidenceRead = (_) async => [row];
    attendance = WorkAttendanceRepository(attendanceSource);
    viewer = WorkEvidenceRepository.worker(attendance, assignmentId: id);
    await viewer.load();
    source = PreviewSource(attendanceSource);
    repo = WorkEvidencePreviewRepository(source);
  });
  tearDown(() async {
    repo.dispose();
    viewer.dispose();
    attendance.dispose();
    await attendanceSource.changes.close();
  });

  test('fresh authorized metadata and per-file authorization precede 90-second signing', () async {
    final reads = attendanceSource.calls;
    await repo.load(viewer, id);
    expect(attendanceSource.calls, greaterThan(reads));
    expect(source.checks, ['$id/file.pdf']);
    expect(source.signed, [('$id/file.pdf', 90)]);
    expect(repo.link, isNotNull);
    expect(repo.error, isNull);
    expect(attendanceSource.checkIns + attendanceSource.checkOuts, 0);
  });
  test(
    'unknown metadata ID never authorizes or signs an arbitrary path',
    () async {
      await repo.load(viewer, other);
      expect(repo.link, isNull);
      expect(source.checks, isEmpty);
      expect(source.signed, isEmpty);
    },
  );
  test('false private-file authorization never signs', () async {
    source.allowed = false;
    await repo.load(viewer, id);
    expect(repo.link, isNull);
    expect(repo.error, isNotNull);
    expect(source.signed, isEmpty);
  });
  test(
    'employer must freshly resolve authorized company before file access',
    () async {
      viewer.dispose();
      viewer = WorkEvidenceRepository.employer(
        attendance,
        assignmentId: id,
        companyId: other,
        loadCompanyAccess: () async =>
            const JobAccess({'company_id': id}, null),
      );
      await repo.load(viewer, id);
      expect(repo.link, isNull);
      expect(source.checks, isEmpty);
    },
  );
  test('authorized employer can preview formally returned evidence', () async {
    viewer.dispose();
    attendanceSource.companyRead = (_) async => [
      assignment(company: true)..['verification_status'] = 'pending_review',
    ];
    viewer = WorkEvidenceRepository.employer(
      attendance,
      assignmentId: id,
      companyId: other,
      loadCompanyAccess: () async =>
          const JobAccess({'company_id': other}, null),
    );
    await repo.load(viewer, id);
    expect(repo.link, isNotNull);
    expect(source.signed, hasLength(1));
  });
  for (final mime in ['text/html', 'application/octet-stream']) {
    test('unsupported $mime never signs or opens', () async {
      row['mime_type'] = mime;
      await repo.load(viewer, id);
      expect(repo.link, isNull);
      expect(source.signed, isEmpty);
    });
  }
  test(
    'missing assignment, foreign path and failed metadata reads fail closed',
    () async {
      row['storage_path'] = '$other/file.pdf';
      await repo.load(viewer, id);
      expect(source.signed, isEmpty);
      attendanceSource.workerRead = () async => [];
      await repo.load(viewer, id);
      expect(source.signed, isEmpty);
      attendanceSource.workerRead = () async =>
          throw StateError('private detail');
      await repo.load(viewer, id);
      expect(repo.error, isNot(contains('private detail')));
    },
  );
  test('missing Storage file error is sanitized', () async {
    source.response = () async => throw StateError('private URL token');
    await repo.load(viewer, id);
    expect(repo.link, isNull);
    expect(repo.error, isNot(contains('token')));
  });
  test('account switch away/back discards late signing and clears an existing link', () async {
    final pending = Completer<Uri>();
    source.response = () => pending.future;
    final loading = repo.load(viewer, id);
    await Future<void>.delayed(Duration.zero);
    attendanceSource.userId = other;
    attendanceSource.changes.add(other);
    attendanceSource.userId = id;
    attendanceSource.changes.add(id);
    pending.complete(Uri.parse('https://private.invalid/?token=fake'));
    await loading;
    expect(repo.link, isNull);
  });
  testWidgets(
    'PDF open uses injected opener, never displays signed URL; expiry removes access',
    (tester) async {
      final opener = PreviewOpener();
      await tester.pumpWidget(
        MaterialApp(
          home: WorkEvidencePreviewDialog(
            viewer: viewer,
            evidenceId: id,
            repository: repo,
            opener: opener,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(opener.opened, isEmpty);
      expect(find.textContaining('token='), findsNothing);
      await tester.tap(find.text('Open PDF'));
      await tester.pumpAndSettle();
      expect(opener.opened, hasLength(1));
      await tester.pump(const Duration(seconds: 91));
      await tester.pumpAndSettle();
      expect(find.text('Open PDF'), findsNothing);
      expect(find.text('Check access again'), findsOneWidget);
    },
  );
  for (final mime in ['image/jpeg', 'image/png', 'image/webp']) {
    testWidgets('$mime preview uses signed access with a fake image renderer', (
      tester,
    ) async {
      row['mime_type'] = mime;
      await tester.pumpWidget(
        MaterialApp(
          home: WorkEvidencePreviewDialog(
            viewer: viewer,
            evidenceId: id,
            repository: repo,
            imageBuilder: (_) => const Text('Private image preview'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private image preview'), findsOneWidget);
      expect(find.text('Open image'), findsOneWidget);
      attendanceSource.userId = null;
      attendanceSource.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Private image preview'), findsNothing);
    });
  }
}
