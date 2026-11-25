import 'package:supabase_flutter/supabase_flutter.dart';

import 'recommendation_explanations.dart';

/// Sends explicitly requested insights to the recommendation Edge Function.
class SupabaseRecommendationExplanationSource
    implements RecommendationExplanationSource {
  const SupabaseRecommendationExplanationSource(this.client);

  final SupabaseClient client;
  static final _jobId = RegExp(r'^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$');

  @override
  Future<Object?> fetch(
    List<ExplanationJob> jobs, {
    Future<void>? abortSignal,
  }) async {
    final session = client.auth.currentSession;
    if (session == null) throw StateError('Sign in to request posting notes.');
    final userId = session.user.id;
    final ids = jobs.map((job) => job.jobId).toList();
    if (ids.isEmpty ||
        ids.length > RecommendationExplanations.shortlistLimit ||
        ids.toSet().length != ids.length ||
        ids.any((id) => !_jobId.hasMatch(id))) {
      throw ArgumentError('Invalid recommendation shortlist.');
    }
    final response = await client.functions.invoke(
      'recommendation-insights',
      abortSignal: abortSignal,
      body: {
        'job_ids': ids,
        'insights_version': RecommendationExplanations.insightsVersion,
      },
    );
    final current = client.auth.currentSession;
    if (current?.user.id != userId ||
        current?.accessToken != session.accessToken) {
      throw StateError('Your session changed while loading posting notes.');
    }
    if (response.status < 200 || response.status >= 300) {
      throw FunctionException(status: response.status);
    }
    return response.data;
  }
}
