import 'package:flutter/material.dart';

import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/auth_style.dart';

/// Dashboard presentation, using records loaded by HomePage.
class DashboardContent extends StatelessWidget {
  const DashboardContent({
    super.key,
    required this.profile,
    required this.email,
    required this.onProfile,
    required this.onCompany,
    required this.onVerification,
    this.company,
    this.companyError,
    this.memberRole = '',
    this.onRetry,
  });
  final Map<String, dynamic> profile;
  final Map<String, dynamic>? company;
  final String email;
  final String memberRole;
  final String? companyError;
  final VoidCallback onProfile;
  final VoidCallback onCompany;
  final VoidCallback onVerification;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final role = profile['role'] as String? ?? '';
    final name = (profile['name'] as String? ?? '').trim();
    final photo = (profile['profile_image_url'] as String? ?? '').trim();
    final fields = [
      name,
      email.trim(),
      (profile['phone_num'] as String? ?? '').trim(),
      photo,
    ];
    final completed = fields.where((field) => field.isNotEmpty).length;
    final summary = WorkspaceCard(
      title: 'Personal profile',
      subtitle: 'Your account details, separate from company information.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipOval(
                child: photo.isEmpty
                    ? const CircleAvatar(
                        radius: 26,
                        child: Icon(Icons.person_outline),
                      )
                    : Image.network(
                        photo,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const CircleAvatar(
                          radius: 26,
                          child: Icon(Icons.person_outline),
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Your account' : name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AuthStyle.heading,
                      ),
                    ),
                    Text(email),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(workspaceLabel(role))),
              WorkspaceStatus(profile['status'] as String? ?? ''),
            ],
          ),
          const SizedBox(height: 16),
          Text('Profile completion: ${completed * 25}%'),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: completed / 4,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
            backgroundColor: AuthStyle.border,
          ),
          const SizedBox(height: 8),
          const Text(
            'Based on name, email, phone and profile photo.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: onProfile,
            child: const Text('View personal profile'),
          ),
        ],
      ),
    );
    final verification = WorkspaceCard(
      title: 'Personal verification',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: WorkspaceStatus(
              profile['verification_status'] as String? ?? '',
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'View your documents, submission history and available review feedback.',
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: onVerification,
            child: const Text('Verification documents'),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${workspaceLabel(role)} dashboard',
          style: const TextStyle(
            color: AuthStyle.teal,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text('Welcome${name.isEmpty ? '' : ', $name'}', style: AuthStyle.title),
        const SizedBox(height: 8),
        const Text('Your profile, verification and next steps in one place.'),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, constraints) {
            if (role != 'job_seeker' && role != 'employer') return summary;
            return constraints.maxWidth >= 760
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: summary),
                      const SizedBox(width: 20),
                      Expanded(child: verification),
                    ],
                  )
                : Column(
                    children: [
                      summary,
                      const SizedBox(height: 20),
                      verification,
                    ],
                  );
          },
        ),
        if (role == 'employer') ...[
          const SizedBox(height: 20),
          WorkspaceCard(
            title: companyError != null
                ? 'Company unavailable'
                : company == null
                ? 'Set up your company'
                : company!['company_name'] as String? ?? 'Company profile',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (companyError != null) ...[
                  Text(companyError!),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: onRetry,
                    child: const Text('Retry company summary'),
                  ),
                ] else if (company == null) ...[
                  const Text(
                    'Create your company profile and submit a supporting document through the existing onboarding process.',
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: onCompany,
                    child: const Text('Set up company'),
                  ),
                ] else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      WorkspaceStatus(
                        company!['verification_status'] as String? ?? '',
                      ),
                      Chip(
                        label: Text(
                          'Membership: ${workspaceLabel(memberRole)}',
                        ),
                      ),
                    ],
                  ),
                  WorkspaceInfo(
                    'Industry',
                    company!['industry'] as String? ?? '',
                  ),
                  WorkspaceInfo(
                    'Location',
                    company!['location'] as String? ?? '',
                  ),
                  Text(switch (company!['verification_status']) {
                    'pending' => 'Your company is awaiting review. Changes remain locked during review.',
                    'verified' => 'Company verification is complete. Your membership still determines available actions.',
                    'rejected' =>
                      memberRole == 'owner'
                          ? 'Review the feedback before resubmitting your company.'
                          : 'The company owner can review feedback and resubmit.',
                    _ => 'Open the company profile for available actions.',
                  }),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: onCompany,
                    child: const Text('View company profile'),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        WorkspaceCard(
          title: 'Coming soon',
          subtitle: 'These modules are planned and are not available yet.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final module in upcomingModules)
                Chip(avatar: Icon(module.$2, size: 16), label: Text(module.$1)),
            ],
          ),
        ),
      ],
    );
  }
}
