import 'package:flutter/material.dart';

import '../../shared/theme/jobmate_theme.dart';
import '../jobs/job_display.dart';
import 'browse_job_card.dart';
import 'employer_applicants_repository.dart';
import 'employer_status_change_form.dart';
import 'module2_widgets.dart';
import 'my_applications_repository.dart';

/// Overview presentation only. The page supplies the authorized action widgets.
class EmployerApplicantCard extends StatelessWidget {
  const EmployerApplicantCard({
    super.key,
    required this.applicant,
    required this.jobTitle,
    required this.profileAction,
    this.resumeAction,
    required this.messageAction,
    required this.updating,
    this.offerAvailable = true,
    required this.onTransition,
  });
  final JobApplicant applicant;
  final String jobTitle;
  final Widget profileAction, messageAction;
  final Widget? resumeAction;
  final bool updating;
  final bool offerAvailable;
  final ValueChanged<MyApplicationStatus> onTransition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = applicant.appliedAt.toLocal();
    final name = applicant.name.trim();
    final words = name
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2);
    final initials = words
        .map((word) => word.characters.first)
        .join()
        .toUpperCase();
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: JobMateTheme.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    final identity = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: JobMateTheme.teal50,
                          foregroundColor: JobMateTheme.darkTeal,
                          child: initials.isEmpty
                              ? const Icon(Icons.person_outline, size: 20)
                              : Text(
                                  initials,
                                  style: const TextStyle(fontSize: 14),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                applicant.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (jobTitle.isNotEmpty)
                                Text(
                                  'Applied for: $jobTitle',
                                  style: const TextStyle(
                                    color: JobMateTheme.body,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                    final badge = MyApplicationStatusBadge(applicant.status);
                    if (box.maxWidth <
                        480 * MediaQuery.textScalerOf(context).scale(14) / 14) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [identity, const SizedBox(height: 6), badge],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: identity),
                        const SizedBox(width: 12),
                        badge,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    JobListingMetadata(
                      Icons.schedule,
                      'Applied: ${jobDate(local)} • ${TimeOfDay.fromDateTime(local).format(context)}',
                    ),
                    JobListingMetadata(
                      Icons.attach_file,
                      applicant.resumeId != null
                          ? 'Resume attached'
                          : 'No resume attached',
                    ),
                  ],
                ),
                if (applicant.coverNote?.trim().isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cover note',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          applicant.coverNote!,
                          style: const TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: JobMateTheme.background,
              border: Border(top: BorderSide(color: JobMateTheme.divider)),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: OutlinedButtonTheme(
                data: OutlinedButtonThemeData(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide.none,
                    foregroundColor: JobMateTheme.darkTeal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    minimumSize: const Size(48, 48),
                  ),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    profileAction,
                    ?resumeAction,
                    for (final next in applicant.employerNext.where(
                      (state) =>
                          state != MyApplicationStatus.rejected &&
                          (state != MyApplicationStatus.offered ||
                              offerAvailable),
                    ))
                      FilledButton(
                        onPressed: updating ? null : () => onTransition(next),
                        child: Text(employerTransitionLabel(next)),
                      ),
                    messageAction,
                    if (applicant.employerNext.contains(
                      MyApplicationStatus.rejected,
                    ))
                      TextButton.icon(
                        onPressed: updating
                            ? null
                            : () => onTransition(MyApplicationStatus.rejected),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        icon: const Icon(Icons.close, size: 17),
                        label: Text(
                          employerTransitionLabel(MyApplicationStatus.rejected),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ApplicantSummaryFilters extends StatelessWidget {
  const ApplicantSummaryFilters({
    super.key,
    required this.counts,
    required this.selected,
    required this.onSelected,
  });
  final Map<String, int> counts;
  final String selected;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = box.maxWidth >= 540 * scale
          ? 3
          : box.maxWidth >= 320 * scale
          ? 2
          : 1;
      const labels = ['All', 'Active', 'Completed'];
      return Column(
        children: [
          for (var offset = 0; offset < labels.length; offset += columns)
            Padding(
              padding: EdgeInsets.only(top: offset == 0 ? 0 : 10),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var i = offset;
                      i < offset + columns && i < labels.length;
                      i++
                    ) ...[
                      if (i > offset) const SizedBox(width: 10),
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: selected == labels[i],
                          label:
                              '${labels[i]} applications: ${counts[labels[i]]}',
                          child: Material(
                            color: selected == labels[i]
                                ? JobMateTheme.teal50
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: selected == labels[i]
                                    ? JobMateTheme.darkTeal
                                    : JobMateTheme.divider,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => onSelected(labels[i]),
                              child: Padding(
                                key: ValueKey('applicant-summary-${labels[i]}'),
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        labels[i],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${counts[labels[i]]}',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        color: JobMateTheme.darkTeal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
