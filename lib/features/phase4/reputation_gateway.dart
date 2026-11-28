import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class ReputationGateway {
  Future<Map<String, dynamic>> workerSummary();
  Future<List<Map<String, dynamic>>> companySummaries();
}

abstract interface class ReputationCriteriaGateway {
  Future<WorkerPublishedReputationData> workerPublishedData();
}

class WorkerPublishedReputationData {
  const WorkerPublishedReputationData({
    required this.criteria,
    required this.recentEvaluations,
    this.additionalSkills = const [],
  });

  final List<Map<String, dynamic>> criteria;
  final List<Map<String, dynamic>> recentEvaluations;
  final List<Map<String, dynamic>> additionalSkills;
}

abstract interface class ReputationSessionSource {
  String? get currentUserId;
  Stream<String?> get userIdChanges;
}

class SupabaseReputationSessionSource implements ReputationSessionSource {
  SupabaseReputationSessionSource(this.client);

  final SupabaseClient client;

  @override
  String? get currentUserId => client.auth.currentSession?.user.id;

  @override
  Stream<String?> get userIdChanges =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);
}

Map<String, dynamic> workerReputationSummaryFromRpc(dynamic result) {
  if (result is! List || result.length != 1 || result.single is! Map) {
    throw const FormatException('Worker reputation summary is unavailable.');
  }
  final row = Map<String, dynamic>.from(result.single as Map);
  validateReputationSummary(row, company: false);
  return row;
}

List<Map<String, dynamic>> companyReputationSummariesFromRpc(dynamic result) {
  if (result is! List) {
    throw const FormatException(
      'Company reputation summaries are unavailable.',
    );
  }
  return result
      .map((value) {
        if (value is! Map) {
          throw const FormatException('Invalid Company reputation summary.');
        }
        final row = Map<String, dynamic>.from(value);
        validateReputationSummary(row, company: true);
        return row;
      })
      .toList(growable: false);
}

class SupabaseReputationGateway
    implements ReputationGateway, ReputationCriteriaGateway {
  SupabaseReputationGateway(this.client)
    : _actorId = client.auth.currentUser?.id;

  final SupabaseClient client;
  final String? _actorId;

  void _checkSession() {
    if (_actorId == null || client.auth.currentUser?.id != _actorId) {
      throw StateError('Your account changed. Reopen Reputation to continue.');
    }
  }

  Future<dynamic> _rpc(String name) async {
    _checkSession();
    final result = await client.rpc(name);
    _checkSession();
    return result;
  }

  @override
  Future<Map<String, dynamic>> workerSummary() async =>
      workerReputationSummaryFromRpc(await _rpc('get_my_worker_reputation'));

  @override
  Future<List<Map<String, dynamic>>> companySummaries() async =>
      companyReputationSummariesFromRpc(
        await _rpc('get_my_company_reputation'),
      );

  @override
  Future<WorkerPublishedReputationData> workerPublishedData() async {
    final result = await _rpc('list_my_application_soft_skill_evaluations');
    if (result is! List) {
      throw const FormatException('Evaluation history is unavailable.');
    }
    final history = result
        .map((value) {
          if (value is! Map) {
            throw const FormatException('Invalid evaluation history row.');
          }
          return Map<String, dynamic>.from(value);
        })
        .toList(growable: false);
    return WorkerPublishedReputationData(
      criteria: aggregatePublishedCoreCriteria(history),
      recentEvaluations: recentPublishedReceivedEvaluations(history),
      additionalSkills: aggregatePublishedComparableWorkerSkills(history),
    );
  }
}

List<Map<String, dynamic>> recentPublishedReceivedEvaluations(
  Iterable<Map<String, dynamic>> history, {
  int limit = 3,
}) {
  final rows = history.toList(growable: false);
  final companyLabelsByApplication = <String, String>{};
  for (final evaluation in rows) {
    if (evaluation['given_by_me'] != true ||
        evaluation['direction'] != 'worker_to_company') {
      continue;
    }
    final applicationId = evaluation['application_id'];
    final targetLabel = evaluation['target_label'];
    if (applicationId is String &&
        applicationId.isNotEmpty &&
        targetLabel is String &&
        targetLabel.trim().isNotEmpty) {
      companyLabelsByApplication[applicationId] = targetLabel.trim();
    }
  }
  final result = <Map<String, dynamic>>[];
  for (final evaluation in rows) {
    if (evaluation['given_by_me'] == true ||
        evaluation['both_parties_submitted'] != true) {
      continue;
    }
    final average = evaluation['core_average'];
    final submittedAt = evaluation['submitted_at'];
    final applicationId = evaluation['application_id'];
    result.add({
      'job_title': '${evaluation['job_title'] ?? 'Job'}',
      'company_label': applicationId is String
          ? companyLabelsByApplication[applicationId]
          : null,
      'submitted_at': submittedAt is String ? submittedAt : null,
      'core_average': average is num && average.isFinite ? average : null,
    });
    if (result.length == limit) break;
  }
  return result;
}

List<Map<String, dynamic>> aggregatePublishedCoreCriteria(
  Iterable<Map<String, dynamic>> history,
) => _aggregatePublishedCriteria(
  history,
  group: 'core',
  order: const ['communication', 'responsibility', 'professionalism'],
);

/// Only the two recommended worker skills have a shared, general-purpose
/// definition here. They are visualization-only and remain additional skills.
List<Map<String, dynamic>> aggregatePublishedComparableWorkerSkills(
  Iterable<Map<String, dynamic>> history,
) => _aggregatePublishedCriteria(
  history.where((row) => row['direction'] == 'employer_to_worker'),
  group: 'worker_additional',
  order: const ['adaptability', 'teamwork'],
);

List<Map<String, dynamic>> _aggregatePublishedCriteria(
  Iterable<Map<String, dynamic>> history, {
  required String group,
  required List<String> order,
}) {
  final totals = <String, ({String label, double sum, int count})>{};
  for (final evaluation in history) {
    if (evaluation['given_by_me'] == true ||
        evaluation['both_parties_submitted'] != true) {
      continue;
    }
    final ratings = evaluation['ratings'];
    if (ratings is! List) continue;
    final seenInApplication = <String>{};
    for (final value in ratings) {
      if (value is! Map ||
          value['group'] != group ||
          value['not_observed'] == true) {
        continue;
      }
      // The reviewed evaluation-history RPC names this field `id`. Retain
      // `skill_id` compatibility for injected/test projections that use the
      // aggregate naming convention.
      final id = value['id'] ?? value['skill_id'];
      final label = value['label'];
      final score = value['rating'];
      if (id is! String ||
          !order.contains(id) ||
          !seenInApplication.add(id) ||
          label is! String ||
          label.trim().isEmpty ||
          score is! num ||
          !score.isFinite ||
          score < 1 ||
          score > 5) {
        continue;
      }
      final current = totals[id];
      totals[id] = (
        label: label.trim(),
        sum: (current?.sum ?? 0) + score.toDouble(),
        count: (current?.count ?? 0) + 1,
      );
    }
  }
  return [
    for (final id in order)
      if (totals[id] case final value?)
        {
          'skill_id': id,
          'label': value.label,
          'average': value.sum / value.count,
          'sample_count': value.count,
        },
  ];
}

/// Read-only aggregates for an authorized Application or visible Company.
/// Worker identifiers are never accepted from the caller.
abstract interface class CrossPartyReputationGateway {
  Future<Map<String, dynamic>> applicantSummary(String applicationId);
  Future<Map<String, dynamic>> visibleCompanySummary(String companyId);
}

class SupabaseCrossPartyReputationGateway
    implements CrossPartyReputationGateway {
  SupabaseCrossPartyReputationGateway(this.client)
    : _actorId = client.auth.currentUser?.id;

  final SupabaseClient client;
  final String? _actorId;

  void _checkSession() {
    if (_actorId == null || client.auth.currentUser?.id != _actorId) {
      throw StateError(
        'Your account changed. Reopen this profile to continue.',
      );
    }
  }

  Future<Map<String, dynamic>> _summary(
    String rpc,
    String parameter,
    String identifier,
    String responseKey, {
    required bool company,
  }) async {
    _checkSession();
    if (identifier.trim().isEmpty) {
      throw ArgumentError.value(
        identifier,
        parameter,
        'An identifier is required.',
      );
    }
    final result = await client.rpc(rpc, params: {parameter: identifier});
    _checkSession();
    if (result is! List || result.length != 1 || result.single is! Map) {
      throw const FormatException('Invalid reputation summary response.');
    }
    final row = Map<String, dynamic>.from(result.single as Map);
    if (row[responseKey] != identifier) {
      throw const FormatException(
        'Reputation summary identity does not match.',
      );
    }
    validateReputationSummary(row, company: company);
    return row;
  }

  @override
  Future<Map<String, dynamic>> applicantSummary(String applicationId) =>
      _summary(
        'get_applicant_reputation_for_company_v1',
        'p_application_id',
        applicationId,
        'application_id',
        company: false,
      );

  @override
  Future<Map<String, dynamic>> visibleCompanySummary(String companyId) =>
      _summary(
        'get_visible_company_reputation_v1',
        'p_company_id',
        companyId,
        'company_id',
        company: true,
      );
}

/// Reject incomplete/invalid aggregates instead of presenting missing counts
/// as zero. Also used at the injected UI gateway boundary.
void validateReputationSummary(
  Map<String, dynamic> row, {
  required bool company,
}) {
  int count(String key) {
    final value = row[key];
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value != value.round()) {
      throw FormatException('Invalid reputation count: $key.');
    }
    return value.toInt();
  }

  bool rating(Object? value) =>
      value is num && value.isFinite && value >= 1 && value <= 5;

  final published = count('published_application_count');
  final rated = count('rated_application_count');
  final average = row['core_average'];
  if (rated > published || (rated == 0 ? average != null : !rating(average))) {
    throw const FormatException('Invalid reputation average or sample count.');
  }
  if (!company) {
    count('verified_completed_shift_count');
    return;
  }
  if (row['company_name'] is! String ||
      (row['company_name'] as String).trim().isEmpty ||
      row['criteria_averages'] is! List) {
    throw const FormatException('Invalid Company reputation fields.');
  }
  final seen = <String>{};
  for (final item in row['criteria_averages'] as List) {
    if (item is! Map ||
        item['skill_id'] is! String ||
        (item['skill_id'] as String).trim().isEmpty ||
        !seen.add(item['skill_id'] as String) ||
        item['label'] is! String ||
        (item['label'] as String).trim().isEmpty ||
        !rating(item['average'])) {
      throw const FormatException('Invalid reputation criterion.');
    }
    final sample = item['sample_count'];
    if (sample is! num ||
        !sample.isFinite ||
        sample < 1 ||
        sample > published ||
        sample != sample.round()) {
      throw const FormatException('Invalid reputation criterion sample count.');
    }
  }
}
