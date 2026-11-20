import 'package:flutter/material.dart';

import '../../shared/theme/jobmate_theme.dart';
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
    required this.onPreview,
    required this.onPublish,
    required this.onClose,
    required this.onApplicants,
    this.unseenApplicantCount = 0,
  });
  final Map<String, dynamic> job;
  final bool busy;
  final int unseenApplicantCount;
  final VoidCallback onEdit, onPreview, onPublish, onClose, onApplicants;

  @override
  Widget build(BuildContext context) {
    final display = BrowseJob(job, company: '');
    final status = display.text('status');
    final statusColor = switch (status) {
      'published' => JobMateTheme.darkTeal,
      'draft' => const Color(0xFF92400E),
      _ => JobMateTheme.body,
    };
    final deadlineMessage = status == 'published'
        ? display.unavailable()
        : null;
    final applicantsButton = FilledButton.tonalIcon(
      onPressed: busy ? null : onApplicants,
      style: FilledButton.styleFrom(
        backgroundColor: JobMateTheme.teal50,
        foregroundColor: JobMateTheme.darkTeal,
        minimumSize: const Size(48, 48),
      ),
      icon: const Icon(Icons.people_outline, size: 18),
      label: const Text('View Applicants'),
    );
    final applicants = unseenApplicantCount > 0
        ? Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              applicantsButton,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: JobMateTheme.applicantNotification,
                  borderRadius: BorderRadius.circular(20),
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
            ],
          )
        : applicantsButton;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: JobMateTheme.divider),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    final title = Text(
                      job['title'] as String? ?? 'Untitled job',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    );
                    final badge = Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        postingStatusLabel(status),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                    if (box.maxWidth <
                        360 * MediaQuery.textScalerOf(context).scale(14) / 14) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 8), badge],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 12),
                        badge,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (display.text('employment_type').isNotEmpty)
                      EmploymentTypeBadge(display.text('employment_type')),
                    if (display.text('location').isNotEmpty)
                      JobListingMetadata(
                        Icons.location_on_outlined,
                        display.text('location'),
                      ),
                    if (display.text('work_arrangement').isNotEmpty)
                      JobListingMetadata(
                        Icons.work_outline,
                        jobLabel(display.text('work_arrangement')),
                      ),
                    Text(
                      marketplaceSalary(display),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    if (display.text('department').isNotEmpty)
                      JobListingMetadata(
                        Icons.business_center_outlined,
                        display.text('department'),
                      ),
                    JobListingMetadata(
                      Icons.people_outline,
                      'Vacancies: ${job['vacancies'] ?? 'Not set'}',
                    ),
                    if (job['application_deadline'] != null)
                      JobListingMetadata(
                        Icons.event_outlined,
                        'Deadline: ${marketplaceDate(job['application_deadline'])}',
                      ),
                    if (job['published_at'] != null)
                      JobListingMetadata(
                        Icons.schedule,
                        'Published: ${marketplaceDate(job['published_at'])}',
                      )
                    else if (job['created_at'] != null)
                      JobListingMetadata(
                        Icons.schedule,
                        'Created: ${marketplaceDate(job['created_at'])}',
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: JobMateTheme.background,
              border: Border(top: BorderSide(color: JobMateTheme.divider)),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final actions = [
                  if (status == 'published') applicants,
                  if (status == 'draft')
                    FilledButton(
                      onPressed: busy ? null : onPublish,
                      child: const Text('Publish'),
                    ),
                  if (status == 'draft' || status == 'published')
                    TextButton.icon(
                      onPressed: busy ? null : onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      label: Text(status == 'draft' ? 'Edit Draft' : 'Edit'),
                    ),
                  TextButton.icon(
                    onPressed: busy ? null : onPreview,
                    icon: const Icon(Icons.visibility_outlined, size: 17),
                    label: const Text('Preview'),
                  ),
                  if (status != 'published') applicants,
                ];
                final close = TextButton.icon(
                  onPressed: busy ? null : onClose,
                  icon: const Icon(Icons.close, size: 17),
                  label: const Text('Close Job'),
                );
                if (status == 'published' &&
                    box.maxWidth >=
                        700 * MediaQuery.textScalerOf(context).scale(14) / 14) {
                  return Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: actions,
                        ),
                      ),
                      const SizedBox(width: 12),
                      close,
                    ],
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [...actions, if (status == 'published') close],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
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
                          padding: const EdgeInsets.all(16),
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
                                  fontSize: 24,
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
