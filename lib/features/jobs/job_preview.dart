import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../company/company_logo.dart';
import '../applications/browse_job_card.dart';
import '../applications/job_details_presentation.dart';
import '../applications/job_marketplace_format.dart';
import '../applications/module2_repository.dart' show BrowseJob;
import '../../shared/widgets/app_workspace.dart';
import '../../shared/theme/jobmate_theme.dart';
import 'job_display.dart';

class JobPreview extends StatefulWidget {
  const JobPreview({
    super.key,
    required this.job,
    required this.company,
    this.logo,
  });
  final Uint8List? logo;
  final Map<String, dynamic> job;
  final String company;
  @override
  State<JobPreview> createState() => _JobPreviewState();
}

class _JobPreviewState extends State<JobPreview> {
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    return AlertDialog(
      constraints: BoxConstraints(
        maxWidth: 640,
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      titlePadding: const EdgeInsets.fromLTRB(20, 10, 10, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Job Preview',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Close preview',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: Scrollbar(
          controller: scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${job['title'] ?? ''}'.trim().isEmpty
                      ? 'Untitled job'
                      : '${job['title']}',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                CompanyIdentity(name: widget.company, logo: widget.logo),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (job['status'] != null)
                      WorkspaceStatus(job['status'] as String),
                    if ('${job['employment_type'] ?? ''}'.isNotEmpty)
                      EmploymentTypeBadge('${job['employment_type']}'),
                    if ('${job['location'] ?? ''}'.isNotEmpty)
                      JobListingMetadata(
                        Icons.location_on_outlined,
                        '${job['location']}',
                      ),
                    if ('${job['work_arrangement'] ?? ''}'.isNotEmpty)
                      JobListingMetadata(
                        Icons.work_outline,
                        jobLabel('${job['work_arrangement']}'),
                      ),
                    Text(
                      marketplaceSalary(
                        BrowseJob(job, company: widget.company),
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: JobMateTheme.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      for (final item in [
                        ('Department', job['department']),
                        ('Vacancies', job['vacancies']),
                        (
                          'Application deadline',
                          marketplaceDate(job['application_deadline']),
                        ),
                        if (job['created_at'] != null)
                          ('Created date', marketplaceDate(job['created_at'])),
                        if (job['published_at'] != null)
                          (
                            'Published date',
                            marketplaceDate(job['published_at']),
                          ),
                        if (job['latitude'] != null)
                          ('Latitude', job['latitude']),
                        if (job['longitude'] != null)
                          ('Longitude', job['longitude']),
                      ])
                        Text(
                          '${item.$1}: ${item.$2 ?? 'Not set'}',
                          style: const TextStyle(
                            color: JobMateTheme.body,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                for (final entry in [
                  ('role_overview', 'Role overview'),
                  ('responsibilities', 'Responsibilities'),
                  ('requirements', 'Requirements'),
                  ('benefits', 'Benefits'),
                ]) ...[
                  const SizedBox(height: 14),
                  Text(
                    entry.$2,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: JobMateTheme.darkTeal,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (JobContent.hasContent(job[entry.$1]))
                    JobContent(job[entry.$1])
                  else
                    const Text(
                      'Not provided',
                      style: TextStyle(color: JobMateTheme.body),
                    ),
                ],
                if ('${job['original_description'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: JobMateTheme.background,
                      border: Border.all(color: JobMateTheme.divider),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Employer Original description',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Retained separately from AI-formatted content.',
                          style: TextStyle(
                            color: JobMateTheme.body,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          '${job['original_description']}',
                          style: const TextStyle(height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'This is a preview, not a publication action.',
                  style: TextStyle(color: JobMateTheme.body, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
      ],
    );
  }
}
