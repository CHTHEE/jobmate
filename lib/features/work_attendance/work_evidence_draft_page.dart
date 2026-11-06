import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../shared/widgets/mobile_back_action.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../applications/module2_widgets.dart';
import 'work_evidence_draft_controller.dart';
import 'work_evidence_draft_upload_controller.dart';
import 'work_evidence_upload_repository.dart';

/// Explicitly injected mock mode only. This final, in-memory implementation has
/// no client, network callbacks, persistence or Storage operations. It retains
/// simulated path receipts, never file bytes. The caller owns the session.
final class WorkEvidenceMockUploadSource implements WorkEvidenceUploadSource {
  WorkEvidenceMockUploadSource({
    required this.session,
    List<bool> outcomes = const [],
    this.delay = Duration.zero,
  }) : _outcomes = List.unmodifiable(outcomes);

  final EvidenceDraftSession session;
  final List<bool> _outcomes;
  final Duration delay;
  final List<String> _attempts = [];
  int eligibilityChecks = 0;
  List<String> get attemptedPaths => List.unmodifiable(_attempts);
  @override
  String? get userId => session.userId;
  @override
  Stream<String?> get accountChanges => session.accountChanges;
  @override
  Future<bool> canUpload(String assignmentId) async {
    eligibilityChecks++;
    return userId != null;
  }

  @override
  Future<void> upload(
    String objectPath,
    Uint8List bytes,
    String contentType,
  ) async {
    final index = _attempts.length;
    _attempts.add(objectPath);
    await Future<void>.delayed(delay);
    if (index < _outcomes.length && !_outcomes[index]) {
      throw StateError('Simulated connection failure');
    }
  }
}

/// Matches the existing dialog/sheet convention, capturing size before opening
/// so a later assignment change cannot access the disposed opener's context.
Future<void> showWorkEvidenceDraft(
  BuildContext context,
  WorkEvidenceDraftController controller,
) {
  final compact = ResponsiveLayout.isCompact(context);
  final maxHeight = MediaQuery.sizeOf(context).height * .9;
  final form = WorkEvidenceDraftPage(controller: controller);
  if (compact) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => FractionallySizedBox(heightFactor: .94, child: form),
    );
  }
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      child: SizedBox(
        width: 640,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: form,
        ),
      ),
    ),
  );
}

/// Responsive modal content. The caller owns the injected controller; unmounting
/// the form clears its local draft and cancels pending reads.
class WorkEvidenceDraftPage extends StatefulWidget {
  const WorkEvidenceDraftPage({
    super.key,
    required this.controller,
    this.onClose,
    this.mockUploadSource,
    this.supervisedQaControls,
    this.supervisedQaLocked = false,
    this.supervisedQaBusy = false,
    this.workflowControls,
    this.workflowLocked = false,
    this.workflowBusy = false,
    this.workflowCompleted = false,
  });
  final WorkEvidenceDraftController controller;
  final VoidCallback? onClose;
  // Only this network-free final source type is accepted. Production callers
  // omit it, so their existing local-only draft behavior remains unchanged.
  final WorkEvidenceMockUploadSource? mockUploadSource;

  /// Optional isolated QA host. Normal production and mock callers omit these.
  final Widget? supervisedQaControls;
  final bool supervisedQaLocked, supervisedQaBusy;
  final Widget? workflowControls;
  final bool workflowLocked, workflowBusy;

  /// Set only after a validated committed server response.
  final bool workflowCompleted;

  @override
  State<WorkEvidenceDraftPage> createState() => _WorkEvidenceDraftPageState();
}

class _WorkEvidenceDraftPageState extends State<WorkEvidenceDraftPage> {
  late final description = TextEditingController(
    text: widget.controller.description,
  );
  bool _leaving = false, _confirming = false;
  WorkEvidenceUploadRepository? _mockUploads;
  WorkEvidenceDraftUploadController? _mockCoordinator;

  void _attachMock() {
    final source = widget.mockUploadSource;
    final assignment = widget.controller.assignmentId;
    if (source == null || assignment == null) return;
    final uploads = WorkEvidenceUploadRepository(
      source,
      assignmentId: assignment,
    );
    _mockUploads = uploads;
    _mockCoordinator = WorkEvidenceDraftUploadController(
      draft: widget.controller,
      uploads: uploads,
    );
  }

  void _detachMock() {
    _mockCoordinator?.dispose();
    _mockUploads?.dispose();
    _mockCoordinator = null;
    _mockUploads = null;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncDescription);
    _attachMock();
  }

  void _syncDescription() {
    final text = widget.controller.description;
    if (description.text != text) {
      description.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  bool get _dirty =>
      widget.controller.description.isNotEmpty ||
      widget.controller.files.isNotEmpty ||
      widget.controller.busy;

  Future<void> _close() async {
    if (_confirming ||
        _leaving ||
        widget.supervisedQaBusy ||
        widget.workflowBusy) {
      return;
    }
    setState(() => _confirming = true);
    final discard = await confirmDiscardChanges(context, _dirty);
    if (!mounted) return;
    setState(() => _confirming = false);
    if (!discard) return;
    widget.controller.clear();
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.onClose != null) {
        widget.onClose!();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void didUpdateWidget(covariant WorkEvidenceDraftPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.workflowCompleted && !oldWidget.workflowCompleted) {
      _leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          widget.controller.clear();
          Navigator.of(context).pop();
        }
      });
    }
    final changedDraft = !identical(oldWidget.controller, widget.controller);
    final changedMock = !identical(
      oldWidget.mockUploadSource,
      widget.mockUploadSource,
    );
    if (changedDraft || changedMock) _detachMock();
    if (changedDraft) {
      oldWidget.controller.removeListener(_syncDescription);
      oldWidget.controller.clear();
      widget.controller.addListener(_syncDescription);
      _syncDescription();
      _leaving = false;
    }
    if (changedDraft || changedMock) _attachMock();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncDescription);
    _detachMock();
    widget.controller.clear();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, ?_mockCoordinator]),
    builder: (context, _) {
      final draft = widget.controller;
      final active = draft.assignmentId != null && draft.session.userId != null;
      final upload = _mockCoordinator?.state;
      final batchLocked =
          widget.workflowLocked ||
          widget.supervisedQaLocked ||
          (upload != null &&
              upload.phase != WorkEvidenceDraftUploadPhase.idle &&
              upload.phase != WorkEvidenceDraftUploadPhase.invalidDraft);
      final canUpload =
          active &&
          draft.ready &&
          !_leaving &&
          !_confirming &&
          upload != null &&
          (upload.phase == WorkEvidenceDraftUploadPhase.idle ||
              upload.phase == WorkEvidenceDraftUploadPhase.invalidDraft ||
              upload.canRetry);
      return PopScope(
        // Evaluate dirty state when Back is requested, including before the
        // next frame has rebuilt after typing or selecting a file.
        canPop: _leaving,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: ModalBody(
          title: widget.workflowControls == null
              ? 'Local work evidence draft'
              : 'Submit work evidence',
          actions: [
            OutlinedButton(
              onPressed:
                  _confirming || widget.supervisedQaBusy || widget.workflowBusy
                  ? null
                  : _close,
              child: const Text('Close draft'),
            ),
            if (widget.workflowControls == null)
              const FilledButton(
                onPressed: null,
                child: Text('Submit Evidence'),
              ),
          ],
          children: [
            Text(
              widget.workflowControls != null
                  ? 'Confirming submission uploads selected files privately and submits them for employer review. An uncertain response must be reconciled before any further action.'
                  : widget.supervisedQaControls == null
                  ? 'Nothing has been uploaded or submitted. This draft is kept only while this form is open.'
                  : 'Supervised QA only. Confirmed actions below write to real private Storage and the deployed evidence RPC. Normal production submission remains disabled.',
            ),
            const SizedBox(height: 12),
            if (widget.workflowControls == null)
              Text(
                widget.supervisedQaControls == null
                    ? 'Submission is not enabled yet.'
                    : 'Normal submission is disabled. Only the explicit supervised QA controls below can submit.',
              ),
            if (widget.supervisedQaControls != null)
              widget.supervisedQaControls!,
            if (widget.workflowControls != null) widget.workflowControls!,
            const SizedBox(height: 20),
            if (!active) ...[
              const Text(
                'Draft cleared. Reopen this form from an authorized work assignment.',
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const ValueKey('evidence-draft-description'),
              controller: description,
              enabled: active && !_leaving && !batchLocked,
              minLines: 4,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              onChanged: draft.setDescription,
              decoration: InputDecoration(
                labelText: 'Work description (required)',
                alignLabelWithHint: true,
                helperText: 'Up to 2,000 characters after trimming surrounding whitespace.',
                helperMaxLines: 3,
                errorText: active ? draft.descriptionError : null,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Choose 1–5 JPEG, PNG, WebP or PDF files. Each file must be non-empty and at most 10 MiB.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: !active || draft.busy || _leaving || batchLocked
                  ? null
                  : draft.selectFiles,
              icon: const Icon(Icons.attach_file),
              label: Text(
                draft.busy ? 'Reading local files…' : 'Choose evidence files',
              ),
            ),
            if (draft.busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                semanticsLabel: 'Reading selected files',
              ),
            ],
            if (draft.filesError != null) ...[
              const SizedBox(height: 8),
              Text(draft.filesError!),
            ],
            for (final file in draft.files)
              Padding(
                key: ValueKey(file.id),
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(file.name),
                          Text(_fileSize(file.sizeBytes)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove ${file.name}',
                      onPressed: draft.busy || _leaving || batchLocked
                          ? null
                          : () => draft.removeFile(file.id),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            if (draft.error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  draft.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (widget.mockUploadSource != null) ...[
              const Text(
                'Mock upload mode. Uploads are simulated in memory; no files are sent to Supabase. Evidence is not submitted.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('evidence-mock-upload'),
                onPressed: canUpload
                    ? () async {
                        await _mockCoordinator!.start();
                      }
                    : null,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(
                  upload?.canRetry == true ? 'Retry Upload' : 'Upload Evidence',
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(switch (upload?.phase) {
                  null =>
                    'Mock upload unavailable. Close and reopen this draft.',
                  WorkEvidenceDraftUploadPhase.idle =>
                    'Ready to simulate an upload after draft validation.',
                  WorkEvidenceDraftUploadPhase.invalidDraft =>
                    'Complete the description and file validation first.',
                  WorkEvidenceDraftUploadPhase.uploading =>
                    'Uploading evidence (mock)',
                  WorkEvidenceDraftUploadPhase.partialFailure =>
                    'Mock upload partially failed',
                  WorkEvidenceDraftUploadPhase.retryable =>
                    'Mock upload failed. Retry is available.',
                  WorkEvidenceDraftUploadPhase.confirmed =>
                    'Mock upload batch confirmed. Nothing was submitted.',
                  WorkEvidenceDraftUploadPhase.blocked =>
                    'Mock upload blocked. Close and reopen this draft.',
                  WorkEvidenceDraftUploadPhase.invalidated => 'Draft or account changed. Close and reopen; this batch cannot be retried.',
                }),
              ),
              if (upload?.phase == WorkEvidenceDraftUploadPhase.uploading)
                const LinearProgressIndicator(
                  semanticsLabel: 'Simulating evidence upload',
                ),
              if (upload != null && upload.confirmedPaths.isNotEmpty)
                Text(
                  'Simulated files confirmed: ${upload.confirmedPaths.length} of ${draft.files.length}.',
                ),
              if (upload?.canRetry == true)
                const Text(
                  'Retry keeps confirmed files and retries only the unchanged pending batch.',
                ),
              const SizedBox(height: 20),
            ],
            Semantics(
              liveRegion: true,
              child: Text(
                draft.ready
                    ? widget.workflowControls == null
                          ? 'Draft ready for future submission'
                          : 'Evidence ready for confirmation'
                    : 'Draft not ready',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      );
    },
  );
}

String _fileSize(int size) {
  if (size < 1024) return '$size B';
  if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KiB';
  return '${(size / (1024 * 1024)).toStringAsFixed(2)} MiB';
}
