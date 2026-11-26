import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../jobs/job_postings_repository.dart';
import 'work_assignment_creation_repository.dart';
import 'work_assignment_people.dart';
import 'work_attendance_models.dart';
import 'work_attendance_repository.dart';
import 'work_completion_report_data.dart';
import 'work_evidence_workflow.dart';

enum WorkCompletionReportFailure { ineligible, unavailable, incomplete, retry }

sealed class WorkCompletionReportResult {
  const WorkCompletionReportResult();
}

final class WorkCompletionReportReady extends WorkCompletionReportResult {
  const WorkCompletionReportReady(this.data);
  final WorkCompletionReportData data;
}

final class WorkCompletionReportUnavailable extends WorkCompletionReportResult {
  const WorkCompletionReportUnavailable(this.reason);
  final WorkCompletionReportFailure reason;
}

typedef ReportReadScope = ({String? actorId, String? companyId});
typedef ReportDisplayDetails = ({String? workerName, String? employmentType});

abstract interface class WorkCompletionReportSource {
  ReportReadScope get scope;

  /// Emits session or company changes, including when a selection switches back.
  Stream<void> get scopeChanges;
  Future<String?> activeRole(String actorId);
  Future<JobAccess> companyAccess(String companyId);
  Future<List<Map<String, dynamic>>> assignments(String? companyId);
  Future<Object?> workflow(String assignmentId);
  Future<List<Map<String, dynamic>>> evidence(String assignmentId);
  Future<ReportDisplayDetails> displayDetails(
    WorkAssignment assignment,
    ReportReadScope scope,
  );
}

class SupabaseWorkCompletionReportSource implements WorkCompletionReportSource {
  SupabaseWorkCompletionReportSource(
    this.client, {
    required this.selectedCompanyId,
    required this.companyChanges,
  }) : _attendance = SupabaseWorkAttendanceSource(client),
       _workflow = SupabaseWorkEvidenceWorkflowSource(client);

  final SupabaseClient client;
  final String? Function() selectedCompanyId;
  final Stream<void> companyChanges;
  final SupabaseWorkAttendanceSource _attendance;
  final SupabaseWorkEvidenceWorkflowSource _workflow;

  @override
  ReportReadScope get scope =>
      (actorId: _attendance.userId, companyId: selectedCompanyId());

  @override
  Stream<void> get scopeChanges {
    late StreamSubscription<String?> accounts;
    late StreamSubscription<void> companies;
    var actor = _attendance.userId;
    final events = StreamController<void>(
      sync: true,
      onCancel: () async {
        await Future.wait([accounts.cancel(), companies.cancel()]);
      },
    );
    events.onListen = () {
      accounts = _attendance.accountChanges.listen((id) {
        if (actor == id) return;
        actor = id;
        events.add(null);
      }, onError: events.addError);
      companies = companyChanges.listen(
        (_) => events.add(null),
        onError: events.addError,
      );
    };
    return events.stream;
  }

  @override
  Future<String?> activeRole(String actorId) async {
    final row = await client
        .from('users')
        .select('role, status')
        .eq('user_id', actorId)
        .maybeSingle();
    return row != null && row['status'] == 'active'
        ? row['role'] as String?
        : null;
  }

  @override
  Future<JobAccess> companyAccess(String companyId) => JobPostingsRepository(
    client,
    companyContext: companyId,
  ).loadAccess(includeLogo: false);

  @override
  Future<List<Map<String, dynamic>>> assignments(String? companyId) =>
      companyId == null
      ? _attendance.listMyAssignments()
      : _attendance.listCompanyAssignments(companyId);

  @override
  Future<Object?> workflow(String assignmentId) => _workflow.call(
    'work_evidence_workflow_context',
    {'p_assignment_id': assignmentId},
  );

  @override
  Future<List<Map<String, dynamic>>> evidence(String assignmentId) =>
      _attendance.listEvidence(assignmentId);

  @override
  Future<ReportDisplayDetails> displayDetails(
    WorkAssignment assignment,
    ReportReadScope scope,
  ) async {
    final companyId = scope.companyId;
    final workerName = await _optional(() async {
      if (assignment is CompanyWorkAssignment && companyId != null) {
        final source = SupabaseWorkAssignmentCreationSource(
          client,
          companyContext: companyId,
        );
        return WorkAssignmentPeopleRepository(source)
            .workerName(assignment, companyId);
      }
      final row = await client
          .from('users')
          .select('name')
          .eq('user_id', scope.actorId!)
          .maybeSingle();
      return row?['name'] as String?;
    });
    final employmentType = await _optional(() async {
      final String jobCompany;
      final List<dynamic> jobs;
      if (assignment is WorkerWorkAssignment) {
        jobCompany = assignment.companyId;
        jobs = await client
            .rpc<List<dynamic>>('list_published_jobs')
            .eq('job_id', assignment.jobId)
            .eq('company_id', jobCompany);
      } else {
        jobCompany = companyId!;
        jobs = await JobPostingsRepository(
          client,
          companyContext: jobCompany,
        ).list(jobCompany);
      }
      final matching = jobs
          .whereType<Map>()
          .where(
            (job) =>
                job['job_id'] == assignment.jobId &&
                job['company_id'] == jobCompany,
          )
          .toList();
      return matching.length == 1
          ? matching.single['employment_type'] as String?
          : null;
    });
    return (workerName: workerName, employmentType: employmentType);
  }
}

Future<T?> _optional<T>(Future<T?> Function() read) async {
  try {
    return await read();
  } on Exception {
    return null;
  } on TypeError {
    return null;
  }
}

/// Stateless loader. A caller that holds a result must clear it on scope
/// changes and discard superseded requests. Preview and export both call load.
/// Only assignment and verification states govern dispute eligibility here.
/// A generated report does not establish whether separate cases exist.
class WorkCompletionReportRepository {
  WorkCompletionReportRepository(this.source, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final WorkCompletionReportSource source;
  final DateTime Function() _clock;

  Future<WorkCompletionReportResult> load(String assignmentId) async {
    final scope = source.scope;
    final employer = scope.companyId != null;
    var invalidated = false;
    final changes = source.scopeChanges.listen(
      (_) => invalidated = true,
      onError: (Object _) => invalidated = true,
    );
    bool current() => !invalidated && source.scope == scope;
    void requireCurrent() {
      if (!current()) throw WorkCompletionReportFailure.unavailable;
    }

    try {
      final id = _requestId(assignmentId);
      final actor = _requestId(scope.actorId);
      final company = employer ? _requestId(scope.companyId) : null;

      Future<String?> authorize() async {
        final role = await source.activeRole(actor);
        requireCurrent();
        if (role != (employer ? 'employer' : 'job_seeker')) {
          throw WorkCompletionReportFailure.unavailable;
        }
        if (company == null) return null;
        final access = await source.companyAccess(company);
        requireCurrent();
        if (!access.allowed || access.company?['company_id'] != company) {
          throw WorkCompletionReportFailure.unavailable;
        }
        return _requiredText(access.company?['company_name']);
      }

      Future<WorkAssignment> assignment() async {
        final rows = await source.assignments(company);
        requireCurrent();
        return _selectAssignment(rows, id, actor, company);
      }

      Future<WorkEvidenceHistoryEvent> verification(WorkAssignment row) async {
        final raw = await source.workflow(id);
        requireCurrent();
        return _verifiedEvent(raw, row, employer);
      }

      final companyName = await authorize();
      final row = await assignment();
      _checkAttendance(row);
      final verified = await verification(row);
      final evidence = await source.evidence(id);
      requireCurrent();
      final files = _submittedFiles(evidence, row, verified.round!, actor);
      final display = await _optional(() => source.displayDetails(row, scope));
      requireCurrent();
      final finalCompanyName = await authorize();
      final latest = await assignment();
      _checkAttendance(latest);
      final latestEvent = await verification(latest);
      if (_assignmentFacts(row) != _assignmentFacts(latest) ||
          _eventFacts(verified) != _eventFacts(latestEvent) ||
          companyName != finalCompanyName) {
        throw WorkCompletionReportFailure.incomplete;
      }

      return WorkCompletionReportReady(
        WorkCompletionReportData(
          generatedAt: _clock().toUtc(),
          jobTitle: _requiredText(row.jobTitle),
          companyName:
              companyName ??
              _requiredText((row as WorkerWorkAssignment).companyName),
          workerName: _nonblank(display?.workerName),
          employmentType: display?.employmentType,
          workplaceLocation: _requiredText(row.workplaceLocation),
          scheduledStart: row.scheduledStart,
          scheduledEnd: row.scheduledEnd,
          checkInAt: row.effectiveCheckInAt!,
          checkOutAt: row.effectiveCheckOutAt!,
          attendanceSource: row.resolution?.decision == 'corrected'
              ? ReportAttendanceSource.corrected
              : ReportAttendanceSource.original,
          checkInLocation: _location(
            row.checkInAt,
            row.resolution?.originalCheckInLocationStatus,
          ),
          checkOutLocation: _location(
            row.checkOutAt,
            row.resolution?.originalCheckOutLocationStatus,
          ),
          verifiedRound: verified.round!,
          submittedFileCount: files.length,
          submittedDescriptions: files.map((file) => file.description),
          verifiedAt: row.verifiedAt!,
        ),
      );
    } on WorkCompletionReportFailure catch (failure) {
      return WorkCompletionReportUnavailable(
        current() ? failure : WorkCompletionReportFailure.unavailable,
      );
    } on AuthException {
      return const WorkCompletionReportUnavailable(
        WorkCompletionReportFailure.unavailable,
      );
    } on PostgrestException catch (error) {
      final reason = switch (error.code) {
        'PGRST116' ||
        '42501' ||
        '28000' ||
        'PGRST301' ||
        'PGRST303' => WorkCompletionReportFailure.unavailable,
        'PGRST202' => WorkCompletionReportFailure.incomplete,
        _ => WorkCompletionReportFailure.retry,
      };
      return WorkCompletionReportUnavailable(
        current() ? reason : WorkCompletionReportFailure.unavailable,
      );
    } catch (error) {
      return WorkCompletionReportUnavailable(
        !current()
            ? WorkCompletionReportFailure.unavailable
            : error is FormatException || error is TypeError
            ? WorkCompletionReportFailure.incomplete
            : WorkCompletionReportFailure.retry,
      );
    } finally {
      await changes.cancel();
    }
  }
}

String _requestId(String? value) {
  try {
    return workUuid(value);
  } on FormatException {
    throw WorkCompletionReportFailure.unavailable;
  }
}

String? _nonblank(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();

String _requiredText(Object? value) {
  final text = value is String ? _nonblank(value) : null;
  if (text == null) throw const FormatException('Missing report field');
  return text;
}

WorkAssignment _selectAssignment(
  List<Map<String, dynamic>> rows,
  String id,
  String actor,
  String? company,
) {
  final matches = rows
      .where((row) => (row['assignment_id'] as String?)?.toLowerCase() == id)
      .toList();
  if (matches.isEmpty) throw WorkCompletionReportFailure.unavailable;
  if (matches.length != 1) throw const FormatException('Ambiguous assignment');
  final row = matches.single;
  // Existing worker and company projections omit the counterparty scope key
  // because the RPC supplies it. Validate the key if a projection includes it.
  if ((company == null &&
          row.containsKey('worker_id') &&
          workUuid(row['worker_id']) != actor) ||
      (company != null &&
          row.containsKey('company_id') &&
          workUuid(row['company_id']) != company)) {
    throw WorkCompletionReportFailure.unavailable;
  }
  return company == null
      ? WorkerWorkAssignment.fromJson(row)
      : CompanyWorkAssignment.fromJson(row);
}

void _checkAttendance(WorkAssignment row) {
  if (row.assignmentStatus != WorkAssignmentStatus.completed ||
      row.verificationStatus != WorkVerificationStatus.verified ||
      row.resolution?.decision == 'confirmed_absent') {
    throw WorkCompletionReportFailure.ineligible;
  }
  final input = row.effectiveCheckInAt;
  final output = row.effectiveCheckOutAt;
  if (row.verifiedAt == null ||
      !row.scheduledEnd.isAfter(row.scheduledStart) ||
      input == null ||
      output == null ||
      output.isBefore(input)) {
    throw const FormatException('Incomplete verified attendance');
  }
}

WorkEvidenceHistoryEvent _verifiedEvent(
  Object? raw,
  WorkAssignment row,
  bool employer,
) {
  if (raw is Map && raw['viewer_role'] != (employer ? 'employer' : 'worker')) {
    throw WorkCompletionReportFailure.unavailable;
  }
  final workflow = WorkEvidenceWorkflowSnapshot(
    raw,
    row.assignmentId,
    employer,
  );
  final events = workflow.history.where((event) => event.action == 'verified');
  if (workflow.assignmentStatus != row.assignmentStatus ||
      workflow.verificationStatus != row.verificationStatus ||
      !workflow.attendanceComplete ||
      workflow.round < 1 ||
      events.length != 1 ||
      events.single.round != workflow.round) {
    // The legacy null-round event has no authoritative link to a submission.
    throw const FormatException('Unconfirmed verified round');
  }
  final event = events.single;
  final review = workflow.review;
  if (review != null &&
      (review['state'] != 'committed' ||
          review['decision'] != 'verified' ||
          review['history_id'] != event.id ||
          review['actor_id'] != event.actorId)) {
    throw const FormatException('Inconsistent review linkage');
  }
  return event;
}

List<WorkEvidence> _submittedFiles(
  List<Map<String, dynamic>> evidence,
  WorkAssignment row,
  int round,
  String actor,
) {
  final worker = row is CompanyWorkAssignment ? row.workerId : actor;
  final files = <WorkEvidence>[];
  final ids = <String>{};
  final paths = <String>{};
  for (final record in evidence) {
    final file = WorkEvidence.fromJson(record);
    if (file.submittedBy != worker ||
        (record.containsKey('assignment_id') &&
            workUuid(record['assignment_id']) != row.assignmentId)) {
      throw WorkCompletionReportFailure.unavailable;
    }
    if (file.submissionRound > round ||
        !file.storagePath.startsWith('${row.assignmentId}/') ||
        !ids.add(file.evidenceId) ||
        !paths.add(file.storagePath)) {
      throw const FormatException('Inconsistent evidence metadata');
    }
    if (file.submissionRound == round) files.add(file);
  }
  if (files.isEmpty || files.length > 5) {
    throw const FormatException('Incomplete verified submission');
  }
  return files;
}

ReportAttendanceLocation _location(DateTime? event, String? status) => (
  originalEventAt: event,
  status: switch (status) {
    'granted' => ReportLocationStatus.granted,
    'denied' => ReportLocationStatus.denied,
    'unavailable' => ReportLocationStatus.unavailable,
    _ => event == null ? ReportLocationStatus.notRecorded : null,
  },
);

Object _assignmentFacts(WorkAssignment row) => (
  row.assignmentId,
  row.applicationId,
  row.jobId,
  row.jobTitle,
  row.scheduledStart,
  row.scheduledEnd,
  row.workplaceLocation,
  row.assignmentStatus,
  row.verificationStatus,
  row.verifiedAt,
  row.checkInAt,
  row.checkOutAt,
  row.effectiveCheckInAt,
  row.effectiveCheckOutAt,
  row.resolution?.decision,
  row.resolution?.requestId,
  row.resolution?.originalCheckInLocationStatus,
  row.resolution?.originalCheckOutLocationStatus,
  switch (row) {
    WorkerWorkAssignment() => (row.companyId, row.companyName),
    CompanyWorkAssignment() => row.workerId,
  },
);

Object _eventFacts(WorkEvidenceHistoryEvent event) =>
    (event.id, event.round, event.actorId, event.at);
