import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class UserReportsGateway {
  Future<List<Map<String, dynamic>>> list({
    required bool admin,
    required int limit,
    required int offset,
  });
  Future<Map<String, dynamic>> details(String reportId);
  Future<List<Map<String, dynamic>>> history(String reportId);
  Future<List<Map<String, dynamic>>> searchTargets({
    required bool companies,
    required String query,
  });
  Future<String> submit(
    String category,
    String subject,
    String description, {
    String? targetUserId,
    String? targetCompanyId,
  });
  Future<String> act(String reportId, String action, String reason);
}

class SupabaseUserReportsGateway implements UserReportsGateway {
  const SupabaseUserReportsGateway(this.client);
  final SupabaseClient client;

  @override
  Future<List<Map<String, dynamic>>> list({
    required bool admin,
    required int limit,
    required int offset,
  }) async {
    final result = await client.rpc(
      admin ? 'list_admin_user_reports' : 'list_my_user_reports',
      params: {'p_limit': limit, 'p_offset': offset},
    );
    if (result is! List) {
      throw const FormatException('Unexpected report list response.');
    }
    return result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> details(String reportId) async {
    final result = await client.rpc(
      'get_user_report',
      params: {'p_report_id': reportId},
    );
    if (result is! Map) {
      throw const FormatException('Unexpected report details response.');
    }
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<List<Map<String, dynamic>>> history(String reportId) async {
    final result = await client.rpc(
      'list_user_report_history',
      params: {'p_report_id': reportId, 'p_limit': 51, 'p_offset': 0},
    );
    if (result is! List) {
      throw const FormatException('Unexpected report history response.');
    }
    return result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> searchTargets({
    required bool companies,
    required String query,
  }) async {
    final response = await client.rpc(
      companies ? 'search_reportable_companies' : 'search_reportable_users',
      params: {'p_query': query, 'p_limit': 15},
    );
    if (response is! List) {
      throw const FormatException('Unexpected report target response.');
    }
    return response
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  @override
  Future<String> submit(
    String category,
    String subject,
    String description, {
    String? targetUserId,
    String? targetCompanyId,
  }) async => (await client.rpc(
    'submit_user_report',
    params: {
      'p_category': category,
      'p_subject': subject,
      'p_description': description,
      'p_target_user_id': targetUserId,
      'p_target_company_id': targetCompanyId,
    },
  )) as String;

  @override
  Future<String> act(String reportId, String action, String reason) async =>
      (await client.rpc(
        'update_user_report',
        params: {
          'p_report_id': reportId,
          'p_action': action,
          'p_reason': reason,
        },
      )) as String;
}
