import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_page.dart';
import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/mobile_back_action.dart';
import '../applications/module2_widgets.dart';
import '../jobs/job_postings_repository.dart';
import 'work_attendance_models.dart';
import 'work_attendance_repository.dart';
import 'work_completion_report_page.dart';
import 'work_completion_report_repository.dart';
import 'work_verification_pages.dart';
import 'work_verification_loading.dart';
import 'work_evidence_pages.dart';
import 'work_evidence_repository.dart';

/// The existing account access loader authorizes the selected company.
/// A report push can carry a company selection from the evidence page.
GoRoute workVerificationRoute({
  WorkAttendanceSource? source,
  Future<bool> Function()? checkAccess,
  Future<JobAccess> Function()? loadCompanyAccess,
  bool evidence = false,
  bool report = false,
  WorkCompletionReportRepository Function(String companyId)? createReport,
}) => GoRoute(
  path: report
      ? AppRoutes.workVerificationReport
      : evidence
      ? AppRoutes.workVerificationEvidence
      : AppRoutes.workVerification,
  pageBuilder: (_, state) => appPage(
    state,
    _EmployerAccess(
      source: source,
      checkAccess: checkAccess,
      loadCompanyAccess: loadCompanyAccess,
      assignmentId: evidence || report
          ? state.pathParameters['assignmentId']
          : null,
      jobId: evidence || report ? null : state.uri.queryParameters['job'],
      report: report,
      createReport: createReport,
      reportCompany: report && state.extra is String
          ? state.extra as String
          : null,
    ),
  ),
);

class _EmployerAccess extends StatefulWidget {
  const _EmployerAccess({
    this.source,
    this.checkAccess,
    this.loadCompanyAccess,
    this.assignmentId,
    this.jobId,
    this.report = false,
    this.createReport,
    this.reportCompany,
  });
  final String? assignmentId;
  final String? jobId;
  final bool report;
  final WorkCompletionReportRepository Function(String companyId)? createReport;
  final String? reportCompany;
  final WorkAttendanceSource? source;
  final Future<bool> Function()? checkAccess;
  final Future<JobAccess> Function()? loadCompanyAccess;
  @override
  State<_EmployerAccess> createState() => _EmployerAccessState();
}

class _EmployerAccessState extends State<_EmployerAccess> {
  late final source =
      widget.source ?? SupabaseWorkAttendanceSource(Supabase.instance.client);
  Future<JobAccess> _loadAccess() async {
    final selected = widget.reportCompany;
    final companyId = selected == null ? null : workUuid(selected);
    final access =
        await (widget.loadCompanyAccess?.call() ??
            JobPostingsRepository(
              Supabase.instance.client,
              companyContext: companyId,
            ).loadAccess(
              includeLogo: !widget.report && widget.assignmentId != null,
            ));
    if (companyId != null && access.company?['company_id'] != companyId) {
      throw const FormatException('Company context changed.');
    }
    return access;
  }

  late final StreamSubscription<String?> subscription;

  @override
  void initState() {
    super.initState();
    subscription = source.accountChanges.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Module2Gate(
    key: ValueKey(source.userId),
    role: 'employer',
    checkAccess: source.userId == null ? () async => false : widget.checkAccess,
    child: _CompanyAssignments(
      key: ValueKey((widget.assignmentId, widget.reportCompany)),
      source: source,
      loadAccess: _loadAccess,
      assignmentId: widget.assignmentId,
      jobId: widget.jobId,
      report: widget.report,
      createReport: widget.createReport,
    ),
  );
}

class _CompanyAssignments extends StatefulWidget {
  const _CompanyAssignments({
    super.key,
    required this.source,
    required this.loadAccess,
    this.assignmentId,
    this.jobId,
    this.report = false,
    this.createReport,
  });
  final String? assignmentId;
  final String? jobId;
  final bool report;
  final WorkCompletionReportRepository Function(String companyId)? createReport;
  final WorkAttendanceSource source;
  final Future<JobAccess> Function() loadAccess;
  @override
  State<_CompanyAssignments> createState() => _CompanyAssignmentsState();
}

class _CompanyAssignmentsState extends State<_CompanyAssignments> {
  late final repository = WorkAttendanceRepository(widget.source);
  late Future<({String id, JobAccess access})> company = _resolveCompany();
  WorkEvidenceRepository? evidence;
  WorkCompletionReportRepository? reportRepository;

  Future<({String id, JobAccess access})> _resolveCompany() async {
    final actor = widget.source.userId;
    final session = repository.sessionGeneration;
    if (actor == null) throw const AuthException('Authentication required');
    // maybeSingle in loadAccess fails closed on multiple memberships.
    final access = await widget.loadAccess();
    if (!mounted ||
        widget.source.userId != actor ||
        repository.sessionGeneration != session) {
      throw const AuthException('Account changed');
    }
    if (!access.allowed) {
      throw StateError(access.message ?? 'Company access is denied.');
    }
    return (id: workUuid(access.company?['company_id']), access: access);
  }

  @override
  void dispose() {
    evidence?.dispose();
    repository.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<({String id, JobAccess access})>(
    future: company,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        if (widget.report) {
          final companyId = snapshot.data!.id;
          reportRepository ??=
              widget.createReport?.call(companyId) ??
              WorkCompletionReportRepository(
                SupabaseWorkCompletionReportSource(
                  Supabase.instance.client,
                  selectedCompanyId: () => companyId,
                  companyChanges: const Stream.empty(),
                ),
              );
          return WorkCompletionReportPage(
            assignmentId: widget.assignmentId!,
            repository: reportRepository!,
            fallback: AppRoutes.workVerification,
            employer: true,
          );
        }
        if (widget.assignmentId != null) {
          evidence ??= WorkEvidenceRepository.employer(
            repository,
            assignmentId: widget.assignmentId!,
            companyId: snapshot.data!.id,
            loadCompanyAccess: widget.loadAccess,
          );
          return WorkEvidencePage(repository: evidence!);
        }
        return WorkVerificationPage(
          repository: repository,
          companyId: snapshot.data!.id,
          initialAccess: snapshot.data!.access,
          loadAccess: widget.loadAccess,
          jobId: widget.jobId,
          overview: widget.jobId == null,
        );
      }
      final failure = snapshot.error;
      final loading = snapshot.connectionState != ConnectionState.done;
      if (loading && !widget.report && widget.assignmentId == null) {
        return const AppWorkspace(
          title: 'Work Management',
          path: AppRoutes.workVerification,
          role: 'employer',
          child: WorkVerificationLoading(),
        );
      }
      final status = snapshot.connectionState != ConnectionState.done
          ? const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Checking company access',
              ),
            )
          : ModuleState(
              title: widget.report
                  ? 'Report unavailable'
                  : 'Company access unavailable',
              message: widget.report
                  ? 'The company context for this report could not be confirmed.'
                  : failure is StateError
                  ? failure.message.toString()
                  : failure is PostgrestException && failure.code == 'PGRST116'
                  ? 'Company access could not be resolved uniquely. Review your company membership before continuing.'
                  : failure is FormatException
                  ? 'Company access did not return a valid company ID.'
                  : 'Unable to resolve authorized company access. Sign in again or retry.',
              action: () => setState(() {
                company = _resolveCompany();
                // Attach a listener before the builder subscribes next frame.
                company.ignore();
              }),
              actionLabel: 'Retry',
            );
      return AppWorkspace(
        title: 'Work Verification',
        path: AppRoutes.workVerification,
        role: 'employer',
        focused: widget.report,
        leading: widget.report
            ? const MobileBackAction(fallback: AppRoutes.workVerification)
            : null,
        child: WorkspaceContent(
          centered: true,
          child: widget.report
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton(
                      onPressed: () =>
                          returnToPage(context, AppRoutes.workVerification),
                      child: const Text('Back'),
                    ),
                    status,
                  ],
                )
              : status,
        ),
      );
    },
  );
}
