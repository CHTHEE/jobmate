import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAccountsPage {
  const AdminAccountsPage({
    required this.accounts,
    required this.totalCount,
    required this.hasMore,
  });

  final List<Map<String, dynamic>> accounts;
  final int totalCount;
  final bool hasMore;
}

abstract class AdminAccountsRepository {
  Future<AdminAccountsPage> fetchPage({
    required String? role,
    required String? status,
    required String search,
    required int limit,
    required int offset,
  });
}

class SupabaseAdminAccountsRepository implements AdminAccountsRepository {
  SupabaseAdminAccountsRepository(this.client)
    : _actorId = client.auth.currentUser?.id;

  final SupabaseClient client;
  final String? _actorId;

  void _checkSession() {
    if (_actorId == null || client.auth.currentUser?.id != _actorId) {
      throw StateError(
        'Your signed-in account has changed. Reopen User management.',
      );
    }
  }

  @override
  Future<AdminAccountsPage> fetchPage({
    required String? role,
    required String? status,
    required String search,
    required int limit,
    required int offset,
  }) async {
    _checkSession();
    final response = await client.rpc(
      'list_user_accounts_page_v1',
      params: {
        'p_role': role,
        'p_status': status,
        'p_search': search,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    _checkSession();
    if (response is! Map) {
      throw const FormatException('Unexpected user directory page response.');
    }
    final accounts = response['accounts'];
    final totalCount = response['total_count'];
    final hasMore = response['has_more'];
    if (accounts is! List || totalCount is! num || hasMore is! bool) {
      throw const FormatException('Invalid user directory page response.');
    }
    return AdminAccountsPage(
      accounts: accounts
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(),
      totalCount: totalCount.toInt(),
      hasMore: hasMore,
    );
  }
}
