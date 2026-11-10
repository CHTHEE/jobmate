import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_membership_details.dart';

/// The database validates permissions and performs all account mutations.
abstract class UserManagementGateway {
  Future<Map<String, dynamic>?> directoryDetails(String userId);
  Future<Map<String, dynamic>?> details(String userId);
  Future<List<Map<String, dynamic>>> history(String userId, int offset);
  Future<void> changeStatus(String userId, String action, String? reason);
}

class SupabaseUserManagementGateway implements UserManagementGateway {
  SupabaseUserManagementGateway(this.client)
    : _actorId = client.auth.currentUser?.id;

  final SupabaseClient client;
  final String? _actorId;

  void _checkSession() {
    if (_actorId == null || client.auth.currentUser?.id != _actorId) {
      throw StateError(
        'Your signed-in account changed. Reopen User management.',
      );
    }
  }

  @override
  Future<Map<String, dynamic>?> directoryDetails(String userId) async {
    _checkSession();
    final result = await client.rpc(
      'get_admin_user_directory_details',
      params: {'p_user_id': userId},
    );
    _checkSession();
    if (result is! List || result.length > 1) {
      throw const FormatException('Unexpected directory details.');
    }
    return result.isEmpty
        ? null
        : Map<String, dynamic>.from(result.first as Map);
  }

  @override
  Future<Map<String, dynamic>?> details(String userId) async {
    _checkSession();
    final result = await client.rpc(
      'get_user_account_details',
      params: {'p_target_user_id': userId},
    );
    _checkSession();
    return normalizeUserMembershipDetails(result, userId);
  }

  @override
  Future<List<Map<String, dynamic>>> history(String userId, int offset) async {
    _checkSession();
    final result = await client.rpc(
      'list_user_account_actions',
      params: {'p_target_user_id': userId, 'p_limit': 21, 'p_offset': offset},
    );
    _checkSession();
    if (result is! List) {
      throw const FormatException('Unexpected account history.');
    }
    return result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<void> changeStatus(
    String userId,
    String action,
    String? reason,
  ) async {
    _checkSession();
    final result = await client.rpc(
      'set_user_account_status',
      params: {
        'p_target_user_id': userId,
        'p_action': action,
        'p_reason': reason,
      },
    );
    _checkSession();
    final expected = action == 'suspend' ? 'suspended' : 'active';
    if (result != expected) {
      throw const FormatException(
        'Unable to confirm the saved account status.',
      );
    }
  }
}
