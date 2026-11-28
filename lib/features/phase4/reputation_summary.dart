import 'package:material_ui/material_ui.dart';

import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../evaluations/radar_chart.dart';
import '../evaluations/rating_display.dart';

int _count(Map<String, dynamic> row, String key) =>
    (row[key] as num?)?.toInt() ?? 0;

List<RadarChartCriterion> _coreRadarCriteria(Map<String, dynamic> row) {
  const core = ['communication', 'responsibility', 'professionalism'];
  final values = (row['criteria_averages'] as List? ?? const [])
      .whereType<Map>()
      .map(Map<String, dynamic>.from)
      .where(
        (item) =>
            core.contains(item['skill_id']) &&
            item['skill_id'] is String &&
            item['label'] is String &&
            item['average'] is num &&
            (item['average'] as num).isFinite &&
            (item['average'] as num) >= 1 &&
            (item['average'] as num) <= 5,
      )
      .map(
        (item) => RadarChartCriterion(
          id: item['skill_id'] as String,
          label: item['label'] as String,
          score: (item['average'] as num).toDouble(),
        ),
      )
      .toList(growable: false);
  values.sort(
    (left, right) => core.indexOf(left.id).compareTo(core.indexOf(right.id)),
  );
  return values;
}

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

List<RadarChartCriterion> _workerSkillAxes(Map<String, dynamic> row) {
  final observed = {for (final axis in _coreRadarCriteria(row)) axis.id: axis};
  const core = {
    'communication': 'Communication',
    'responsibility': 'Responsibility',
    'professionalism': 'Professionalism',
  };
  const additional = {'adaptability': 'Adaptability', 'teamwork': 'Teamwork'};
  final comparable = <String, RadarChartCriterion>{};
  for (final item
      in (row['additional_skill_averages'] as List? ?? const [])
          .whereType<Map>()) {
    final id = item['skill_id'];
    final score = item['average'];
    if (id is String &&
        additional.containsKey(id) &&
        score is num &&
        score.isFinite &&
        score >= 1 &&
        score <= 5) {
      comparable[id] = RadarChartCriterion(
        id: id,
        label: additional[id]!,
        score: score.toDouble(),
      );
    }
  }
  return [
    for (final axis in core.entries)
      observed[axis.key] ??
          RadarChartCriterion(id: axis.key, label: axis.value, score: null),
    for (final id in additional.keys) ?comparable[id],
  ];
}

bool _hasObservedSkills(List<RadarChartCriterion> criteria) => criteria.any(
  (criterion) => criterion.score != null && !criterion.notObserved,
);

class WorkerReputationSummary extends StatelessWidget {
  const WorkerReputationSummary({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final criteria = _workerSkillAxes(row);
    final recentEvaluations = (row['recent_evaluations'] as List? ?? const [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
    final breakdown = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final criterion in criteria)
          RatingBreakdownRow(
            label: criterion.label,
            rating: criterion.score,
            unratedLabel: 'Not rated',
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
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
        ),
        const SizedBox(height: 12),
        WorkspaceCard(
          title: 'Soft Skill Profile',
          subtitle: criteria.length > 3
              ? 'Published received evaluations. Additional skills do not count toward the Evaluation Rating.'
              : 'Published received evaluations · Core skills only',
          leading: const Icon(Icons.insights_outlined),
          child: !_hasObservedSkills(criteria)
              ? const Text('No published skill ratings are available yet.')
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final chart = EvaluationRadarChart(criteria: criteria);
                    return constraints.maxWidth >=
                            600 *
                                MediaQuery.textScalerOf(context).scale(14) /
                                14
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: chart),
                              const SizedBox(width: 24),
                              Expanded(child: breakdown),
                            ],
                          )
                        : Column(children: [chart, breakdown]);
                  },
                ),
        ),
        if (recentEvaluations.isNotEmpty) ...[
          const SizedBox(height: 12),
          WorkspaceCard(
            title: 'Recent published evaluations',
            child: Column(
              children: [
                for (final evaluation in recentEvaluations)
                  _RecentEvaluationSummary(evaluation),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class CompactWorkerReputationSummary extends StatelessWidget {
  const CompactWorkerReputationSummary({
    super.key,
    required this.row,
    this.onViewFull,
  });

  final Map<String, dynamic> row;
  final VoidCallback? onViewFull;

  @override
  Widget build(BuildContext context) {
    final criteria = _workerSkillAxes(row);
    final metrics = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Evaluation Rating'),
        _RatingSummary(row),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            Text(
              '${_count(row, 'verified_completed_shift_count')}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Text('Verified completed shifts'),
          ],
        ),
        if (onViewFull != null)
          TextButton(
            onPressed: onViewFull,
            child: const Text('View Full Reputation'),
          ),
      ],
    );
    return WorkspaceCard(
      title: 'Professional reputation',
      leading: const Icon(Icons.insights_outlined, size: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chart = !_hasObservedSkills(criteria)
              ? const Text('No published skill ratings are available yet.')
              : Column(
                  children: [
                    EvaluationRadarChart(
                      criteria: criteria,
                      presentation: RadarChartPresentation.compact,
                    ),
                    if (criteria.length > 3)
                      const Text(
                        'Additional skills are outside the Evaluation Rating.',
                      ),
                  ],
                );
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          if (constraints.maxWidth >= 560 * scale) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: metrics),
                const SizedBox(width: 16),
                Expanded(child: chart),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [metrics, const SizedBox(height: 8), chart],
          );
        },
      ),
    );
  }
}

class _RecentEvaluationSummary extends StatelessWidget {
  const _RecentEvaluationSummary(this.evaluation);

  final Map<String, dynamic> evaluation;

  @override
  Widget build(BuildContext context) {
    final submitted = DateTime.tryParse('${evaluation['submitted_at'] ?? ''}');
    final average = evaluation['core_average'] as num?;
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        title: Text(
          '${evaluation['job_title'] ?? 'Job'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            if (evaluation['company_label'] case final String company) company,
            if (submitted != null)
              '${submitted.toLocal().day}/${submitted.toLocal().month}/${submitted.toLocal().year}',
            if (evaluation['company_label'] == null && submitted == null)
              'Published received evaluation',
          ].join(' · '),
        ),
        trailing: average == null
            ? const Text('Not rated')
            : Text(formatRating(average)),
      ),
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
    final radarCriteria = _coreRadarCriteria(row);
    return WorkspaceCard(
      title: row['company_name'] as String? ?? 'Company',
      subtitle: 'Evaluation Rating',
      leading: const Icon(Icons.business_outlined),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RatingSummary(row),
          const SizedBox(height: 8),
          if (radarCriteria.length >= 3) ...[
            EvaluationRadarChart(
              criteria: radarCriteria,
              presentation: RadarChartPresentation.compact,
            ),
            const SizedBox(height: 8),
          ],
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
