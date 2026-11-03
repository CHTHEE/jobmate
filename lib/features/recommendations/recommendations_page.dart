import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../applications/module2_repository.dart';
import '../applications/module2_widgets.dart';
import '../applications/job_details_page.dart';
import '../demo_work/demo_widgets.dart';
import '../jobs/job_display.dart';

class DemoMatch {
  DemoMatch(this.job) {
    final special = switch (job.id) {
      'demo-job-1' => ['retail'],
      'demo-job-2' => ['dart', 'flutter'],
      'demo-job-3' => ['customer service'],
      _ => ['event setup'],
    };
    final requiredSkills = {
      ...job.bullets('requirements').map((s) => s.toLowerCase()),
      ...special,
    };
    matched = requiredSkills.intersection(profileSkills).toList();
    missing = requiredSkills.difference(profileSkills).toList();
    score =
        (70 * matched.length / requiredSkills.length +
                (job.text('location') == 'Shah Alam' ? 20 : 0) +
                (job.text('employment_type') == 'part_time' ? 10 : 0))
            .round();
  }
  static const profileSkills = {
    'communication skills',
    'willingness to learn',
    'retail',
  };
  final BrowseJob job;
  late final List<String> matched, missing;
  late final int score;
  String get label => score >= 90
      ? 'Excellent'
      : score >= 75
      ? 'Strong'
      : score >= 60
      ? 'Good'
      : 'Fair';
}

class RecommendationsPage extends StatefulWidget {
  const RecommendationsPage({super.key, this.repository});
  final Module2Repository? repository;
  @override
  State<RecommendationsPage> createState() => _RecommendationsPageState();
}

class _RecommendationsPageState extends State<RecommendationsPage> {
  late final repo = widget.repository ?? Module2Repository.session;
  String location = '',
      type = '',
      category = '',
      minimum = '0',
      sort = 'Match score';
  void clear() => setState(() {
    location = '';
    type = '';
    category = '';
    minimum = '0';
    sort = 'Match score';
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final matches = repo
          .searchJobs(location: location, type: type)
          .where((j) => category.isEmpty || j.text('department') == category)
          .map(DemoMatch.new)
          .where((m) => m.score >= int.parse(minimum))
          .toList();
      matches.sort(
        (a, b) => sort == 'Title'
            ? a.job.title.compareTo(b.job.title)
            : b.score.compareTo(a.score),
      );
      return DemoPage(
        title: 'For You',
        path: AppRoutes.recommendations,
        role: 'job_seeker',
        children: [
          const Phase3Notice(
            'AI transparency: this page uses a deterministic demo score, not Gemini or an AI recommendation service. Matches do not guarantee placement. No personal profile is analysed.',
          ),
          Text(
            'Opportunities for you',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Sample profile: communication, willingness to learn and retail; prefers Shah Alam and part-time work. Score: 70% skill overlap + 20% location + 10% type.',
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              ModuleSelect(
                label: 'Location',
                value: location,
                options: {
                  '': 'All locations',
                  for (final j in repo.searchJobs())
                    j.text('location'): j.text('location'),
                },
                onChanged: (v) => setState(() => location = v),
              ),
              ModuleSelect(
                label: 'Type',
                value: type,
                options: {
                  '': 'All types',
                  for (final j in repo.searchJobs())
                    j.text('employment_type'): jobLabel(
                      j.text('employment_type'),
                    ),
                },
                onChanged: (v) => setState(() => type = v),
              ),
              ModuleSelect(
                label: 'Category',
                value: category,
                options: {
                  '': 'All categories',
                  for (final j in repo.searchJobs())
                    j.text('department'): j.text('department'),
                },
                onChanged: (v) => setState(() => category = v),
              ),
              ModuleSelect(
                label: 'Minimum demo match',
                value: minimum,
                options: const {
                  '0': 'All matches',
                  '60': '60% • Good+',
                  '75': '75% • Strong+',
                  '90': '90% • Excellent',
                },
                onChanged: (v) => setState(() => minimum = v),
              ),
              ModuleSelect(
                label: 'Sort',
                value: sort,
                options: const {'Match score': 'Match score', 'Title': 'Title'},
                onChanged: (v) => setState(() => sort = v),
              ),
              TextButton(onPressed: clear, child: const Text('Clear filters')),
            ],
          ),
          const SizedBox(height: 24),
          Text('${matches.length} demo recommendations'),
          const SizedBox(height: 16),
          if (matches.isEmpty)
            ModuleState(
              title: 'No matching recommendations',
              message: 'Change your filters to explore the sample catalogue.',
              action: clear,
              actionLabel: 'Clear filters',
            ),
          for (final match in matches)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: WorkspaceCard(
                title: match.job.title,
                subtitle: match.job.company,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox.expand(
                                child: CircularProgressIndicator(
                                  value: match.score / 100,
                                  strokeWidth: 5,
                                ),
                              ),
                              Text('${match.score}%'),
                            ],
                          ),
                        ),
                        Chip(label: Text('${match.label} • demo score')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    JobFacts(match.job),
                    const SizedBox(height: 12),
                    const Text('Matched skills'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final skill in match.matched)
                          Chip(
                            avatar: const Icon(Icons.check, size: 16),
                            label: Text(skill),
                          ),
                      ],
                    ),
                    const Text('Skills to develop'),
                    Text(
                      match.missing.isEmpty
                          ? 'No gaps in the sample skill set'
                          : match.missing.join(', '),
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Why recommended?'),
                      children: [
                        Text(
                          '${match.matched.length} of ${match.matched.length + match.missing.length} sample skills match. Location preference: ${match.job.text('location') == 'Shah Alam' ? 'matches' : 'does not match'}. Part-time preference: ${match.job.text('employment_type') == 'part_time' ? 'matches' : 'does not match'}. No work history or protected attributes are used.',
                        ),
                      ],
                    ),
                    const Text(
                      'Company reputation is not connected; no rating is asserted.',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton(
                          onPressed: () => context.push(
                            '${AppRoutes.browseJobs}/${match.job.id}',
                          ),
                          child: const Text('View Job'),
                        ),
                        OutlinedButton(
                          onPressed: () => repo.toggleSave(match.job.id),
                          child: Text(
                            repo.saved(match.job.id)
                                ? 'Unsave (demo)'
                                : 'Save (demo)',
                          ),
                        ),
                        FilledButton(
                          onPressed:
                              match.job.unavailable() != null ||
                                  repo.applied(match.job.id)
                              ? null
                              : () => moduleModal<void>(
                                  context,
                                  ApplyDemoForm(
                                    job: match.job,
                                    repository: repo,
                                  ),
                                ),
                          child: Text(
                            repo.applied(match.job.id)
                                ? 'Applied in demo'
                                : 'Apply (demo)',
                          ),
                        ),
                      ],
                    ),
                    if (match.job.unavailable() case final String reason)
                      Text(reason),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
