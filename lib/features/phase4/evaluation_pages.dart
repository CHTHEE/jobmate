import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../applications/module2_widgets.dart';
import '../demo_work/demo_widgets.dart';
import '../jobs/job_display.dart';
import 'phase4_store.dart';

String evaluationRoot(bool employer) =>
    employer ? AppRoutes.employerEvaluations : AppRoutes.evaluations;
bool sampleAssignmentVisible(SampleAssignment a, bool employer) =>
    employer || a.worker == 'Demo candidate (you)';

class EvaluationsPage extends StatefulWidget {
  const EvaluationsPage({super.key, this.employer = false, this.store});
  final bool employer;
  final Phase4Store? store;
  @override
  State<EvaluationsPage> createState() => _EvaluationsPageState();
}

class _EvaluationsPageState extends State<EvaluationsPage> {
  late final store = widget.store ?? Phase4Store.session;
  String tab = 'Pending', direction = 'Given';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final role = widget.employer ? 'employer' : 'job_seeker',
          other = widget.employer ? 'job_seeker' : 'employer',
          root = evaluationRoot(widget.employer);
      final assignments = store.assignments
          .where(
            (a) => a.completed && sampleAssignmentVisible(a, widget.employer),
          )
          .toList();
      final rows = assignments
          .where(
            (a) => tab == 'Pending'
                ? store.evaluation(a.id, role) == null
                : store.evaluation(a.id, direction == 'Given' ? role : other) !=
                      null,
          )
          .toList();
      return DemoPage(
        title: 'Evaluations',
        path: root,
        role: role,
        children: [
          const Phase3Notice(
            'Evaluations are intended for completed assignments. These fictional requests and ratings are local only. The intended both-sides-submit visibility rule is illustrated here, not enforced by a server.',
          ),
          DemoStats({
            'Completed sample assignments': assignments.length,
            'Pending': assignments
                .where((a) => store.evaluation(a.id, role) == null)
                .length,
            'Given': assignments
                .where((a) => store.evaluation(a.id, role) != null)
                .length,
          }),
          Wrap(
            spacing: 8,
            children: [
              for (final v in ['Pending', 'History'])
                ChoiceChip(
                  label: Text(v),
                  selected: tab == v,
                  onSelected: (_) => setState(() => tab = v),
                ),
            ],
          ),
          if (tab == 'History')
            Wrap(
              spacing: 8,
              children: [
                for (final v in ['Given', 'Received'])
                  ChoiceChip(
                    label: Text(v),
                    selected: direction == v,
                    onSelected: (_) => setState(() => direction = v),
                  ),
              ],
            ),
          const SizedBox(height: 20),
          if (rows.isEmpty)
            const ModuleState(
              title: 'No evaluations here',
              message: 'Only completed sample assignments can be evaluated. Complete your pending demo evaluation or choose another history view.',
            ),
          for (final a in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: WorkspaceCard(
                title: a.job,
                subtitle: widget.employer ? a.worker : a.company,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Completed sample assignment • ${jobDate(a.date)}'),
                    if (tab == 'Pending')
                      Text(
                        'Demo availability deadline: ${jobDate(a.date.add(const Duration(days: 30)))}',
                      ),
                    if (tab == 'History' &&
                        direction == 'Received' &&
                        !store.revealed(a.id))
                      const Text(
                        'Feedback hidden until both demo parties submit.',
                      ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => context.push(
                        '$root/${a.id}${tab == 'Pending' ? '/rate' : ''}',
                      ),
                      child: Text(
                        tab == 'Pending' ? 'Start Evaluation' : 'View Details',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class EvaluationFormPage extends StatefulWidget {
  const EvaluationFormPage({
    super.key,
    required this.assignmentId,
    this.employer = false,
    this.store,
  });
  final String assignmentId;
  final bool employer;
  final Phase4Store? store;
  @override
  State<EvaluationFormPage> createState() => _EvaluationFormPageState();
}

class _EvaluationFormPageState extends State<EvaluationFormPage> {
  late final store = widget.store ?? Phase4Store.session;
  String get role => widget.employer ? 'employer' : 'job_seeker';
  late final draft = store.evaluationDraft(widget.assignmentId, role);
  late final feedback = TextEditingController(text: draft.feedback);
  String? error;
  bool submitting = false, success = false;
  @override
  void dispose() {
    feedback.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (submitting) return;
    if (evaluationCriteria(role).any((c) => !draft.ratings.containsKey(c))) {
      setState(() => error = 'Rate all six criteria from 1 to 5.');
      return;
    }
    if (!await demoConfirm(
      context,
      'Submit demo evaluation?',
      'All six ratings will be recorded in memory. Demo evaluations cannot be edited after submission.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => submitting = true);
    try {
      store.submitEvaluation(widget.assignmentId, role);
      setState(() {
        success = true;
        error = null;
      });
    } on StateError catch (e) {
      setState(() => error = e.message.toString());
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final root = evaluationRoot(widget.employer),
          a = store.assignment(widget.assignmentId),
          existing = store.evaluation(widget.assignmentId, role);
      return DemoPage(
        title: success
            ? 'Evaluation Submitted'
            : 'Evaluate ${widget.employer ? 'Worker' : 'Employer'}',
        path: root,
        role: role,
        back: root,
        children: [
          const Phase3Notice(
            'Six ratings are required. Optional feedback is limited to 300 characters. Draft ratings/feedback are retained during in-app navigation. This is not a real review of an actual person or company.',
          ),
          if (a == null ||
              !a.completed ||
              !sampleAssignmentVisible(a, widget.employer))
            const ModuleState(
              title: 'Evaluation unavailable',
              message:
                  'A completed sample assignment for this role is required.',
            )
          else if (existing != null)
            WorkspaceCard(
              title: success
                  ? 'Demo evaluation recorded'
                  : 'Already evaluated in demo',
              subtitle: 'Nothing was sent to Supabase.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Your sample average: ${existing.average.toStringAsFixed(1)} / 5',
                  ),
                  const Text(
                    'Feedback remains hidden from the other demo party until both submit.',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => context.go('$root/${a.id}'),
                    child: const Text('View Evaluation Details / History'),
                  ),
                ],
              ),
            )
          else
            WorkspaceCard(
              title: a.job,
              subtitle: widget.employer ? a.worker : a.company,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${draft.ratings.length} / 6 criteria rated'),
                  LinearProgressIndicator(value: draft.ratings.length / 6),
                  const SizedBox(height: 20),
                  for (final criterion in evaluationCriteria(role))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            criterion,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var score = 1; score <= 5; score++)
                                ChoiceChip(
                                  label: Text('$score'),
                                  tooltip: '$criterion: $score out of 5',
                                  selected: draft.ratings[criterion] == score,
                                  onSelected: submitting
                                      ? null
                                      : (_) => setState(
                                          () =>
                                              draft.ratings[criterion] = score,
                                        ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  TextField(
                    controller: feedback,
                    maxLength: 300,
                    minLines: 3,
                    maxLines: 6,
                    onChanged: (v) => draft.feedback = v,
                    decoration: const InputDecoration(
                      labelText: 'Written feedback (optional)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  FilledButton(
                    onPressed: submitting ? null : submit,
                    child: const Text('Submit Evaluation (demo)'),
                  ),
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () => moduleBack(context, root),
                    child: const Text('Cancel (keep draft)'),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class EvaluationDetailPage extends StatelessWidget {
  const EvaluationDetailPage({
    super.key,
    required this.assignmentId,
    this.employer = false,
    this.store,
  });
  final String assignmentId;
  final bool employer;
  final Phase4Store? store;
  @override
  Widget build(BuildContext context) {
    final data = store ?? Phase4Store.session,
        role = employer ? 'employer' : 'job_seeker',
        other = employer ? 'job_seeker' : 'employer',
        root = evaluationRoot(employer);
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final a = data.assignment(assignmentId),
            given = data.evaluation(assignmentId, role),
            received = data.evaluation(assignmentId, other);
        return DemoPage(
          title: 'Evaluation Details',
          path: root,
          role: role,
          back: root,
          children: [
            const Phase3Notice(
              'Intended visibility: both parties submit before received feedback is revealed. This local UI illustration is not a security or server-enforced guarantee.',
            ),
            if (a == null || !sampleAssignmentVisible(a, employer))
              const ModuleState(
                title: 'Evaluation unavailable',
                message: 'No visible sample assignment exists.',
              )
            else ...[
              Text(a.job, style: Theme.of(context).textTheme.headlineSmall),
              Text('${a.worker} • ${a.company}'),
              const SizedBox(height: 20),
              if (given == null)
                OutlinedButton(
                  onPressed: () => context.push('$root/${a.id}/rate'),
                  child: const Text('Complete your demo evaluation'),
                ),
              for (final entry in <(String, SampleEvaluation?)>[
                ('Given', given),
                ('Received', received),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: WorkspaceCard(
                    title: entry.$1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (entry.$1 == 'Received' && !data.revealed(a.id))
                          const Text(
                            'Hidden: waiting for both sample submissions.',
                          )
                        else if (entry.$2 == null)
                          const Text('Not submitted')
                        else ...[
                          Text(
                            'Average: ${entry.$2!.average.toStringAsFixed(1)} / 5',
                          ),
                          for (final rating in entry.$2!.ratings.entries)
                            WorkspaceInfo(rating.key, '${rating.value} / 5'),
                          Text(
                            entry.$2!.feedback.isEmpty
                                ? 'No written feedback'
                                : entry.$2!.feedback,
                          ),
                        ],
                        if (entry.$1 == 'Received' &&
                            data.revealed(a.id) &&
                            entry.$2 != null) ...[
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: entry.$2!.reportId != null
                                ? null
                                : () => moduleModal<void>(
                                    context,
                                    EvaluationReportForm(
                                      assignmentId: a.id,
                                      role: role,
                                      store: data,
                                    ),
                                  ),
                            child: const Text(
                              'Report Received Evaluation (demo)',
                            ),
                          ),
                          if (entry.$2!.reportId != null)
                            Text(
                              'Demo report ${entry.$2!.reportId} • ${data.dispute(entry.$2!.reportId!)?.state.label}',
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (given != null && received == null)
                OutlinedButton(
                  onPressed: () {
                    data.simulateCounterpart(a.id, role);
                    demoMessage(
                      context,
                      'Sample counterpart submitted locally; both demo reviews are now visible',
                    );
                  },
                  child: const Text('Simulate counterpart submission (demo)'),
                ),
            ],
          ],
        );
      },
    );
  }
}

class EvaluationReportForm extends StatefulWidget {
  const EvaluationReportForm({
    super.key,
    required this.assignmentId,
    required this.role,
    required this.store,
  });
  final String assignmentId, role;
  final Phase4Store store;
  @override
  State<EvaluationReportForm> createState() => _EvaluationReportFormState();
}

class _EvaluationReportFormState extends State<EvaluationReportForm> {
  late final keyName =
      'evaluation-report:${widget.assignmentId}:${widget.role}';
  late final text = TextEditingController(
    text: widget.store.formDrafts[keyName] ?? '',
  );
  late String reason = widget.store.formDrafts['$keyName:reason'] ?? '';
  String error = '';
  bool done = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModalBody(
    title: done
        ? 'Demo evaluation report recorded'
        : 'Report received evaluation',
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(done ? 'Done' : 'Cancel (keep draft)'),
      ),
      if (!done)
        FilledButton(
          onPressed: () {
            if (reason.isEmpty) {
              setState(() => error = 'Choose a report reason.');
              return;
            }
            try {
              widget.store.reportEvaluation(
                widget.assignmentId,
                widget.role,
                '$reason: ${text.text}',
              );
              widget.store.formDrafts.remove(keyName);
              widget.store.formDrafts.remove('$keyName:reason');
              setState(() => done = true);
            } on StateError catch (e) {
              setState(() => error = e.message.toString());
            }
          },
          child: const Text('Record Demo Report'),
        ),
    ],
    children: [
      const Text(
        'DEMO ONLY • No actual moderation request or review deadline is promised.',
      ),
      if (done)
        const Text('The local report is linked to the demo dispute list.')
      else ...[
        const SizedBox(height: 16),
        ModuleSelect(
          label: 'Report reason (required)',
          value: reason,
          options: const {
            '': 'Select reason',
            'Inaccurate': 'Inaccurate',
            'Abusive': 'Abusive',
            'Unrelated': 'Unrelated',
            'Other': 'Other',
          },
          onChanged: (v) => setState(() {
            reason = v;
            widget.store.formDrafts['$keyName:reason'] = v;
          }),
        ),
        TextField(
          controller: text,
          maxLength: 800,
          minLines: 3,
          maxLines: 5,
          onChanged: (v) => widget.store.formDrafts[keyName] = v,
          decoration: const InputDecoration(labelText: 'Details (optional)'),
        ),
        if (error.isNotEmpty)
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ],
  );
}
