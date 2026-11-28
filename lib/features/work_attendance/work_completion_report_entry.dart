import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'work_attendance_models.dart';

/// A visibility hint. The report route independently authorizes the report.
bool showsWorkCompletionReport(WorkAssignment assignment) =>
    assignment.assignmentStatus == WorkAssignmentStatus.completed &&
    assignment.verificationStatus == WorkVerificationStatus.verified &&
    assignment.resolution?.decision != 'confirmed_absent';

class WorkCompletionReportEntry extends StatelessWidget {
  const WorkCompletionReportEntry({
    super.key,
    required this.employer,
    required this.onOpen,
  });

  final bool employer;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .045),
        border: Border.all(color: colors.primary.withValues(alpha: .26)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final details = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    LucideIcons.fileCheck,
                    color: colors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Attendance & Work Completion Report',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        employer
                            ? 'View the recorded attendance, submitted work evidence and verification details for this assignment.'
                            : 'View a summary of your recorded attendance, submitted work evidence and employer verification.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final action = FilledButton(
              onPressed: onOpen,
              child: const Text('View Report'),
            );
            return compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [details, const SizedBox(height: 12), action],
                  )
                : Row(
                    children: [
                      Expanded(child: details),
                      const SizedBox(width: 16),
                      action,
                    ],
                  );
          },
        ),
      ),
    );
  }
}
