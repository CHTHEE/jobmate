import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../jobs/job_display.dart';
import 'radar_chart.dart';
import 'rating_display.dart';
import 'soft_skill_evaluation_gateway.dart';

const _coreSkills = <(String, String)>[
  ('communication', 'Communication'),
  ('responsibility', 'Responsibility'),
  ('professionalism', 'Professionalism'),
];

String evaluationDirection(bool employer) =>
    employer ? 'employer_to_worker' : 'worker_to_company';

String softSkillEvaluationRoot(bool employer) => employer
    ? AppRoutes.employerSoftSkillEvaluations
    : AppRoutes.softSkillEvaluations;

class SoftSkillEvaluationsPage extends StatefulWidget {
  const SoftSkillEvaluationsPage({
    super.key,
    required this.employer,
    this.showReceived = false,
    this.applicationId,
    this.gateway,
  });

  final bool employer;
  final bool showReceived;
  final String? applicationId;
  final SoftSkillEvaluationGateway? gateway;

  @override
  State<SoftSkillEvaluationsPage> createState() =>
      _SoftSkillEvaluationsPageState();
}

class _SoftSkillEvaluationsPageState extends State<SoftSkillEvaluationsPage> {
  late final SoftSkillEvaluationGateway gateway =
      widget.gateway ??
      SupabaseSoftSkillEvaluationGateway(Supabase.instance.client);
  List<Map<String, dynamic>> candidates = [];
  List<Map<String, dynamic>> history = [];
  final _companyByApplication = <String, String>{};
  final _workerByApplication = <String, String>{};
  Map<String, EvaluationJobContext> _jobContexts = const {};
  final _formKey = GlobalKey<_EvaluationFormState>();
  Map<String, dynamic>? form;
  late String tab = widget.showReceived ? 'Received' : 'Pending';
  String? error;
  bool loading = true;

  String get direction => evaluationDirection(widget.employer);
  String get root => softSkillEvaluationRoot(widget.employer);

  String? _companyName(Map<String, dynamic> row) {
    String? companyTarget(Map<String, dynamic> record) {
      final label = record['target_label'];
      return record['direction'] == 'worker_to_company' &&
              label is String &&
              label.trim().isNotEmpty
          ? label
          : null;
    }

    final direct = companyTarget(row);
    if (direct != null) return direct;
    return _companyByApplication[row['application_id']] ??
        _jobContexts[row['application_id']]?.companyName;
  }

  String? _workerName(Map<String, dynamic> row) =>
      _workerByApplication[row['application_id']] ??
      (row['direction'] == 'employer_to_worker'
          ? row['target_label'] as String?
          : null);

  Future<void> _loadJobContexts(
    EvaluationJobContextGateway source,
    int generation,
  ) async {
    try {
      final contexts = await source.applicationJobContexts(
        employer: widget.employer,
        evaluations: [...candidates, ...history],
      );
      if (mounted && generation == _loadGeneration) {
        setState(() => _jobContexts = contexts);
      }
    } catch (_) {
      // Keep the authorized evaluation rows usable if enrichment fails.
    }
  }

  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SoftSkillEvaluationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showReceived != widget.showReceived) {
      tab = widget.showReceived ? 'Received' : 'Pending';
    }
    if (oldWidget.applicationId != widget.applicationId) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final values = await Future.wait([
        gateway.candidates(direction),
        gateway.history(),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      candidates = values[0];
      history = values[1];
      _companyByApplication.clear();
      _workerByApplication.clear();
      _jobContexts = const {};
      for (final row in [...candidates, ...history]) {
        final id = row['application_id'];
        final label = row['target_label'];
        if (row['direction'] == 'worker_to_company' &&
            id is String &&
            label is String &&
            label.trim().isNotEmpty) {
          _companyByApplication[id] = label;
        }
        if (row['direction'] == 'employer_to_worker' &&
            id is String &&
            label is String &&
            label.trim().isNotEmpty) {
          _workerByApplication[id] = label;
        }
      }
      form = widget.applicationId == null
          ? null
          : candidates.cast<Map<String, dynamic>?>().firstWhere(
              (row) =>
                  row?['application_id'] == widget.applicationId &&
                  row?['already_evaluated'] != true,
              orElse: () => null,
            );
      if (gateway is EvaluationJobContextGateway) {
        unawaited(
          _loadJobContexts(gateway as EvaluationJobContextGateway, generation),
        );
      }
    } catch (_) {
      error = 'Evaluations are unavailable. Check the service and try again.';
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AppWorkspace(
    title: widget.employer ? 'Worker evaluations' : 'Company evaluations',
    path: root,
    role: widget.employer ? 'employer' : 'job_seeker',
    focused: widget.applicationId != null,
    leading: widget.applicationId == null
        ? null
        : IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _leaveForm(root),
          ),
    onNavigate: widget.applicationId == null ? null : _leaveForm,
    child: ResponsiveContent(
      maxWidth: 1280,
      alignment: Alignment.topLeft,
      child: Padding(
        padding: ResponsiveLayout.pagePadding(context),
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
            ? _MessageState(message: error!, retry: _load)
            : widget.applicationId != null
            ? _EvaluationForm(
                key: _formKey,
                employer: widget.employer,
                applicationId: widget.applicationId!,
                direction: direction,
                root: root,
                row: form,
                companyName: form == null ? null : _companyName(form!),
                jobContext: _jobContexts[widget.applicationId],
                gateway: gateway,
              )
            : _evaluationList(),
      ),
    ),
  );

  void _leaveForm(String destination) {
    if (_formKey.currentState case final form?) {
      unawaited(form._leave(destination));
    } else {
      context.go(destination);
    }
  }

  Widget _evaluationList() {
    final visibleHistory = history
        .where((row) {
          final given = row['given_by_me'] == true;
          return tab == 'Given'
              ? given
              : !given && row['both_parties_submitted'] == true;
        })
        .toList(growable: false);
    final pending = candidates
        .where((row) => row['already_evaluated'] != true)
        .toList(growable: false);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeading(
                title: widget.employer
                    ? 'Worker evaluations'
                    : 'Company evaluations',
                description: widget.employer
                    ? 'Evaluate a worker after the Job Engagement is closed.'
                    : 'Share feedback about a Company after your Job Engagement is closed.',
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final value in ['Pending', 'Given', 'Received'])
                    ChoiceChip(
                      label: Text(value),
                      selected: tab == value,
                      onSelected: (_) => setState(() => tab = value),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        if (tab == 'Pending')
          if (pending.isEmpty)
            const SliverToBoxAdapter(
              child: _MessageState(
                message: 'No closed Job Engagements need an evaluation.',
              ),
            )
          else
            _cardGrid(pending, pending: true)
        else if (visibleHistory.isEmpty)
          const SliverToBoxAdapter(
            child: _MessageState(
              message: 'No visible evaluations in this history yet.',
            ),
          )
        else
          _cardGrid(visibleHistory),
      ],
    );
  }

  Widget _cardGrid(List<Map<String, dynamic>> rows, {bool pending = false}) =>
      SliverLayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final columns =
              constraints.crossAxisExtent >=
                  (pending ? 760 : 900) * textScale.clamp(1, 1.3)
              ? 2
              : 1;
          Widget card(int index, {required bool horizontal}) => pending
              ? _pendingCard(rows[index])
              : _historyCard(rows[index], horizontal: horizontal);
          if (columns == 1) {
            return SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: RepaintBoundary(child: card(index, horizontal: false)),
              ),
            );
          }
          final rowCount = (rows.length + 1) ~/ 2;
          return SliverList.builder(
            itemCount: rowCount,
            itemBuilder: (context, rowIndex) {
              final firstIndex = rowIndex * 2;
              final secondIndex = firstIndex + 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: RepaintBoundary(
                          child: card(firstIndex, horizontal: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: secondIndex < rows.length
                            ? RepaintBoundary(
                                child: card(secondIndex, horizontal: true),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

  Widget _cardIdentity(Map<String, dynamic> row) => _EvaluationIdentity(
    row: row,
    companyName: _companyName(row),
    workerName: widget.employer ? _workerName(row) : null,
    showWorker: widget.employer,
    jobContext: _jobContexts[row['application_id']],
  );

  Widget _pendingCard(Map<String, dynamic> row) {
    void evaluate() => context.go('$root/${row['application_id']}/rate');
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: evaluate,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _cardIdentity(row),
              const SizedBox(height: 10),
              if (DateTime.tryParse('${row['closed_at']}') case final closed?)
                Text('Engagement closed ${_date(closed.toLocal())}'),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const _EvaluationStatus(label: 'Pending'),
                  Text(_directionLabel(row['direction'], true)),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.icon(
                  onPressed: evaluate,
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('Evaluate'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> row, {required bool horizontal}) {
    final ratings = (row['ratings'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    final criteria = radarCriteriaFromRatings(ratings);
    final count = (row['core_valid_rating_count'] as num?)?.toInt() ?? 0;
    final total = ratings.where((rating) => rating['group'] == 'core').length;
    final average = row['core_average'] as num?;
    final given = row['given_by_me'] == true;
    final published = row['both_parties_submitted'] == true;
    final submitted = DateTime.tryParse('${row['submitted_at'] ?? ''}');
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(given ? 'Given by you' : 'Received evaluation'),
        Text(_directionLabel(row['direction'], given)),
        if (submitted != null) Text('Submitted ${_date(submitted.toLocal())}'),
        _EvaluationStatus(
          label: published ? 'Published' : 'Awaiting publication',
        ),
        const SizedBox(height: 8),
        Text(
          average == null
              ? 'Core rating unavailable'
              : 'Core rating: ${formatRating(average)}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(
          total >= count && total > 0
              ? '$count of $total core skills assessed'
              : 'Based on $count rated core skills',
        ),
      ],
    );
    final chart = EvaluationRadarChart(
      criteria: criteria,
      presentation: RadarChartPresentation.compact,
      emptyMessage: ratings.isEmpty
          ? 'Criterion scores are not available.'
          : 'At least three comparable criteria are needed.',
    );
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardIdentity(row),
            const SizedBox(height: 10),
            if (horizontal)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: summary),
                  const SizedBox(width: 12),
                  SizedBox(width: 220, child: chart),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [summary, chart],
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showEvaluationDetails(row, ratings, criteria),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('View Evaluation'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEvaluationDetails(
    Map<String, dynamic> row,
    List<Map<String, dynamic>> ratings,
    List<RadarChartCriterion> criteria,
  ) => showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['job_title'] ?? 'Evaluation'}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          _directionLabel(
                            row['direction'],
                            row['given_by_me'] == true,
                          ),
                        ),
                        if (row['target_label'] != null)
                          Text('${row['target_label']}'),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              EvaluationRadarChart(criteria: criteria),
              Text(
                row['core_average'] is num
                    ? 'Core rating: ${formatRating(row['core_average'] as num)}'
                    : 'Core rating unavailable',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              for (final core in [true, false]) ...[
                Text(
                  core ? 'Core skills' : 'Additional criteria',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final rating in ratings.where(
                  (rating) => (rating['group'] == 'core') == core,
                ))
                  RatingBreakdownRow(
                    label: '${rating['label']}',
                    rating: rating['rating'] as num?,
                    notObserved: rating['not_observed'] == true,
                  ),
                const SizedBox(height: 8),
              ],
              if ((row['comment'] as String?)?.isNotEmpty == true) ...[
                Text('Feedback', style: Theme.of(context).textTheme.titleSmall),
                Text('${row['comment']}'),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

List<RadarChartCriterion> radarCriteriaFromRatings(
  Iterable<Map<String, dynamic>> ratings,
) {
  final result = <RadarChartCriterion>[];
  final seen = <String>{};
  for (final rating in ratings) {
    final label = '${rating['label'] ?? ''}'.trim();
    if (label.isEmpty) continue;
    final skillId = rating['skill_id'];
    final id = skillId is String && skillId.trim().isNotEmpty
        ? skillId.trim()
        : label;
    if (!seen.add(id)) continue;
    final value = rating['rating'];
    final notObserved = rating['not_observed'] == true;
    result.add(
      RadarChartCriterion(
        id: id,
        label: label,
        score:
            !notObserved &&
                value is num &&
                value.isFinite &&
                value >= 1 &&
                value <= 5
            ? value.toDouble()
            : null,
        notObserved: notObserved,
      ),
    );
  }
  return result;
}

String _directionLabel(dynamic value, bool given) => switch (value) {
  'employer_to_worker' => 'Employer → Worker',
  'worker_to_company' => 'Worker → Company',
  _ => given ? 'Evaluation given' : 'Evaluation received',
};

String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.retry});
  final String message;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        if (retry != null)
          TextButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  );
}

class _EvaluationIdentity extends StatelessWidget {
  const _EvaluationIdentity({
    required this.row,
    required this.companyName,
    this.workerName,
    this.showWorker = false,
    this.useCompanyLogo = false,
    this.jobContext,
  });

  final Map<String, dynamic> row;
  final String? companyName;
  final String? workerName;
  final bool showWorker, useCompanyLogo;
  final EvaluationJobContext? jobContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workerAvatar = showWorker && !useCompanyLogo;
    final avatarName = workerAvatar ? workerName : companyName;
    final initials = (avatarName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word.characters.first.toUpperCase())
        .join();
    final placeholder = CircleAvatar(
      radius: 24,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: initials.isEmpty
          ? Icon(workerAvatar ? Icons.person_outline : Icons.business_outlined)
          : Text(initials),
    );
    final logo = workerAvatar ? null : jobContext?.logoUrl;
    final department = row['department'];
    final employment = jobContext?.employmentType;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: 48,
          child: logo == null
              ? placeholder
              : FutureBuilder<String?>(
                  future: logo(),
                  builder: (context, snapshot) {
                    final url = snapshot.connectionState == ConnectionState.done
                        ? snapshot.data
                        : null;
                    if (url == null) return placeholder;
                    return ClipOval(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        semanticLabel: '${companyName ?? 'Company'} logo',
                        frameBuilder: (_, image, frame, synchronous) =>
                            frame == null && !synchronous ? placeholder : image,
                        errorBuilder: (_, _, _) => placeholder,
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showWorker && workerName != null)
                Text(
                  'Worker: $workerName',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              Text(
                '${row['job_title'] ?? 'Job'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: showWorker && workerName != null
                    ? theme.textTheme.titleSmall
                    : theme.textTheme.titleMedium,
              ),
              if (companyName != null)
                Text(
                  companyName!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              if ((department is String && department.trim().isNotEmpty) ||
                  jobEmploymentTypes.contains(employment))
                Text(
                  [
                    if (department is String && department.trim().isNotEmpty)
                      department.trim(),
                    if (jobEmploymentTypes.contains(employment))
                      jobLabel(employment!),
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EvaluationStatus extends StatelessWidget {
  const _EvaluationStatus({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final published = label == 'Published';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: published
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Text(label, style: theme.textTheme.labelMedium),
      ),
    );
  }
}

class _EvaluationForm extends StatefulWidget {
  const _EvaluationForm({
    super.key,
    required this.employer,
    required this.applicationId,
    required this.direction,
    required this.root,
    required this.row,
    required this.companyName,
    required this.jobContext,
    required this.gateway,
  });

  final bool employer;
  final String applicationId;
  final String direction;
  final String root;
  final Map<String, dynamic>? row;
  final String? companyName;
  final EvaluationJobContext? jobContext;
  final SoftSkillEvaluationGateway gateway;

  @override
  State<_EvaluationForm> createState() => _EvaluationFormState();
}

class _EvaluationFormState extends State<_EvaluationForm> {
  final comment = TextEditingController();
  final _fieldsScroll = ScrollController();
  final responses = <String, dynamic>{};
  late List<Map<String, dynamic>> selected;
  bool saving = false;
  bool reviewing = false;
  bool confirmingExit = false;
  bool criteriaChanged = false;
  String? error;

  List<Map<String, dynamic>> get available =>
      (widget.row?['available_additional'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

  @override
  void initState() {
    super.initState();
    selected = (widget.row?['recommended_additional'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  @override
  void dispose() {
    _fieldsScroll.dispose();
    comment.dispose();
    super.dispose();
  }

  static const additionalCount = 2; // Required by the submission contract.
  int get responseCount => _coreSkills.length + additionalCount;

  int get answered => [
    ..._coreSkills.map((item) => item.$1),
    ...selected.map((item) => item['id'] as String),
  ].where(responses.containsKey).length;

  bool get hasNumericRating => responses.values.any((value) => value is int);
  bool get canReview =>
      selected.length == additionalCount &&
      selected.map((item) => item['id']).toSet().length == additionalCount &&
      answered == responseCount &&
      hasNumericRating;

  Future<void> _submit() async {
    if (saving || reviewing) return;
    final selectedIds = selected.map((item) => item['id'] as String).toList();
    final allIds = [..._coreSkills.map((item) => item.$1), ...selectedIds];
    if (selectedIds.length != additionalCount ||
        selectedIds.toSet().length != additionalCount ||
        allIds.any((id) => !responses.containsKey(id)) ||
        !responses.values.any((value) => value is int)) {
      setState(
        () => error =
            'Answer all $responseCount criteria and give at least one numeric rating.',
      );
      return;
    }
    setState(() => reviewing = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review evaluation'),
        content: Text(
          'Submit your evaluation for ${widget.row?['target_label']} on ${widget.row?['job_title']}? You cannot submit another evaluation for this Job Application and direction.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit evaluation'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      reviewing = false;
      saving = confirmed == true;
      if (saving) error = null;
    });
    if (!saving) return;
    try {
      await widget.gateway.submit(
        applicationId: widget.applicationId,
        direction: widget.direction,
        selectedAdditionalSkillIds: selectedIds,
        ratings: {for (final id in allIds) id: responses[id]},
        comment: comment.text.trim().isEmpty ? null : comment.text.trim(),
      );
      if (mounted) context.go(widget.root);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Submission failed. Your answers are still here; review them and retry.';
        });
      }
    }
  }

  Future<void> _back() => _leave(widget.root);

  Future<void> _leave(String destination) async {
    if (saving || reviewing || confirmingExit) return;
    if (responses.isNotEmpty ||
        comment.text.trim().isNotEmpty ||
        criteriaChanged) {
      confirmingExit = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard evaluation draft?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard draft'),
            ),
          ],
        ),
      );
      confirmingExit = false;
      if (discard != true || !mounted) return;
    }
    context.go(destination);
  }

  Widget _backAction(VoidCallback? onPressed) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_back, size: 20),
      label: const Text('Back to Evaluations'),
    ),
  );

  List<RadarChartCriterion> get _previewCriteria {
    final items = <(String, String)>[
      ..._coreSkills,
      ...selected.map(
        (item) => (item['id'] as String, item['label'] as String),
      ),
    ];
    return [
      for (final item in items)
        RadarChartCriterion(
          id: item.$1,
          label: item.$2,
          score: responses[item.$1] is int
              ? (responses[item.$1] as int).toDouble()
              : null,
          notObserved: responses[item.$1] == 'not_observed',
        ),
    ];
  }

  double? get _corePreviewAverage {
    final observed = _coreSkills
        .map((item) => responses[item.$1])
        .whereType<int>()
        .toList(growable: false);
    if (observed.isEmpty) return null;
    return observed.reduce((left, right) => left + right) / observed.length;
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_back());
    },
    child: _buildForm(context),
  );

  Widget _buildForm(BuildContext context) {
    final row = widget.row;
    if (row == null) {
      return ListView(
        children: [
          _backAction(() => context.go(widget.root)),
          const _MessageState(
            message: 'This Job Application is not closed and eligible, or an evaluation for this direction has already been submitted.',
          ),
        ],
      );
    }
    final progress = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$answered of $responseCount responses completed'),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: answered / responseCount),
      ],
    );
    final fields = <Widget>[
      Text('Core skills', style: Theme.of(context).textTheme.titleLarge),
      const Text(
        'Observed core skills determine the core rating. Choose Not Observed when you cannot assess a skill.',
      ),
      const SizedBox(height: 6),
      const Text(
        '1 Very Poor · 2 Poor · 3 Satisfactory · 4 Good · 5 Excellent',
      ),
      for (final skill in _coreSkills)
        _RatingCard(
          id: skill.$1,
          label: skill.$2,
          explanation: switch (skill.$1) {
            'communication' =>
              'Shares information clearly and listens respectfully.',
            'responsibility' =>
              'Follows through on agreed duties and commitments.',
            _ => 'Acts respectfully and appropriately at work.',
          },
          value: responses[skill.$1],
          enabled: !saving,
          onChanged: (value) => setState(() => responses[skill.$1] = value),
        ),
      const SizedBox(height: 8),
      Text(
        'Additional criteria',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const Text('These responses add context to your feedback.'),
      const SizedBox(height: 8),
      for (var index = 0; index < additionalCount; index++) ...[
        DropdownButtonFormField<String>(
          key: ValueKey(
            'additional-$index-${selected.length > index ? selected[index]['id'] : ''}',
          ),
          initialValue: selected.length > index
              ? selected[index]['id'] as String
              : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Additional criterion ${index + 1}',
          ),
          items: [
            for (final item in available)
              if (item['id'] ==
                      (selected.length > index
                          ? selected[index]['id']
                          : null) ||
                  !selected.any((other) => other['id'] == item['id']))
                DropdownMenuItem(
                  value: item['id'] as String,
                  child: Text(item['label'] as String),
                ),
          ],
          onChanged: saving
              ? null
              : (value) {
                  if (value == null) return;
                  final picked = available.firstWhere(
                    (item) => item['id'] == value,
                  );
                  setState(() {
                    criteriaChanged = true;
                    if (selected.length > index) {
                      selected[index] = picked;
                    } else {
                      selected.add(picked);
                    }
                    responses.removeWhere(
                      (id, _) => ![
                        ..._coreSkills.map((item) => item.$1),
                        ...selected.map((item) => item['id']),
                      ].contains(id),
                    );
                  });
                },
        ),
        if (selected.length > index)
          _RatingCard(
            id: selected[index]['id'] as String,
            label: selected[index]['label'] as String,
            explanation: selected[index]['explanation'] as String,
            value: responses[selected[index]['id']],
            enabled: !saving,
            onChanged: (value) => setState(
              () => responses[selected[index]['id'] as String] = value,
            ),
          ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: comment,
        enabled: !saving,
        maxLength: 1000,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(labelText: 'Optional feedback'),
      ),
    ];
    final submissionError = error == null
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
    final submission = <Widget>[
      const SizedBox(height: 12),
      if (!canReview)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            answered < responseCount
                ? 'Complete all $responseCount criteria to review.'
                : 'Give at least one numeric rating to review.',
          ),
        ),
      FilledButton.icon(
        onPressed: saving || reviewing || !canReview ? null : _submit,
        icon: saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send_outlined),
        label: Text(saving ? 'Submitting...' : 'Review and submit'),
      ),
    ];
    final previewHeading = Text(
      'Live rating preview',
      style: Theme.of(context).textTheme.titleMedium,
    );
    Widget previewData({double? chartHeight}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EvaluationRadarChart(criteria: _previewCriteria, height: chartHeight),
        Text(
          _corePreviewAverage == null
              ? 'Core rating preview unavailable'
              : 'Core rating preview: ${formatRating(_corePreviewAverage!)}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Only observed core skills count toward this rating.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
    final header = Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _EvaluationIdentity(
          row: row,
          companyName: widget.companyName,
          workerName: widget.employer ? row['target_label'] as String? : null,
          showWorker: widget.employer,
          useCompanyLogo: true,
          jobContext: widget.jobContext,
        ),
      ),
    );
    final back = _backAction(saving ? null : _back);
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final wide =
            constraints.maxWidth >= 920 * textScale &&
            constraints.maxHeight >= 620 * textScale;
        if (!wide) {
          final keepBackVisible = constraints.maxHeight >= 160;
          final stack = ListView(
            key: const PageStorageKey('evaluation-form-stacked'),
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              if (!keepBackVisible) back,
              header,
              const SizedBox(height: 12),
              WorkspaceCard(
                title: 'Live rating preview',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    progress,
                    previewData(
                      chartHeight: constraints.maxWidth < 600 ? 180 : 220,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ...fields,
              ?submissionError,
              ...submission,
            ],
          );
          return keepBackVisible
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    back,
                    const SizedBox(height: 10),
                    Expanded(child: stack),
                  ],
                )
              : stack;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            back,
            const SizedBox(height: 10),
            header,
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Scrollbar(
                      controller: _fieldsScroll,
                      thumbVisibility: true,
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context)
                            .copyWith(scrollbars: false),
                        child: ListView(
                          key: const PageStorageKey('evaluation-form-fields'),
                          controller: _fieldsScroll,
                          primary: false,
                          padding: const EdgeInsets.only(right: 12, bottom: 16),
                          children: fields,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 360 * textScale.clamp(1.0, 1.25),
                    child: Card.outlined(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            previewHeading,
                            const SizedBox(height: 8),
                            progress,
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, pane) {
                                  final chartHeight = (pane.maxHeight - 70)
                                      .clamp(180.0, 250.0);
                                  return SingleChildScrollView(
                                    primary: false,
                                    padding: const EdgeInsets.only(top: 8),
                                    child: previewData(
                                      chartHeight: chartHeight,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const Divider(height: 12),
                            ?submissionError,
                            ...submission,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({
    required this.id,
    required this.label,
    required this.explanation,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String id;
  final String label;
  final String explanation;
  final dynamic value;
  final bool enabled;
  final ValueChanged<dynamic> onChanged;

  static const _ratingLabels = {
    1: 'Very Poor',
    2: 'Poor',
    3: 'Satisfactory',
    4: 'Good',
    5: 'Excellent',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.outlined(
      key: ValueKey('rating-$id'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(explanation, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var score = 1; score <= 5; score++)
                  ChoiceChip(
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: value == score
                          ? colors.onPrimary
                          : colors.onSurface,
                    ),
                    selectedColor: colors.primary,
                    backgroundColor: colors.surfaceContainerLow,
                    side: BorderSide(
                      color: value == score ? colors.primary : colors.outline,
                    ),
                    label: Tooltip(
                      message: _ratingLabels[score]!,
                      child: SizedBox(
                        width: 24,
                        child: Text(
                          '$score',
                          textAlign: TextAlign.center,
                          semanticsLabel:
                              '$label, $score out of 5, ${_ratingLabels[score]}',
                        ),
                      ),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    selected: value == score,
                    onSelected: enabled ? (_) => onChanged(score) : null,
                  ),
                ChoiceChip(
                  avatar: Icon(
                    Icons.visibility_off_outlined,
                    size: 17,
                    color: value == 'not_observed'
                        ? colors.onPrimary
                        : colors.onSurfaceVariant,
                  ),
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  selectedColor: colors.primary,
                  backgroundColor: colors.surfaceContainerHighest,
                  labelStyle: TextStyle(
                    color: value == 'not_observed'
                        ? colors.onPrimary
                        : colors.onSurface,
                  ),
                  label: Text(
                    'Not Observed',
                    semanticsLabel: '$label, Not Observed',
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  selected: value == 'not_observed',
                  onSelected: enabled ? (_) => onChanged('not_observed') : null,
                ),
              ],
            ),
            if (value != null) ...[
              const SizedBox(height: 4),
              Text(
                value is int
                    ? '$value — ${_ratingLabels[value]}'
                    : 'Not Observed selected',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
