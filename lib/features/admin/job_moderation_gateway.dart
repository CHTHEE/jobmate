import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class JobModerationGateway {
  Future<List<Map<String, dynamic>>> list({
    required String? status,
    required int limit,
    required int offset,
  });
  Future<Map<String, dynamic>> details(String jobId);
  Future<List<Map<String, dynamic>>> history(String jobId);
  Future<void> act(String jobId, String action, String reason);
}

class SupabaseJobModerationGateway implements JobModerationGateway {
  const SupabaseJobModerationGateway(this.client);
  final SupabaseClient client;

  @override
  Future<List<Map<String, dynamic>>> list({
    required String? status,
    required int limit,
    required int offset,
  }) async {
    final result = await client.rpc(
      'list_admin_job_moderation',
      params: {
        'p_status': status,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    if (result is! List) {
      throw const FormatException('Unexpected Job Moderation list response.');
    }
    return result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> details(String jobId) async {
    final result = await client.rpc(
      'get_admin_job_moderation',
      params: {'p_job_id': jobId},
    );
    if (result is! Map) {
      throw const FormatException('Unexpected Job Moderation details response.');
    }
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<List<Map<String, dynamic>>> history(String jobId) async {
    final result = await client.rpc(
      'list_job_moderation_history',
      params: {'p_job_id': jobId, 'p_limit': 51, 'p_offset': 0},
    );
    if (result is! List) {
      throw const FormatException('Unexpected Job Moderation history response.');
    }
    return result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<void> act(String jobId, String action, String reason) async {
    await client.rpc(
      'update_job_moderation',
      params: {
        'p_job_id': jobId,
        'p_action': action,
        'p_reason': reason,
      },
    );
  }
}
