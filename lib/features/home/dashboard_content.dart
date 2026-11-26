import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/auth_style.dart';
import '../../shared/widgets/design_primitives.dart';
import 'employer_dashboard.dart';
import 'job_seeker_dashboard.dart';

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
    this.jobPostings,
    this.jobPostingsError,
    this.seekerClient,
    this.employerClient,
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
  final List<Map<String, dynamic>>? jobPostings;
  final String? jobPostingsError;
  final SupabaseClient? seekerClient, employerClient;

  @override
  Widget build(BuildContext context) {
    final role = profile['role'] as String? ?? '';
    final name = (profile['name'] as String? ?? '').trim();
    final photo = (profile['profile_image_url'] as String? ?? '').trim();
    if (role == 'job_seeker') {
      return JobSeekerDashboard(
        key: ValueKey(profile['status']),
        name: name,
        email: email == 'No email available' ? '' : email,
        phone: (profile['phone_num'] as String? ?? '').trim(),
        photo: photo,
        onProfile: onProfile,
        client: profile['status'] == 'active' ? seekerClient : null,
      );
    }
    if (role == 'employer') {
      return EmployerDashboard(
        key: ValueKey((
          employerClient?.auth.currentUser?.id,
          company?['company_id'],
          memberRole,
          profile['status'],
          company?['verification_status'],
        )),
        profile: profile,
        email: email,
        company: company,
        companyError: companyError,
        memberRole: memberRole,
        client: employerClient,
        initialPostings: jobPostings,
        initialPostingError: jobPostingsError,
        onProfile: onProfile,
        onCompany: onCompany,
        onVerification: onVerification,
        onRefresh: onRetry,
      );
    }
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
          if (completed < 4) ...[
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
          ],
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: onProfile,
            child: const Text('View personal profile'),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading(
          fontSize: 24,
          title: 'Welcome${name.isEmpty ? '' : ', $name'}',
          description: 'Discover opportunities, track applications and plan your next step.',
          actions: [
            if (onRetry != null)
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Check for updates'),
              ),
          ],
        ),
        summary,
        const SizedBox(height: 20),
        if (upcomingModules.isNotEmpty)
          WorkspaceCard(
            title: 'Coming soon',
            subtitle: 'These modules are planned and are not available yet.',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final module in upcomingModules)
                  Chip(
                    avatar: Icon(module.$2, size: 16),
                    label: Text(module.$1),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
