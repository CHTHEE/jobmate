import 'package:flutter/material.dart';

import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../evaluations/rating_display.dart';

int _count(Map<String, dynamic> row, String key) =>
    (row[key] as num?)?.toInt() ?? 0;

class _RatingSummary extends StatelessWidget {
  const _RatingSummary(this.row);
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final rating = row['core_average'] as num?;
    final published = _count(row, 'published_application_count');
    final rated = _count(row, 'rated_application_count');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rating == null ? 'No ratings yet' : formatRating(rating),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (rating != null) RatingStars(rating: rating),
        const SizedBox(height: 8),
        Text('$rated rated applications'),
        Text('$published published evaluations'),
      ],
    );
  }
}

class WorkerReputationSummary extends StatelessWidget {
  const WorkerReputationSummary({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) => ResponsiveGrid(
    maxColumns: 2,
    equalRowHeight: true,
    children: [
      WorkspaceCard(
        title: 'Evaluation Rating',
        leading: const Icon(Icons.rate_review_outlined),
        child: _RatingSummary(row),
      ),
      WorkspaceCard(
        title: 'Verified Work',
        leading: const Icon(Icons.verified_outlined),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _count(row, 'verified_completed_shift_count').toString(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Verified completed shifts'),
          ],
        ),
      ),
    ],
  );
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
      subtitle: 'Evaluation Rating',
      leading: const Icon(Icons.business_outlined),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RatingSummary(row),
          const SizedBox(height: 8),
          if (criteria.isEmpty)
            const Text('No published criterion ratings yet.')
          else
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              title: const Text('View rating breakdown'),
              children: [
                for (final item in criteria)
                  RatingBreakdownRow(
                    label:
                        "${item['label']} (${item['sample_count']} applications)",
                    rating: item['average'] as num?,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
