import 'package:jobmate/features/phase4/reputation_gateway.dart';

/// Deterministic read-only reputation data for layout and presentation tests.
class ReputationGatewayFixture implements ReputationGateway {
  @override
  Future<Map<String, dynamic>> workerSummary() async => {
    'core_average': 4.25,
    'published_application_count': 3,
    'rated_application_count': 2,
    'verified_completed_shift_count': 4,
  };

  @override
  Future<List<Map<String, dynamic>>> companySummaries() async => [
    {
      'company_name': 'Synthetic Company',
      'core_average': 4.5,
      'published_application_count': 2,
      'rated_application_count': 2,
      'criteria_averages': [
        {'label': 'Communication', 'average': 4.5, 'sample_count': 2},
      ],
    },
  ];
}
