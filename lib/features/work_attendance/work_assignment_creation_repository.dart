import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../applications/my_applications_repository.dart';
import '../jobs/job_postings_repository.dart';
import 'work_attendance_models.dart';

/// Rows plus a required completeness signal; null/mismatched totals fail closed.
/// These reads are not an atomic database snapshot or creation authorization.
class WorkAssignmentCandidateRead {
  WorkAssignmentCandidateRead(
    List<Map<String, dynamic>> rows, {
    required this.total,
  }) : rows = List.unmodifiable(
         rows.map((row) => Map<String, dynamic>.unmodifiable(row)),
       );
  final List<Map<String, dynamic>> rows;
  final int? total;
}

abstract class WorkAssignmentCreationSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<JobAccess> loadAccess();
  Future<WorkAssignmentCandidateRead> listJobs(String companyId);
  Future<WorkAssignmentCandidateRead> listApplicants(String jobId);
  Future<WorkAssignmentCandidateRead> listAssignments(String companyId);
  Future<Object?> createAssignment(Map<String, dynamic> parameters);
}

/// Supabase adapter. Existing job access checks are reused unchanged.
/// Existing listing RPC names/parameters are retained. Unlike the older list
/// adapters, count=exact is requested so HTTP row caps cannot silently omit an
/// existing assignment. Creation is explicit and transport retries are disabled.
class SupabaseWorkAssignmentCreationSource
    implements WorkAssignmentCreationSource {
  SupabaseWorkAssignmentCreationSource(this.client)
    : jobs = JobPostingsRepository(client);
  final SupabaseClient client;
  final JobPostingsRepository jobs;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((e) => e.session?.user.id);
  @override
  Future<JobAccess> loadAccess() => jobs.loadAccess();
  Future<WorkAssignmentCandidateRead> _read(
    String rpc,
    Map<String, dynamic> params,
  ) async {
    final actor = userId;
    if (actor == null) throw const AuthException('Authentication required');
    final response = await client
        .rpc(rpc, params: params)
        .count(CountOption.exact);
    if (userId != actor) throw const AuthException('Account changed');
    final data = response.data;
    if (data is! List || data.any((row) => row is! Map)) {
      throw const FormatException('Invalid candidate read');
    }
    return WorkAssignmentCandidateRead(
      data.map((row) => Map<String, dynamic>.from(row as Map)).toList(),
      total: response.count,
    );
  }

  @override
  Future<WorkAssignmentCandidateRead> listJobs(String companyId) => _read(
    'list_employer_job_postings',
    {'p_company_id': workUuid(companyId)},
  );
  @override
  Future<WorkAssignmentCandidateRead> listApplicants(String jobId) =>
      _read('list_job_applicants', {'p_job_id': workUuid(jobId)});
  @override
  Future<WorkAssignmentCandidateRead> listAssignments(String companyId) =>
      _read('list_company_work_assignments', {
        'p_company_id': workUuid(companyId),
      });

  @override
  Future<Object?> createAssignment(Map<String, dynamic> parameters) async {
    if (userId == null) throw const AuthException('Authentication required');
    return await client
        .rpc('create_work_assignment', params: parameters)
        .retry(enabled: false, requestTimeout: const Duration(seconds: 30));
  }
}

enum WorkAssignmentCreateStatus {
  idle,
  submitting,
  success,
  rejected,
  uncertain,
}

/// Process-lifetime protection, including dialog/route recreation. This is NOT
/// durable across browser refresh or app restart. Never infer failure from an
/// absent assignment after a lost response. Tests inject a fresh ledger.
class WorkAssignmentCreationLedger {
  final _attempts = <(String, String, String), _CreationAttempt>{};
}

final _creationLedger = WorkAssignmentCreationLedger();

class _CreationAttempt {
  _CreationAttempt(this.start, this.end, this.location);
  final DateTime start, end;
  final String location;
  WorkAssignmentCreateStatus status = WorkAssignmentCreateStatus.submitting;
  String? assignmentId;
}

@immutable
class WorkAssignmentCreateResult {
  const WorkAssignmentCreateResult(
    this.status,
    this.message, {
    this.assignmentId,
  });
  final WorkAssignmentCreateStatus status;
  final String message;
  final String? assignmentId;
}

/// Parse wall-clock Malaysia input independently of the device timezone.
/// Reject DateTime's normalizing overflow (e.g. February 31).
DateTime? workAssignmentMalaysiaUtc(String date, String time) {
  // Pasted input may contain surrounding spaces, including nonbreaking spaces.
  // Normalize at the shared parser so field validation and UTC conversion agree.
  date = date.trim();
  time = time.trim();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
      !RegExp(r'^\d{2}:\d{2}$').hasMatch(time)) {
    return null;
  }
  final d = date.split('-').map(int.parse).toList();
  final t = time.split(':').map(int.parse).toList();
  if (d[0] < 1) return null;
  final wall = DateTime.utc(d[0], d[1], d[2], t[0], t[1]);
  if (wall.year != d[0] ||
      wall.month != d[1] ||
      wall.day != d[2] ||
      wall.hour != t[0] ||
      wall.minute != t[1]) {
    return null;
  }
  return wall.subtract(const Duration(hours: 8));
}

@immutable
class WorkAssignmentCandidate {
  const WorkAssignmentCandidate._({
    required this._accountId,
    required this.companyId,
    required this.companyName,
    required this.jobId,
    required this.jobTitle,
    required this.applicationId,
    required this.workerId,
    required this.applicantName,
  });
  final String _accountId;
  final String companyId,
      companyName,
      jobId,
      jobTitle,
      applicationId,
      workerId,
      applicantName;
}

enum WorkAssignmentCreationError {
  authentication,
  permission,
  incompleteData,
  connection,
  contextChanged,
}

@immutable
class WorkAssignmentCandidateState {
  WorkAssignmentCandidateState._({
    this.loading = false,
    this.companyId,
    List<WorkAssignmentCandidate> candidates = const [],
    this.errorKind,
  }) : candidates = List.unmodifiable(candidates);
  final bool loading;
  final String? companyId;
  final List<WorkAssignmentCandidate> candidates;
  final WorkAssignmentCreationError? errorKind;
  String? get error => switch (errorKind) {
    null => null,
    WorkAssignmentCreationError.authentication =>
      'Sign in again to load eligible applications.',
    WorkAssignmentCreationError.permission =>
      'Employer company access is denied or ambiguous.',
    WorkAssignmentCreationError.incompleteData => 'Application eligibility could not be checked completely. Refresh before continuing.',
    WorkAssignmentCreationError.connection =>
      'Unable to load eligible applications. Check your connection and retry.',
    WorkAssignmentCreationError.contextChanged =>
      'Your account or company changed. Reload eligible applications.',
  };
}

/// All-or-nothing candidate discovery and explicitly confirmed creation.
/// Caller owns disposal. No automatic writes or cached creation authorization.
/// Reload when company membership changes; no live membership subscription exists.
class WorkAssignmentCreationRepository extends ChangeNotifier {
  WorkAssignmentCreationRepository(
    this.source, {
    WorkAssignmentCreationLedger? ledger,
  }) : ledger = ledger ?? _creationLedger,
       _actor = source.userId {
    _subscription = source.accountChanges.listen((id) {
      if (id != _actor || source.userId != _actor) {
        ++_request;
        _actor = source.userId;
        _state = WorkAssignmentCandidateState._(
          errorKind: _actor == null
              ? WorkAssignmentCreationError.authentication
              : WorkAssignmentCreationError.contextChanged,
        );
        if (!_disposed) notifyListeners();
      }
    });
  }
  final WorkAssignmentCreationSource source;
  final WorkAssignmentCreationLedger ledger;
  bool _creating = false;
  bool get creating => _creating;

  WorkAssignmentCreateStatus statusFor(WorkAssignmentCandidate candidate) =>
      ledger
          ._attempts[(
            source.userId ?? '',
            candidate.companyId,
            candidate.applicationId,
          )]
          ?.status ??
      WorkAssignmentCreateStatus.idle;

  /// No automatic retry. The caller must obtain explicit user confirmation.
  Future<WorkAssignmentCreateResult> create({
    required WorkAssignmentCandidate candidate,
    required DateTime start,
    required DateTime end,
    required String location,
  }) async {
    WorkAssignmentCreateResult rejected(String message) =>
        WorkAssignmentCreateResult(
          WorkAssignmentCreateStatus.rejected,
          message,
        );
    final actor = source.userId;
    if (_disposed ||
        actor == null ||
        _actor != actor ||
        candidate._accountId != actor ||
        _creating) {
      return rejected('Sign in again or wait for the current request.');
    }
    final key = (actor, candidate.companyId, candidate.applicationId);
    if (ledger._attempts.containsKey(key)) {
      return const WorkAssignmentCreateResult(
        WorkAssignmentCreateStatus.uncertain,
        'This application already has a creation attempt. Check its current assignment; do not retry.',
      );
    }
    if (!start.isUtc ||
        !end.isUtc ||
        !end.isAfter(start) ||
        location.trim().isEmpty ||
        location.runes.length > 500) {
      return rejected(
        'Enter a valid MYT schedule and workplace location of up to 500 characters.',
      );
    }
    // Reserve before asynchronous preflight; concurrent repositories share it.
    final attempt = _CreationAttempt(start, end, location.trim());
    ledger._attempts[key] = attempt;
    _creating = true;
    var dispatched = false;
    final generation = _request + 1;
    try {
      await load(companyId: candidate.companyId);
      bool current() =>
          !_disposed &&
          source.userId == actor &&
          _actor == actor &&
          generation == _request;
      final matches = state.candidates.where(
        (c) =>
            c.applicationId == candidate.applicationId &&
            c.workerId == candidate.workerId &&
            c.jobId == candidate.jobId &&
            c.companyId == candidate.companyId &&
            c.companyName == candidate.companyName &&
            c.jobTitle == candidate.jobTitle &&
            c.applicantName == candidate.applicantName,
      );
      if (!current() || state.error != null || matches.length != 1) {
        ledger._attempts.remove(key);
        return rejected(
          state.error ?? 'Eligibility or account changed. Reload and confirm the application again.',
        );
      }
      dispatched = true;
      final response = await source.createAssignment({
        'p_application_id': candidate.applicationId,
        'p_scheduled_start': start.toIso8601String(),
        'p_scheduled_end': end.toIso8601String(),
        'p_workplace_location': attempt.location,
      });
      // Even a stale completion must retain the attempt lock for its old account.
      if (!current()) {
        attempt.status = WorkAssignmentCreateStatus.uncertain;
        return rejected(
          'Account or company context changed. Check assignments before continuing.',
        );
      }
      attempt.assignmentId = workUuid(response);
      attempt.status = WorkAssignmentCreateStatus.success;
      return WorkAssignmentCreateResult(
        WorkAssignmentCreateStatus.success,
        'Assignment created. Refreshing company assignments.',
        assignmentId: attempt.assignmentId,
      );
    } catch (error) {
      // A structured SQL rejection proves that this transaction did not commit.
      final definite =
          error is PostgrestException &&
          ([
            'P0001',
            '42501',
            '28000',
            '23P01',
            '23503',
            '23514',
            '22023',
            'PGRST301',
            'PGRST302',
            'PGRST303',
          ].contains(error.code));
      if (!dispatched || definite) {
        ledger._attempts.remove(key);
        if (error is PostgrestException &&
            [
              '28000',
              'PGRST301',
              'PGRST302',
              'PGRST303',
            ].contains(error.code)) {
          return rejected(
            'Session expired. Sign in again before creating an assignment.',
          );
        }
        return rejected(
          'Assignment was not created. Check permissions, eligibility and schedule, then reload.',
        );
      }
      attempt.status = WorkAssignmentCreateStatus.uncertain;
      if (_disposed || source.userId != actor || generation != _request) {
        return rejected(
          'Account or company context changed. Check assignments before continuing.',
        );
      }
      // A failed or empty reconciliation never permits another write.
      return await reconcile(candidate);
    } finally {
      _creating = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Read-only, positive reconciliation. Absence is never proof of rollback.
  Future<WorkAssignmentCreateResult> reconcile(
    WorkAssignmentCandidate candidate,
  ) async {
    const uncertain = WorkAssignmentCreateResult(
      WorkAssignmentCreateStatus.uncertain,
      'Creation outcome is uncertain. Do not create again or refresh/restart to retry. Check assignments or ask for support.',
    );
    final actor = source.userId;
    if (actor == null || _disposed || candidate._accountId != actor) {
      return uncertain;
    }
    final attempt =
        ledger._attempts[(actor, candidate.companyId, candidate.applicationId)];
    if (attempt == null) return uncertain;
    if (attempt.status == WorkAssignmentCreateStatus.submitting) {
      return uncertain;
    }
    final generation = _request;
    bool current() =>
        !_disposed && actor == source.userId && generation == _request;
    try {
      final access = await source.loadAccess();
      if (!current() || _company(access) != candidate.companyId) {
        return uncertain;
      }
      final rows = _complete(await source.listAssignments(candidate.companyId));
      _assigned(
        rows,
      ); // Reject incomplete/duplicate rows before using any match.
      final matches = rows
          .map(CompanyWorkAssignment.fromJson)
          .where(
            (a) =>
                a.applicationId == candidate.applicationId &&
                a.workerId == candidate.workerId &&
                a.jobId == candidate.jobId &&
                a.scheduledStart == attempt.start &&
                a.scheduledEnd == attempt.end &&
                a.workplaceLocation == attempt.location,
          )
          .toList();
      final finalAccess = await source.loadAccess();
      if (!current() ||
          _company(finalAccess) != candidate.companyId ||
          matches.length != 1) {
        return uncertain;
      }
      attempt.status = WorkAssignmentCreateStatus.success;
      attempt.assignmentId = matches.single.assignmentId;
      return WorkAssignmentCreateResult(
        WorkAssignmentCreateStatus.success,
        'A matching assignment was found in fresh company reads.',
        assignmentId: attempt.assignmentId,
      );
    } catch (_) {
      return uncertain;
    }
  }

  late final StreamSubscription<String?> _subscription;
  String? _actor;
  int _request = 0;
  bool _disposed = false;
  WorkAssignmentCandidateState _state = WorkAssignmentCandidateState._();
  WorkAssignmentCandidateState get state =>
      !_disposed && source.userId == _actor
      ? _state
      : WorkAssignmentCandidateState._(
          errorKind: WorkAssignmentCreationError.contextChanged,
        );

  /// With no company argument, use only the uniquely authorized loadAccess result.
  /// An explicit caller scope must match it; never pick an arbitrary membership.
  Future<void> load({String? companyId}) async {
    if (_disposed) return;
    _actor = source.userId;
    final actor = _actor, request = ++_request;
    bool current() =>
        !_disposed && request == _request && actor == source.userId;
    _state = WorkAssignmentCandidateState._(loading: true);
    notifyListeners();
    try {
      if (!current()) return;
      if (actor == null) throw const AuthException('Authentication required');
      final access = await source.loadAccess();
      if (!current()) return;
      final company = _company(access);
      final name = _text(access.company!, 'company_name');
      if (companyId != null && workUuid(companyId) != company) {
        throw const _CandidateFailure(WorkAssignmentCreationError.permission);
      }
      final jobs = _complete(await source.listJobs(company));
      if (!current()) return;
      final jobIds = <String>{};
      for (final job in jobs) {
        if (workUuid(job['company_id']) != company) {
          throw const _CandidateFailure(WorkAssignmentCreationError.permission);
        }
        if (!jobIds.add(workUuid(job['job_id']))) {
          throw const FormatException('Duplicate job');
        }
        _text(job, 'title');
      }
      // Failure here can NEVER be interpreted as an empty assignment set.
      final initiallyAssigned = _assigned(
        _complete(await source.listAssignments(company)),
      );
      if (!current()) return;
      final applications = <String>{};
      final candidates = <WorkAssignmentCandidate>[];
      for (final job in jobs) {
        final jobId = workUuid(job['job_id']);
        final rows = _complete(await source.listApplicants(jobId));
        if (!current()) return;
        for (final row in rows) {
          final application = workUuid(row['application_id']);
          final worker = workUuid(row['applicant_id']);
          final applicantName = _text(row, 'applicant_name');
          final status = _text(row, 'status');
          if (!MyApplicationStatus.values.any(
                (value) => value.name == status,
              ) ||
              !applications.add(application)) {
            throw const FormatException('Ambiguous application');
          }
          // The tested applicant RPC is job-scoped, not guaranteed to project
          // job/company IDs. If supplied, contradictory IDs must be rejected.
          if ((row.containsKey('job_id') && workUuid(row['job_id']) != jobId) ||
              (row.containsKey('company_id') &&
                  workUuid(row['company_id']) != company)) {
            throw const FormatException('Applicant context mismatch');
          }
          if (status == 'hired') {
            candidates.add(
              WorkAssignmentCandidate._(
                accountId: actor,
                companyId: company,
                companyName: name,
                jobId: jobId,
                jobTitle: _text(job, 'title'),
                applicationId: application,
                workerId: worker,
                applicantName: applicantName,
              ),
            );
          }
        }
      }
      // Re-read assignments after discovery to exclude applications assigned
      // while applicant reads were pending. Every assignment status counts.
      final assigned = _assigned(
        _complete(await source.listAssignments(company)),
      )..addAll(initiallyAssigned);
      if (!current()) return;
      final finalAccess = await source.loadAccess();
      if (!current()) return;
      if (_company(finalAccess) != company) {
        throw const _CandidateFailure(
          WorkAssignmentCreationError.contextChanged,
        );
      }
      _text(finalAccess.company!, 'company_name');
      _state = WorkAssignmentCandidateState._(
        companyId: company,
        candidates: candidates
            .where((row) => !assigned.contains(row.applicationId))
            .toList(),
      );
    } catch (error) {
      if (!current()) return;
      final kind = error is _CandidateFailure
          ? error.kind
          : error is AuthException
          ? WorkAssignmentCreationError.authentication
          : error is PostgrestException &&
                ['42501', 'PGRST116'].contains(error.code)
          ? WorkAssignmentCreationError.permission
          : error is FormatException || error is TypeError
          ? WorkAssignmentCreationError.incompleteData
          : WorkAssignmentCreationError.connection;
      _state = WorkAssignmentCandidateState._(errorKind: kind);
    }
    if (current()) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_request;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

String _company(JobAccess access) {
  if (!access.allowed) {
    throw const _CandidateFailure(WorkAssignmentCreationError.permission);
  }
  return workUuid(access.company?['company_id']);
}

String _text(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Missing candidate field');
  }
  return value;
}

List<Map<String, dynamic>> _complete(WorkAssignmentCandidateRead read) {
  if (read.total == null || read.total != read.rows.length) {
    throw const FormatException('Incomplete candidate read');
  }
  return read.rows;
}

Set<String> _assigned(List<Map<String, dynamic>> rows) {
  final ids = <String>{};
  final applications = <String>{};
  for (final row in rows) {
    final assignment = CompanyWorkAssignment.fromJson(row);
    if (!ids.add(assignment.assignmentId)) {
      throw const FormatException('Duplicate assignment');
    }
    applications.add(assignment.applicationId);
  }
  return applications;
}

class _CandidateFailure implements Exception {
  const _CandidateFailure(this.kind);
  final WorkAssignmentCreationError kind;
}
