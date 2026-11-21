import 'package:supabase_flutter/supabase_flutter.dart';

typedef AdminPermissionListRpcVersion = ({String name, int schemaVersion});

const _adminPermissionListV10Fields = <String>{
  'user_id',
  'name',
  'email',
  'profile_image_url',
  'account_status',
  'can_manage_admin_permissions',
  'can_invite_admins',
  'can_review_companies',
  'can_manage_user_accounts',
  'can_manage_disputes',
  'dispute_management_available',
  'can_manage_company_restrictions',
  'can_manage_user_reports',
  'user_reports_available',
  'can_manage_job_moderation',
  'can_view_internal_trust_scores',
};

const _adminPermissionListV10RequiredBooleans = <String>{
  'can_manage_admin_permissions',
  'can_invite_admins',
  'can_review_companies',
  'can_manage_user_accounts',
  'dispute_management_available',
  'can_manage_company_restrictions',
  'user_reports_available',
  'can_manage_job_moderation',
  'can_view_internal_trust_scores',
};

const _adminPermissionListV10NullableBooleans = <String>{
  'can_manage_disputes',
  'can_manage_user_reports',
};

/// The new projection is queried only by the Debug-only Internal Trust gate.
/// Gate-off builds retain the established v9-to-v2 fallback sequence.
List<AdminPermissionListRpcVersion> adminPermissionListRpcVersions({
  required bool includeInternalTrustProjection,
}) => [
  if (includeInternalTrustProjection)
    (name: 'list_admin_accounts_v10', schemaVersion: 10),
  (name: 'list_admin_accounts_v9', schemaVersion: 9),
  (name: 'list_admin_accounts_v8', schemaVersion: 8),
  (name: 'list_admin_accounts_v7', schemaVersion: 7),
  (name: 'list_admin_accounts_v6', schemaVersion: 6),
  (name: 'list_admin_accounts_v5', schemaVersion: 5),
  (name: 'list_admin_accounts_v4', schemaVersion: 4),
  (name: 'list_admin_accounts_v3', schemaVersion: 3),
  (name: 'list_admin_accounts_v2', schemaVersion: 2),
];

/// Rejects malformed or expanded v10 rows. A missing permission boolean is not
/// equivalent to false; callers must not render a sensitive control from it.
List<Map<String, dynamic>> validateAdminPermissionListV10(dynamic response) {
  if (response is! List) {
    throw const FormatException('Unexpected administrator list response.');
  }

  return response
      .map<Map<String, dynamic>>((item) {
        if (item is! Map) {
          throw const FormatException('Unexpected administrator list row.');
        }
        final row = Map<String, dynamic>.from(item);
        if (row.keys.toSet().length != _adminPermissionListV10Fields.length ||
            !row.keys.toSet().containsAll(_adminPermissionListV10Fields)) {
          throw const FormatException('Unexpected administrator list fields.');
        }
        if (row['user_id'] is! String ||
            (row['user_id'] as String).isEmpty ||
            row['account_status'] is! String ||
            (row['account_status'] as String).isEmpty) {
          throw const FormatException(
            'Invalid administrator identity response.',
          );
        }
        for (final field in const ['name', 'email', 'profile_image_url']) {
          if (row[field] != null && row[field] is! String) {
            throw FormatException('Invalid administrator $field response.');
          }
        }
        for (final field in _adminPermissionListV10RequiredBooleans) {
          if (row[field] is! bool) {
            throw FormatException('Invalid administrator $field response.');
          }
        }
        for (final field in _adminPermissionListV10NullableBooleans) {
          if (row[field] != null && row[field] is! bool) {
            throw FormatException('Invalid administrator $field response.');
          }
        }
        return row;
      })
      .toList(growable: false);
}

abstract interface class AdminInternalTrustPermissionGateway {
  Future<void> setPermission({
    required String targetUserId,
    required bool canView,
  });
}

String internalTrustPermissionFailureMessage(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is StateError) return error.message.toString();
  return 'Unable to update Internal Trust access. Reloading saved permissions.';
}

/// Uses the current authenticated Admin session only. Server-side authorization
/// remains authoritative for both Superadmin status and target eligibility.
class SupabaseAdminInternalTrustPermissionGateway
    implements AdminInternalTrustPermissionGateway {
  SupabaseAdminInternalTrustPermissionGateway(this._client)
    : _actorId = _client.auth.currentUser?.id;

  final SupabaseClient _client;
  final String? _actorId;

  void _checkSession() {
    if (_actorId == null || _client.auth.currentUser?.id != _actorId) {
      throw StateError('Your administrator account changed. Reopen this page.');
    }
  }

  @override
  Future<void> setPermission({
    required String targetUserId,
    required bool canView,
  }) async {
    _checkSession();
    await _client.rpc(
      'set_admin_internal_trust_score_permission',
      params: {'p_target_user_id': targetUserId, 'p_can_view': canView},
    );
    _checkSession();
  }
}
