import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Compile-time approval for the not-yet-deployed Admin scoring RPCs.
///
/// `kDebugMode` keeps this unavailable in profile and release builds even if a
/// build accidentally supplies the dart define.
const bool adminScoringEnabled =
    kDebugMode &&
    bool.fromEnvironment('ENABLE_ADMIN_SCORING', defaultValue: false);

abstract interface class AdminScoringSessionSource {
  String? get currentUserId;
  Stream<String?> get userIdChanges;
}

class SupabaseAdminScoringSessionSource implements AdminScoringSessionSource {
  SupabaseAdminScoringSessionSource(this.client);

  final SupabaseClient client;

  @override
  String? get currentUserId => client.auth.currentSession?.user.id;

  @override
  Stream<String?> get userIdChanges =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);
}

class AdminJobSeekerReputation {
  const AdminJobSeekerReputation({
    required this.targetUserId,
    required this.coreAverage,
    required this.publishedApplicationCount,
    required this.ratedApplicationCount,
    required this.verifiedCompletedShiftCount,
  });

  final String targetUserId;
  final num? coreAverage;
  final int publishedApplicationCount;
  final int ratedApplicationCount;
  final int verifiedCompletedShiftCount;

  factory AdminJobSeekerReputation.fromRpc(dynamic result, String targetId) {
    final row = _singleRow(result, 'Job Seeker Reputation');
    _requireExactKeys(row, const {
      'target_user_id',
      'core_average',
      'published_application_count',
      'rated_application_count',
      'verified_completed_shift_count',
    });
    _requireTarget(row['target_user_id'], targetId, 'Job Seeker Reputation');
    final published = _count(
      row['published_application_count'],
      'published_application_count',
    );
    final rated = _count(
      row['rated_application_count'],
      'rated_application_count',
    );
    final shifts = _count(
      row['verified_completed_shift_count'],
      'verified_completed_shift_count',
    );
    final average = _ratingOrNull(row['core_average'], 'core_average');
    if (rated > published || (rated == 0 ? average != null : average == null)) {
      throw const FormatException('Invalid Job Seeker Reputation aggregate.');
    }
    return AdminJobSeekerReputation(
      targetUserId: targetId,
      coreAverage: average,
      publishedApplicationCount: published,
      ratedApplicationCount: rated,
      verifiedCompletedShiftCount: shifts,
    );
  }
}

class AdminCompanyReputation {
  const AdminCompanyReputation({
    required this.companyId,
    required this.companyName,
    required this.coreAverage,
    required this.publishedApplicationCount,
    required this.ratedApplicationCount,
  });

  final String companyId;
  final String companyName;
  final num? coreAverage;
  final int publishedApplicationCount;
  final int ratedApplicationCount;

  factory AdminCompanyReputation.fromRpc(dynamic result, String companyId) {
    final row = _singleRow(result, 'Company Reputation');
    _requireExactKeys(row, const {
      'company_id',
      'company_name',
      'core_average',
      'published_application_count',
      'rated_application_count',
      'criteria_averages',
    });
    _requireTarget(row['company_id'], companyId, 'Company Reputation');
    if (row['company_name'] is! String ||
        (row['company_name'] as String).trim().isEmpty ||
        row['criteria_averages'] is! List) {
      throw const FormatException('Invalid Company Reputation response.');
    }
    final published = _count(
      row['published_application_count'],
      'published_application_count',
    );
    final rated = _count(
      row['rated_application_count'],
      'rated_application_count',
    );
    final average = _ratingOrNull(row['core_average'], 'core_average');
    if (rated > published || (rated == 0 ? average != null : average == null)) {
      throw const FormatException('Invalid Company Reputation aggregate.');
    }
    _validateCriteria(row['criteria_averages'] as List, published);
    return AdminCompanyReputation(
      companyId: companyId,
      companyName: row['company_name'] as String,
      coreAverage: average,
      publishedApplicationCount: published,
      ratedApplicationCount: rated,
    );
  }
}

class AdminJobSeekerTrustScore {
  const AdminJobSeekerTrustScore({
    required this.targetUserId,
    required this.state,
    required this.availability,
    required this.trustScore,
    required this.missingFactors,
  });

  static const contractVersion = 'admin-job-seeker-trust-read-v1';
  static const calculationVersion = 'js-trust-v2-dispute-provisional';
  static const certificationState = 'provisional_not_certified';
  static const allowedStates = {
    'available',
    'insufficient_history',
    'temporarily_blocked_evidence',
    'missing_authoritative_contract',
    'dispute_evidence_unavailable',
  };
  static const allowedMissingFactors = {
    'evaluation',
    'completion',
    'attendance',
    'dispute',
  };

  final String targetUserId;
  final String state;
  final String availability;
  final num? trustScore;
  final List<String> missingFactors;

  bool get isAvailable => availability == 'available';

  factory AdminJobSeekerTrustScore.fromRpc(dynamic result, String targetId) {
    if (result is! Map) {
      throw const FormatException('Invalid Internal Trust Score response.');
    }
    final row = Map<String, dynamic>.from(result);
    _requireExactKeys(row, const {
      'target_user_id',
      'contract_version',
      'calculation_version',
      'state',
      'availability',
      'trust_score',
      'missing_factors',
      'provisional',
      'certification_state',
    });
    _requireTarget(row['target_user_id'], targetId, 'Internal Trust Score');
    if (row['contract_version'] != contractVersion ||
        row['calculation_version'] != calculationVersion ||
        row['provisional'] != true ||
        row['certification_state'] != certificationState ||
        row['state'] is! String ||
        !allowedStates.contains(row['state']) ||
        row['availability'] is! String ||
        !{'available', 'unavailable'}.contains(row['availability']) ||
        row['missing_factors'] is! List) {
      throw const FormatException('Invalid Internal Trust Score contract.');
    }
    final factors = <String>[];
    for (final value in row['missing_factors'] as List) {
      if (value is! String ||
          !allowedMissingFactors.contains(value) ||
          factors.contains(value)) {
        throw const FormatException('Invalid Internal Trust Score factors.');
      }
      factors.add(value);
    }
    final score = row['trust_score'];
    if (row['availability'] == 'available') {
      if (row['state'] != 'available' ||
          score is! num ||
          !score.isFinite ||
          score < 0 ||
          score > 100) {
        throw const FormatException('Invalid available Internal Trust Score.');
      }
    } else if (row['state'] == 'available' || score != null) {
      throw const FormatException('Invalid unavailable Internal Trust Score.');
    }
    return AdminJobSeekerTrustScore(
      targetUserId: targetId,
      state: row['state'] as String,
      availability: row['availability'] as String,
      trustScore: score as num?,
      missingFactors: List.unmodifiable(factors),
    );
  }
}

abstract interface class AdminScoringGateway {
  Future<AdminJobSeekerReputation> jobSeekerReputation(String targetUserId);
  Future<AdminJobSeekerTrustScore> jobSeekerTrustScore(String targetUserId);
  Future<AdminCompanyReputation> companyReputation(String companyId);
}

/// The protected Trust RPC denied the currently authenticated Administrator.
/// Callers must not render an unavailable-evidence state from this failure.
class AdminTrustAccessDenied implements Exception {
  const AdminTrustAccessDenied();
}

class SupabaseAdminScoringGateway implements AdminScoringGateway {
  SupabaseAdminScoringGateway(this.client)
    : _actorId = client.auth.currentUser?.id;

  final SupabaseClient client;
  final String? _actorId;

  void _checkSession() {
    if (_actorId == null || client.auth.currentUser?.id != _actorId) {
      throw StateError(
        'Your administrator account changed. Reopen the details.',
      );
    }
  }

  Future<dynamic> _rpc(String rpc, Map<String, dynamic> params) async {
    _checkSession();
    final response = await client.rpc(rpc, params: params);
    _checkSession();
    return response;
  }

  @override
  Future<AdminJobSeekerReputation> jobSeekerReputation(
    String targetUserId,
  ) async => AdminJobSeekerReputation.fromRpc(
    await _rpc('get_admin_job_seeker_reputation_v1', {
      'p_target_user_id': targetUserId,
    }),
    targetUserId,
  );

  @override
  Future<AdminJobSeekerTrustScore> jobSeekerTrustScore(
    String targetUserId,
  ) async {
    try {
      return AdminJobSeekerTrustScore.fromRpc(
        await _rpc('get_admin_job_seeker_internal_trust_v2', {
          'p_target_user_id': targetUserId,
        }),
        targetUserId,
      );
    } on PostgrestException catch (error) {
      if (error.code == '42501') throw const AdminTrustAccessDenied();
      rethrow;
    }
  }

  @override
  Future<AdminCompanyReputation> companyReputation(String companyId) async =>
      AdminCompanyReputation.fromRpc(
        await _rpc('get_admin_company_reputation_v1', {
          'p_company_id': companyId,
        }),
        companyId,
      );
}

Map<String, dynamic> _singleRow(dynamic result, String label) {
  if (result is! List || result.length != 1 || result.single is! Map) {
    throw FormatException('Invalid $label response.');
  }
  return Map<String, dynamic>.from(result.single as Map);
}

void _requireExactKeys(Map<String, dynamic> row, Set<String> allowed) {
  if (row.keys.toSet().length != allowed.length ||
      !row.keys.toSet().containsAll(allowed)) {
    throw const FormatException('Unexpected scoring response fields.');
  }
}

void _requireTarget(Object? value, String expected, String label) {
  if (value is! String || value != expected) {
    throw FormatException('$label identity does not match.');
  }
}

int _count(Object? value, String field) {
  if (value is! num || !value.isFinite || value < 0 || value != value.round()) {
    throw FormatException('Invalid scoring count: $field.');
  }
  return value.toInt();
}

num? _ratingOrNull(Object? value, String field) {
  if (value == null) return null;
  if (value is! num || !value.isFinite || value < 1 || value > 5) {
    throw FormatException('Invalid scoring rating: $field.');
  }
  return value;
}

void _validateCriteria(List values, int published) {
  final ids = <String>{};
  for (final value in values) {
    if (value is! Map) {
      throw const FormatException('Invalid Company criterion.');
    }
    final row = Map<String, dynamic>.from(value);
    _requireExactKeys(row, const {
      'skill_id',
      'label',
      'average',
      'sample_count',
    });
    final id = row['skill_id'];
    final label = row['label'];
    if (id is! String ||
        id.trim().isEmpty ||
        !ids.add(id) ||
        label is! String ||
        label.trim().isEmpty ||
        _ratingOrNull(row['average'], 'average') == null) {
      throw const FormatException('Invalid Company criterion.');
    }
    final count = _count(row['sample_count'], 'sample_count');
    if (count < 1 || count > published) {
      throw const FormatException('Invalid Company criterion sample count.');
    }
  }
}
