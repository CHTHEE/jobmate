import 'package:supabase_flutter/supabase_flutter.dart';

import '../applications/module2_repository.dart';
import '../jobs/job_postings_repository.dart';

class EvaluationJobContext {
  const EvaluationJobContext({
    this.companyName,
    this.employmentType,
    this.logoUrl,
  });

  final String? companyName, employmentType;
  final Future<String?> Function()? logoUrl;
}

/// Optional presentation data, keyed by the exact authorized application.
abstract interface class EvaluationJobContextGateway {
  Future<Map<String, EvaluationJobContext>> applicationJobContexts({
    required bool employer,
    required List<Map<String, dynamic>> evaluations,
  });
}

abstract interface class SoftSkillEvaluationGateway {
  Future<List<Map<String, dynamic>>> candidates(String direction);
  Future<List<Map<String, dynamic>>> history();
  Future<String> submit({
    required String applicationId,
    required String direction,
    required List<String> selectedAdditionalSkillIds,
    required Map<String, dynamic> ratings,
    required String? comment,
  });
}

class SupabaseSoftSkillEvaluationGateway
    implements SoftSkillEvaluationGateway, EvaluationJobContextGateway {
  SupabaseSoftSkillEvaluationGateway(this.client)
    : _actorId = client.auth.currentUser?.id;

  final SupabaseClient client;
  final String? _actorId;
  final _logos = <String, (DateTime, Future<String?>)>{};

  void _checkSession() {
    if (_actorId == null || client.auth.currentUser?.id != _actorId) {
      throw StateError('Your account changed. Reopen Evaluations to continue.');
    }
  }

  Future<dynamic> _rpc(String name, [Map<String, dynamic>? parameters]) async {
    _checkSession();
    final result = await client.rpc(name, params: parameters);
    _checkSession();
    return result;
  }

  List<Map<String, dynamic>> _rows(dynamic result) => (result as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  @override
  Future<List<Map<String, dynamic>>> candidates(String direction) async =>
      _rows(
        await _rpc('list_application_evaluation_candidates', {
          'p_direction': direction,
        }),
      );

  @override
  Future<List<Map<String, dynamic>>> history() async =>
      _rows(await _rpc('list_my_application_soft_skill_evaluations'));

  Future<String?> _logoUrl(String path) {
    if (_actorId == null || client.auth.currentUser?.id != _actorId) {
      return Future.value();
    }
    final now = DateTime.now();
    final cached = _logos[path];
    if (cached != null && now.isBefore(cached.$1)) return cached.$2;
    final future = () async {
      try {
        final url = await SupabasePublishedJobsSource(client).signLogo(path);
        _checkSession();
        return url;
      } catch (_) {
        return null;
      }
    }();
    _logos[path] = (now.add(const Duration(seconds: 285)), future);
    return future;
  }

  @override
  Future<Map<String, EvaluationJobContext>> applicationJobContexts({
    required bool employer,
    required List<Map<String, dynamic>> evaluations,
  }) async {
    _checkSession();
    final jobByApplication = <String, String>{};
    final missing = <String>{};
    for (final row in evaluations) {
      if (row['application_id'] case final String application) {
        if (row['job_id'] case final String job) {
          jobByApplication[application] = job;
        } else {
          missing.add(application);
        }
      }
    }
    missing.removeAll(jobByApplication.keys);
    if (!employer && missing.isNotEmpty) {
      try {
        for (final batch in _batches(missing)) {
          _checkSession();
          final rows = await client
              .rpc<List<dynamic>>('list_my_job_applications')
              .inFilter('application_id', batch)
              .select('application_id,job_id');
          _checkSession();
          for (final row in rows) {
            if (row['application_id'] case final String application
                when batch.contains(application)) {
              if (row['job_id'] case final String job) {
                jobByApplication[application] = job;
              }
            }
          }
        }
      } catch (_) {
        // History still works with its own authorized identity.
      }
    }
    if (jobByApplication.isEmpty) return const {};
    _checkSession();
    final jobs = jobByApplication.values.toSet();
    final byJob = <String, EvaluationJobContext>{};
    if (!employer) {
      try {
        for (final batch in _batches(jobs)) {
          _checkSession();
          final rows = await client
              .rpc<List<dynamic>>('list_published_jobs')
              .inFilter('job_id', batch)
              .select('job_id,company_name,employment_type,logo_storage_path');
          _checkSession();
          for (final row in rows) {
            if (row['job_id'] case final String job when batch.contains(job)) {
              byJob[job] = _jobContext(
                row,
                row['company_name'],
                row['logo_storage_path'],
              );
            }
          }
        }
      } catch (_) {
        // Unpublished jobs and inaccessible images use the case's own identity.
      }
    } else {
      try {
        final repository = JobPostingsRepository(client);
        final access = await repository.loadAccess(includeLogo: false);
        _checkSession();
        final company = access.company;
        if (company?['company_id'] case final String companyId
            when access.allowed) {
          final rows = await repository.list(companyId);
          _checkSession();
          for (final row in rows) {
            if (row['job_id'] case final String job when jobs.contains(job)) {
              byJob.putIfAbsent(
                job,
                () => _jobContext(
                  row,
                  company?['company_name'],
                  company?['logo_storage_path'],
                ),
              );
            }
          }
        }
      } catch (_) {
        // Matching a job requires the existing employer authorization.
      }
    }
    _checkSession();
    return {
      for (final entry in jobByApplication.entries)
        entry.key: ?byJob[entry.value],
    };
  }

  Iterable<List<String>> _batches(Set<String> ids) sync* {
    final pending = ids.toList(growable: false);
    const size = 80;
    for (var start = 0; start < pending.length; start += size) {
      final end = (start + size).clamp(0, pending.length);
      yield pending.sublist(start, end);
    }
  }

  EvaluationJobContext _jobContext(
    Map<String, dynamic> row,
    Object? companyName,
    Object? logoPath,
  ) => EvaluationJobContext(
    companyName: companyName is String && companyName.trim().isNotEmpty
        ? companyName.trim()
        : null,
    employmentType: row['employment_type'] as String?,
    logoUrl: logoPath is String && logoPath.trim().isNotEmpty
        ? () => _logoUrl(logoPath)
        : null,
  );

  @override
  Future<String> submit({
    required String applicationId,
    required String direction,
    required List<String> selectedAdditionalSkillIds,
    required Map<String, dynamic> ratings,
    required String? comment,
  }) async => (await _rpc('submit_application_soft_skill_evaluation', {
    'p_application_id': applicationId,
    'p_direction': direction,
    'p_selected_additional_skill_ids': selectedAdditionalSkillIds,
    'p_ratings': ratings,
    'p_comment': comment,
  })) as String;
}
