import 'package:material_ui/material_ui.dart';

import '../../shared/theme/jobmate_theme.dart';
import '../jobs/job_display.dart';
import 'module2_repository.dart';
import 'job_marketplace_format.dart';

/// Presentation only; eligibility and salary disclosure stay in BrowseJob.
class BrowseJobCard extends StatelessWidget {
  const BrowseJobCard({
    super.key,
    required this.job,
    required this.logo,
    required this.saved,
    required this.onSave,
    required this.onDetails,
    this.distanceKm,
    this.availabilityAsOf,
  });
  final BrowseJob job;
  final Widget logo;
  final bool saved;
  final double? distanceKm;
  final DateTime? availabilityAsOf;
  final VoidCallback onSave, onDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final salary = marketplaceSalary(job);
    final reason = job.unavailable(availabilityAsOf);
    final metadata = Wrap(
      spacing: 14,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (job.text('employment_type').isNotEmpty)
          EmploymentTypeBadge(job.text('employment_type')),
        if (job.text('location').isNotEmpty)
          JobListingMetadata(Icons.location_on_outlined, job.text('location')),
        if (job.text('work_arrangement').isNotEmpty)
          JobListingMetadata(
            Icons.work_outline,
            jobLabel(job.text('work_arrangement')),
          ),
        if (distanceKm case final distance?)
          JobListingMetadata(
            Icons.straighten,
            '${distance.toStringAsFixed(1)} km straight-line from selected area',
          ),
      ],
    );
    final secondaryMetadata = Wrap(
      spacing: 16,
      key: const ValueKey('job-secondary-metadata'),
      runSpacing: 8,
      children: [
        if (job.text('application_deadline').isNotEmpty)
          JobListingMetadata(
            Icons.event_outlined,
            'Deadline: ${marketplaceDate(job.fields['application_deadline'])}',
          ),
        if (job.text('vacancies').isNotEmpty)
          JobListingMetadata(
            Icons.people_outline,
            'Vacancies: ${job.text('vacancies')}',
          ),
        if (job.text('published_at').isNotEmpty)
          JobListingMetadata(
            Icons.schedule,
            'Published: ${marketplaceDate(job.fields['published_at'])}',
          ),
      ],
    );
    final pay = Text(
      salary,
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
    );
    final action = TextButton.icon(
      onPressed: onDetails,
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.chevron_right, size: 16),
      label: const Text('View Details'),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: JobMateTheme.divider),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >= 700 &&
              MediaQuery.textScalerOf(context).scale(14) <= 18;
          return Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      logo,
                      const SizedBox(width: 12),
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
                      IconButton(
                        tooltip: saved
                            ? 'Unsave job (this session)'
                            : 'Save job (this session)',
                        isSelected: saved,
                        onPressed: onSave,
                        icon: const Icon(Icons.bookmark_border),
                        selectedIcon: const Icon(Icons.bookmark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (wide)
                    Row(
                      children: [
                        Expanded(flex: 3, child: metadata),
                        const SizedBox(width: 16),
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: pay,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    metadata,
                    const SizedBox(height: 10),
                    pay,
                    const SizedBox(height: 10),
                    secondaryMetadata,
                  ],
                  if (reason != null)
                    Text(
                      reason,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              if (wide)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Expanded(child: secondaryMetadata),
                      const SizedBox(width: 8),
                      action,
                    ],
                  ),
                )
              else
                Align(alignment: AlignmentDirectional.centerEnd, child: action),
            ],
          );
        },
      ),
    );
  }
}

class EmploymentTypeBadge extends StatelessWidget {
  const EmploymentTypeBadge(this.type, {super.key});
  final String type;
  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      'full_time' => const Color(0xFF1D4ED8),
      'part_time' => const Color(0xFF7E22CE),
      'internship' => const Color(0xFF4338CA),
      'temporary' => const Color(0xFF92400E),
      _ => JobMateTheme.darkTeal,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        jobLabel(type),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class JobListingMetadata extends StatelessWidget {
  const JobListingMetadata(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: JobMateTheme.body),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          text,
          style: const TextStyle(color: JobMateTheme.body, fontSize: 12),
        ),
      ),
    ],
  );
}
