import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/ai_service_notice.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/expandable_filter_bar.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../applications/browse_job_card.dart' show JobListingMetadata;
import '../applications/job_details_page.dart';
import '../applications/job_marketplace_format.dart';
import '../applications/module2_repository.dart';
import '../applications/module2_widgets.dart';
import '../applications/published_company_logo.dart';
import '../jobs/job_display.dart';
import '../profile/job_seeker_profile_sections.dart';
import 'job_matching.dart';
import 'recommendation_explanations.dart';

class RecommendationsPage extends StatefulWidget {
  const RecommendationsPage({
    super.key,
    this.repository,
    this.loadProfile,
    this.explanationSource,
    this.now,
  });

  final Module2Repository? repository;
  final Future<JobSeekerProfileData> Function(String userId)? loadProfile;
  final RecommendationExplanationSource? explanationSource;
  final DateTime Function()? now;

  @override
  State<RecommendationsPage> createState() => _RecommendationsPageState();
}

class _RecommendationsPageState extends State<RecommendationsPage> {
  static final _requestsBySession = Expando<RecommendationInsightRequests>();
  late final module = widget.repository ?? Module2Repository.session;
  late final jobs = module.browse;
  late final applications = module.myApplications;
  late final Listenable sources = Listenable.merge([jobs, applications]);
  late final StreamSubscription<String?> accountChanges;
  late final insightRequests = _requestsBySession[module] ??=
      RecommendationInsightRequests(now: widget.now);
  Timer? cooldownTick;
  final salaryController = TextEditingController();
  JobSeekerProfileData profile = const {};
  String? actor;
  bool loadingProfile = true;
  bool failedProfile = false;
  int generation = 0;
  String location = '', type = '', salaryPeriod = '', minimumScore = '0';
  String salaryInput = '';
  RecommendationSort sort = RecommendationSort.bestMatch;

  @override
  void initState() {
    super.initState();
    insightRequests.addListener(updateInsightStatus);
    accountChanges = jobs.source.accountChanges.listen((id) {
      if (!mounted || id == actor) return;
      clearFilters();
      unawaited(refresh());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) refresh();
    });
  }

  @override
  void didUpdateWidget(covariant RecommendationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.explanationSource, widget.explanationSource)) {
      activateInsights(actor);
    }
  }

  @override
  void dispose() {
    accountChanges.cancel();
    cooldownTick?.cancel();
    insightRequests.removeListener(updateInsightStatus);
    insightRequests.cancel(this);
    salaryController.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final userId = jobs.source.userId;
    activateInsights(userId);
    final request = ++generation;
    setState(() {
      actor = userId;
      profile = const {};
      failedProfile = false;
      loadingProfile = userId != null;
    });
    if (userId == null) return;
    unawaited(jobs.load());
    unawaited(applications.load());
    try {
      final data =
          await (widget.loadProfile?.call(userId) ??
              SupabaseJobSeekerProfileRepository(Supabase.instance.client)
                  .load(userId, matchingOnly: true));
      if (mounted && request == generation && jobs.source.userId == userId) {
        setState(() => profile = data);
      }
    } catch (_) {
      if (mounted && request == generation && jobs.source.userId == userId) {
        setState(() => failedProfile = true);
      }
    } finally {
      if (mounted && request == generation) {
        setState(() => loadingProfile = false);
      }
    }
  }

  Future<void> openJob(BrowseJob job, {bool apply = false}) async {
    await context.push<void>(
      '${AppRoutes.browseJobs}/${Uri.encodeComponent(job.id)}',
      extra: apply ? JobDetailsPage.applyIntent : null,
    );
    if (mounted && jobs.source.userId == actor) await applications.load();
  }

  void activateInsights(String? id) {
    insightRequests.activate(this, id, widget.explanationSource);
    scheduleCooldownTick();
  }

  void scheduleCooldownTick() {
    cooldownTick?.cancel();
    if (insightRequests.remaining > Duration.zero) {
      cooldownTick = Timer(const Duration(seconds: 1), updateInsightStatus);
    }
  }

  void updateInsightStatus() {
    if (!mounted) return;
    scheduleCooldownTick();
    setState(() {});
  }

  void clearFilters() => setState(() {
    location = type = salaryPeriod = salaryInput = '';
    minimumScore = '0';
    sort = RecommendationSort.bestMatch;
    salaryController.clear();
  });

  Future<void> loadExplanations(List<JobMatch> results) async {
    final userId = actor;
    if (userId == null ||
        jobs.source.userId != userId ||
        applications.source.userId != userId) {
      return;
    }
    await insightRequests.load(this, results);
  }

  @override
  Widget build(BuildContext context) => AppWorkspace(
    title: 'For You',
    path: AppRoutes.recommendations,
    role: 'job_seeker',
    child: WorkspaceContent(
      maxWidth: 1120,
      child: ListenableBuilder(listenable: sources, builder: buildResults),
    ),
  );

  Widget buildResults(BuildContext context, Widget? child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const PageHeading(
        title: 'Recommended for you',
        description: 'Discover opportunities based on your skills, experience and preferences.',
      ),
      const Padding(
        padding: EdgeInsets.only(bottom: JobMateTheme.space8),
        child: JobListingMetadata(
          LucideIcons.sparkles,
          'Estimated matches reflect profile fit only. Employers make hiring decisions separately.',
        ),
      ),
      const _MatchCalculation(),
      const SizedBox(height: JobMateTheme.space16),
      resultsContent(),
    ],
  );

  Widget resultsContent() {
    if (loadingProfile || jobs.loading || applications.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: JobMateTheme.space32),
        child: Center(
          child: Column(
            children: [
              ExcludeSemantics(child: CircularProgressIndicator()),
              SizedBox(height: JobMateTheme.space12),
              Text('Loading recommendations'),
            ],
          ),
        ),
      );
    }
    if (actor == null ||
        jobs.source.userId != actor ||
        applications.source.userId != actor) {
      return state(
        'Recommendations unavailable',
        'Sign in with an active Job Seeker account and retry.',
      );
    }
    if (!jobs.loaded) {
      return state(
        'Unable to load published jobs',
        jobs.error ?? 'Please retry.',
      );
    }
    if (failedProfile) {
      return state(
        'Unable to load your profile',
        'Retry to load your matching information.',
      );
    }
    if (!applications.loaded) {
      return state(
        'Unable to check previous applications',
        'Retry so jobs you already applied to can be excluded.',
      );
    }
    final now = widget.now?.call() ?? DateTime.now();
    final appliedJobIds = applications.applications
        .map((row) => row.jobId)
        .toSet();
    final published = jobs.jobs;
    final locations =
        published
            .where(
              (job) =>
                  job.unavailable(now) == null &&
                  !appliedJobIds.contains(job.id),
            )
            .map((job) => job.text('location'))
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final selectedLocation = locations.contains(location) ? location : '';
    final matches = matchJobs(
      published,
      profile,
      appliedJobIds: appliedJobIds,
      now: now,
      location: selectedLocation,
      employmentType: type,
    );
    final selectedSort =
        sort == RecommendationSort.salary && salaryPeriod.isEmpty
        ? RecommendationSort.bestMatch
        : sort;
    final parsedSalary = num.tryParse(salaryInput.trim());
    final validSalary =
        parsedSalary != null && parsedSalary.isFinite && parsedSalary >= 0;
    final results = filterMatches(
      matches,
      location: selectedLocation,
      employmentType: type,
      salaryPeriod: salaryPeriod,
      minimumSalary: salaryPeriod.isNotEmpty && validSalary
          ? parsedSalary
          : null,
      minimumScore: int.parse(minimumScore),
      sort: selectedSort,
    );
    final scored = results.where((match) => match.score != null).toList();
    final unscored = results.where((match) => match.score == null).toList();
    final activeFilters = [
      selectedLocation.isNotEmpty,
      type.isNotEmpty,
      salaryPeriod.isNotEmpty,
      salaryPeriod.isNotEmpty && validSalary,
      minimumScore != '0',
    ].where((active) => active).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (profile.values.every((rows) => rows.isEmpty) &&
            matches.any(
              (match) =>
                  match.limitedEvidenceReasons.contains(
                    LimitedEvidenceReason.profile,
                  ) &&
                  !match.limitedEvidenceReasons.contains(
                    LimitedEvidenceReason.jobRequirements,
                  ),
            ))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                await context.push<void>(AppRoutes.profile);
                if (mounted) await refresh();
              },
              child: const Text('Complete your profile for better matches'),
            ),
          ),
        ExpandableFilterBar(
          activeCount: activeFilters,
          onClear:
              (results.isNotEmpty || matches.isEmpty) &&
                  (activeFilters > 0 || sort != RecommendationSort.bestMatch)
              ? clearFilters
              : null,
          filters: [
            SizedBox(
              width: double.infinity,
              child: ResponsiveGrid(
                spacing: JobMateTheme.space12,
                minItemWidth: 150,
                maxColumns: 5,
                children: [
                  _RecommendationFilter(
                    label: 'Location',
                    value: selectedLocation,
                    options: {
                      '': 'All locations',
                      for (final value in locations) value: value,
                    },
                    onChanged: (value) => setState(() => location = value),
                  ),
                  _RecommendationFilter(
                    label: 'Employment type',
                    value: type,
                    options: {
                      '': 'All types',
                      for (final value in jobEmploymentTypes)
                        value: jobLabel(value),
                    },
                    onChanged: (value) => setState(() => type = value),
                  ),
                  _RecommendationFilter(
                    label: 'Salary period',
                    value: salaryPeriod,
                    options: {
                      '': 'Any period',
                      for (final value in jobSalaryPeriods)
                        value: jobLabel(value),
                    },
                    onChanged: (value) => setState(() => salaryPeriod = value),
                  ),
                  if (salaryPeriod.isNotEmpty)
                    TextFormField(
                      controller: salaryController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Minimum pay (RM)',
                        errorText: salaryInput.trim().isEmpty || validSalary
                            ? null
                            : 'Enter a valid amount',
                      ),
                      onChanged: (value) => setState(() => salaryInput = value),
                    ),
                  _RecommendationFilter(
                    label: 'Minimum match',
                    value: minimumScore,
                    options: const {
                      '0': 'Any match',
                      '25': '25% and above',
                      '50': '50% and above',
                      '70': '70% and above',
                      '90': '90% and above',
                    },
                    onChanged: (value) => setState(() => minimumScore = value),
                  ),
                  _RecommendationFilter(
                    label: 'Sort',
                    value: selectedSort.name,
                    options: {
                      'bestMatch': 'Best Match',
                      'newest': 'Newest',
                      if (salaryPeriod.isNotEmpty)
                        'salary': 'Highest disclosed minimum',
                    },
                    onChanged: (value) => setState(
                      () => sort = RecommendationSort.values.byName(value),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: JobMateTheme.space8),
          child: Text(
            'Selected location and employment type also count toward your estimated match.',
          ),
        ),
        const SizedBox(height: JobMateTheme.space16),
        if (!jobs.catalogueComplete) ...[
          const Text('The full published feed could not be confirmed.'),
          const SizedBox(height: JobMateTheme.space12),
        ],
        if (matches.isEmpty)
          ModuleState(
            title: 'No recommendations available yet',
            message: 'Browse published jobs to see current listings and their availability.',
            action: () => context.go(AppRoutes.browseJobs),
            actionLabel: 'Browse Jobs',
          )
        else if (results.isEmpty)
          ModuleState(
            title: 'No matching jobs found',
            message:
                'Try adjusting your filters to discover more opportunities.',
            action: clearFilters,
            actionLabel: 'Clear filters',
          ),
        if (results.isNotEmpty && widget.explanationSource != null)
          aiNotesControl(scored, hasUnscored: unscored.isNotEmpty),
        if (scored.isNotEmpty)
          resultSection('Your job matches', switch (selectedSort) {
            RecommendationSort.bestMatch =>
              'Ranked by your estimated profile fit.',
            RecommendationSort.newest => 'Newest job matches first.',
            RecommendationSort.salary => 'Highest disclosed minimum pay first.',
          }, scored),
        if (unscored.isNotEmpty) ...[
          if (scored.isNotEmpty) const SizedBox(height: JobMateTheme.space24),
          resultSection(
            'Other opportunities to explore',
            'These jobs may interest you, but there is not enough information to estimate your match.',
            unscored,
          ),
        ],
      ],
    );
  }

  Widget resultSection(
    String title,
    String description,
    List<JobMatch> matches,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '$title (${matches.length})',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Text(description, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: JobMateTheme.space12),
      if (matches.length == 1)
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: card(matches.single),
          ),
        )
      else
        ResponsiveGrid(
          minItemWidth: 420,
          maxColumns: 2,
          children: [for (final match in matches) card(match)],
        ),
    ],
  );

  Widget state(String title, String message) => ModuleState(
    title: title,
    message: message,
    action: refresh,
    actionLabel: 'Retry',
  );

  Widget aiNotesControl(List<JobMatch> results, {required bool hasUnscored}) {
    const padding = EdgeInsets.only(bottom: JobMateTheme.space16);
    if (insightRequests.hasLoaded) {
      final showCoverage =
          hasUnscored ||
          results.any((match) => insightRequests.planFor(match.job) == null);
      return Padding(
        padding: padding,
        child: _AiInsightsNotice(
          icon: LucideIcons.circleCheck,
          title: 'AI insights loaded',
          message: 'Personalised guidance is now available for jobs with AI insights. These insights adapt as you adjust your matching preferences.',
          footer: Text(
            'No need to reload insights when adjusting filters for the same jobs.'
            '${showCoverage ? '\nOnly jobs covered by the original request have AI insights.' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    if (insightRequests.loading) {
      return const Padding(
        padding: padding,
        child: _AiInsightsNotice(
          icon: LucideIcons.sparkles,
          title: 'Loading AI insights…',
          message: 'Your estimated matches are available while we prepare your guidance.',
        ),
      );
    }
    final shortlist = insightRequests.shortlist(results);
    final failure = insightRequests.failureFor(shortlist);
    final remaining = (insightRequests.remaining.inMilliseconds / 1000).ceil();
    if (shortlist.isNotEmpty &&
        (failure == null || failure == InsightFailure.temporary)) {
      final retry = failure == InsightFailure.temporary;
      final controls = Wrap(
        spacing: JobMateTheme.space8,
        runSpacing: JobMateTheme.space4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: remaining > 0 ? null : () => loadExplanations(results),
            icon: const Icon(LucideIcons.sparkles, size: 18),
            label: Text(retry ? 'Retry AI insights' : 'Load AI insights'),
            style: OutlinedButton.styleFrom(
              foregroundColor: JobMateTheme.teal800,
              backgroundColor: JobMateTheme.teal50,
            ),
          ),
          if (remaining > 0)
            Text(
              'Available in ${remaining}s',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (!retry)
            Text(
              'Optional · Available for up to ${RecommendationExplanations.shortlistLimit} recommended jobs at a time.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      );
      return Padding(
        padding: padding,
        child: retry
            ? AiServiceNotice(
                title: 'AI insights are temporarily unavailable',
                message: 'Our AI service is currently experiencing a temporary issue. You can still explore your recommended jobs, view match scores and apply as usual.',
                actions: controls,
              )
            : _AiInsightsNotice(
                icon: LucideIcons.sparkles,
                title: 'AI recommendation insights',
                message: 'Understand why a job may suit you, what requirements to consider, and how to strengthen your application based on your skills, experience and preferences.',
                footer: controls,
              ),
      );
    }
    final status = switch ((results.isEmpty, shortlist.isEmpty, failure)) {
      (true, _, _) =>
        'AI insights are available for jobs with an estimated match.',
      (_, true, _) => 'No jobs in these results support AI insights.',
      (_, _, InsightFailure.shortlist) => 'AI insights are unavailable for this selection. Your estimated matches are still available.',
      _ => 'AI insights are unavailable. Your estimated matches are still available.',
    };
    return Padding(
      padding: padding,
      child: Semantics(
        liveRegion: true,
        child: JobListingMetadata(LucideIcons.sparkles, status),
      ),
    );
  }

  Widget card(JobMatch match) {
    final job = match.job;
    final saved = jobs.saved(job.id);
    final salary = marketplaceSalary(job);
    final sections = widget.explanationSource != null && match.score != null
        ? insightRequests.planFor(job)?.sectionsFor(match) ??
              const <InsightSection>[]
        : const <InsightSection>[];
    final theme = Theme.of(context);
    final score = match.score;
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PublishedCompanyLogo(job: job, repository: jobs, size: 36),
        const SizedBox(width: JobMateTheme.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                job.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                job.company,
                style: const TextStyle(color: JobMateTheme.body),
              ),
            ],
          ),
        ),
      ],
    );
    final indicator = DecoratedBox(
      decoration: BoxDecoration(
        color: score == null ? JobMateTheme.background : JobMateTheme.teal50,
        borderRadius: BorderRadius.circular(JobMateTheme.controlRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          score == null
              ? 'Limited matching evidence'
              : 'Estimated Match $score%',
          style: theme.textTheme.labelMedium?.copyWith(
            color: score == null ? JobMateTheme.body : JobMateTheme.teal800,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(JobMateTheme.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                if (constraints.maxWidth >= 380 * scale) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: JobMateTheme.space12),
                      Flexible(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: indicator,
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    const SizedBox(height: JobMateTheme.space12),
                    indicator,
                  ],
                );
              },
            ),
            if (score != null) ...[
              const SizedBox(height: JobMateTheme.space12),
              ExcludeSemantics(
                child: LinearProgressIndicator(
                  value: score / 100,
                  minHeight: 4,
                  color: JobMateTheme.darkTeal,
                  backgroundColor: JobMateTheme.teal100,
                  borderRadius: BorderRadius.circular(
                    JobMateTheme.controlRadius,
                  ),
                ),
              ),
            ],
            const SizedBox(height: JobMateTheme.space16),
            Wrap(
              spacing: JobMateTheme.space12,
              runSpacing: JobMateTheme.space8,
              children: [
                if (job.text('location').isNotEmpty)
                  JobListingMetadata(LucideIcons.mapPin, job.text('location')),
                if (job.text('employment_type').isNotEmpty)
                  JobListingMetadata(
                    LucideIcons.briefcase,
                    jobLabel(job.text('employment_type')),
                  ),
                if (salary != salaryNotDisclosed)
                  JobListingMetadata(Icons.payments_outlined, salary),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: JobMateTheme.space8),
              child: Divider(color: JobMateTheme.divider),
            ),
            if (match.matchedSkills.isNotEmpty) ...[
              Text('Matching skills', style: theme.textTheme.titleSmall),
              const SizedBox(height: JobMateTheme.space4),
              Wrap(
                spacing: JobMateTheme.space8,
                runSpacing: JobMateTheme.space4,
                children: [
                  for (final skill in match.matchedSkills)
                    Chip(
                      label: Text(
                        skill,
                        style: const TextStyle(color: JobMateTheme.teal800),
                      ),
                      backgroundColor: JobMateTheme.teal50,
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: JobMateTheme.space8),
            ],
            if (match.skillsToDevelop.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: JobMateTheme.space8),
                child: Text(
                  'Skills to develop: ${match.skillsToDevelop.join(', ')}',
                ),
              ),
            Text(
              match.explanation.isEmpty && score == null
                  ? 'There is not enough comparable information to estimate your match. Review the job details to see if it suits you.'
                  : match.explanation,
              style: sections.isNotEmpty && score != null
                  ? theme.textTheme.bodySmall
                  : const TextStyle(color: JobMateTheme.body, height: 1.5),
            ),
            if (sections.isNotEmpty) ...[
              const SizedBox(height: JobMateTheme.space12),
              _InsightCallout(sections),
            ],
            const SizedBox(height: JobMateTheme.space16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => openJob(job),
                  child: const Text('View Job'),
                ),
                OutlinedButton(
                  onPressed: () => jobs.toggleSave(job.id),
                  child: Text(saved ? 'Unsave Job' : 'Save Job'),
                ),
                FilledButton(
                  onPressed: () => openJob(job, apply: true),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchCalculation extends StatelessWidget {
  const _MatchCalculation();

  @override
  Widget build(BuildContext context) => ExpansionTile(
    leading: const Icon(LucideIcons.info, size: 18),
    title: const Text('How is my match calculated?'),
    textColor: JobMateTheme.teal800,
    collapsedTextColor: JobMateTheme.teal800,
    iconColor: JobMateTheme.teal800,
    collapsedIconColor: JobMateTheme.teal800,
    backgroundColor: JobMateTheme.teal50,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: JobMateTheme.teal100),
      borderRadius: BorderRadius.circular(JobMateTheme.controlRadius),
    ),
    collapsedShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(JobMateTheme.controlRadius),
    ),
    minTileHeight: kMinInteractiveDimension,
    expansionAnimationStyle: AnimationStyle.noAnimation,
    expandedAlignment: Alignment.centerLeft,
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    childrenPadding: const EdgeInsets.fromLTRB(
      JobMateTheme.space16,
      0,
      JobMateTheme.space16,
      JobMateTheme.space16,
    ),
    children: [
      Text(
        'Understanding your estimated match',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const Text(
        'JobMate compares your listed skills with the skills listed in the posting. It also compares keywords from your headline, bio and work experience with the job title and overview.',
      ),
      const SizedBox(height: JobMateTheme.space12),
      Text(
        'Matching factors and base weights',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: JobMateTheme.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Matching skills — 50%'),
            Text('Profile and work experience — 30%'),
            Text('Employment type preference — 10%'),
            Text('Location preference — 10%'),
          ],
        ),
      ),
      const Text(
        'Only factors with enough information to compare count toward the score. Their weights are scaled to 100%. A factor can contribute zero if it does not match. If there is too little evidence overall, no percentage is shown.',
      ),
      const SizedBox(height: JobMateTheme.space12),
      Text(
        'How filters affect your match',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const Text(
        'Selecting a location or employment type can affect your estimated match. Salary and minimum match filters change which jobs are shown. Sorting changes their order.',
      ),
      const SizedBox(height: JobMateTheme.space12),
      Text(
        'Improve your recommendations',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const Text(
        'Keep your profile, skills and work experience up to date. Missing profile details can make your estimate less informative or leave too little evidence to show a score.',
      ),
      const SizedBox(height: JobMateTheme.space12),
      Text('Important', style: Theme.of(context).textTheme.titleSmall),
      const Text('An estimated match is not a hiring probability.'),
    ],
  );
}

class _AiInsightsNotice extends StatelessWidget {
  const _AiInsightsNotice({
    required this.icon,
    required this.title,
    required this.message,
    this.footer,
  });

  final IconData icon;
  final String title, message;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(JobMateTheme.space12),
      decoration: BoxDecoration(
        color: JobMateTheme.teal50,
        border: Border.all(color: JobMateTheme.teal100),
        borderRadius: BorderRadius.circular(JobMateTheme.controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(JobMateTheme.space8),
                  decoration: BoxDecoration(
                    color: JobMateTheme.teal100,
                    borderRadius: BorderRadius.circular(
                      JobMateTheme.controlRadius,
                    ),
                  ),
                  child: Icon(icon, size: 16, color: JobMateTheme.teal800),
                ),
                const SizedBox(width: JobMateTheme.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: JobMateTheme.teal800,
                        ),
                      ),
                      const SizedBox(height: JobMateTheme.space4),
                      Text(message, style: text.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (footer case final content?) ...[
            const SizedBox(height: JobMateTheme.space8),
            content,
          ],
        ],
      ),
    );
  }
}

class _RecommendationFilter extends StatelessWidget {
  const _RecommendationFilter({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label, value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey('$label:$value'),
    initialValue: value,
    isExpanded: true,
    itemHeight: null,
    borderRadius: BorderRadius.circular(JobMateTheme.controlRadius),
    dropdownColor: Colors.white,
    decoration: InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
    ),
    selectedItemBuilder: (_) => [
      for (final text in options.values)
        Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: text,
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
    ],
    items: [
      for (final entry in options.entries)
        DropdownMenuItem(
          value: entry.key,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(
              minHeight: kMinInteractiveDimension,
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(
              horizontal: JobMateTheme.space8,
              vertical: JobMateTheme.space8,
            ),
            decoration: BoxDecoration(
              color: entry.key == value
                  ? JobMateTheme.teal50
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(JobMateTheme.controlRadius),
            ),
            child: Text(
              entry.value,
              style: TextStyle(
                color: entry.key == value
                    ? JobMateTheme.teal800
                    : JobMateTheme.heading,
              ),
            ),
          ),
        ),
    ],
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}

class _InsightCallout extends StatelessWidget {
  const _InsightCallout(this.sections);

  final List<InsightSection> sections;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(JobMateTheme.space16),
      decoration: BoxDecoration(
        color: JobMateTheme.teal50,
        border: Border.all(color: JobMateTheme.teal100),
        borderRadius: BorderRadius.circular(JobMateTheme.controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: JobMateTheme.teal100,
                  borderRadius: BorderRadius.circular(
                    JobMateTheme.controlRadius,
                  ),
                ),
                child: const Icon(
                  LucideIcons.sparkles,
                  size: 16,
                  color: JobMateTheme.teal800,
                ),
              ),
              const SizedBox(width: JobMateTheme.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI recommendation insights',
                      style: text.titleMedium?.copyWith(
                        color: JobMateTheme.teal800,
                      ),
                    ),
                    Text(
                      'AI-selected guidance, tailored to your match.',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: JobMateTheme.space12),
          const Divider(height: 1, color: JobMateTheme.teal100),
          for (final section in sections) ...[
            const SizedBox(height: JobMateTheme.space12),
            _section(section, text),
          ],
        ],
      ),
    );
  }

  Widget _section(InsightSection section, TextTheme text) {
    final (icon, color) = switch (section.kind) {
      InsightSectionKind.why => (LucideIcons.circleCheck, JobMateTheme.teal800),
      InsightSectionKind.consider => (LucideIcons.info, JobMateTheme.body),
      InsightSectionKind.next => (LucideIcons.lightbulb, JobMateTheme.teal800),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: JobMateTheme.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: JobMateTheme.space4),
              Text.rich(
                TextSpan(
                  children: [
                    for (final run in section.runs)
                      TextSpan(
                        text: run.text,
                        style: run.emphasis
                            ? const TextStyle(fontWeight: FontWeight.w600)
                            : null,
                      ),
                  ],
                ),
                style: text.bodyMedium,
              ),
              if (!section.fromAi) ...[
                const SizedBox(height: JobMateTheme.space4),
                Text('JobMate suggestion', style: text.bodySmall),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
