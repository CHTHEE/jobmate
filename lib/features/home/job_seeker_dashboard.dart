import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../applications/module2_repository.dart';

/// A compact overview. Application records below belong to the demo session.
class JobSeekerDashboard extends StatelessWidget {
  const JobSeekerDashboard({
    super.key,
    required this.name,
    required this.email,
    required this.phone,
    required this.photo,
    required this.onProfile,
  });

  final String name;
  final String email;
  final String phone;
  final String photo;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final needsProfileReminder =
        name.trim().isEmpty ||
        email.trim().isEmpty ||
        phone.trim().isEmpty ||
        photo.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading(
          title: name.isEmpty ? 'Your dashboard' : 'Welcome, $name',
          description: 'Your next opportunity starts here.',
          fontSize: 24,
        ),
        if (needsProfileReminder) ...[
          _ProfileCompletion(
            name: name,
            email: email,
            phone: phone,
            photo: photo,
            onProfile: onProfile,
          ),
          const SizedBox(height: 24),
        ],
        const _AppliedCompanies(),
        const SizedBox(height: 24),
        const WorkspaceCard(
          title: 'Evaluations from others',
          child: Row(
            children: [
              Icon(Icons.rate_review_outlined, color: JobMateTheme.darkTeal),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Evaluations will appear here when this feature is available.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileCompletion extends StatelessWidget {
  const _ProfileCompletion({
    required this.name,
    required this.email,
    required this.phone,
    required this.photo,
    required this.onProfile,
  });

  final String name;
  final String email;
  final String phone;
  final String photo;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final checks = <(String, bool)>[
      ('Add your name', name.isNotEmpty),
      ('Email on account', email.trim().isNotEmpty),
      ('Add a phone number', phone.isNotEmpty),
      ('Add a profile photo', photo.isNotEmpty),
    ];
    final completed = checks.where((check) => check.$2).length;
    final percentage = completed * 25;
    return WorkspaceCard(
      title: 'Complete your profile',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$percentage%',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: JobMateTheme.darkTeal,
              ),
            ),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: completed / checks.length,
            minHeight: 10,
            borderRadius: BorderRadius.circular(10),
            backgroundColor: JobMateTheme.divider,
            color: JobMateTheme.primary,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 520;
              final width = twoColumns
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 16,
                runSpacing: 10,
                children: [
                  for (final check in checks)
                    SizedBox(
                      width: width,
                      child: Row(
                        children: [
                          Icon(
                            check.$2
                                ? Icons.check_circle_outline
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: check.$2
                                ? JobMateTheme.darkTeal
                                : JobMateTheme.border,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              check.$1,
                              style: TextStyle(
                                color: check.$2
                                    ? JobMateTheme.body
                                    : JobMateTheme.heading,
                                decoration: check.$2
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onProfile,
              child: const Text('Edit profile'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppliedCompanies extends StatelessWidget {
  const _AppliedCompanies();

  @override
  Widget build(BuildContext context) {
    final repository = Module2Repository.session;
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final applications = repository.searchApplications(mineOnly: true);
        return WorkspaceCard(
          title: 'Applied companies',
          subtitle: 'Demo applications only. These are not real submissions.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (applications.isEmpty)
                const Text('No demo applications yet.')
              else
                for (final application in applications.take(2)) ...[
                  _ApplicationRow(
                    company:
                        repository.job(application.jobId)?.company ??
                        'Demo company',
                    title:
                        repository.job(application.jobId)?.title ?? 'Demo job',
                    status: application.stage.label,
                  ),
                  const SizedBox(height: 12),
                ],
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () => context.go(AppRoutes.applications),
                  child: const Text('View applications'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ApplicationRow extends StatelessWidget {
  const _ApplicationRow({
    required this.company,
    required this.title,
    required this.status,
  });

  final String company;
  final String title;
  final String status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: JobMateTheme.background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: JobMateTheme.divider),
    ),
    child: Row(
      children: [
        const CircleAvatar(
          backgroundColor: JobMateTheme.teal100,
          child: Icon(Icons.business_outlined, color: JobMateTheme.darkTeal),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                company,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(title, style: const TextStyle(color: JobMateTheme.body)),
              Text(
                status,
                style: const TextStyle(color: JobMateTheme.darkTeal),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
