import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../applications/module2_widgets.dart';
import '../demo_work/demo_widgets.dart';
import 'phase4_store.dart';
import 'evaluation_pages.dart';

class ReputationPage extends StatefulWidget {
  const ReputationPage({super.key, this.employer = false, this.store});
  final bool employer;
  final Phase4Store? store;
  @override
  State<ReputationPage> createState() => _ReputationPageState();
}

class _ReputationPageState extends State<ReputationPage> {
  late final store = widget.store ?? Phase4Store.session;
  bool enough = true;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final role = widget.employer ? 'employer' : 'job_seeker',
          other = widget.employer ? 'job_seeker' : 'employer',
          score = widget.employer ? 90 : 84;
      final received = store.evaluations
          .where(
            (e) =>
                e.author == other &&
                store.revealed(e.assignmentId) &&
                sampleAssignmentVisible(
                  store.assignment(e.assignmentId)!,
                  widget.employer,
                ),
          )
          .toList();
      final average = received.isEmpty
          ? null
          : received.map((e) => e.average).reduce((a, b) => a + b) /
                received.length;
      return DemoPage(
        title: widget.employer ? 'Company Reputation' : 'My Reputation',
        path: widget.employer
            ? AppRoutes.employerReputation
            : AppRoutes.reputation,
        role: role,
        children: [
          const Phase3Notice(
            'Every trust score, factor and trend below is an illustrative fixture, not a score for your real account/company. No production scoring algorithm is implemented. Past performance does not guarantee future outcomes.',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show illustrative sample data'),
            subtitle: const Text(
              'Turn off to preview the not-enough-data state.',
            ),
            value: enough,
            onChanged: (v) => setState(() => enough = v),
          ),
          if (!enough)
            const ModuleState(
              title: 'Not enough verified data',
              message: 'A reputation score should appear only after sufficient verified assignments, evaluations and reliability data exist. No real score is available in this phase.',
            )
          else ...[
            WorkspaceCard(
              title: widget.employer ? 'Demo company' : 'Demo candidate',
              subtitle: 'Illustrative trust score • 0–100',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ScoreRing(value: score, label: 'DEMO'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$score / 100 • DEMO',
                    style: const TextStyle(fontFamily: 'DM Mono', fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Fixed preview value. It does not recalculate from your activity or represent a verified assessment.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            DemoStats({
              'Visible demo evaluations': received.length,
              'Completed sample assignments': store.assignments
                  .where(
                    (a) =>
                        a.completed &&
                        sampleAssignmentVisible(a, widget.employer),
                  )
                  .length,
            }),
            WorkspaceCard(
              title: 'Score factors explained',
              subtitle: 'Explanations only; percentages below are sample indicators, not formula weights.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final factor
                      in widget.employer
                          ? {
                              'Payment reliability': 96,
                              'Job description accuracy': 90,
                              'Worker satisfaction': 88,
                              'Response consistency': 86,
                              'Account standing / disputes': 92,
                            }.entries
                          : {
                              'Completion reliability': 92,
                              'Attendance consistency': 90,
                              'Soft skills': 84,
                              'Account standing': 100,
                              'Dispute history': 88,
                            }.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('${factor.key}: ${factor.value}% • fixture'),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: factor.value / 100),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            WorkspaceCard(
              title: 'Evaluation summary',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    average == null
                        ? 'No revealed demo evaluations yet'
                        : 'Average from revealed demo evaluations: ${average.toStringAsFixed(1)} / 5',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () =>
                        context.push(evaluationRoot(widget.employer)),
                    child: const Text('View Evaluations'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            WorkspaceCard(
              title: 'Illustrative trend',
              subtitle: 'Sample snapshots only; not historical scores for a real identity.',
              child: Column(
                children: [
                  for (final row in <(String, int)>[
                    ('Three months ago', score - 6),
                    ('Two months ago', score - 4),
                    ('Last month', score - 2),
                    ('Sample current', score),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('${row.$1}: ${row.$2}'),
                          LinearProgressIndicator(value: row.$2 / 100),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}
