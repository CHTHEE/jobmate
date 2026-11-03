import 'package:flutter/material.dart';

import 'dart:typed_data';

import '../company/company_logo.dart';

import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/theme/jobmate_theme.dart';
import 'job_display.dart';

class JobPreview extends StatelessWidget {
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
  Widget build(BuildContext context) => AlertDialog(
    constraints: BoxConstraints(
      maxWidth: 512,
      maxHeight: MediaQuery.sizeOf(context).height * .8,
    ),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'JOB PREVIEW',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            color: JobMateTheme.darkTeal,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${job['title'] ?? 'Untitled job'}',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ],
    ),
    content: SizedBox(
      width: 464,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDFA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CompanyIdentity(name: company, logo: logo),
                  const SizedBox(height: 8),
                  if (job['status'] != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: WorkspaceStatus(job['status'] as String),
                    ),
                ],
              ),
            ),
            const FormSectionHeading(
              'The opportunity',
              'A preview of the details candidates will see.',
              icon: Icons.work_outline,
            ),
            for (final key in [
              'department',
              'employment_type',
              'work_arrangement',
              'location',
              'vacancies',
            ])
              WorkspaceInfo(jobLabel(key), jobLabel('${job[key] ?? ''}')),
            if (job['latitude'] != null)
              WorkspaceInfo('Latitude', '${job['latitude']}'),
            if (job['longitude'] != null)
              WorkspaceInfo('Longitude', '${job['longitude']}'),
            if (job['salary_visible'] == true)
              WorkspaceInfo('Salary', jobSalary(job)),
            WorkspaceInfo(
              'Application deadline',
              jobDate(job['application_deadline']),
            ),
            if (job['created_at'] != null)
              WorkspaceInfo('Created date', jobDate(job['created_at'])),
            if (job['published_at'] != null)
              WorkspaceInfo('Published date', jobDate(job['published_at'])),
            const FormSectionHeading(
              'About the role',
              'Review your content and ensure every detail is accurate.',
              icon: Icons.description_outlined,
            ),
            WorkspaceInfo('Role overview', '${job['role_overview'] ?? ''}'),
            for (final key in [
              'responsibilities',
              'requirements',
              'benefits',
            ]) ...[
              const SizedBox(height: 12),
              Text(
                jobLabel(key),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: JobMateTheme.darkTeal,
                ),
              ),
              if ((job[key] as List? ?? []).isEmpty) const Text('Not provided'),
              for (final item in job[key] as List? ?? [])
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('\u2022  '),
                      Expanded(child: SelectableText('$item')),
                    ],
                  ),
                ),
            ],
            if ('${job['original_description'] ?? ''}'.isNotEmpty) ...[
              const FormSectionHeading(
                'Employer original',
                'Your original description is retained separately from AI-formatted content.',
                icon: Icons.edit_note_outlined,
              ),
              WorkspaceInfo(
                'Original description',
                '${job['original_description']}',
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'This is a preview, not a publication action.',
              style: TextStyle(color: JobMateTheme.body, fontSize: 12),
            ),
          ],
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
