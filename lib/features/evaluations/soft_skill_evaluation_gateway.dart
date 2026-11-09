import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SoftSkillEvaluationGateway {
  Future<List<Map<String, dynamic>>> candidates(String direction);
  Future<List<Map<String, dynamic>>> history();
  Future<String> submit({
    required String applicationId,
    required String direction,
    required List<String> selectedAdditionalSkillIds,
    required Map<String, dynamic> ratings,
    required String? comment,
  });
}

class SupabaseSoftSkillEvaluationGateway
    implements SoftSkillEvaluationGateway {
  SupabaseSoftSkillEvaluationGateway(this.client)
    : _actorId = client.auth.currentUser?.id;

  final SupabaseClient client;
  final String? _actorId;

  void _checkSession() {
    if (_actorId == null || client.auth.currentUser?.id != _actorId) {
      throw StateError('Your account changed. Reopen Evaluations to continue.');
    }
  }

  Future<dynamic> _rpc(String name, [Map<String, dynamic>? parameters]) async {
    _checkSession();
    final result = await client.rpc(name, params: parameters);
    _checkSession();
    return result;
  }

  List<Map<String, dynamic>> _rows(dynamic result) => (result as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  @override
  Future<List<Map<String, dynamic>>> candidates(String direction) async =>
      _rows(
        await _rpc(
          'list_application_evaluation_candidates',
          {'p_direction': direction},
        ),
      );

  @override
  Future<List<Map<String, dynamic>>> history() async =>
      _rows(await _rpc('list_my_application_soft_skill_evaluations'));

  @override
  Future<String> submit({
    required String applicationId,
    required String direction,
    required List<String> selectedAdditionalSkillIds,
    required Map<String, dynamic> ratings,
    required String? comment,
  }) async =>
      (await _rpc('submit_application_soft_skill_evaluation', {
            'p_application_id': applicationId,
            'p_direction': direction,
            'p_selected_additional_skill_ids': selectedAdditionalSkillIds,
            'p_ratings': ratings,
            'p_comment': comment,
          }))
          as String;
}