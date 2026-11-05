import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_evidence_draft_controller.dart';

const assignmentA = '11111111-1111-4111-8111-111111111111';
const assignmentB = '22222222-2222-4222-8222-222222222222';

class FakeDraftSession implements EvidenceDraftSession {
  @override
  String? userId = 'worker-a';
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get accountChanges => changes.stream;
  void account(String? value) {
    userId = value;
    changes.add(value);
  }
}

Uint8List pdf([int marker = 1]) =>
    Uint8List.fromList(utf8.encode('%PDF-1.7\n$marker\n%%EOF'));
Uint8List png([int marker = 1]) =>
    Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, marker]);
Uint8List jpeg([int marker = 1]) =>
    Uint8List.fromList([255, 216, 255, 224, marker, 255, 217]);
Uint8List webp([int marker = 1]) {
  final bytes = Uint8List(22);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  ByteData.sublistView(bytes).setUint32(4, 14, Endian.little);
  bytes.setRange(8, 12, ascii.encode('WEBP'));
  bytes.setRange(12, 16, ascii.encode('VP8L'));
  ByteData.sublistView(bytes).setUint32(16, 2, Endian.little);
  bytes[20] = marker;
  return bytes;
}

XFile file(Uint8List bytes, {String name = 'evidence.pdf', String? mime}) =>
    XFile.fromData(bytes, name: name, path: name, mimeType: mime);

class ControlledFile extends XFile {
  ControlledFile({
    this.displayName = 'evidence.pdf',
    required this.reportedSize,
    required this.chunks,
    this.onLength,
    this.claimedMime,
  }) : super('/private/local-path/never-display.pdf');
  final String displayName;
  final int reportedSize;
  final Stream<Uint8List> Function() chunks;
  final Future<int> Function()? onLength;
  final String? claimedMime;
  int reads = 0;
  @override
  String get name => displayName;
  @override
  String? get mimeType => claimedMime;
  @override
  Future<int> length() => onLength?.call() ?? Future.value(reportedSize);
  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    reads++;
    return chunks();
  }
}

void main() {
  late FakeDraftSession session;
  late WorkEvidenceDraftController draft;
  late Future<List<XFile>> Function() selection;
  setUp(() {
    session = FakeDraftSession();
    selection = () async => [];
    draft = WorkEvidenceDraftController(
      session: session,
      assignmentId: assignmentA,
      pickFiles: () => selection(),
    );
  });
  tearDown(() async {
    draft.dispose();
    await session.changes.close();
  });

  test(
    'description required, trimmed code-point limit and draft readiness',
    () async {
      expect(draft.ready, isFalse);
      expect(draft.descriptionError, contains('Enter'));
      expect(draft.filesError, contains('1 and 5'));
      for (final blank in ['', '   ', '\n\t', '\u2003']) {
        draft.setDescription(blank);
        expect(draft.descriptionError, isNotNull);
      }
      draft.setDescription('  Completed the assigned work.  ');
      await draft.addFiles([file(pdf())]);
      expect(draft.description, '  Completed the assigned work.  ');
      expect(draft.ready, isTrue);
      draft.setDescription(List.filled(2000, '😀').join());
      expect(draft.descriptionError, isNull);
      draft.setDescription(List.filled(2001, '😀').join());
      expect(draft.ready, isFalse);
      expect(draft.descriptionError, contains('2,000'));
      expect(draft.files, hasLength(1));
    },
  );

  test(
    'detects JPEG PNG WebP PDF from bytes with matching extensions and MIME',
    () async {
      await draft.addFiles([
        file(jpeg(), name: 'photo.JPEG', mime: 'image/jpeg'),
        file(png(), name: 'photo.png', mime: 'image/png'),
        file(webp(), name: 'photo.webp', mime: 'image/webp'),
        file(pdf(), name: 'report.pdf', mime: 'application/pdf'),
      ]);
      expect(draft.error, isNull);
      expect(draft.files.map((f) => f.mimeType), [
        'image/jpeg',
        'image/png',
        'image/webp',
        'application/pdf',
      ]);
      expect(draft.files.first.sizeBytes, jpeg().length);
      expect(() => draft.files.clear(), throwsUnsupportedError);
      expect(() => draft.files.first.bytes[0] = 0, throwsUnsupportedError);
    },
  );

  test(
    'unknown generic MIME uses detected bytes; JPEG alias normalizes',
    () async {
      await draft.addFiles([
        file(pdf(), mime: 'application/octet-stream'),
        file(jpeg(), name: 'photo.jpg', mime: 'image/jpg'),
        file(png(), name: 'photo.png'),
      ]);
      expect(draft.files, hasLength(3));
      expect(draft.error, isNull);
    },
  );

  test('rejects false extensions, claimed MIME mismatches and unsupported signatures', () async {
    for (final selected in [
      file(pdf(), name: 'photo.png'),
      file(png(), name: 'photo.png', mime: 'application/pdf'),
      file(pdf(), name: 'file.exe'),
      file(Uint8List.fromList(ascii.encode('GIF89a')), name: 'photo.png'),
      file(Uint8List.fromList([137, 80, 78]), name: 'photo.png'),
      file(webp()..[8] = 0, name: 'photo.webp'),
      file(webp()..[4] = 0, name: 'photo.webp'),
      file(webp()..[16] = 99, name: 'photo.webp'),
    ]) {
      await draft.addFiles([selected]);
      expect(draft.files, isEmpty);
      expect(draft.error, contains('contents match'));
    }
  });

  test('empty and oversized advertised files fail before reading', () async {
    for (final size in [0, -1, WorkEvidenceDraftController.maxFileBytes + 1]) {
      final selected = ControlledFile(
        reportedSize: size,
        chunks: () => Stream.value(pdf()),
      );
      await draft.addFiles([selected]);
      expect(selected.reads, 0);
      expect(draft.error, contains('10 MiB'));
      expect(draft.files, isEmpty);
    }
  });

  test('exact 10 MiB accepted; actual oversized streams rejected even when size lies', () async {
    final boundary = Uint8List(WorkEvidenceDraftController.maxFileBytes);
    boundary.setRange(0, 5, ascii.encode('%PDF-'));
    await draft.addFiles([file(boundary)]);
    expect(draft.error, isNull);
    expect(
      draft.files.single.sizeBytes,
      WorkEvidenceDraftController.maxFileBytes,
    );
    draft.clear();
    final oversized = ControlledFile(
      reportedSize: 5,
      chunks: () => Stream.fromIterable([
        boundary,
        Uint8List.fromList([1]),
      ]),
    );
    await draft.addFiles([oversized]);
    expect(draft.files, isEmpty);
    expect(draft.error, contains('10 MiB'));
  });

  test(
    'unreadable metadata/stream and incomplete bytes have sanitized errors',
    () async {
      final secret = 'C:/private/path/customer-secret.pdf';
      for (final selected in [
        ControlledFile(
          reportedSize: 5,
          chunks: () => Stream.value(pdf()),
          onLength: () async => throw Exception(secret),
        ),
        ControlledFile(
          reportedSize: 5,
          chunks: () => Stream.error(Exception(secret)),
        ),
        ControlledFile(
          reportedSize: 5,
          chunks: () => Stream.value(Uint8List(0)),
        ),
        ControlledFile(reportedSize: 999, chunks: () => Stream.value(pdf())),
      ]) {
        await draft.addFiles([selected]);
        expect(draft.error, isNotNull);
        expect(draft.error, isNot(contains(secret)));
        expect(draft.error, isNot(contains('customer-secret')));
        expect(draft.files, isEmpty);
        expect(draft.busy, isFalse);
      }
    },
  );

  test(
    '1–5 files across selections; exceeding count fails before reads',
    () async {
      draft.setDescription('Work completed');
      await draft.addFiles([
        for (var i = 0; i < 5; i++) file(pdf(i), name: 'file-$i.pdf'),
      ]);
      expect(draft.files, hasLength(5));
      expect(draft.ready, isTrue);
      final extra = ControlledFile(
        reportedSize: 5,
        chunks: () => Stream.value(pdf(6)),
      );
      await draft.addFiles([extra]);
      expect(extra.reads, 0);
      expect(draft.error, contains('at most 5'));
      expect(draft.files, hasLength(5));
      expect(draft.ready, isTrue);
      draft.removeFile(draft.files.first.id);
      await draft.addFiles([file(pdf(6))]);
      expect(draft.error, isNull);
      expect(draft.files, hasLength(5));
    },
  );

  test('duplicates are rejected by content even with renamed files; batches are atomic', () async {
    await draft.addFiles([file(pdf())]);
    await draft.addFiles([file(pdf(), name: 'renamed.pdf')]);
    expect(draft.error, contains('duplicate'));
    expect(draft.files, hasLength(1));
    await draft.addFiles([file(pdf(2)), file(pdf(2), name: 'same.pdf')]);
    expect(draft.files, hasLength(1));
    expect(draft.error, contains('duplicate'));
    // Same display name with different content is not the same file.
    await draft.addFiles([file(pdf(3))]);
    expect(draft.files, hasLength(2));
  });

  test('invalid batch preserves original draft and description', () async {
    draft.setDescription('Retain this description');
    await draft.addFiles([file(pdf())]);
    final original = draft.files.single;
    await draft.addFiles([file(png(), name: 'photo.png'), file(Uint8List(0))]);
    expect(draft.files.single, same(original));
    expect(draft.description, 'Retain this description');
    expect(draft.ready, isTrue);
    expect(original.bytes, pdf());
  });

  test(
    'removing and clearing release owned bytes without altering original input',
    () async {
      final input = pdf();
      await draft.addFiles([file(input)]);
      final retained = draft.files.single;
      final view = retained.bytes;
      draft.removeFile(retained.id);
      expect(draft.files, isEmpty);
      expect(retained.bytes, isEmpty);
      expect(view.every((byte) => byte == 0), isTrue);
      expect(input, pdf());
      await draft.addFiles([file(pdf(2))]);
      final next = draft.files.single;
      draft.setDescription('Description');
      draft.clear();
      expect(next.bytes, isEmpty);
      expect(draft.description, isEmpty);
      expect(draft.assignmentId, assignmentA);
    },
  );

  test('picker cancellation and errors preserve retained files with sanitized feedback', () async {
    await draft.addFiles([file(pdf())]);
    await draft.selectFiles();
    expect(draft.files, hasLength(1));
    expect(draft.error, isNull);
    selection = () async => throw Exception('/private/token/worker.pdf');
    await draft.selectFiles();
    expect(draft.error, contains('Could not read'));
    expect(draft.error, isNot(contains('token')));
    expect(draft.files, hasLength(1));
  });

  test('one picker/read at a time; late picker results cannot cross assignment changes', () async {
    final picker = Completer<List<XFile>>();
    var picks = 0;
    selection = () {
      picks++;
      return picker.future;
    };
    final operation = draft.selectFiles();
    expect(draft.busy, isTrue);
    await draft.selectFiles();
    await draft.addFiles([file(pdf(2))]);
    expect(picks, 1);
    draft.setDescription('Old description');
    draft.changeAssignment(assignmentB);
    expect(draft.description, isEmpty);
    expect(draft.busy, isFalse);
    picker.complete([file(pdf())]);
    await operation;
    expect(draft.files, isEmpty);
    expect(draft.assignmentId, assignmentB);
  });

  test(
    'same assignment preserves draft; invalid assignment clears it',
    () async {
      draft.setDescription('Retain');
      await draft.addFiles([file(pdf())]);
      draft.changeAssignment(assignmentA.toUpperCase());
      expect(draft.files, hasLength(1));
      draft.changeAssignment('not-a-valid-assignment');
      expect(draft.files, isEmpty);
      expect(draft.description, isEmpty);
      expect(draft.assignmentId, isNull);
      expect(draft.error, isNot(contains('not-a-valid-assignment')));
      expect(draft.ready, isFalse);
    },
  );

  test(
    'logout/account switching zero bytes and require a new assignment context',
    () async {
      for (final actor in [null, 'worker-b']) {
        draft.changeAssignment(assignmentA);
        draft.setDescription('Private description');
        await draft.addFiles([file(pdf())]);
        final old = draft.files.single;
        session.account(actor);
        expect(draft.description, isEmpty);
        expect(draft.files, isEmpty);
        expect(old.bytes, isEmpty);
        expect(draft.assignmentId, isNull);
        expect(draft.ready, isFalse);
        await draft.addFiles([file(pdf(2))]);
        expect(draft.files, isEmpty);
        if (actor == null) session.account('worker-a');
      }
    },
  );

  test('token refresh preserves draft; identity change before stream delivery hides it', () async {
    draft.setDescription('Work summary');
    await draft.addFiles([file(pdf())]);
    session.changes.add(session.userId);
    expect(draft.ready, isTrue);
    session.userId = 'worker-b';
    expect(draft.files, isEmpty);
    expect(draft.description, isEmpty);
    expect(draft.ready, isFalse);
    session.changes.add('worker-b');
    expect(draft.assignmentId, isNull);
  });

  test(
    'account change during file stream discards old bytes and stale errors',
    () async {
      final chunks = StreamController<Uint8List>();
      final selected = ControlledFile(
        reportedSize: pdf().length,
        chunks: () => chunks.stream,
      );
      final old = draft.addFiles([selected]);
      await Future<void>.delayed(Duration.zero);
      chunks.add(pdf().sublist(0, 5));
      await Future<void>.delayed(Duration.zero);
      session.account('worker-b');
      draft.changeAssignment(assignmentB);
      draft.setDescription('New account description');
      await draft.addFiles([file(pdf(2))]);
      chunks.addError(Exception('/old/private/file.pdf'));
      await chunks.close();
      await old;
      expect(draft.description, 'New account description');
      expect(draft.files, hasLength(1));
      expect(draft.error, isNull);
      expect(draft.ready, isTrue);
    },
  );

  test(
    'assignment change cancels waits even if file metadata never resolves',
    () async {
      final length = Completer<int>();
      final unread = ControlledFile(
        reportedSize: 0,
        onLength: () => length.future,
        chunks: () => Stream.value(pdf()),
      );
      final old = draft.addFiles([file(pdf()), unread]);
      await Future<void>.delayed(Duration.zero);
      draft.changeAssignment(assignmentB);
      await old;
      expect(draft.files, isEmpty);
      expect(draft.busy, isFalse);
      expect(unread.reads, 0);
      length.complete(pdf().length);
      await Future<void>.delayed(Duration.zero);
      expect(draft.files, isEmpty);
    },
  );

  test(
    'clear cancels an active byte stream before its source completes',
    () async {
      var cancelled = false;
      final stream = StreamController<Uint8List>(
        onCancel: () {
          cancelled = true;
        },
      );
      final selected = ControlledFile(
        reportedSize: pdf().length,
        chunks: () => stream.stream,
      );
      final old = draft.addFiles([selected]);
      await Future<void>.delayed(Duration.zero);
      stream.add(pdf().sublist(0, 5));
      await Future<void>.delayed(Duration.zero);
      draft.clear();
      await old;
      expect(cancelled, isTrue);
      expect(draft.files, isEmpty);
      expect(draft.busy, isFalse);
      await stream.close();
    },
  );

  test(
    'display filename strips path components without exposing them',
    () async {
      await draft.addFiles([
        file(pdf(), name: 'C:\\private\\customer\\proof.pdf'),
      ]);
      expect(draft.files.single.name, 'proof.pdf');
      expect(draft.error, isNull);
    },
  );

  test(
    'disposal cancels auth listener, zeroes files and ignores a pending picker',
    () async {
      await draft.addFiles([file(pdf())]);
      final held = draft.files.single;
      final pending = Completer<List<XFile>>();
      selection = () => pending.future;
      final old = draft.selectFiles();
      draft.dispose();
      expect(session.changes.hasListener, isFalse);
      expect(held.bytes, isEmpty);
      pending.complete([file(pdf(2))]);
      await old;
      expect(draft.files, isEmpty);
      expect(draft.ready, isFalse);
      // Give tearDown a live controller to dispose.
      draft = WorkEvidenceDraftController(
        session: session,
        assignmentId: assignmentB,
      );
    },
  );
}
