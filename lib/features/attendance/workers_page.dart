import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../applications/module2_widgets.dart';
import '../demo_work/demo_widgets.dart';
import '../demo_work/phase3_store.dart';

/// Worker directory derived from the attendance sandbox, never real applicants.
class WorkersPage extends StatefulWidget {
  const WorkersPage({super.key, this.store});
  final Phase3Store? store;
  @override
  State<WorkersPage> createState() => _WorkersPageState();
}

class _WorkersPageState extends State<WorkersPage> {
  late final data = widget.store ?? Phase3Store.session;
  String query = '';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: data,
    builder: (context, _) {
      final workers = data.attendance.map((r) => r.worker).toSet().toList()
        ..sort();
      final visible = workers.where(
        (name) => name.toLowerCase().contains(query.trim().toLowerCase()),
      );
      return DemoPage(
        title: 'Workers',
        path: AppRoutes.workers,
        role: 'employer',
        children: [
          const Phase3Notice(
            'Fictional workers from the attendance sandbox. These are not your actual employees, applicants or verified assignments.',
          ),
          DemoStats({
            'Workers': workers.length,
            'Active assignments': data.attendance
                .where((r) => r.checkOut == null)
                .length,
            'Checked-out assignments': data.attendance
                .where((r) => r.checkOut != null)
                .length,
          }),
          TextField(
            onChanged: (value) => setState(() => query = value),
            decoration: const InputDecoration(
              labelText: 'Search demo workers',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 20),
          if (visible.isEmpty)
            const ModuleState(
              title: 'No workers found',
              message: 'Try another name. This directory uses the same session as demo attendance.',
            ),
          for (final name in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: WorkspaceCard(
                title: name,
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                subtitle: 'Fictional worker • demo only',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final record in data.attendance.where(
                      (r) => r.worker == name,
                    ))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(record.job),
                        subtitle: Text(
                          '${record.state} • ${record.review} (demo)',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(
                          '${AppRoutes.attendanceReview}/${record.id}',
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.stars_outlined, size: 18),
                        label: const Text('View Reputation'),
                        onPressed: () => moduleModal<void>(
                          context,
                          ModalBody(
                            title: '$name • Reputation',
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],

                            children: [
                              const Phase3Notice(
                                'Demo worker context only. No personal score, received evaluations or real reputation has been calculated.',
                              ),
                              WorkspaceInfo(
                                'Sample assignments',
                                '${data.attendance.where((r) => r.worker == name).length}',
                              ),
                              WorkspaceInfo(
                                'Checked out',
                                '${data.attendance.where((r) => r.worker == name && r.checkOut != null).length}',
                              ),
                              const ModuleState(
                                title: 'Not enough reputation data',
                                message: 'A worker-specific score requires verified assignment outcomes and eligible evaluations. No score is invented here.',
                              ),
                            ],
                          ),
                          maxWidth: 672,
                        ),
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
