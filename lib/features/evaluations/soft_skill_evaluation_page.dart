import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/responsive_layout.dart';
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
  Map<String, dynamic>? form;
  late String tab = widget.showReceived ? 'Received' : 'Pending';
  String? error;
  bool loading = true;

  String get direction => evaluationDirection(widget.employer);
  String get root => softSkillEvaluationRoot(widget.employer);

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
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final values = await Future.wait([
        gateway.candidates(direction),
        gateway.history(),
      ]);
      if (!mounted) return;
      candidates = values[0];
      history = values[1];
      form = widget.applicationId == null
          ? null
          : candidates.cast<Map<String, dynamic>?>().firstWhere(
              (row) =>
                  row?['application_id'] == widget.applicationId &&
                  row?['already_evaluated'] != true,
              orElse: () => null,
            );
    } catch (_) {
      error = 'Evaluations are unavailable. Check the service and try again.';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppWorkspace(
    title: widget.employer ? 'Worker evaluations' : 'Company evaluations',
    path: root,
    role: widget.employer ? 'employer' : 'job_seeker',
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
                employer: widget.employer,
                applicationId: widget.applicationId!,
                direction: direction,
                root: root,
                row: form,
                gateway: gateway,
              )
            : _evaluationList(),
      ),
    ),
  );

  Widget _evaluationList() {
    final visibleHistory = history.where((row) {
      final given = row['given_by_me'] == true;
      return tab == 'Given'
          ? given
          : !given && row['both_parties_submitted'] == true;
    });
    final pending = candidates.where((row) => row['already_evaluated'] != true);
    return ListView(
      children: [
        PageHeading(
          title: widget.employer ? 'Worker evaluations' : 'Company evaluations',
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
        if (tab == 'Pending') ...[
          if (pending.isEmpty)
            const _MessageState(
              message: 'No closed Job Engagements need an evaluation.',
            ),
          for (final row in pending)
            Card.outlined(
              child: ListTile(
                title: Text('${row['job_title'] ?? 'Job'}'),
                subtitle: Text(
                  '${widget.employer ? 'Worker' : 'Company'}: ${row['target_label'] ?? 'Unavailable'}'
                  '${_department(row['department'])}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('$root/${row['application_id']}/rate'),
              ),
            ),
        ] else ...[
          if (visibleHistory.isEmpty)
            const _MessageState(
              message: 'No visible evaluations in this history yet.',
            ),
          for (final row in visibleHistory) _historyCard(row),
        ],
      ],
    );
  }

  Widget _historyCard(Map<String, dynamic> row) {
    final ratings = (row['ratings'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final count = (row['core_valid_rating_count'] as num?)?.toInt() ?? 0;
    final total = ratings.where((rating) => rating['group'] == 'core').length;
    final average = row['core_average'] as num?;
    final given = row['given_by_me'] == true;
    final published = row['both_parties_submitted'] == true;
    final submitted = DateTime.tryParse('${row['submitted_at'] ?? ''}');
    final party = given
        ? row['target_label']
        : widget.employer
        ? 'Worker feedback'
        : 'Company feedback';
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${row['job_title'] ?? 'Job'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (party != null) Text('$party'),
                Text(given ? 'Given by you' : 'Received evaluation'),
                if (submitted != null)
                  Text('Submitted ${_date(submitted.toLocal())}'),
                Text(published ? 'Published' : 'Awaiting the other evaluation'),
              ],
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
            ExpansionTile(
              key: PageStorageKey(row['evaluation_id'] ?? row),
              tilePadding: EdgeInsets.zero,
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              title: const Text('View rating breakdown'),
              children: [
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
                if ((row['comment'] as String?)?.isNotEmpty == true)
                  Text('${row['comment']}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _department(dynamic value) => value is String && value.trim().isNotEmpty
    ? ' \u00b7 Department: ${value.trim()}'
    : '';

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

class _EvaluationForm extends StatefulWidget {
  const _EvaluationForm({
    required this.employer,
    required this.applicationId,
    required this.direction,
    required this.root,
    required this.row,
    required this.gateway,
  });

  final bool employer;
  final String applicationId;
  final String direction;
  final String root;
  final Map<String, dynamic>? row;
  final SoftSkillEvaluationGateway gateway;

  @override
  State<_EvaluationForm> createState() => _EvaluationFormState();
}

class _EvaluationFormState extends State<_EvaluationForm> {
  final comment = TextEditingController();
  final responses = <String, dynamic>{};
  late List<Map<String, dynamic>> selected;
  bool saving = false;
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
    comment.dispose();
    super.dispose();
  }

  static const additionalCount = 2; // Required by the submission contract.
  int get responseCount => _coreSkills.length + additionalCount;

  int get answered => [
    ..._coreSkills.map((item) => item.$1),
    ...selected.map((item) => item['id'] as String),
  ].where(responses.containsKey).length;

  Future<void> _submit() async {
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
    if (confirmed != true || !mounted) return;
    setState(() {
      saving = true;
      error = null;
    });
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

  Future<void> _back() async {
    if (responses.isNotEmpty ||
        comment.text.trim().isNotEmpty ||
        criteriaChanged) {
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
      if (discard != true || !mounted) return;
    }
    context.go(widget.root);
  }

  Widget _backAction(VoidCallback? onPressed) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: kIsWeb
        ? TextButton(
            onPressed: onPressed,
            child: const Text('Back to Evaluations'),
          )
        : TextButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to Evaluations'),
          ),
  );

  @override
  Widget build(BuildContext context) {
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
        const SizedBox(height: 16),
      ],
    );
    final fields = <Widget>[
      Text('Core skills', style: Theme.of(context).textTheme.titleLarge),
      const Text(
        'Observed core skills determine the core rating. Choose Not Observed when you cannot assess a skill.',
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
    final submission = <Widget>[
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: saving ? null : _submit,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final wide = constraints.maxWidth >= 920 * textScale;
        return ListView(
          children: [
            _backAction(saving ? null : _back),
            Text(
              '${row['job_title']}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '${widget.employer ? 'Your evaluation of worker' : 'Your evaluation of Company'}: ${row['target_label']}',
            ),
            if (_department(row['department']).isNotEmpty)
              Text(_department(row['department']).substring(3)),
            const SizedBox(height: 12),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: fields,
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 280,
                    child: WorkspaceCard(
                      title: 'Evaluation progress',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [progress, ...submission],
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              progress,
              ...fields,
              ...submission,
            ],
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
  Widget build(BuildContext context) => Card.outlined(
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
                  label: Tooltip(
                    message: _ratingLabels[score]!,
                    child: Text(
                      '$score',
                      semanticsLabel:
                          '$label, $score out of 5, ${_ratingLabels[score]}',
                    ),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  selected: value == score,
                  onSelected: enabled ? (_) => onChanged(score) : null,
                ),
              ChoiceChip(
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
          if (value is int) Text(_ratingLabels[value] ?? ''),
        ],
      ),
    ),
  );
}
