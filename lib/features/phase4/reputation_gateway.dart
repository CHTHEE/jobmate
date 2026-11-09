import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class ReputationGateway {
  Future<Map<String, dynamic>> workerSummary();
  Future<List<Map<String, dynamic>>> companySummaries();
}

class SupabaseReputationGateway implements ReputationGateway {
  SupabaseReputationGateway(this.client) : _actorId = client.auth.currentUser?.id;

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
  Future<Map<String, dynamic>> workerSummary() async {
    final rows = (await _rpc('get_my_worker_reputation')) as List;
    if (rows.length != 1) {
      throw const FormatException('Worker reputation summary is unavailable.');
    }
    return Map<String, dynamic>.from(rows.single as Map);
  }

  @override
  Future<List<Map<String, dynamic>>> companySummaries() async =>
      ((await _rpc('get_my_company_reputation')) as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
}
