import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_page.dart';
import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../applications/module2_widgets.dart';
import '../jobs/job_postings_repository.dart';
import 'work_attendance_models.dart';
import 'work_attendance_repository.dart';
import 'work_verification_pages.dart';
import 'work_evidence_pages.dart';
import 'work_evidence_repository.dart';

/// Company identity comes exclusively from the existing account access loader.
/// Neither path parameters nor query parameters participate in company selection.
GoRoute workVerificationRoute({
  WorkAttendanceSource? source,
  Future<bool> Function()? checkAccess,
  Future<JobAccess> Function()? loadCompanyAccess,
  bool evidence = false,
}) => GoRoute(
  path: evidence
      ? AppRoutes.workVerificationEvidence
      : AppRoutes.workVerification,
  pageBuilder: (_, state) => appPage(
    state,
    _EmployerAccess(
      source: source,
      checkAccess: checkAccess,
      loadCompanyAccess: loadCompanyAccess,
      assignmentId: evidence ? state.pathParameters['assignmentId'] : null,
    ),
  ),
);

class _EmployerAccess extends StatefulWidget {
  const _EmployerAccess({
    this.source,
    this.checkAccess,
    this.loadCompanyAccess,
    this.assignmentId,
  });
  final String? assignmentId;
  final WorkAttendanceSource? source;
  final Future<bool> Function()? checkAccess;
  final Future<JobAccess> Function()? loadCompanyAccess;
  @override
  State<_EmployerAccess> createState() => _EmployerAccessState();
}

class _EmployerAccessState extends State<_EmployerAccess> {
  late final source =
      widget.source ?? SupabaseWorkAttendanceSource(Supabase.instance.client);
  late final loadAccess =
      widget.loadCompanyAccess ??
      JobPostingsRepository(Supabase.instance.client).loadAccess;
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
      key: ValueKey(widget.assignmentId),
      source: source,
      loadAccess: loadAccess,
      assignmentId: widget.assignmentId,
    ),
  );
}

class _CompanyAssignments extends StatefulWidget {
  const _CompanyAssignments({
    super.key,
    required this.source,
    required this.loadAccess,
    this.assignmentId,
  });
  final String? assignmentId;
  final WorkAttendanceSource source;
  final Future<JobAccess> Function() loadAccess;
  @override
  State<_CompanyAssignments> createState() => _CompanyAssignmentsState();
}

class _CompanyAssignmentsState extends State<_CompanyAssignments> {
  late final repository = WorkAttendanceRepository(widget.source);
  late Future<String> company = _resolveCompany();
  WorkEvidenceRepository? evidence;

  Future<String> _resolveCompany() async {
    final actor = widget.source.userId;
    if (actor == null) throw const AuthException('Authentication required');
    // maybeSingle in loadAccess fails closed on multiple memberships.
    final access = await widget.loadAccess();
    if (!mounted || widget.source.userId != actor) {
      throw const AuthException('Account changed');
    }
    if (!access.allowed) {
      throw StateError(access.message ?? 'Company access is denied.');
    }
    return workUuid(access.company?['company_id']);
  }

  @override
  void dispose() {
    evidence?.dispose();
    repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: company,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        if (widget.assignmentId != null) {
          evidence ??= WorkEvidenceRepository.employer(
            repository,
            assignmentId: widget.assignmentId!,
            companyId: snapshot.data!,
            loadCompanyAccess: widget.loadAccess,
          );
          return WorkEvidencePage(repository: evidence!);
        }
        return WorkVerificationPage(
          repository: repository,
          companyId: snapshot.data!,
          loadAccess: widget.loadAccess,
        );
      }
      final failure = snapshot.error;
      return AppWorkspace(
        title: 'Work Verification',
        path: AppRoutes.workVerification,
        role: 'employer',
        child: WorkspaceContent(
          child: snapshot.connectionState != ConnectionState.done
              ? const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Checking company access',
                  ),
                )
              : ModuleState(
                  title: 'Company access unavailable',
                  message: failure is StateError
                      ? failure.message.toString()
                      : failure is PostgrestException &&
                            failure.code == 'PGRST116'
                      ? 'Company access could not be resolved uniquely. Review your company membership before continuing.'
                      : failure is FormatException
                      ? 'Company access did not return a valid company ID.'
                      : 'Unable to resolve authorized company access. Sign in again or retry.',
                  action: () => setState(() {
                    company = _resolveCompany();
                    // The builder subscribes on the next frame. An immediate
                    // denial must already have an error listener meanwhile.
                    company.ignore();
                  }),
                  actionLabel: 'Retry',
                ),
        ),
      );
    },
  );
}
