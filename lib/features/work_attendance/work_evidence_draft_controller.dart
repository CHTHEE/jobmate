import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_models.dart';

abstract class EvidenceDraftSession {
  String? get userId;
  Stream<String?> get accountChanges;
}

/// Observes authentication only; this adapter performs no backend operations.
class SupabaseEvidenceDraftSession implements EvidenceDraftSession {
  SupabaseEvidenceDraftSession(this.client);
  final SupabaseClient client;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);
}

Future<List<XFile>> pickWorkEvidenceFiles() => openFiles(
  acceptedTypeGroups: const [
    XTypeGroup(
      label: 'JPEG, PNG, WebP or PDF',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'],
    ),
  ],
);

/// An in-memory local file, with no local path or backend storage identity.
/// Retained byte views are read-only and zeroed when this draft releases a file.
class EvidenceDraftFile {
  EvidenceDraftFile._(this.id, this.name, this.mimeType, this._bytes);
  final int id;
  final String name, mimeType;
  Uint8List _bytes;
  int get sizeBytes => _bytes.length;
  Uint8List get bytes => _bytes.asUnmodifiableView();
  void _release() {
    _bytes.fillRange(0, _bytes.length, 0);
    _bytes = Uint8List(0);
  }
}

/// Local preparation only. Readiness is not assignment/upload authorization.
/// The future worker UI must independently resolve authorized assignments.
class WorkEvidenceDraftController extends ChangeNotifier {
  WorkEvidenceDraftController({
    required this.session,
    required String assignmentId,
    Future<List<XFile>> Function()? pickFiles,
  }) : _assignmentId = workUuid(assignmentId),
       _picker = pickFiles ?? pickWorkEvidenceFiles,
       _actor = session.userId {
    _subscription = session.accountChanges.listen((id) {
      if (id != _actor || session.userId != _actor) _resetAccount();
    });
  }

  static const maxFileBytes = 10 * 1024 * 1024;
  static const maxFiles = 5;
  final EvidenceDraftSession session;
  final Future<List<XFile>> Function() _picker;
  late final StreamSubscription<String?> _subscription;
  String? _actor, _assignmentId;
  String _description = '';
  String? _error;
  bool _busy = false, _disposed = false;
  int _generation = 0, _nextFileId = 0;
  final List<EvidenceDraftFile> _files = [];
  _DraftReadOperation? _selectionOperation;

  bool get _active =>
      !_disposed &&
      _actor != null &&
      _actor == session.userId &&
      _assignmentId != null;
  String get description => _active ? _description : '';
  String? get assignmentId => !_disposed ? _assignmentId : null;
  List<EvidenceDraftFile> get files =>
      _active ? List.unmodifiable(_files) : const [];
  bool get busy => _active && _busy;
  String? get error => _disposed
      ? null
      : _actor != session.userId
      ? 'Your account changed. Reopen this draft.'
      : _error;
  String? get descriptionError {
    final length = description.trim().runes.length;
    if (length == 0) return 'Enter a work description.';
    if (length > 2000) return 'Use a description of at most 2,000 characters.';
    return null;
  }

  String? get filesError =>
      files.isEmpty ? 'Choose between 1 and 5 evidence files.' : null;
  // A failed addition does not invalidate previously valid, retained files.
  bool get ready =>
      _active &&
      !_busy &&
      descriptionError == null &&
      _files.isNotEmpty &&
      _files.length <= maxFiles;

  bool _current(int generation) => _active && generation == _generation;

  void _clear() {
    ++_generation;
    _selectionOperation?.cancel();
    _selectionOperation = null;
    _description = '';
    _error = null;
    _busy = false;
    for (final file in _files) {
      file._release();
    }
    _files.clear();
  }

  void _resetAccount() {
    _clear();
    _actor = session.userId;
    _assignmentId =
        null; // The new account must establish its assignment context.
    notifyListeners();
  }

  bool _syncAccount() {
    if (_disposed) return false;
    if (session.userId != _actor) _resetAccount();
    if (!_active) {
      _error = _actor == null
          ? 'Sign in to prepare evidence.'
          : 'Select a valid work assignment.';
      notifyListeners();
      return false;
    }
    return true;
  }

  void setDescription(String value) {
    if (!_syncAccount()) return;
    _description = value;
    notifyListeners();
  }

  void changeAssignment(String value) {
    if (_disposed) return;
    String? next;
    try {
      next = workUuid(value);
    } on FormatException {
      // Invalid new context must not retain the old assignment's draft.
    }
    if (next != null && next == _assignmentId && _actor == session.userId) {
      return;
    }
    _clear();
    _actor = session.userId;
    _assignmentId = next;
    if (next == null) _error = 'Select a valid work assignment.';
    notifyListeners();
  }

  void clear() {
    if (_disposed) return;
    _clear();
    notifyListeners();
  }

  void removeFile(int fileId) {
    if (!_syncAccount() || _busy) return;
    final index = _files.indexWhere((file) => file.id == fileId);
    if (index < 0) return;
    _files.removeAt(index)._release();
    _error = null;
    notifyListeners();
  }

  Future<void> selectFiles() => _select(_picker);
  Future<void> addFiles(List<XFile> selected) =>
      _select(() async => List<XFile>.of(selected));

  Future<void> _select(Future<List<XFile>> Function() select) async {
    if (!_syncAccount() || _busy) return;
    final generation = _generation;
    _busy = true;
    _error = null;
    notifyListeners();
    if (!_current(generation)) return;
    final pending = <EvidenceDraftFile>[];
    final operation = _DraftReadOperation();
    _selectionOperation = operation;
    void releasePending() {
      for (final file in pending) {
        file._release();
      }
      pending.clear();
    }

    operation.addCleanup(releasePending);
    try {
      final selected = await operation.wait(select());
      if (!_current(generation)) return;
      if (selected.length + _files.length > maxFiles) {
        throw const _DraftValidation(
          'Choose at most 5 evidence files in total.',
        );
      }
      for (final file in selected) {
        final validated = await _read(file, generation, operation);
        pending.add(validated);
        if (!_current(generation)) return;
        final previous = [..._files, ...pending.take(pending.length - 1)];
        if (previous.any(
          (existing) => listEquals(existing._bytes, validated._bytes),
        )) {
          throw const _DraftValidation(
            'This selection contains a file already in the draft or a duplicate file.',
          );
        }
      }
      if (!_current(generation)) return;
      _files.addAll(pending);
      pending.clear(); // Ownership transfers to the controller only on success.
    } on _DraftInvalidated {
      // Account/assignment/disposal changed while awaiting local file I/O.
    } on _DraftValidation catch (failure) {
      if (_current(generation)) _error = failure.message;
    } catch (_) {
      if (_current(generation)) {
        _error = 'Could not read the selected files. Choose readable files and retry.';
      }
    } finally {
      operation.release();
      // A completed read can resume just after cancellation released callbacks.
      releasePending();
      if (identical(_selectionOperation, operation)) _selectionOperation = null;
      if (_current(generation)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<EvidenceDraftFile> _read(
    XFile file,
    int generation,
    _DraftReadOperation operation,
  ) async {
    final builder = BytesBuilder(copy: true);
    Uint8List? bytes;
    StreamSubscription<Uint8List>? subscription;
    void cleanup() {
      final owned = bytes;
      owned?.fillRange(0, owned.length, 0);
      bytes = null;
      final partial = builder.takeBytes();
      partial.fillRange(0, partial.length, 0);
      final active = subscription;
      subscription = null;
      if (active != null) {
        // Cleanup must not surface a platform error containing a local path.
        try {
          unawaited(active.cancel().catchError((Object _) {}));
        } catch (_) {
          // No file data or native error is logged.
        }
      }
    }

    operation.addCleanup(cleanup);
    try {
      final size = await operation.wait(file.length());
      if (!_current(generation)) throw const _DraftInvalidated();
      if (size <= 0 || size > maxFileBytes) {
        throw const _DraftValidation(
          'Each file must be non-empty and at most 10 MiB.',
        );
      }
      var read = 0;
      // Bound actual bytes too: picker-reported length is not trusted.
      final done = Completer<void>();
      void fail(Object failure, [StackTrace? trace]) {
        if (!done.isCompleted) done.completeError(failure, trace);
      }

      subscription = file.openRead().listen(
        (chunk) {
          if (done.isCompleted) return;
          if (!_current(generation)) {
            fail(const _DraftInvalidated());
            return;
          }
          read += chunk.length;
          if (read > maxFileBytes) {
            fail(
              const _DraftValidation(
                'Each file must be non-empty and at most 10 MiB.',
              ),
            );
          } else {
            builder.add(chunk);
          }
        },
        onError: (Object error, StackTrace trace) => fail(error, trace),
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await operation.wait(done.future);
      if (!_current(generation)) throw const _DraftInvalidated();
      final data = builder.takeBytes();
      bytes = data;
      if (data.isEmpty || data.length != size) {
        throw const _DraftValidation(
          'The selected file could not be read completely. Select it again.',
        );
      }
      final name = _displayName(file.name);
      final mime = _signature(data);
      final extension = name.split('.').last.toLowerCase();
      final expected = switch (extension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => null,
      };
      var claimed = file.mimeType?.split(';').first.trim().toLowerCase();
      if (claimed == 'image/jpg') claimed = 'image/jpeg';
      if (mime == null ||
          expected != mime ||
          (claimed != null &&
              claimed.isNotEmpty &&
              claimed != 'application/octet-stream' &&
              claimed != mime)) {
        throw const _DraftValidation(
          'Choose a JPEG, PNG, WebP or PDF whose contents match its file type.',
        );
      }
      final result = EvidenceDraftFile._(++_nextFileId, name, mime, data);
      bytes = null; // Transfer the owned buffer, without retaining the XFile.
      return result;
    } finally {
      operation.removeCleanup(cleanup);
      cleanup();
    }
  }

  @override
  void dispose() {
    _clear();
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}

String _displayName(String name) {
  final leaf = name
      .replaceAll('\\', '/')
      .split('/')
      .last
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
      .trim();
  if (leaf.isEmpty || leaf.runes.length > 255 || !leaf.contains('.')) {
    throw const _DraftValidation(
      'Choose a file with a valid JPEG, PNG, WebP or PDF filename.',
    );
  }
  return leaf;
}

/// Basic signatures, not complete image/PDF decoding or malware scanning.
String? _signature(Uint8List bytes) {
  bool starts(List<int> signature) =>
      bytes.length >= signature.length &&
      listEquals(bytes.sublist(0, signature.length), signature);
  if (starts([0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
  if (starts([37, 80, 68, 70, 45])) return 'application/pdf';
  if (bytes.length >= 20 &&
      starts([82, 73, 70, 70]) &&
      listEquals(bytes.sublist(8, 12), [87, 69, 66, 80])) {
    final data = ByteData.sublistView(bytes);
    final chunk = String.fromCharCodes(bytes.sublist(12, 16));
    if (data.getUint32(4, Endian.little) + 8 == bytes.length &&
        ['VP8 ', 'VP8L', 'VP8X'].contains(chunk) &&
        data.getUint32(16, Endian.little) > 0 &&
        data.getUint32(16, Endian.little) + 20 <= bytes.length) {
      return 'image/webp';
    }
  }
  return null;
}

class _DraftValidation implements Exception {
  const _DraftValidation(this.message);
  final String message;
}

class _DraftInvalidated implements Exception {
  const _DraftInvalidated();
}

/// Cancels waits and scrubs staged buffers even if a native read never returns.
class _DraftReadOperation {
  _DraftReadOperation() {
    _cancelled.future.ignore();
  }
  final _cancelled = Completer<Never>();
  final _cleanups = <VoidCallback>[];
  Future<T> wait<T>(Future<T> future) =>
      Future.any([future, _cancelled.future]);
  void addCleanup(VoidCallback cleanup) => _cleanups.add(cleanup);
  void removeCleanup(VoidCallback cleanup) => _cleanups.remove(cleanup);
  void release() {
    final callbacks = List<VoidCallback>.of(_cleanups);
    _cleanups.clear();
    for (final cleanup in callbacks) {
      cleanup();
    }
  }

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.completeError(const _DraftInvalidated());
    }
    release();
  }
}
