import 'dart:async';

import 'package:flutter/foundation.dart';

import 'work_evidence_draft_controller.dart';
import 'work_evidence_upload_repository.dart';

enum WorkEvidenceDraftUploadPhase {
  idle,
  invalidDraft,
  uploading,
  partialFailure,
  retryable,
  confirmed,
  blocked,
  invalidated,
}

@immutable
class WorkEvidenceDraftUploadState {
  WorkEvidenceDraftUploadState._({
    required this.phase,
    List<String> paths = const [],
    this.receipt,
    this.error,
    this.message,
    this.canRetry = false,
    this.objectsMayExist = false,
  }) : confirmedPaths = List.unmodifiable(paths);

  final WorkEvidenceDraftUploadPhase phase;
  final List<String> confirmedPaths;
  final WorkEvidenceConfirmedBatch? receipt;
  final WorkEvidenceUploadError? error;
  final String? message;
  final bool canRetry, objectsMayExist;
}

/// Explicit upload orchestration only; never constructs a backend adapter or
/// submits evidence. The caller supplies a dedicated, exclusively used upload
/// repository for this draft and owns both dependencies. Dispose this controller
/// before its dependencies. Do not replace/reuse that repository
/// behind this controller. Draft/selection changes after a batch starts require
/// a fresh coordinator/repository, rather than silently mixing retry cohorts.
///
/// Invalidation uses the repository's invalid assignment context to stop future
/// requests; an in-flight Storage request cannot be rolled back. Disposal does
/// not clear the caller's draft, dispose dependencies, or delete uploaded files.
class WorkEvidenceDraftUploadController extends ChangeNotifier {
  WorkEvidenceDraftUploadController({
    required this.draft,
    required this.uploads,
  }) : _actor = draft.session.userId,
       _assignment = draft.assignmentId {
    draft.addListener(_observeDraft);
    uploads.addListener(_observeUploads);
    _draftAccount = draft.session.accountChanges.listen(_accountChanged);
    _uploadAccount = uploads.source.accountChanges.listen(_accountChanged);
  }

  final WorkEvidenceDraftController draft;
  final WorkEvidenceUploadRepository uploads;
  final String? _actor, _assignment;
  late final StreamSubscription<String?> _draftAccount, _uploadAccount;
  bool _disposed = false, _invalidated = false, _running = false;
  List<EvidenceDraftFile>? _selection;
  String? _description;
  WorkEvidenceUploadResult? _lastResult;
  WorkEvidenceDraftUploadState _state = WorkEvidenceDraftUploadState._(
    phase: WorkEvidenceDraftUploadPhase.idle,
  );

  bool get _contextCurrent =>
      !_disposed &&
      !_invalidated &&
      _actor != null &&
      _assignment != null &&
      draft.session.userId == _actor &&
      uploads.source.userId == _actor &&
      draft.assignmentId == _assignment;

  bool get _batchCurrent {
    if (!_contextCurrent) return false;
    final selected = _selection;
    if (selected == null) return true;
    final files = draft.files;
    return !draft.busy &&
        draft.description == _description &&
        files.length == selected.length &&
        List.generate(
          files.length,
          (i) => identical(files[i], selected[i]),
        ).every((same) => same);
  }

  /// Read this live state after awaits; previously returned snapshots do not
  /// authorize reuse. Confirmed receipts still require repository revalidation.
  WorkEvidenceDraftUploadState get state =>
      _batchCurrent &&
          (_state.receipt == null ||
              uploads.isConfirmedBatchCurrent(_state.receipt!, draft: draft))
      ? _state
      : WorkEvidenceDraftUploadState._(
          phase: WorkEvidenceDraftUploadPhase.invalidated,
          message:
              'Draft or upload context changed. Reopen an authorized draft. '
              'In-flight uploads may have stored files; nothing was rolled back or deleted.',
          objectsMayExist: _state.objectsMayExist || _running,
        );

  void _accountChanged(String? actor) {
    if (actor != _actor || !_contextCurrent) _invalidate();
  }

  void _observeDraft() {
    if (!_batchCurrent) {
      _invalidate();
    } else if (!_disposed) {
      notifyListeners();
    }
  }

  void _observeUploads() {
    if (_disposed || _invalidated) return;
    final last = _lastResult;
    if (!_batchCurrent || (last != null && !uploads.isCurrent(last))) {
      _invalidate();
      return;
    }
    if (_running) {
      final paths = uploads.uploadedPaths;
      _state = WorkEvidenceDraftUploadState._(
        phase: WorkEvidenceDraftUploadPhase.uploading,
        paths: paths,
        objectsMayExist: _state.objectsMayExist || paths.isNotEmpty,
      );
      notifyListeners();
    } else if (_state.receipt != null &&
        !uploads.isConfirmedBatchCurrent(_state.receipt!, draft: draft)) {
      _invalidate();
    }
  }

  void _invalidate({bool notify = true}) {
    if (_disposed || _invalidated) return;
    final mayExist =
        _running || _state.objectsMayExist || uploads.uploadedPaths.isNotEmpty;
    _invalidated = true;
    _selection = null;
    _description = null;
    _lastResult = null;
    _state = WorkEvidenceDraftUploadState._(
      phase: WorkEvidenceDraftUploadPhase.invalidated,
      objectsMayExist: mayExist,
    );
    // Invalidating the dedicated repository stops its remaining file loop.
    // Confirmed objects are intentionally not deleted or claimed to be undone.
    uploads.changeAssignment('');
    if (notify) notifyListeners();
  }

  /// The ONLY entry point that can initiate eligibility/upload requests. Retry
  /// requires another explicit call and an unchanged batch; never automatic.
  Future<WorkEvidenceDraftUploadState> start() async {
    if (!_batchCurrent) {
      _invalidate();
      return state;
    }
    if (_running ||
        _state.phase == WorkEvidenceDraftUploadPhase.confirmed ||
        (_lastResult != null && !_state.canRetry)) {
      return state;
    }
    if (!draft.ready) {
      _state = WorkEvidenceDraftUploadState._(
        phase: WorkEvidenceDraftUploadPhase.invalidDraft,
        message:
            draft.descriptionError ??
            draft.filesError ??
            'Wait for local file validation to finish.',
      );
      notifyListeners();
      return state;
    }
    _running = true;
    // Explicitly scope the dedicated repository; it exposes no assignment
    // getter. This performs local context binding, not an authorization check.
    uploads.changeAssignment(_assignment!);
    _selection ??= List.unmodifiable(draft.files);
    _description ??= draft.description;
    _state = WorkEvidenceDraftUploadState._(
      phase: WorkEvidenceDraftUploadPhase.uploading,
      paths: uploads.uploadedPaths,
      objectsMayExist: _state.objectsMayExist,
    );
    try {
      notifyListeners();
      // A listener may synchronously edit/close the draft before dispatch.
      if (!_batchCurrent) return state;
      final result = await uploads.upload(_selection!);
      if (!_batchCurrent) return state;
      if (!uploads.isCurrent(result)) {
        _invalidate();
        return state;
      }
      _lastResult = result;
      final receipt = uploads.validateConfirmedBatch(
        result: result,
        draft: draft,
      );
      if (receipt != null) {
        _state = WorkEvidenceDraftUploadState._(
          phase: WorkEvidenceDraftUploadPhase.confirmed,
          paths: receipt.uploadedPaths,
          receipt: receipt,
          objectsMayExist: result.objectsMayExist,
        );
      } else {
        final retry = result.error == WorkEvidenceUploadError.connection;
        _state = WorkEvidenceDraftUploadState._(
          phase: result.uploadedPaths.isNotEmpty
              ? WorkEvidenceDraftUploadPhase.partialFailure
              : retry
              ? WorkEvidenceDraftUploadPhase.retryable
              : WorkEvidenceDraftUploadPhase.blocked,
          paths: result.uploadedPaths,
          error: result.error,
          message: result.message ?? 'Upload batch could not be confirmed.',
          canRetry: retry,
          objectsMayExist: result.objectsMayExist,
        );
      }
    } finally {
      _running = false;
      if (!_disposed) notifyListeners();
    }
    return state;
  }

  @override
  void dispose() {
    if (_disposed) return;
    draft.removeListener(_observeDraft);
    uploads.removeListener(_observeUploads);
    _invalidate(notify: false);
    _disposed = true;
    unawaited(_draftAccount.cancel());
    unawaited(_uploadAccount.cancel());
    super.dispose();
  }
}
