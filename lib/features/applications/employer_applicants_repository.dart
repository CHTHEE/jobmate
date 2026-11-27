import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../jobs/job_postings_repository.dart';
import 'applicant_unseen_controller.dart';
import 'compensation_offer.dart';
import 'my_applications_repository.dart';

class JobApplicant {
  JobApplicant(Map<String, dynamic> row)
    : id = row['application_id'] as String,
      applicantId = row['applicant_id'] as String,
      name = row['applicant_name'] as String,
      resumeId = row['resume_id'] as String?,
      coverNote = row['cover_note'] as String?,
      status = MyApplicationStatus.values.firstWhere(
        (s) => s.name == row['status'],
      ),
      appliedAt = DateTime.parse(row['applied_at'] as String),
      updatedAt = DateTime.parse(row['updated_at'] as String);
  final String id, applicantId, name;
  final String? resumeId, coverNote;
  final MyApplicationStatus status;
  final DateTime appliedAt, updatedAt;
  List<MyApplicationStatus> get employerNext => switch (status) {
    MyApplicationStatus.submitted => [
      MyApplicationStatus.shortlisted,
      MyApplicationStatus.rejected,
    ],
    MyApplicationStatus.shortlisted => [
      MyApplicationStatus.interview,
      MyApplicationStatus.rejected,
    ],
    MyApplicationStatus.interview => [
      MyApplicationStatus.offered,
      MyApplicationStatus.rejected,
    ],
    MyApplicationStatus.offered =>
      p03CompensationOffersEnabled ? [MyApplicationStatus.offered] : [],
    _ => [],
  };
}

class EmployerPostingContext {
  const EmployerPostingContext(this.access, this.jobs);
  final JobAccess access;
  final List<Map<String, dynamic>> jobs;
}

abstract class EmployerApplicantsSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<EmployerPostingContext> loadJobs();
  Future<List<Map<String, dynamic>>> applicants(String jobId);
  Future<FunctionResponse> viewResume(String applicationId);
  Future<void> updateStatus(
    String applicationId,
    MyApplicationStatus status,
    String? note,
  );
  Future<Map<String, dynamic>> issueCompensationOffer(
    String applicationId,
    String requestId,
    String? note,
  );
}

class SupabaseEmployerApplicantsSource implements EmployerApplicantsSource {
  SupabaseEmployerApplicantsSource(this.client)
    : jobs = JobPostingsRepository(client);
  final SupabaseClient client;
  final JobPostingsRepository jobs;
  ApplicantUnseenController get applicantUnseen =>
      ApplicantUnseenController.session(client);
  @override
  Future<FunctionResponse> viewResume(String applicationId) =>
      client.functions.invoke(
        'view-application-resume',
        method: HttpMethod.post,
        body: {'application_id': applicationId},
      );
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((e) => e.session?.user.id);
  @override
  Future<EmployerPostingContext> loadJobs() async {
    final accountId = userId;
    final access = await jobs.loadAccess();
    applicantUnseen.enterWorkspace(
      accountId: accountId,
      companyId: access.allowed
          ? access.company!['company_id'] as String?
          : null,
    );
    if (!access.allowed) {
      throw StateError(access.message ?? 'Job access denied.');
    }
    final rows = await jobs.list(access.company!['company_id'] as String);
    return EmployerPostingContext(access, rows);
  }

  @override
  Future<List<Map<String, dynamic>>> applicants(String jobId) async {
    final rows = await client.rpc(
      'list_job_applicants',
      params: {'p_job_id': jobId},
    );
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  @override
  Future<void> updateStatus(
    String applicationId,
    MyApplicationStatus status,
    String? note,
  ) async {
    await client.rpc(
      'update_job_application_status',
      params: {
        'p_application_id': applicationId,
        'p_new_status': status.name,
        'p_note': note,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> issueCompensationOffer(
    String applicationId,
    String requestId,
    String? note,
  ) async {
    final result = await client.rpc(
      'issue_application_compensation_offer_v1',
      params: {
        'p_application_id': applicationId,
        'p_request_id': requestId,
        'p_note': note,
      },
    );
    if (result is! Map) {
      throw const FormatException('Invalid compensation offer response.');
    }
    return Map<String, dynamic>.from(result);
  }
}

class EmployerApplicantsRepository extends ChangeNotifier {
  EmployerApplicantsRepository(
    this.source,
    this.jobId, {
    this.applicantUnseen,
    this.compensationOffersEnabled = p03CompensationOffersEnabled,
  }) : _actor = source.userId {
    _subscription = source.accountChanges.listen((id) {
      if (id == _actor) return;
      _reset();
      if (id != null) load();
    });
  }
  final bool compensationOffersEnabled;
  final EmployerApplicantsSource source;
  final String? jobId;
  final ApplicantUnseenController? applicantUnseen;
  late final StreamSubscription<String?> _subscription;
  String? _actor;
  int _generation = 0;
  bool _disposed = false;
  bool loading = true;
  bool updating = false;
  bool get active =>
      !_disposed && source.userId != null && source.userId == _actor;
  String? error;
  EmployerPostingContext? _context;
  List<JobApplicant> _rows = [];
  final Map<String, String> _pendingOfferRequests = {};
  String compensationOfferRequestId(String applicationId) =>
      _pendingOfferRequests.putIfAbsent(applicationId, const Uuid().v4);
  ApplicantDisplayScope? _displayScope;
  ApplicantDisplayScope? get displayScope =>
      active && !loading && !updating && error == null ? _displayScope : null;
  EmployerPostingContext? get context =>
      source.userId == _actor ? _context : null;
  Map<String, dynamic>? get job =>
      context?.jobs.where((j) => j['job_id'] == jobId).firstOrNull;
  List<JobApplicant> get applicants =>
      source.userId == _actor ? List.unmodifiable(_rows) : const [];
  List<JobApplicant> search({
    String query = '',
    String status = '',
    String tab = 'All',
    String sort = 'Newest',
  }) {
    final rows = applicants
        .where(
          (a) =>
              a.name.toLowerCase().contains(query.trim().toLowerCase()) &&
              (status.isEmpty || a.status.name == status) &&
              (tab == 'All' ||
                  (tab == 'Completed'
                      ? a.status.completed
                      : !a.status.completed)),
        )
        .toList();
    rows.sort((a, b) {
      if (sort == 'Name') return a.name.compareTo(b.name);
      final byDate = a.appliedAt.compareTo(b.appliedAt);
      final order = byDate == 0 ? a.id.compareTo(b.id) : byDate;
      return sort == 'Oldest' ? order : -order;
    });
    return rows;
  }

  bool _current(int generation, String? actor) =>
      !_disposed && generation == _generation && source.userId == actor;
  void _reset() {
    ++_generation;
    _actor = source.userId;
    _context = null;
    _rows = [];
    _pendingOfferRequests.clear();
    _displayScope = null;
    loading = false;
    updating = false;
    error = 'Your account changed. Refresh to view applicants.';
    notifyListeners();
  }

  Future<void> load({bool quietly = false}) async {
    if (_disposed || updating) return;
    if (_actor != source.userId) _reset();
    final generation = ++_generation, actor = _actor;
    if (!quietly) {
      _context = null;
      _rows = [];
      _displayScope = null;
    }
    loading = !quietly;
    error = null;
    if (!quietly) notifyListeners();
    try {
      if (actor == null) {
        throw StateError('Sign in as an Employer to view applicants.');
      }
      final context = await source.loadJobs();
      if (!_current(generation, actor)) return;
      // Revalidate job/company context before every applicant request.
      _context = context;
      if (jobId != null && job != null) {
        final companyId = context.access.company?['company_id'];
        final scope = context.access.allowed && companyId is String
            ? applicantUnseen?.beginApplicantLoad(jobId, companyId: companyId)
            : null;
        final rows = await source.applicants(jobId!);
        if (!_current(generation, actor)) return;
        _rows = rows.map(JobApplicant.new).toList();
        _displayScope = scope;
      }
    } catch (failure) {
      if (!_current(generation, actor)) return;
      final accessLost =
          failure is StateError ||
          failure is PostgrestException && failure.code == '42501';
      if (!quietly || _rows.isEmpty || accessLost) {
        _context = null;
        _rows = [];
        error = failure is StateError
            ? failure.message.toString()
            : failure is PostgrestException && failure.code == '42501'
            ? 'Permission denied. Check your Employer membership and company access.'
            : 'Unable to load applicants. Please retry.';
      }
    } finally {
      if (_current(generation, actor)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> updateStatus(
    JobApplicant applicant,
    MyApplicationStatus next,
    String note,
  ) async {
    if (_disposed ||
        updating ||
        loading ||
        job == null ||
        source.userId == null ||
        source.userId != _actor) {
      throw StateError(
        'This job or session changed. Refresh before changing a status.',
      );
    }
    final current = applicants.where((a) => a.id == applicant.id).firstOrNull;
    if (current == null ||
        current.status != applicant.status ||
        !current.employerNext.contains(next)) {
      throw StateError(
        'This status change is unavailable. Refresh the applicant list.',
      );
    }
    final trimmed = note.trim();
    if (trimmed.runes.length > 2000) {
      throw StateError('Keep the note within 2,000 characters.');
    }
    if (next == MyApplicationStatus.offered) {
      final selectedJob = job;
      if (selectedJob == null || !hasPaymentTermsMetadata(selectedJob)) {
        throw StateError('Refresh the Job terms before issuing an Offer.');
      }
      if (isPaymentSupportedJob(selectedJob)) {
        throw StateError(
          compensationOffersEnabled
              ? 'Use versioned Offer issuance for this Job.'
              : 'Versioned Offer issuance is currently unavailable.',
        );
      }
    }
    final generation = _generation, actor = _actor;
    final companyId = context!.access.company!['company_id'];
    Object? failure;
    updating = true;
    notifyListeners();
    try {
      final fresh = await source.loadJobs();
      final freshJob = fresh.jobs
          .where((j) => j['job_id'] == jobId)
          .firstOrNull;
      if (!_current(generation, actor) ||
          fresh.access.company?['company_id'] != companyId ||
          !fresh.access.allowed ||
          freshJob == null) {
        throw StateError(
          'Your account or company access changed. Reopen this job.',
        );
      }
      if (next == MyApplicationStatus.offered &&
          (!hasPaymentTermsMetadata(freshJob) ||
              isPaymentSupportedJob(freshJob))) {
        throw StateError('Job terms changed. Refresh before issuing an Offer.');
      }
      await source.updateStatus(
        applicant.id,
        next,
        trimmed.isEmpty ? null : trimmed,
      );
      if (!_current(generation, actor)) {
        throw StateError(
          'Your session changed. Reopen this job to check the result.',
        );
      }
    } catch (error) {
      failure = error;
    } finally {
      if (_current(generation, actor)) updating = false;
    }
    if (!_current(generation, actor)) {
      throw StateError(
        'Your session or job changed. Reopen this job to check the result.',
      );
    }
    // Never mutate the displayed status optimistically. Reconcile both success
    // and backend conflicts against the authoritative list for this job.
    await load();
    if (_disposed ||
        source.userId != actor ||
        (context != null &&
            context!.access.company?['company_id'] != companyId)) {
      throw StateError(
        'Your session or company changed. Reopen this job to check the result.',
      );
    }
    if (failure != null) throw failure;
  }

  Future<CompensationOffer> issueCompensationOffer(
    JobApplicant applicant,
    String note,
    String requestId,
  ) async {
    if (!compensationOffersEnabled ||
        _disposed ||
        updating ||
        loading ||
        job == null ||
        source.userId == null ||
        source.userId != _actor) {
      throw StateError(
        'Versioned Offer issuance is unavailable. Refresh and try again.',
      );
    }
    final selectedJob = job!;
    if (!isPaymentSupportedJob(selectedJob)) {
      throw StateError(
        'This Job uses the existing non-payment Offer workflow.',
      );
    }
    final current = applicants
        .where((row) => row.id == applicant.id)
        .firstOrNull;
    if (current == null ||
        current.status != applicant.status ||
        !current.employerNext.contains(MyApplicationStatus.offered)) {
      throw StateError(
        'This Offer transition is unavailable. Refresh applicants.',
      );
    }
    if (note.trim().runes.length > 2000) {
      throw StateError('Keep the note within 2,000 characters.');
    }
    final generation = _generation, actor = _actor;
    final companyId = context!.access.company!['company_id'];
    Object? failure;
    CompensationOffer? offer;
    updating = true;
    notifyListeners();
    try {
      final fresh = await source.loadJobs();
      final freshJob = fresh.jobs
          .where((row) => row['job_id'] == jobId)
          .firstOrNull;
      if (!_current(generation, actor) ||
          !fresh.access.allowed ||
          fresh.access.company?['company_id'] != companyId ||
          freshJob == null ||
          !isPaymentSupportedJob(freshJob)) {
        throw StateError(
          'Your account, company or Job terms changed. Reopen this Job.',
        );
      }
      final raw = await source.issueCompensationOffer(
        applicant.id,
        requestId,
        note.trim().isEmpty ? null : note.trim(),
      );
      offer = CompensationOffer.fromJson(raw);
      if (offer.applicationId != applicant.id || !offer.isCurrent) {
        throw const FormatException('The server returned a stale Offer.');
      }
      if (!_current(generation, actor)) {
        throw StateError(
          'Your session changed. Reopen this Job to check the result.',
        );
      }
    } catch (error) {
      failure = error;
    } finally {
      if (_current(generation, actor)) updating = false;
    }
    if (!_current(generation, actor)) {
      throw StateError(
        'Your session or Job changed. Reopen to check the result.',
      );
    }
    await load();
    if (!_current(_generation, actor)) {
      throw StateError('Your session or company changed. Reopen this Job.');
    }
    if (failure != null) throw failure;
    _pendingOfferRequests.remove(applicant.id);
    return offer!;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _subscription.cancel();
    super.dispose();
  }
}

bool isPaymentSupportedJob(Map<String, dynamic> job) =>
    const {'part_time', 'temporary'}.contains(job['employment_type']) &&
    const {'hourly', 'daily'}.contains(job['salary_period']);

bool hasPaymentTermsMetadata(Map<String, dynamic> job) =>
    job.containsKey('employment_type') && job.containsKey('salary_period');

bool canOfferForJob(
  Map<String, dynamic> job, {
  required bool versionedOffersEnabled,
  required bool reissue,
}) {
  if (!hasPaymentTermsMetadata(job)) return false;
  return isPaymentSupportedJob(job) ? versionedOffersEnabled : !reissue;
}

String employerStatusError(Object error) {
  if (error is StateError) return error.message.toString();
  if (error is PostgrestException) {
    return error.code == '42501'
        ? 'Permission denied. Check your Employer company access.'
        : error.message;
  }
  return 'Unable to confirm the status change. Check the refreshed list before retrying.';
}
