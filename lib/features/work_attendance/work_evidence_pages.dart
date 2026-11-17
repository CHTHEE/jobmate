import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/mobile_back_action.dart';
import '../applications/module2_widgets.dart';
import '../applications/resume_pdf_opener.dart';
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
import 'work_evidence_workflow.dart';
import 'work_evidence_workflow_panel.dart';
import 'work_evidence_deadline.dart';
import 'work_attendance_lifecycle.dart';
import 'work_evidence_upload_repository.dart';
import 'employer_work_evidence_summary.dart';
import 'work_attendance_gps.dart';
import 'work_shift_ui.dart';
import 'work_status_presentation.dart';

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
    this.previewOpener,
    this.loadWorkerName,
    this.workflowSource,
    this.createWorkflowUploads,
    this.returnToHistory = false,
  });
  final WorkEvidenceRepository repository;
  final bool returnToHistory;
  final Future<List<XFile>> Function()? pickDraftFiles;
  final MockWorkEvidenceReviewOperations? mockReviewOperations;
  final WorkEvidenceQaDependencies Function(WorkEvidenceDraftController)?
  createQaDependencies;
  final WorkEvidenceQaReviewSource Function()? createQaReviewSource;
  final WorkEvidenceQaReviewSession? qaReviewSession;
  final WorkEvidencePreviewRepository Function()? createPreviewRepository;
  final ResumePdfOpener? previewOpener;
  final WorkAssignmentNameLoader? loadWorkerName;
  final WorkEvidenceWorkflowSource? workflowSource;
  final WorkEvidenceUploadRepository Function(WorkEvidenceDraftController)?
  createWorkflowUploads;

  @override
  State<WorkEvidencePage> createState() => _WorkEvidencePageState();
}

class _WorkEvidencePageState extends State<WorkEvidencePage> {
  WorkEvidenceDraftController? _draft;
  bool _qaOpening = false;
  bool _reviewOpen = false;
  bool _previewOpen = false;
  bool _gpsOpen = false;
  Future<void> _viewGps() async {
    final viewer = widget.repository;
    final source = viewer.attendance.source;
    if (_gpsOpen ||
        !viewer.employer ||
        viewer.loading ||
        viewer.error != null ||
        viewer.assignment == null ||
        source is! SupabaseWorkAttendanceSource) {
      return;
    }
    final repository = WorkAttendanceGpsRepository(
      SupabaseWorkAttendanceGpsSource(source.client),
      viewer.companyId!,
      viewer.assignmentId,
    );
    setState(() => _gpsOpen = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => WorkAttendanceGpsDialog(repository: repository),
      );
    } finally {
      repository.dispose();
      if (mounted) setState(() => _gpsOpen = false);
    }
  }

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
    final opener = widget.previewOpener ?? createResumePdfOpener();
    // Reserve during the click, before any authorized metadata/signing awaits.
    final reserved = file.mimeType == 'application/pdf' && opener.isWeb
        ? opener.reserve()
        : null;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => WorkEvidencePreviewDialog(
          viewer: widget.repository,
          evidenceId: file.evidenceId,
          repository: repo,
          opener: opener,
          autoOpen: file.mimeType == 'application/pdf',
          reservedWindow: reserved,
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
      final workflow =
          widget.workflowSource ??
          (repo.attendance.source is SupabaseWorkAttendanceSource
              ? SupabaseWorkEvidenceWorkflowSource(
                  (repo.attendance.source as SupabaseWorkAttendanceSource)
                      .client,
                )
              : null);
      final rounds =
          repo.evidence.map((file) => file.submissionRound).toSet().toList()
            ..sort((a, b) => b.compareTo(a));
      if (repo.assignment case final CompanyWorkAssignment row) {
        _resolveName(row);
      }
      final fallback = repo.employer
          ? AppRoutes.workVerification
          : widget.returnToHistory
          ? AppRoutes.attendanceHistory
          : AppRoutes.workAttendance;
      final employerTitle =
          repo.assignment?.verificationStatus == WorkVerificationStatus.verified
          ? 'Work Verification Details'
          : repo.assignment?.verificationStatus ==
                WorkVerificationStatus.pendingReview
          ? 'Review Work Evidence'
          : 'Work Evidence';
      return AppWorkspace(
        title: repo.employer ? employerTitle : 'Work Evidence',
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
                        : widget.returnToHistory
                        ? 'Back to Attendance History'
                        : 'Back to My Work Shifts',
                  ),
                ),
              ),
              Text(
                repo.employer ? employerTitle : 'Work evidence',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                repo.employer
                    ? 'Review attendance, private evidence and recorded verification results.'
                    : 'Open submitted PDFs and images through authorized private previews.',
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
                if (repo.employer && repo.assignment != null)
                  EmployerWorkEvidenceSummary(
                    assignment: repo.assignment!,
                    workerName: _workerName,
                    onGps:
                        !_gpsOpen &&
                            repo.attendance.source
                                is SupabaseWorkAttendanceSource
                        ? _viewGps
                        : null,
                  )
                else if (repo.assignment != null)
                  WorkspaceCard(
                    title: repo.assignment!.jobTitle,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Your work assignment'),
                        AttendanceStatusBadge(
                          label:
                              'Verification: ${workVerificationStatusLabel(repo.assignment!.verificationStatus)}',
                          tone: verificationTone(
                            repo.assignment!.verificationStatus,
                          ),
                        ),
                        AttendanceLifecycleNotice(
                          assignment: repo.assignment!,
                          employer: repo.employer,
                        ),
                        Text(
                          'Scheduled: ${_malaysiaTime(repo.assignment!.scheduledStart)} to ${_malaysiaTime(repo.assignment!.scheduledEnd)}',
                        ),
                        Text(
                          'Workplace: ${repo.assignment!.workplaceLocation}',
                        ),
                        if (repo.assignment!.verificationStatus ==
                                WorkVerificationStatus.verified &&
                            workflow == null)
                          const Text(
                            'No submission required. Work verification does not confirm payment.',
                          )
                        else if ((workflow == null ||
                                repo.assignmentId ==
                                    supervisedWorkEvidenceQaAssignment) &&
                            repo.assignment!.effectiveCheckOutAt != null)
                          EvidenceDeadlineSummary(assignment: repo.assignment!),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                if (workflow != null &&
                    repo.assignment != null &&
                    repo.assignmentId != supervisedWorkEvidenceQaAssignment)
                  WorkEvidenceWorkflowPanel(
                    key: ValueKey((repo, repo.attendance.source.userId)),
                    viewer: repo,
                    workerName: _workerName,
                    source: workflow,
                    pickFiles: widget.pickDraftFiles,
                    createUploads: widget.createWorkflowUploads,
                  ),
                if (repo.employer && widget.mockReviewOperations != null)
                  MockWorkEvidenceReviewPanel(
                    key: ObjectKey(repo),
                    repository: repo,
                    operations: widget.mockReviewOperations!,
                  ),
                if (workflow == null && canReviewWorkEvidenceQa(repo)) ...[
                  OutlinedButton(
                    onPressed: _reviewOpen ? null : _openQaReview,
                    child: const Text('Review work (QA only)'),
                  ),
                  const SizedBox(height: 16),
                ],
                if (workflow == null &&
                    !repo.employer &&
                    repo.assignment != null) ...[
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
                else ...[
                  _EvidenceRound(
                    round: rounds.first,
                    files: repo.evidence
                        .where((f) => f.submissionRound == rounds.first)
                        .toList(),
                    latest: true,
                    employer: repo.employer,
                    workerName: repo.employer ? _workerName : null,
                    onPreview: _previewOpen ? null : _preview,
                  ),
                  if (rounds.length > 1)
                    ExpansionTile(
                      title: Text('Earlier submissions (${rounds.length - 1})'),
                      subtitle: const Text(
                        'Previous files remain available for reference',
                      ),
                      children: [
                        for (final round in rounds.skip(1))
                          _EvidenceRound(
                            round: round,
                            files: repo.evidence
                                .where((f) => f.submissionRound == round)
                                .toList(),
                            latest: false,
                            employer: repo.employer,
                            workerName: repo.employer ? _workerName : null,
                            onPreview: _previewOpen ? null : _preview,
                          ),
                      ],
                    ),
                ],
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
  const _EvidenceCard(
    this.file, {
    required this.label,
    this.onPreview,
    this.employer = false,
  });
  final WorkEvidence file;
  final String label;
  final VoidCallback? onPreview;
  final bool employer;

  @override
  Widget build(BuildContext context) => Card.outlined(
    key: ValueKey(file.evidenceId),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                file.mimeType == 'application/pdf'
                    ? Icons.picture_as_pdf_outlined
                    : Icons.image_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              child: OutlinedButton.icon(
                onPressed: onPreview,
                icon: const Icon(Icons.visibility_outlined),
                label: Text(
                  file.mimeType == 'application/pdf'
                      ? 'View PDF'
                      : 'View image',
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _malaysiaTime(DateTime timestamp) {
  return '${shiftDateLabel(timestamp)} ${shiftTimeLabel(timestamp)} MYT';
}

class _EvidenceRound extends StatelessWidget {
  const _EvidenceRound({
    required this.round,
    required this.files,
    required this.latest,
    this.workerName,
    this.onPreview,
    this.employer = false,
  });
  final int round;
  final List<WorkEvidence> files;
  final bool latest;
  final String? workerName;
  final ValueChanged<WorkEvidence>? onPreview;
  final bool employer;
  @override
  Widget build(BuildContext context) {
    var pdf = 0, image = 0;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            latest
                ? 'Latest submission - Round $round'
                : 'Submission round $round',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (files.isNotEmpty) ...[
            const SizedBox(height: 8),
            if (employer && files.first.description.trim().isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ColorScheme.fromSeed(
                    seedColor: Colors.lightBlue,
                    brightness: Theme.of(context).brightness,
                  ).primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Worker note',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      files.first.description,
                      style: TextStyle(
                        color: ColorScheme.fromSeed(
                          seedColor: Colors.lightBlue,
                          brightness: Theme.of(context).brightness,
                        ).onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              )
            else if (!employer)
              Text(files.first.description),
            const SizedBox(height: 8),
            Text(
              '${workerName == null ? 'Submitted by the assigned worker' : 'Submitted by: $workerName'} - ${employer ? '${shiftDateLabel(files.first.submittedAt)} ${shiftTimeLabel(files.first.submittedAt)} MYT' : _malaysiaTime(files.first.submittedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          if (employer && workerName == null && files.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Submission audit identity'),
              children: [SelectableText(files.first.submittedBy)],
            ),
          if (employer)
            Text('${files.length} ${files.length == 1 ? 'file' : 'files'}'),
          for (final file in files)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _EvidenceCard(
                file,
                employer: employer,
                label:
                    safeEvidenceDisplayName(file.fileName) ??
                    (file.mimeType == 'application/pdf'
                        ? 'Evidence PDF ${++pdf}'
                        : 'Evidence Image ${++image}'),
                onPreview: onPreview == null ? null : () => onPreview!(file),
              ),
            ),
        ],
      ),
    );
    return employer
        ? Card.outlined(
            child: Padding(padding: const EdgeInsets.all(12), child: content),
          )
        : content;
  }
}
