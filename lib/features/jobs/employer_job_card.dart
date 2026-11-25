import 'package:flutter/material.dart';

import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../applications/browse_job_card.dart';
import '../applications/job_marketplace_format.dart';
import '../applications/module2_repository.dart';
import 'job_display.dart';

String postingStatusLabel(String status) => switch (status) {
  'all' => 'All',
  'published' => 'Published',
  'draft' => 'Draft',
  'closed' => 'Closed',
  _ => status,
};

/// All operations are supplied by the existing page; this widget only presents them.
class EmployerJobCard extends StatelessWidget {
  const EmployerJobCard({
    super.key,
    required this.job,
    required this.busy,
    required this.onEdit,
    required this.onApplicants,
    this.unseenApplicantCount = 0,
  });
  final Map<String, dynamic> job;
  final bool busy;
  final int unseenApplicantCount;
  final VoidCallback onEdit, onApplicants;

  @override
  Widget build(BuildContext context) {
    final display = BrowseJob(job, company: '');
    final status = display.text('status');
    final title = job['title'] as String? ?? 'Untitled job';
    final titleStyle = Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w700, height: 1.25);
    final statusColor = status == 'draft'
        ? const Color(0xFF92400E)
        : JobMateTheme.body;
    final deadlineMessage = status == 'published'
        ? display.unavailable()
        : null;
    final employmentType = display.text('employment_type');
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: JobMateTheme.divider),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        MediaQuery.textScalerOf(context)
                            .scale(titleStyle?.fontSize ?? 16) *
                        2.5,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.topStart,
                    child: Tooltip(
                      message: title,
                      excludeFromSemantics: true,
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (employmentType.isNotEmpty)
                      EmploymentTypeBadge(employmentType)
                    else
                      const Text('Employment type not set'),
                    if (status != 'published')
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          child: Text(
                            postingStatusLabel(status),
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (unseenApplicantCount > 0)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: JobMateTheme.applicantNotification,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Text(
                            unseenApplicantCount > 999
                                ? '999+ new'
                                : '$unseenApplicantCount new',
                            semanticsLabel: unseenApplicantCount == 1
                                ? '1 new application'
                                : '$unseenApplicantCount new applications',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  marketplaceSalary(display),
                  key: const ValueKey('posting-salary'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                ResponsiveGrid(
                  minItemWidth: 135,
                  maxColumns: 2,
                  spacing: 8,
                  equalRowHeight: true,
                  children: [
                    JobListingMetadata(
                      Icons.location_on_outlined,
                      _metadata(display.text('location'), 'Location not set'),
                    ),
                    JobListingMetadata(
                      Icons.work_outline,
                      _metadata(
                        jobLabel(display.text('work_arrangement')),
                        'Arrangement not set',
                      ),
                    ),
                    JobListingMetadata(
                      Icons.business_center_outlined,
                      _metadata(
                        display.text('department'),
                        'Department not set',
                      ),
                    ),
                    JobListingMetadata(
                      Icons.people_outline,
                      'Vacancies: ${job['vacancies'] ?? 'Not set'}',
                    ),
                    JobListingMetadata(
                      Icons.event_outlined,
                      job['application_deadline'] == null
                          ? 'Deadline not set'
                          : 'Deadline: ${marketplaceDate(job['application_deadline'])}',
                    ),
                    JobListingMetadata(
                      Icons.schedule,
                      job['published_at'] != null
                          ? 'Published: ${marketplaceDate(job['published_at'])}'
                          : job['created_at'] != null
                          ? 'Created: ${marketplaceDate(job['created_at'])}'
                          : 'Date not available',
                    ),
                  ],
                ),
                if (deadlineMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      deadlineMessage,
                      style: const TextStyle(
                        color: JobMateTheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            key: const ValueKey('posting-actions'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: JobMateTheme.background,
              border: Border(top: BorderSide(color: JobMateTheme.divider)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: ResponsiveLayout.actionGap,
              runSpacing: ResponsiveLayout.actionGap,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onApplicants,
                  style: FilledButton.styleFrom(
                    backgroundColor: JobMateTheme.teal50,
                    foregroundColor: JobMateTheme.darkTeal,
                    minimumSize: const Size(0, ResponsiveLayout.actionHeight),
                  ),
                  icon: const Icon(Icons.people_outline, size: 18),
                  label: const Text('View Applicants'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('posting-edit'),
                  onPressed: busy ? null : onEdit,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, ResponsiveLayout.actionHeight),
                  ),
                  icon: Icon(
                    status == 'closed'
                        ? Icons.visibility_outlined
                        : Icons.edit_outlined,
                    size: 18,
                  ),
                  label: Text(status == 'closed' ? 'View' : 'Edit'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _metadata(String value, String fallback) =>
      value.isEmpty ? fallback : value;
}

class PostingSummary extends StatelessWidget {
  const PostingSummary(this.counts, {super.key});
  final Map<String, int> counts;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = box.maxWidth >= 680 * scale
          ? 4
          : box.maxWidth >= 320 * scale
          ? 2
          : 1;
      final items = [
        ('all', 'Total Jobs', Icons.work_outline, JobMateTheme.heading),
        (
          'published',
          'Published',
          Icons.public_outlined,
          JobMateTheme.darkTeal,
        ),
        ('draft', 'Draft', Icons.edit_note_outlined, const Color(0xFF92400E)),
        ('closed', 'Closed', Icons.task_alt_outlined, JobMateTheme.body),
      ];
      return Column(
        children: [
          for (var offset = 0; offset < items.length; offset += columns)
            Padding(
              padding: EdgeInsets.only(top: offset == 0 ? 0 : 12),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var i = offset;
                      i < offset + columns && i < items.length;
                      i++
                    ) ...[
                      if (i > offset) const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          key: ValueKey('posting-stat-${items[i].$1}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: JobMateTheme.divider),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      items[i].$2,
                                      style: const TextStyle(
                                        color: JobMateTheme.body,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    items[i].$3,
                                    size: 18,
                                    color: items[i].$4,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${counts[items[i].$1] ?? 0}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
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
