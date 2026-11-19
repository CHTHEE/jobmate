import 'package:jobmate/features/phase4/reputation_gateway.dart';

class FakeReputationGateway implements ReputationGateway {
  @override
  Future<Map<String, dynamic>> workerSummary() async => {
    'published_application_count': 2,
    'rated_application_count': 2,
    'core_average': 4.5,
    'verified_completed_shift_count': 3,
  };

  @override
  Future<List<Map<String, dynamic>>> companySummaries() async => [
    {
      'company_name': 'Fixture Company',
      'published_application_count': 2,
      'rated_application_count': 2,
      'core_average': 4.5,
      'criteria_averages': <Map<String, dynamic>>[],
    },
  ];
}