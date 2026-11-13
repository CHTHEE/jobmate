import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class CompanyManagementGateway {
  Future<List<Map<String, dynamic>>> list({
    required int limit,
    required int offset,
    String? search,
    String? verificationStatus,
    String? restrictionStatus,
  });
  Future<bool> canManageRestrictions();
  Future<Map<String, dynamic>> details(String companyId);
  Future<Map<String, dynamic>> managementDetails(String companyId);
  Future<List<Map<String, dynamic>>> history(String companyId);
  Future<void> setRestriction(String companyId, String action, String reason);
}

class SupabaseCompanyManagementGateway implements CompanyManagementGateway {
  const SupabaseCompanyManagementGateway(this.client);
  final SupabaseClient client;

  @override
  Future<List<Map<String, dynamic>>> list({
    required int limit,
    required int offset,
    String? search,
    String? verificationStatus,
    String? restrictionStatus,
  }) async {
    final result = await client.rpc(
      'list_admin_company_directory_v2',
      params: {
        'p_search': search,
        'p_verification_status': verificationStatus,
        'p_restriction_status': restrictionStatus,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    if (result is! List) {
      throw const FormatException('Unexpected company directory response.');
    }
    return result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<bool> canManageRestrictions() async {
    final actorId = client.auth.currentUser?.id;
    if (actorId == null) return false;
    try {
      final profile = await client
          .from('administrator_profiles')
          .select('*')
          .eq('user_id', actorId)
          .maybeSingle();
      return client.auth.currentUser?.id == actorId &&
          profile?['can_manage_company_restrictions'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> details(String companyId) async {
    final result = await client.rpc(
      'get_admin_company_directory_details',
      params: {'p_company_id': companyId},
    );
    if (result is! Map) {
      throw const FormatException('Unexpected company details response.');
    }
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<Map<String, dynamic>> managementDetails(String companyId) async {
    final result = await client.rpc(
      'get_managed_company',
      params: {'p_company_id': companyId},
    );
    if (result is! Map) {
      throw const FormatException(
        'Unexpected managed company details response.',
      );
    }
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<List<Map<String, dynamic>>> history(String companyId) async {
    final result = await client.rpc(
      'list_company_restriction_history',
      params: {'p_company_id': companyId, 'p_limit': 51, 'p_offset': 0},
    );
    if (result is! List) {
      throw const FormatException('Unexpected restriction history response.');
    }
    return result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<void> setRestriction(
    String companyId,
    String action,
    String reason,
  ) async {
    await client.rpc(
      'set_company_restriction',
      params: {
        'p_company_id': companyId,
        'p_action': action,
        'p_reason': reason,
      },
    );
  }
}
