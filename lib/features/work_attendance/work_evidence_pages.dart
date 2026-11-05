import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/mobile_back_action.dart';
import '../applications/module2_widgets.dart';
import 'work_attendance_models.dart';
import 'work_attendance_repository.dart';
import 'work_evidence_repository.dart';
import 'work_evidence_draft_controller.dart';
import 'work_evidence_draft_page.dart';
import 'work_evidence_mock_review.dart';
import 'work_evidence_qa_page.dart';
import 'work_evidence_qa_review.dart';
import 'work_evidence_preview.dart';
import 'work_assignment_people.dart';
import 'work_assignment_creation_repository.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Metadata viewer with a worker-only local draft form.
/// The caller owns the evidence repository.
class WorkEvidencePage extends StatefulWidget {
  const WorkEvidencePage({
    super.key,
    required this.repository,
    this.pickDraftFiles,
    this.mockReviewOperations,
    this.createQaDependencies,
    this.createQaReviewSource,
    this.qaReviewSession,
    this.createPreviewRepository,
    this.loadWorkerName,
  });
  final WorkEvidenceRepository repository;
  final Future<List<XFile>> Function()? pickDraftFiles;
  final MockWorkEvidenceReviewOperations? mockReviewOperations;
  final WorkEvidenceQaDependencies Function(WorkEvidenceDraftController)?
  createQaDependencies;
  final WorkEvidenceQaReviewSource Function()? createQaReviewSource;
  final WorkEvidenceQaReviewSession? qaReviewSession;
  final WorkEvidencePreviewRepository Function()? createPreviewRepository;
  final WorkAssignmentNameLoader? loadWorkerName;

  @override
  State<WorkEvidencePage> createState() => _WorkEvidencePageState();
}

class _WorkEvidencePageState extends State<WorkEvidencePage> {
  WorkEvidenceDraftController? _draft;
  bool _qaOpening = false;
  bool _reviewOpen = false;
  bool _previewOpen = false;
  Object? _nameScope;
  String? _workerName;
  void _resolveName(CompanyWorkAssignment row) {
    final viewer = widget.repository;
    final scope = (viewer.attendance.source.userId, viewer.companyId, row);
    if (_nameScope == scope) return;
    _nameScope = scope;
    _workerName = null;
    final loader =
        widget.loadWorkerName ??
        (viewer.attendance.source is SupabaseWorkAttendanceSource
            ? WorkAssignmentPeopleRepository(
                SupabaseWorkAssignmentCreationSource(Supabase.instance.client),
              ).workerName
            : null);
    if (loader != null && viewer.companyId != null) {
      loader(row, viewer.companyId!)
          .then((name) {
            if (mounted &&
                _nameScope == scope &&
                widget.repository.attendance.source.userId == scope.$1 &&
                widget.repository.assignment?.assignmentId ==
                    row.assignmentId) {
              setState(() => _workerName = name);
            }
          })
          .catchError((Object _) {});
    }
  }

  Future<void> _preview(WorkEvidence file) async {
    if (_previewOpen) return;
    setState(() => _previewOpen = true);
    final repo =
        widget.createPreviewRepository?.call() ??
        WorkEvidencePreviewRepository(
          SupabaseWorkEvidencePreviewSource(Supabase.instance.client),
        );
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => WorkEvidencePreviewDialog(
          viewer: widget.repository,
          evidenceId: file.evidenceId,
          repository: repo,
        ),
      );
    } finally {
      repo.dispose();
      if (mounted) setState(() => _previewOpen = false);
    }
  }

  Future<void> _openQaReview() async {
    final viewer = widget.repository;
    if (_reviewOpen || !canReviewWorkEvidenceQa(viewer)) return;
    setState(() => _reviewOpen = true);
    try {
      // The dialog rechecks company access and the exact evidence snapshot
      // after confirmation, immediately before its only write.
      final source =
          widget.createQaReviewSource?.call() ??
          SupabaseWorkEvidenceQaReviewSource(Supabase.instance.client);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => WorkEvidenceQaReviewDialog(
          viewer: viewer,
          source: source,
          session: widget.qaReviewSession,
          workerName: _workerName,
        ),
      );
    } finally {
      if (mounted) setState(() => _reviewOpen = false);
    }
  }

  Future<void> _openQa() async {
    final repo = widget.repository;
    final actor = repo.attendance.source.userId;
    if (_qaOpening || _draft != null || !canUseSupervisedWorkEvidenceQa(repo)) {
      return;
    }
    setState(() => _qaOpening = true);
    try {
      await repo.load().timeout(const Duration(seconds: 20));
      if (!mounted ||
          !identical(repo, widget.repository) ||
          actor != repo.attendance.source.userId ||
          !canUseSupervisedWorkEvidenceQa(repo)) {
        return;
      }
      final draft = WorkEvidenceDraftController(
        session: _WorkerDraftSession(repo.attendance.source),
        assignmentId: supervisedWorkEvidenceQaAssignment,
        pickFiles: widget.pickDraftFiles,
      );
      setState(() => _draft = draft);
      try {
        final dependencies =
            widget.createQaDependencies?.call(draft) ??
            WorkEvidenceQaDependencies.supabase(draft);
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => Dialog(
            child: SizedBox(
              width: 640,
              height: MediaQuery.sizeOf(context).height * .9,
              child: WorkEvidenceQaPage(
                viewer: repo,
                draft: draft,
                dependencies: dependencies,
              ),
            ),
          ),
        );
      } finally {
        draft.dispose();
        if (mounted) setState(() => _draft = null);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'QA flow could not continue. If an action was started, stop and investigate manually. Nothing will be automatically retried.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _qaOpening = false);
    }
  }

  Future<void> _openDraft() async {
    final repo = widget.repository;
    if (repo.employer ||
        _qaOpening ||
        repo.assignment == null ||
        repo.loading ||
        repo.error != null ||
        _draft != null) {
      return;
    }
    final draft = WorkEvidenceDraftController(
      session: _WorkerDraftSession(repo.attendance.source),
      assignmentId: repo.assignment!.assignmentId,
      pickFiles: widget.pickDraftFiles,
    );
    setState(() => _draft = draft);
    try {
      await showWorkEvidenceDraft(context, draft);
    } finally {
      draft.dispose();
      if (mounted) setState(() => _draft = null);
    }
  }

  void _invalidateDraft() {
    final draft = _draft;
    // A dialog can outlive its underlying page when a direct URL changes.
    // Invalidate its context after tree updates, without notifying during dispose.
    if (draft != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        draft.changeAssignment('');
      });
    }
  }

  @override
  void initState() {
    super.initState();
    widget.repository.load();
  }

  @override
  void didUpdateWidget(covariant WorkEvidencePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      _invalidateDraft();
      widget.repository.load();
    }
  }

  @override
  void dispose() {
    _invalidateDraft();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.repository,
    builder: (context, _) {
      final repo = widget.repository;
      if (repo.assignment case final CompanyWorkAssignment row) {
        _resolveName(row);
      }
      final fallback = repo.employer
          ? AppRoutes.workVerification
          : AppRoutes.workAttendance;
      return AppWorkspace(
        title: 'Work Evidence',
        path: fallback,
        role: repo.employer ? 'employer' : 'job_seeker',
        focused: true,
        leading: MobileBackAction(fallback: fallback),
        actions: [
          IconButton(
            tooltip: 'Refresh evidence',
            onPressed: repo.loading ? null : repo.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: WorkspaceContent(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => returnToPage(context, fallback),
                  child: Text(
                    repo.employer
                        ? 'Back to Work Verification'
                        : 'Back to My Work Shifts',
                  ),
                ),
              ),
              Text(
                'Work evidence',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Evidence metadata only. Private files are not opened or downloaded here.',
              ),
              const Text('All times are Malaysia time (MYT, UTC+08:00).'),
              const SizedBox(height: 24),
              if (repo.loading)
                const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Loading work evidence',
                  ),
                )
              else if (repo.error != null)
                Semantics(
                  liveRegion: true,
                  child: ModuleState(
                    title: switch (repo.errorKind) {
                      WorkAttendanceError.permission =>
                        'Evidence access denied',
                      WorkAttendanceError.authentication => 'Sign in required',
                      _ => 'Unable to load evidence',
                    },
                    message: repo.error!,
                    action: repo.load,
                    actionLabel: 'Retry',
                  ),
                )
              else ...[
                if (repo.assignment != null)
                  WorkspaceCard(
                    title: repo.assignment!.jobTitle,
                    child: Text(
                      '${repo.employer ? (_workerName == null ? 'Assigned worker' : 'Worker: $_workerName') : 'Your work assignment'}'
                      '${repo.assignment!.checkInAt == null ? '' : '\nChecked in: ${_malaysiaTime(repo.assignment!.checkInAt!)}'}'
                      '${repo.assignment!.checkOutAt == null ? '' : '\nChecked out: ${_malaysiaTime(repo.assignment!.checkOutAt!)}'}',
                    ),
                  ),
                const SizedBox(height: 16),
                if (repo.employer && widget.mockReviewOperations != null)
                  MockWorkEvidenceReviewPanel(
                    key: ObjectKey(repo),
                    repository: repo,
                    operations: widget.mockReviewOperations!,
                  ),
                if (canReviewWorkEvidenceQa(repo)) ...[
                  OutlinedButton(
                    onPressed: _reviewOpen ? null : _openQaReview,
                    child: const Text('Review work (QA only)'),
                  ),
                  const SizedBox(height: 16),
                ],
                if (!repo.employer && repo.assignment != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: _draft == null && !_qaOpening
                          ? _openDraft
                          : null,
                      child: const Text('Prepare local evidence draft'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (canUseSupervisedWorkEvidenceQa(repo)) ...[
                    OutlinedButton(
                      onPressed: _draft == null && !_qaOpening ? _openQa : null,
                      child: const Text('Open supervised real QA submission'),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
                if (repo.awaitingFirstSubmission)
                  const ModuleState(
                    title: 'No evidence submitted yet',
                    message: 'The worker has not formally submitted evidence for this assignment. Refresh after the worker submits evidence.',
                  )
                else if (repo.evidence.isEmpty)
                  const ModuleState(
                    title: 'No work evidence',
                    message: 'No submitted evidence was returned for this assignment.',
                  )
                else
                  for (final file in repo.evidence)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _EvidenceCard(
                        file,
                        workerName: repo.employer ? _workerName : null,
                        onPreview: _previewOpen ? null : () => _preview(file),
                      ),
                    ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _WorkerDraftSession implements EvidenceDraftSession {
  _WorkerDraftSession(this.source);
  final WorkAttendanceSource source;
  @override
  String? get userId => source.userId;
  @override
  Stream<String?> get accountChanges => source.accountChanges;
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard(this.file, {this.workerName, this.onPreview});
  final WorkEvidence file;
  final String? workerName;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) => Card.outlined(
    key: ValueKey(file.evidenceId),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Submission round ${file.submissionRound}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(file.fileName, style: Theme.of(context).textTheme.titleLarge),
          Text('File type: ${file.mimeType}'),
          const SizedBox(height: 12),
          Text(file.description),
          const SizedBox(height: 12),
          Text(
            workerName == null
                ? 'Submitted by the assigned worker'
                : 'Submitted by: $workerName',
          ),
          Text('Submitted at: ${_malaysiaTime(file.submittedAt)}'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onPreview,
            icon: const Icon(Icons.visibility_outlined),
            label: Text(
              file.mimeType == 'application/pdf' ? 'View PDF' : 'View image',
            ),
          ),
        ],
      ),
    ),
  );
}

String _malaysiaTime(DateTime timestamp) {
  final time = timestamp.toUtc().add(const Duration(hours: 8));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.day)}/${two(time.month)}/${time.year} ${two(time.hour)}:${two(time.minute)} MYT';
}
