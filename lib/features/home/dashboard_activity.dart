import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../applications/module2_repository.dart';
import '../demo_work/phase3_store.dart';

/// Deliberately separate from real account and company statistics.
class DashboardActivity extends StatelessWidget {
  const DashboardActivity({super.key, required this.employer});
  final bool employer;
  @override
  Widget build(BuildContext context) {
    final jobs = Module2Repository.session, work = Phase3Store.session;
    return ListenableBuilder(
      listenable: Listenable.merge([jobs, work]),
      builder: (context, _) {
        final applications = jobs.searchApplications(mineOnly: !employer),
            assignment = work.record('today');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const PreviewNotice(
              'Activity below belongs to the fictional demo workspace, not your real account, workers or applicants.',
            ),
            StatGrid(
              children: [
                StatTile(
                  label: employer ? 'Sample applicants' : 'Sample applications',
                  value: '${applications.length}',
                  icon: Icons.assignment_outlined,
                  note: 'Demo session',
                ),
                StatTile(
                  label: 'Active',
                  value:
                      '${applications.where((a) => !a.stage.completed).length}',
                  icon: Icons.pending_actions_outlined,
                  note: 'Demo applications',
                ),
                StatTile(
                  label: employer ? 'Pending work reviews' : 'Completed',
                  value: employer
                      ? '${work.attendance.where((r) => r.checkOut != null && r.review == 'Pending').length}'
                      : '${applications.where((a) => a.stage.completed).length}',
                  icon: Icons.task_alt,
                  note: 'Demo session',
                ),
              ],
            ),
            const SizedBox(height: 24),
            BrandPanel(
              title: employer
                  ? 'Your hiring workspace, connected'
                  : 'Find work that fits you',
              description: employer
                  ? 'Preview applicant management and worker attendance separately from your real job posting workflow.'
                  : 'Explore skill-based demo recommendations, discover workplaces and keep your applications together.',
              icon: employer
                  ? Icons.people_outline
                  : Icons.auto_awesome_outlined,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: () => context.push(
                      employer
                          ? AppRoutes.applicants
                          : AppRoutes.recommendations,
                    ),
                    child: Text(
                      employer
                          ? 'View Sample Applicants'
                          : 'Explore For You (demo)',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => context.push(
                      employer
                          ? AppRoutes.attendanceReview
                          : AppRoutes.nearbyJobs,
                    ),
                    child: Text(
                      employer
                          ? 'Workers / Attendance (demo)'
                          : 'Explore Nearby (demo)',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            WorkspaceCard(
              title: employer
                  ? 'Worker attendance preview'
                  : 'Your work preview',
              subtitle: 'Fictional assignment • demo only',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    assignment?.job ?? 'No active demo assignment',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    assignment == null
                        ? 'No work is scheduled in this sample session.'
                        : '${assignment.worker} • ${assignment.state} • simulated workplace',
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(
                        employer
                            ? AppRoutes.attendanceReview
                            : AppRoutes.attendance,
                      ),
                      icon: const Icon(Icons.event_available_outlined),
                      label: Text(
                        employer
                            ? 'Review Demo Attendance'
                            : 'Open Demo Attendance',
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
