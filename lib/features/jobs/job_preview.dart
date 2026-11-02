import 'package:flutter/material.dart';

import 'dart:typed_data';

import '../company/company_logo.dart';

import '../../shared/widgets/app_workspace.dart';
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
    title: Text('${job['title'] ?? 'Untitled job'}'),
    content: SizedBox(
      width: 640,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CompanyIdentity(name: company, logo: logo),
            if (job['status'] != null) WorkspaceStatus(job['status'] as String),
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
            const Divider(),
            WorkspaceInfo('Role overview', '${job['role_overview'] ?? ''}'),
            for (final key in [
              'responsibilities',
              'requirements',
              'benefits',
            ]) ...[
              const SizedBox(height: 12),
              Text(
                jobLabel(key),
                style: Theme.of(context).textTheme.titleMedium,
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
              const Divider(height: 32),
              WorkspaceInfo(
                'Original description',
                '${job['original_description']}',
              ),
            ],
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
