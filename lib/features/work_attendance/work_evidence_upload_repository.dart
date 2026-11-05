import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'work_attendance_models.dart';
import 'work_evidence_draft_controller.dart';

abstract class WorkEvidenceUploadSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<bool> canUpload(String assignmentId);
  Future<void> upload(String objectPath, Uint8List bytes, String contentType);
}

/// Only the eligibility RPC and append-only private Storage insertion are used.
/// Call via the repository to bind eligibility and retries to a single batch.
class SupabaseWorkEvidenceUploadSource implements WorkEvidenceUploadSource {
  SupabaseWorkEvidenceUploadSource(this.client);
  final SupabaseClient client;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);

  String _actor() {
    final actor = userId;
    if (actor == null) throw const AuthException('Authentication required');
    return actor;
  }

  @override
  Future<bool> canUpload(String assignmentId) async {
    final actor = _actor();
    final result = await client.rpc(
      'can_upload_work_evidence',
      params: {'p_assignment_id': workUuid(assignmentId)},
    );
    if (userId != actor) throw const AuthException('Account changed');
    if (result is! bool) {
      throw const FormatException('Invalid eligibility response');
    }
    return result;
  }

  @override
  Future<void> upload(
    String objectPath,
    Uint8List bytes,
    String contentType,
  ) async {
    final actor = _actor();
    _validatePayload(bytes, contentType);
    final parts = objectPath.split('/');
    if (parts.length != 2 ||
        workUuid(parts.first) != parts.first ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,199}\.(jpg|jpeg|png|webp|pdf)$')
            .hasMatch(parts.last) ||
        !parts.last.endsWith('.${_extension(contentType)}')) {
      throw const FormatException('Invalid evidence object path');
    }
    final key = await client.storage
        .from('work-evidence')
        .uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
          retryAttempts: 0, // Explicit retries must recheck eligibility.
        );
    if (userId != actor) throw const AuthException('Account changed');
    if (key != 'work-evidence/$objectPath') {
      throw const FormatException('Unconfirmed evidence upload response');
    }
  }
}

enum WorkEvidenceUploadError {
  authentication,
  notEligible,
  invalidFiles,
  selectionChanged,
  permission,
  connection,
  invalidResponse,
  conflict,
  busy,
  invalidated,
}

@immutable
class WorkEvidenceUploadResult {
  WorkEvidenceUploadResult._(
    this._owner,
    this._generation,
    this._attempt, {
    required List<String> paths,
    required List<int> pending,
    required this.complete,
    required this.objectsMayExist,
    this.error,
    this.message,
  }) : uploadedPaths = List.unmodifiable(paths),
       pendingFileIndexes = List.unmodifiable(pending);

  final Object _owner;
  final int _generation;
  final int _attempt;

  /// Confirmed paths only, always in the original file order.
  final List<String> uploadedPaths;

  /// Includes the failed file and any files not attempted after that failure.
  final List<int> pendingFileIndexes;
  final bool complete;
  final bool objectsMayExist;
  final WorkEvidenceUploadError? error;
  final String? message;
}

/// Locally confirmed upload receipt, never a backend authorization grant.
/// Step 101E should obtain this from validateConfirmedBatch using the latest
/// upload result and the live draft. After any asynchronous eligibility/read
/// checks, call isConfirmedBatchCurrent with that same live draft immediately
/// before submission. The submission service must separately validate/observe
/// the description and reconcile ambiguous submission outcomes.
@immutable
final class WorkEvidenceConfirmedBatch {
  WorkEvidenceConfirmedBatch._(
    this._owner,
    this._generation,
    this._attempt,
    this._draft,
    this.assignmentId,
    List<String> paths,
  ) : uploadedPaths = List.unmodifiable(paths);
  final Object _owner;
  final int _generation, _attempt;
  final WorkEvidenceDraftController _draft;
  final String assignmentId;
  final List<String> uploadedPaths;
}

/// One ordered batch per account/assignment. Not wired to any production UI.
/// Source files are accepted only as validated EvidenceDraftFile instances.
/// File identity and order cannot change once a batch starts. Recreate the
/// repository for a deliberately new batch; never silently mix retry cohorts.
///
/// Uploads stop at the first failure. Confirmed files are skipped on retry;
/// unconfirmed files retain their original UUID path. A 409 is NOT proof of
/// success and requires reconciliation, rather than overwrite or deletion.
class WorkEvidenceUploadRepository extends ChangeNotifier {
  WorkEvidenceUploadRepository(this.source, {required String assignmentId})
    : _assignmentId = workUuid(assignmentId),
      _actor = source.userId {
    _subscription = source.accountChanges.listen((id) {
      if (id != _actor || source.userId != _actor) _resetAccount();
    });
  }
  final WorkEvidenceUploadSource source;
  late final StreamSubscription<String?> _subscription;
  String? _actor;
  String _assignmentId;
  int _generation = 0;
  int _attempt = 0;
  int? _completedAttempt;
  bool _disposed = false, _busy = false, _objectsMayExist = false;
  List<_UploadSlot>? _batch;
  final _fileContexts = Expando<Object>();
  Object _context = Object();

  bool get _visible => !_disposed && _actor != null && source.userId == _actor;
  bool get busy => _visible && _busy;
  List<String> get uploadedPaths => _visible
      ? List.unmodifiable(
          _batch?.where((slot) => slot.confirmed).map((slot) => slot.path) ??
              const <String>[],
        )
      : const [];
  bool isCurrent(WorkEvidenceUploadResult result) =>
      _visible &&
      identical(result._owner, this) &&
      result._generation == _generation &&
      result.error != WorkEvidenceUploadError.invalidated;

  /// Pure local validation: no uploads, eligibility RPCs, notifications or
  /// mutation. Null means the live draft is not the latest confirmed batch.
  /// An earlier successful result cannot override a later failed retry.
  WorkEvidenceConfirmedBatch? validateConfirmedBatch({
    required WorkEvidenceUploadResult result,
    required WorkEvidenceDraftController draft,
  }) {
    if (!identical(result._owner, this) ||
        !result.complete ||
        result.error != null ||
        result.pendingFileIndexes.isNotEmpty) {
      return null;
    }
    final paths = _confirmedPaths(result._generation, result._attempt, draft);
    if (paths == null || !listEquals(paths, result.uploadedPaths)) return null;
    return WorkEvidenceConfirmedBatch._(
      this,
      _generation,
      _attempt,
      draft,
      _assignmentId,
      paths,
    );
  }

  /// Rechecks a previously issued receipt against current draft/account state.
  /// Call again after awaiting anything; possession of a receipt is not enough.
  bool isConfirmedBatchCurrent(
    WorkEvidenceConfirmedBatch receipt, {
    required WorkEvidenceDraftController draft,
  }) {
    if (!identical(receipt._owner, this) ||
        !identical(receipt._draft, draft) ||
        receipt.assignmentId != _assignmentId) {
      return false;
    }
    final paths = _confirmedPaths(receipt._generation, receipt._attempt, draft);
    return paths != null && listEquals(paths, receipt.uploadedPaths);
  }

  List<String>? _confirmedPaths(
    int generation,
    int attempt,
    WorkEvidenceDraftController draft,
  ) {
    if (!_visible ||
        _busy ||
        generation != _generation ||
        attempt != _attempt ||
        _completedAttempt != attempt ||
        draft.busy ||
        draft.session.userId != _actor ||
        draft.assignmentId != _assignmentId) {
      return null;
    }
    final slots = _batch;
    final files = draft.files;
    if (slots == null ||
        files.isEmpty ||
        files.length > 5 ||
        slots.length != files.length) {
      return null;
    }
    try {
      if (workUuid(_assignmentId) != _assignmentId) return null;
      final pattern = RegExp(
        '^$_assignmentId/'
        r'[A-Za-z0-9][A-Za-z0-9._-]{0,199}[.](jpg|jpeg|png|webp|pdf)$',
      );
      final paths = <String>[];
      for (var i = 0; i < files.length; i++) {
        final slot = slots[i], file = files[i];
        if (!slot.confirmed ||
            !identical(slot.file, file) ||
            !identical(_fileContexts[file], _context) ||
            !pattern.hasMatch(slot.path) ||
            !slot.path.endsWith('.${_extension(file.mimeType)}')) {
          return null;
        }
        // A released draft file no longer represents the original selection.
        _validatePayload(file.bytes, file.mimeType);
        paths.add(slot.path);
      }
      if (paths.toSet().length != paths.length) return null;
      return paths;
    } on FormatException {
      return null;
    } on _UploadValidation {
      return null;
    }
  }

  void _resetAccount() {
    ++_generation;
    _completedAttempt = null;
    _context = Object();
    _actor = source.userId;
    _batch = null;
    _busy = false;
    _objectsMayExist = false;
    notifyListeners();
  }

  void changeAssignment(String assignmentId) {
    if (_disposed) return;
    String next;
    try {
      next = workUuid(assignmentId);
    } on FormatException {
      next = '';
    }
    if (next.isNotEmpty && next == _assignmentId && _actor == source.userId) {
      return;
    }
    // Invalid new context must also invalidate any pending old operation.
    ++_generation;
    _completedAttempt = null;
    _context = Object();
    _batch = null;
    _busy = false;
    _objectsMayExist = false;
    _assignmentId = next;
    notifyListeners();
  }

  WorkEvidenceUploadResult _result({
    WorkEvidenceUploadError? error,
    String? message,
    bool invalidated = false,
    bool objectsMayExist = false,
  }) {
    final slots = invalidated ? null : _batch;
    return WorkEvidenceUploadResult._(
      this,
      _generation,
      _attempt,
      paths: invalidated ? const [] : uploadedPaths,
      pending: [
        if (slots != null)
          for (var i = 0; i < slots.length; i++)
            if (!slots[i].confirmed) i,
      ],
      complete:
          !invalidated &&
          error == null &&
          slots != null &&
          slots.isNotEmpty &&
          slots.every((slot) => slot.confirmed),
      objectsMayExist: objectsMayExist || (!invalidated && _objectsMayExist),
      error: error,
      message: message,
    );
  }

  Future<WorkEvidenceUploadResult> upload(List<EvidenceDraftFile> files) async {
    if (_disposed) {
      return _result(
        error: WorkEvidenceUploadError.invalidated,
        invalidated: true,
        message: 'This upload context is no longer active.',
      );
    }
    if (source.userId != _actor) _resetAccount();
    if (_actor == null) {
      return _result(
        error: WorkEvidenceUploadError.authentication,
        message: 'Sign in again before uploading evidence.',
      );
    }
    if (_busy) {
      return _result(
        error: WorkEvidenceUploadError.busy,
        message: 'An evidence upload is already in progress.',
      );
    }
    final generation = _generation, actor = _actor, assignment = _assignmentId;
    bool current() =>
        !_disposed &&
        generation == _generation &&
        actor == source.userId &&
        assignment == _assignmentId;
    var operationMayHaveStoredObjects = false;
    ++_attempt;
    _completedAttempt = null;
    _busy = true;
    notifyListeners();
    try {
      workUuid(assignment);
      final selected = List<EvidenceDraftFile>.of(files);
      if (selected.isEmpty ||
          selected.length > 5 ||
          (Set<EvidenceDraftFile>.identity()..addAll(selected)).length !=
              selected.length) {
        throw const _UploadValidation(WorkEvidenceUploadError.invalidFiles);
      }
      if (_batch != null &&
          (_batch!.length != selected.length ||
              List.generate(
                selected.length,
                (i) => identical(_batch![i].file, selected[i]),
              ).contains(false))) {
        throw const _UploadValidation(WorkEvidenceUploadError.selectionChanged);
      }
      for (final file in selected) {
        final bound = _fileContexts[file];
        if (bound != null && !identical(bound, _context)) {
          throw const _UploadValidation(
            WorkEvidenceUploadError.selectionChanged,
          );
        }
        _validatePayload(file.bytes, file.mimeType);
      }
      if (!current()) return _stale(operationMayHaveStoredObjects);
      for (final file in selected) {
        _fileContexts[file] = _context;
      }
      final eligible = await source.canUpload(assignment);
      if (!current()) return _stale(operationMayHaveStoredObjects);
      if (!eligible) {
        return _result(
          error: WorkEvidenceUploadError.notEligible,
          message:
              'This assignment is not currently eligible for evidence uploads.',
        );
      }
      _batch ??= [
        for (final file in selected)
          _UploadSlot(
            file,
            '$assignment/${const Uuid().v4()}.${_extension(file.mimeType)}',
          ),
      ];
      final slots = _batch!;
      for (final slot in slots) {
        if (!current()) return _stale(operationMayHaveStoredObjects);
        if (slot.confirmed) continue;
        _validatePayload(slot.file.bytes, slot.file.mimeType);
        // A draft can be cleared while the request is pending. Send an owned
        // snapshot; never let clearing the draft alter bytes already in flight.
        final bytes = Uint8List.fromList(slot.file.bytes);
        try {
          operationMayHaveStoredObjects = true;
          _objectsMayExist = true;
          await source.upload(slot.path, bytes, slot.file.mimeType);
        } finally {
          // Invalidation cannot roll back an in-flight Storage request. Keep its
          // owned snapshot until the source completes, then release it.
          bytes.fillRange(0, bytes.length, 0);
        }
        if (!current()) return _stale(operationMayHaveStoredObjects);
        slot.confirmed = true;
        notifyListeners();
      }
      if (!current()) return _stale(operationMayHaveStoredObjects);
      _completedAttempt = _attempt;
      return _result();
    } catch (failure) {
      if (!current()) return _stale(operationMayHaveStoredObjects);
      final kind = _errorKind(failure);
      return _result(error: kind, message: _message(kind));
    } finally {
      if (current()) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  WorkEvidenceUploadResult _stale(bool objectsMayExist) => _result(
    invalidated: true,
    error: WorkEvidenceUploadError.invalidated,
    objectsMayExist: objectsMayExist,
    message: 'Upload context changed. In-flight requests may have stored files; nothing was rolled back or deleted.',
  );

  @override
  void dispose() {
    ++_generation;
    _completedAttempt = null;
    _disposed = true;
    _batch = null;
    _subscription.cancel();
    super.dispose();
  }
}

class _UploadSlot {
  _UploadSlot(this.file, this.path);
  final EvidenceDraftFile file;
  final String path;
  bool confirmed = false;
}

String? _extension(String mime) => switch (mime) {
  'image/jpeg' => 'jpg',
  'image/png' => 'png',
  'image/webp' => 'webp',
  'application/pdf' => 'pdf',
  _ => null,
};

void _validatePayload(Uint8List bytes, String mime) {
  if (_extension(mime) == null ||
      bytes.isEmpty ||
      bytes.length > WorkEvidenceDraftController.maxFileBytes) {
    throw const _UploadValidation(WorkEvidenceUploadError.invalidFiles);
  }
}

class _UploadValidation implements Exception {
  const _UploadValidation(this.kind);
  final WorkEvidenceUploadError kind;
}

WorkEvidenceUploadError _errorKind(Object failure) {
  if (failure is _UploadValidation) return failure.kind;
  if (failure is AuthException ||
      failure is PostgrestException &&
          ['PGRST301', 'PGRST302', 'PGRST303'].contains(failure.code) ||
      failure is StorageException &&
          ['401', '403'].contains(failure.statusCode)) {
    return failure is StorageException && failure.statusCode == '403'
        ? WorkEvidenceUploadError.permission
        : WorkEvidenceUploadError.authentication;
  }
  if (failure is StorageException && failure.statusCode == '409') {
    return WorkEvidenceUploadError.conflict;
  }
  if (failure is PostgrestException && failure.code == '42501') {
    return WorkEvidenceUploadError.permission;
  }
  if (failure is FormatException) {
    return WorkEvidenceUploadError.invalidResponse;
  }
  return WorkEvidenceUploadError.connection;
}

String _message(WorkEvidenceUploadError kind) => switch (kind) {
  WorkEvidenceUploadError.authentication =>
    'Your session has expired. Sign in again before uploading evidence.',
  WorkEvidenceUploadError.permission =>
    'Evidence upload access is denied. Recheck your account and assignment.',
  WorkEvidenceUploadError.invalidFiles => 'Choose 1–5 validated JPEG, PNG, WebP or PDF files, each non-empty and at most 10 MiB.',
  WorkEvidenceUploadError.selectionChanged => 'The selected files or their order changed. Retry only with the original upload batch.',
  WorkEvidenceUploadError.invalidResponse => 'The server response could not be confirmed. Recheck upload eligibility before retrying.',
  WorkEvidenceUploadError.conflict => 'A pending object already exists, but its upload is unconfirmed. Reconciliation is required; no file was overwritten.',
  _ => 'An evidence upload could not be confirmed. Some files may already be stored; no files were deleted.',
};
