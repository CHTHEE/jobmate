import 'package:flutter/material.dart';

import '../../shared/widgets/app_workspace.dart';

int _count(Map<String, dynamic> row, String key) =>
    (row[key] as num?)?.toInt() ?? 0;

String _average(Object? value) => value == null
    ? 'No ratings yet'
    : '${(value as num).toStringAsFixed(2)} / 5';

Widget _metric(BuildContext context, String value, String detail) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(value, style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 4),
    Text(detail),
  ],
);

/// The same aggregate presentation is used on self and applicant profiles.
class WorkerReputationSummary extends StatelessWidget {
  const WorkerReputationSummary({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final published = _count(row, 'published_application_count');
    final rated = _count(row, 'rated_application_count');
    final shifts = _count(row, 'verified_completed_shift_count');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspaceCard(
          title: 'Evaluation',
          subtitle: 'Company evaluations revealed after both sides submit.',
          leading: const Icon(Icons.rate_review_outlined),
          child: _metric(
            context,
            _average(row['core_average']),
            '$rated Core-rated applications - $published published evaluations',
          ),
        ),
        const SizedBox(height: 12),
        WorkspaceCard(
          title: 'Working Performance',
          subtitle:
              'Verified work records only; each row is one scheduled Shift.',
          leading: const Icon(Icons.verified_outlined),
          child: _metric(
            context,
            shifts == 0 ? 'No verified completed Shifts yet' : '$shifts',
            'completed and verified Shifts',
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Applications have equal weight in the evaluation average. Shifts with an unresolved related dispute are excluded. Attendance and punctuality are not scored.',
        ),
      ],
    );
  }
}

class CompanyReputationSummary extends StatelessWidget {
  const CompanyReputationSummary({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final criteria = (row['criteria_averages'] as List? ?? const []).map(
      (item) => Map<String, dynamic>.from(item as Map),
    );
    return WorkspaceCard(
      title: row['company_name'] as String? ?? 'Company',
      subtitle: 'Evaluation - Worker feedback revealed after both sides submit',
      leading: const Icon(Icons.business_outlined),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _metric(
            context,
            _average(row['core_average']),
            '${_count(row, 'rated_application_count')} Core-rated applications - ${_count(row, 'published_application_count')} published evaluations',
          ),
          const SizedBox(height: 16),
          const Text('Criteria breakdown'),
          const SizedBox(height: 8),
          for (final item in criteria)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${item['label']}: ${item['average'] == null ? 'No ratings' : _average(item['average'])} (${item['sample_count']} applications)',
              ),
            ),
          if (criteria.isEmpty)
            const Text('No published criterion ratings yet.'),
        ],
      ),
    );
  }
}
