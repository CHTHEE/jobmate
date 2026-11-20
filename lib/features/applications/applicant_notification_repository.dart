import 'package:supabase_flutter/supabase_flutter.dart';

typedef ApplicantNotificationRpc = Future<Object?> Function(
  String name,
  Map<String, dynamic> params,
);

class ApplicantNotificationRepository {
  ApplicantNotificationRepository(SupabaseClient client)
    : this.withRpc(
        (name, params) async => await client.rpc(name, params: params),
      );

  ApplicantNotificationRepository.withRpc(this._rpc);

  final ApplicantNotificationRpc _rpc;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static String jobId(Object? value) => _parseUuid(value);

  static String _parseUuid(Object? value) {
    if (value is! String || value.length != 36 || !_uuid.hasMatch(value)) {
      throw const FormatException('Invalid applicant notification UUID.');
    }
    return value.toLowerCase();
  }

  Future<Map<String, int>> listUnseenCounts() async {
    final result = await _rpc('list_unseen_applicant_counts', const {});
    if (result is! List) {
      throw const FormatException('Invalid unseen applicant counts.');
    }
    final counts = <String, int>{};
    for (final row in result) {
      if (row is! Map) {
        throw const FormatException('Invalid unseen applicant count row.');
      }
      final id = _parseUuid(row['job_id']);
      final count = row['unseen_count'];
      if (count is! int || count < 0 || counts.containsKey(id)) {
        throw const FormatException('Invalid unseen applicant count.');
      }
      counts[id] = count;
    }
    return Map.unmodifiable(counts);
  }

  Future<int> acknowledge(String jobId, List<String> applicationIds) async {
    if (applicationIds.isEmpty || applicationIds.length > 100) {
      throw ArgumentError('Provide 1 to 100 displayed application IDs.');
    }
    final ids = applicationIds.map(_parseUuid).toList(growable: false);
    final result = await _rpc('acknowledge_applicants_seen', {
      'p_job_id': _parseUuid(jobId),
      'p_application_ids': ids,
    });
    if (result is! int || result < 0 || result > ids.toSet().length) {
      throw const FormatException('Invalid applicant receipt count.');
    }
    return result;
  }
}
