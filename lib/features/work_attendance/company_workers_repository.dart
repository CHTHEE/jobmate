import 'dart:async';

import 'package:flutter/foundation.dart';

import 'work_assignment_creation_repository.dart';
import 'work_attendance_models.dart';

@immutable
class CompanyWorker {
  CompanyWorker({
    required this.id,
    required this.name,
    required Map<String, String> jobs,
    this.assignedShifts,
    this.verifiedShifts,
  }) : jobs = Map.unmodifiable(jobs);

  final String id, name;
  final Map<String, String> jobs;
  final int? assignedShifts, verifiedShifts;
}

/// Read-only directory using the same authorized RPC adapter as shift creation.
/// The company is resolved by loadAccess, never by a URL or a chosen worker ID.
class CompanyWorkersRepository extends ChangeNotifier {
  CompanyWorkersRepository(this.source) : _actor = source.userId {
    _subscription = source.accountChanges.listen((_) {
      if (_actor != source.userId && !_disposed) {
        _actor = source.userId;
        unawaited(load());
      }
    });
  }

  final WorkAssignmentCreationSource source;
  late final StreamSubscription<String?> _subscription;
  String? _actor;
  int _generation = 0;
  bool _disposed = false;
  bool loading = false;
  String? error, companyName;
  bool countsAvailable = false;
  List<CompanyWorker> _workers = const [];
  List<CompanyWorker> get workers =>
      source.userId == _actor ? _workers : const [];

  Future<void> load() async {
    if (_disposed) return;
    final actor = _actor = source.userId;
    final generation = ++_generation;
    bool current() =>
        !_disposed && generation == _generation && actor == source.userId;
    loading = true;
    error = companyName = null;
    countsAvailable = false;
    _workers = const [];
    notifyListeners();
    try {
      if (actor == null) {
        throw _DirectoryFailure('Sign in to view company workers.');
      }
      final access = await source.loadAccess();
      if (!current()) return;
      if (!access.allowed) {
        throw _DirectoryFailure(
          'Employer company access is denied or unavailable.',
        );
      }
      final company = workUuid(access.company?['company_id']);
      final name = _text(access.company?['company_name']);
      final jobs = _complete(await source.listJobs(company));
      if (!current()) return;
      final jobTitles = <String, String>{};
      for (final job in jobs) {
        if (workUuid(job['company_id']) != company) {
          throw const FormatException('Company mismatch');
        }
        final id = workUuid(job['job_id']);
        if (jobTitles.containsKey(id)) {
          throw const FormatException('Duplicate job');
        }
        jobTitles[id] = _text(job['title']);
      }
      final names = <String, String>{};
      final workerJobs = <String, Map<String, String>>{};
      final applications = <String, (String, String)>{};
      final seenApplications = <String>{};
      for (final job in jobTitles.entries) {
        final applicants = _complete(await source.listApplicants(job.key));
        if (!current()) return;
        for (final row in applicants) {
          if ((row.containsKey('company_id') &&
                  workUuid(row['company_id']) != company) ||
              (row.containsKey('job_id') &&
                  workUuid(row['job_id']) != job.key)) {
            throw const FormatException('Applicant scope mismatch');
          }
          final application = workUuid(row['application_id']);
          if (!seenApplications.add(application)) {
            throw const FormatException('Duplicate application');
          }
          if (row['status'] != 'hired') continue;
          final worker = workUuid(row['applicant_id']);
          final workerName = _text(row['applicant_name']);
          if (names.containsKey(worker) && names[worker] != workerName) {
            throw const FormatException('Inconsistent worker name');
          }
          names[worker] = workerName;
          (workerJobs[worker] ??= {})[job.key] = job.value;
          applications[application] = (worker, job.key);
        }
      }

      final assigned = <String, int>{}, verified = <String, int>{};
      var completeCounts = false;
      if (names.isNotEmpty) {
        try {
          final shifts = _complete(await source.listAssignments(company));
          if (!current()) return;
          final seen = <String>{};
          for (final raw in shifts) {
            if (raw.containsKey('company_id') &&
                workUuid(raw['company_id']) != company) {
              throw const FormatException('Assignment scope mismatch');
            }
            final shift = CompanyWorkAssignment.fromJson(raw);
            if (!seen.add(shift.assignmentId)) {
              throw const FormatException('Duplicate shift');
            }
            final identity = applications[shift.applicationId];
            if (identity == null) continue;
            if (identity != (shift.workerId, shift.jobId)) {
              throw const FormatException('Shift identity mismatch');
            }
            assigned.update(shift.workerId, (n) => n + 1, ifAbsent: () => 1);
            if (shift.verificationStatus == WorkVerificationStatus.verified) {
              verified.update(shift.workerId, (n) => n + 1, ifAbsent: () => 1);
            }
          }
          completeCounts = true;
        } catch (_) {
          // Never turn unavailable/incomplete counts into fabricated zeroes.
          completeCounts = false;
        }
      }
      if (!current()) return;
      final finalAccess = await source.loadAccess();
      if (!current()) return;
      if (!finalAccess.allowed ||
          workUuid(finalAccess.company?['company_id']) != company) {
        throw _DirectoryFailure('Company access changed. Refresh to continue.');
      }
      final result =
          [
            for (final worker in names.entries)
              CompanyWorker(
                id: worker.key,
                name: worker.value,
                jobs: workerJobs[worker.key]!,
                assignedShifts: completeCounts
                    ? assigned[worker.key] ?? 0
                    : null,
                verifiedShifts: completeCounts
                    ? verified[worker.key] ?? 0
                    : null,
              ),
          ]..sort((a, b) {
            final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
            return byName != 0 ? byName : a.id.compareTo(b.id);
          });
      _workers = List.unmodifiable(result);
      companyName = name;
      countsAvailable = completeCounts;
    } on _DirectoryFailure catch (failure) {
      if (current()) error = failure.message;
    } on FormatException {
      if (current()) error = 'Company worker data could not be checked completely. Refresh to retry.';
    } catch (_) {
      if (current()) error = 'Unable to load company workers. Check your connection and company access, then retry.';
    } finally {
      if (current()) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

List<Map<String, dynamic>> _complete(WorkAssignmentCandidateRead read) {
  if (read.total == null || read.total != read.rows.length) {
    throw const FormatException('Incomplete read');
  }
  return read.rows;
}

String _text(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Missing text');
  }
  return value.trim();
}

class _DirectoryFailure implements Exception {
  const _DirectoryFailure(this.message);
  final String message;
}
