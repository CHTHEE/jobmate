import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import 'soft_skill_evaluation_gateway.dart';

const _coreSkills = <(String, String)>[
  ('communication', 'Communication'),
  ('responsibility', 'Responsibility'),
  ('professionalism', 'Professionalism'),
];

String evaluationDirection(bool employer) =>
    employer ? 'employer_to_worker' : 'worker_to_company';

String softSkillEvaluationRoot(bool employer) =>
    employer
        ? AppRoutes.employerSoftSkillEvaluations
        : AppRoutes.softSkillEvaluations;

class SoftSkillEvaluationsPage extends StatefulWidget {
  const SoftSkillEvaluationsPage({
    super.key,
    required this.employer,
    this.assignmentId,
    this.gateway,
  });

  final bool employer;
  final String? assignmentId;
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
  String tab = 'Pending';
  String historyDirection = 'Given';
  String? error;
  bool loading = true;

  String get direction => evaluationDirection(widget.employer);
  String get root => softSkillEvaluationRoot(widget.employer);

  @override
  void initState() {
    super.initState();
    _load();
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
      form = widget.assignmentId == null
          ? null
          : candidates.cast<Map<String, dynamic>?>().firstWhere(
              (row) =>
                  row?['assignment_id'] == widget.assignmentId &&
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
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
              ? _MessageState(message: error!, retry: _load)
              : widget.assignmentId != null
              ? _EvaluationForm(
                  employer: widget.employer,
                  assignmentId: widget.assignmentId!,
                  direction: direction,
                  root: root,
                  row: form,
                  gateway: gateway,
                )
              : _evaluationList(),
        ),
      ),
    ),
  );

  Widget _evaluationList() {
    final visibleHistory = history.where((row) {
      final mine = row['given_by_me'] == true;
      return historyDirection == 'Given' ? mine : !mine;
    }).toList();
    return ListView(
      children: [
        Text(
          widget.employer
              ? 'Evaluate a worker after verified work is complete.'
              : 'Share feedback about a Company after your verified work is complete.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final value in ['Pending', 'History'])
              ChoiceChip(
                label: Text(value),
                selected: tab == value,
                onSelected: (_) => setState(() => tab = value),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (tab == 'Pending') ...[
          if (candidates.isEmpty)
            const _MessageState(
              message: 'No completed and verified assignments need an evaluation.',
            ),
          for (final row in candidates)
            Card.outlined(
              child: ListTile(
                title: Text('${row['job_title'] ?? 'Job'}'),
                subtitle: Text(
                  '${widget.employer ? 'Worker' : 'Company'}: ${row['target_label'] ?? 'Unavailable'}'
                  '${_department(row['department'])}',
                ),
                trailing: row['already_evaluated'] == true
                    ? const Text('Already evaluated')
                    : const Icon(Icons.chevron_right),
                onTap: row['already_evaluated'] == true
                    ? null
                    : () => context.go('$root/${row['assignment_id']}/rate'),
              ),
            ),
        ] else ...[
          Wrap(
            spacing: 8,
            children: [
              for (final value in ['Given', 'Received'])
                ChoiceChip(
                  label: Text(value),
                  selected: historyDirection == value,
                  onSelected: (_) => setState(() => historyDirection = value),
                ),
            ],
          ),
          const SizedBox(height: 12),
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
    final average = row['core_average'];
    final submitted = DateTime.tryParse('${row['submitted_at'] ?? ''}');
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${row['job_title'] ?? 'Job'}', style: Theme.of(context).textTheme.titleMedium),
            Text('${row['target_label'] ?? ''} · ${row['given_by_me'] == true ? 'Given by you' : 'Received'}'),
            if (submitted != null) Text('Submitted ${_date(submitted)}'),
            const SizedBox(height: 8),
            Text(count == 0
                ? 'Core Skill Average: Not enough numeric ratings (0 valid ratings).'
                : 'Core Skill Average: ${average ?? '—'} / 5 ($count valid ratings)'),
            if (row['given_by_me'] == true &&
                row['both_parties_submitted'] != true)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Your evaluation is private until the other party submits theirs.',
                ),
              ),
            for (final rating in ratings)
              Text('${rating['label']}: ${rating['not_observed'] == true ? 'Not Observed' : '${rating['rating']} / 5'}'),
            if ((row['comment'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text('${row['comment']}'),
            ],
          ],
        ),
      ),
    );
  }
}

String _department(dynamic value) =>
    value is String && value.trim().isNotEmpty ? ' · Department: ${value.trim()}' : '';

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
        if (retry != null) TextButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  );
}

class _EvaluationForm extends StatefulWidget {
  const _EvaluationForm({
    required this.employer,
    required this.assignmentId,
    required this.direction,
    required this.root,
    required this.row,
    required this.gateway,
  });

  final bool employer;
  final String assignmentId;
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

  int get answered => [
    ..._coreSkills.map((item) => item.$1),
    ...selected.map((item) => item['id'] as String),
  ].where(responses.containsKey).length;

  Future<void> _submit() async {
    final selectedIds = selected.map((item) => item['id'] as String).toList();
    final allIds = [..._coreSkills.map((item) => item.$1), ...selectedIds];
    if (selectedIds.length != 2 || selectedIds.toSet().length != 2 ||
        allIds.any((id) => !responses.containsKey(id)) ||
        !responses.values.any((value) => value is int)) {
      setState(() => error = 'Answer all five criteria and give at least one numeric rating.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review evaluation'),
        content: Text('Submit your evaluation for ${widget.row?['target_label']} on ${widget.row?['job_title']}? You cannot submit another evaluation for this assignment and direction.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Continue editing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit evaluation')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { saving = true; error = null; });
    try {
      await widget.gateway.submit(
        assignmentId: widget.assignmentId,
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

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    if (row == null) {
      return ListView(children: [
        TextButton.icon(onPressed: () => context.go(widget.root), icon: const Icon(Icons.arrow_back), label: const Text('Evaluations')),
        const _MessageState(message: 'This assignment is not currently eligible, or an evaluation for this direction has already been submitted.'),
      ]);
    }
    return ListView(
      children: [
        TextButton.icon(onPressed: saving ? null : () => context.go(widget.root), icon: const Icon(Icons.arrow_back), label: const Text('Evaluations')),
        Text('${row['job_title']}', style: Theme.of(context).textTheme.headlineSmall),
        Text('${widget.employer ? 'Your evaluation of worker' : 'Your evaluation of Company'}: ${row['target_label']}'),
        if (_department(row['department']).isNotEmpty) Text(_department(row['department']).substring(3)),
        const SizedBox(height: 12),
        const Text('The current Job Posting schema has no controlled Job Category. General recommendations are shown until one is added.'),
        const SizedBox(height: 16),
        Text('Progress: $answered / 5 responses', style: Theme.of(context).textTheme.titleSmall),
        LinearProgressIndicator(value: answered / 5),
        const SizedBox(height: 20),
        for (final skill in _coreSkills)
          _RatingCard(
            id: skill.$1,
            label: skill.$2,
            explanation: switch (skill.$1) {
              'communication' => 'Shares information clearly and listens respectfully.',
              'responsibility' => 'Follows through on agreed duties and commitments.',
              _ => 'Acts respectfully and appropriately at work.',
            },
            value: responses[skill.$1],
            enabled: !saving,
            onChanged: (value) => setState(() => responses[skill.$1] = value),
          ),
        const SizedBox(height: 8),
        Text(widget.employer ? 'Recommended job skills' : 'Employer experience criteria', style: Theme.of(context).textTheme.titleLarge),
        for (var index = 0; index < 2; index++) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('additional-$index-${selected.length > index ? selected[index]['id'] : ''}'),
            initialValue: selected.length > index ? selected[index]['id'] as String : null,
            decoration: InputDecoration(labelText: 'Additional criterion ${index + 1}'),
            items: [
              for (final item in available)
                if (item['id'] == (selected.length > index ? selected[index]['id'] : null) ||
                    !selected.any((other) => other['id'] == item['id']))
                  DropdownMenuItem(value: item['id'] as String, child: Text(item['label'] as String)),
            ],
            onChanged: saving ? null : (value) {
              if (value == null) return;
              final picked = available.firstWhere((item) => item['id'] == value);
              setState(() {
                if (selected.length > index) {
                  selected[index] = picked;
                } else {
                  selected.add(picked);
                }
                responses.removeWhere((id, _) => ![..._coreSkills.map((item) => item.$1), ...selected.map((item) => item['id'])].contains(id));
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
              onChanged: (value) => setState(() => responses[selected[index]['id'] as String] = value),
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
        if (error != null) Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: saving ? null : _submit,
          icon: saving ? const SizedBox(width: 18,height: 18,child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_outlined),
          label: Text(saving ? 'Submitting…' : 'Review and submit'),
        ),
      ],
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
    1: 'Very Poor', 2: 'Poor', 3: 'Satisfactory', 4: 'Good', 5: 'Excellent',
  };

  @override
  Widget build(BuildContext context) => Card.outlined(
    key: ValueKey('rating-$id'),
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(explanation, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var score = 1; score <= 5; score++)
              ChoiceChip(
                label: Text('$score · ${_ratingLabels[score]}'),
                selected: value == score,
                onSelected: enabled ? (_) => onChanged(score) : null,
              ),
            ChoiceChip(
              label: const Text('Not Observed'),
              selected: value == 'not_observed',
              onSelected: enabled ? (_) => onChanged('not_observed') : null,
            ),
          ]),
        ],
      ),
    ),
  );
}
