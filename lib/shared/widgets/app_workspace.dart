import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../navigation/app_routes.dart';
import 'auth_style.dart';
import 'responsive_layout.dart';

const upcomingModules = <(String, IconData)>[];

/// A presentation shell around existing GoRouter pages; no auth or data writes.
class AppWorkspace extends StatelessWidget {
  const AppWorkspace({
    super.key,
    required this.title,
    required this.path,
    required this.role,
    required this.child,
    this.actions = const [],
    this.leading,
    this.onNavigate,
    this.navigationLocked = false,
  });
  final String title;
  final String path;
  final String role;
  final Widget child;
  final List<Widget> actions;
  final Widget? leading;
  final ValueChanged<String>? onNavigate;
  final bool navigationLocked;

  @override
  Widget build(BuildContext context) {
    final base = AuthStyle.theme(context);
    return Theme(
      data: base,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop =
              constraints.maxWidth >= ResponsiveLayout.expandedBreakpoint;
          void navigate(String destination, {bool closeDrawer = false}) {
            if (navigationLocked) return;
            if (closeDrawer && !desktop) Navigator.of(context).pop();
            if (destination == path) return;
            if (onNavigate != null) {
              onNavigate!(destination);
            } else if (destination == AppRoutes.home) {
              context.go(destination);
            } else {
              context.push<void>(destination);
            }
          }

          final navigation = Material(
            color: Colors.white,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: AuthWordmark(),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'WORKSPACE',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final item in <(String, String, IconData)>[
                    (AppRoutes.home, 'Dashboard', Icons.grid_view_rounded),
                    if (role == 'administrator') ...[
                      (
                        AppRoutes.adminUsers,
                        'Real User Directory',
                        Icons.people_outline,
                      ),
                      (
                        AppRoutes.adminPreview,
                        'UI Sandbox (demo)',
                        Icons.dashboard_customize_outlined,
                      ),
                      (
                        AppRoutes.adminDemoAccounts,
                        'Account Actions (demo)',
                        Icons.manage_accounts_outlined,
                      ),
                      (
                        AppRoutes.adminDemoJobs,
                        'Job Moderation (demo)',
                        Icons.work_outline,
                      ),
                      (
                        AppRoutes.adminDemoDisputes,
                        'Disputes (demo)',
                        Icons.gavel_outlined,
                      ),
                      (
                        AppRoutes.adminDemoReports,
                        'Reports (demo)',
                        Icons.analytics_outlined,
                      ),
                    ],
                    if (role == 'job_seeker')
                      (AppRoutes.browseJobs, 'Browse Jobs', Icons.search),
                    if (role == 'job_seeker')
                      (
                        AppRoutes.applications,
                        'My Applications',
                        Icons.assignment_outlined,
                      ),
                    if (role == 'employer')
                      (
                        AppRoutes.applicants,
                        'Applications (demo)',
                        Icons.people_outline,
                      ),
                    (
                      AppRoutes.profile,
                      'Personal profile',
                      Icons.person_outline,
                    ),
                    if (role == 'employer')
                      (
                        AppRoutes.company,
                        'Company profile',
                        Icons.business_outlined,
                      ),
                    if (role == 'employer')
                      (
                        AppRoutes.jobPostings,
                        'My Job Postings',
                        Icons.work_outline,
                      ),
                    if (role == 'employer')
                      (
                        AppRoutes.createJob,
                        'Create Job',
                        Icons.add_circle_outline,
                      ),
                    if (role == 'job_seeker')
                      (
                        AppRoutes.recommendations,
                        'For You (demo)',
                        Icons.auto_awesome_outlined,
                      ),
                    if (role == 'job_seeker')
                      (
                        AppRoutes.nearbyJobs,
                        'Nearby Jobs (demo)',
                        Icons.map_outlined,
                      ),
                    if (role == 'job_seeker')
                      (
                        AppRoutes.attendance,
                        'Attendance (demo)',
                        Icons.event_available_outlined,
                      ),
                    if (role == 'employer')
                      (
                        AppRoutes.attendanceReview,
                        'Attendance Review (demo)',
                        Icons.fact_check_outlined,
                      ),
                    if (['job_seeker', 'employer'].contains(role))
                      (
                        role == 'employer'
                            ? AppRoutes.employerMessages
                            : AppRoutes.messages,
                        'Messages (demo)',
                        Icons.chat_bubble_outline,
                      ),
                    if (role == 'employer')
                      (
                        AppRoutes.jobLocationDemo,
                        'Location Picker (demo)',
                        Icons.add_location_alt_outlined,
                      ),
                    if (['job_seeker', 'employer'].contains(role)) ...[
                      (
                        role == 'employer'
                            ? AppRoutes.employerEvaluations
                            : AppRoutes.evaluations,
                        'Evaluations (demo)',
                        Icons.rate_review_outlined,
                      ),
                      (
                        role == 'employer'
                            ? AppRoutes.employerReputation
                            : AppRoutes.reputation,
                        'Reputation (demo)',
                        Icons.stars_outlined,
                      ),
                      (
                        role == 'employer'
                            ? AppRoutes.employerPayments
                            : AppRoutes.payments,
                        'Payments (demo)',
                        Icons.receipt_long_outlined,
                      ),
                    ],
                    (
                      role == 'employer'
                          ? AppRoutes.employerSettings
                          : role == 'administrator'
                          ? AppRoutes.adminSettings
                          : AppRoutes.settings,
                      'Account Settings',
                      Icons.settings_outlined,
                    ),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        selected: path == item.$1,
                        selectedTileColor: const Color(0xFFF0FDFA),
                        selectedColor: AuthStyle.darkTeal,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: Icon(item.$3),
                        title: Text(item.$2),
                        enabled: !navigationLocked,
                        onTap: () => navigate(item.$1, closeDrawer: true),
                      ),
                    ),
                  if (upcomingModules.isNotEmpty) ...[
                    const Divider(height: 32),
                    const Text(
                      'COMING SOON',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final module in upcomingModules.where(
                      (m) =>
                          !['employer', 'job_seeker'].contains(role) ||
                          m.$1 != 'Job Posting',
                    ))
                      ListTile(
                        enabled: false,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        leading: Icon(module.$2, size: 20),
                        title: Text(
                          module.$1,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
          return Scaffold(
            bottomNavigationBar:
                !desktop && ['job_seeker', 'employer'].contains(role)
                ? SafeArea(
                    child: NavigationBar(
                      selectedIndex: role == 'job_seeker'
                          ? (path == AppRoutes.browseJobs
                                ? 1
                                : path == AppRoutes.applications
                                ? 2
                                : path == AppRoutes.profile
                                ? 3
                                : 0)
                          : (path == AppRoutes.jobPostings ||
                                    path == AppRoutes.createJob
                                ? 1
                                : path == AppRoutes.applicants
                                ? 2
                                : path == AppRoutes.company
                                ? 3
                                : 0),
                      onDestinationSelected: navigationLocked
                          ? null
                          : (index) => navigate(
                              (role == 'job_seeker'
                                  ? [
                                      AppRoutes.home,
                                      AppRoutes.browseJobs,
                                      AppRoutes.applications,
                                      AppRoutes.profile,
                                    ]
                                  : [
                                      AppRoutes.home,
                                      AppRoutes.jobPostings,
                                      AppRoutes.applicants,
                                      AppRoutes.company,
                                    ])[index],
                            ),
                      destinations: [
                        const NavigationDestination(
                          icon: Icon(Icons.dashboard_outlined),
                          label: 'Home',
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.work_outline),
                          label: role == 'job_seeker' ? 'Jobs' : 'Posts',
                        ),
                        const NavigationDestination(
                          icon: Icon(Icons.assignment_outlined),
                          label: 'Applications',
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.person_outline),
                          label: role == 'job_seeker' ? 'Profile' : 'Company',
                        ),
                      ],
                    ),
                  )
                : null,
            drawer: desktop ? null : Drawer(child: navigation),
            drawerEnableOpenDragGesture: !navigationLocked,
            appBar: AppBar(
              automaticallyImplyLeading: !kIsWeb,
              leading:
                  leading ??
                  (kIsWeb && !desktop
                      ? Builder(
                          builder: (context) => IconButton(
                            tooltip: 'Open navigation menu',
                            onPressed: navigationLocked
                                ? null
                                : () => Scaffold.of(context).openDrawer(),
                            icon: const Icon(Icons.menu),
                          ),
                        )
                      : null),
              title: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: actions,
            ),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (desktop) SizedBox(width: 288, child: navigation),
                Expanded(child: SafeArea(child: child)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class WorkspaceContent extends StatelessWidget {
  const WorkspaceContent({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: ResponsiveLayout.pagePadding(context),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}

class WorkspaceCard extends StatelessWidget {
  const WorkspaceCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AuthStyle.heading,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: const TextStyle(height: 1.5)),
          ],
          const SizedBox(height: 20),
          child,
        ],
      ),
    ),
  );
}

class WorkspaceStatus extends StatelessWidget {
  const WorkspaceStatus(this.value, {super.key});
  final String value;
  @override
  Widget build(BuildContext context) {
    final color = switch (value) {
      'verified' || 'active' => AuthStyle.darkTeal,
      'pending' => const Color(0xFF92400E),
      'rejected' || 'suspended' || 'deactivated' => AuthStyle.error,
      _ => AuthStyle.body,
    };
    return Chip(
      backgroundColor: color.withValues(alpha: .07),
      side: BorderSide(color: color.withValues(alpha: .15)),
      avatar: Icon(
        value == 'verified' ? Icons.verified_outlined : Icons.circle,
        color: color,
        size: 14,
      ),
      label: Text(
        workspaceLabel(value),
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}

String workspaceLabel(String value) =>
    const {
      'job_seeker': 'Job Seeker',
      'employer': 'Employer',
      'administrator': 'Administrator',
      'not_submitted': 'Not submitted',
      'pending': 'Pending review',
      'verified': 'Verified',
      'rejected': 'Rejected',
      'active': 'Active',
      'suspended': 'Suspended',
      'deactivated': 'Deactivated',
      'owner': 'Owner',
    }[value] ??
    (value.isEmpty ? 'Not available' : value.replaceAll('_', ' '));

class WorkspaceInfo extends StatelessWidget {
  const WorkspaceInfo(this.label, this.value, {super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AuthStyle.body),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value.isEmpty ? 'Not provided' : value,
          style: const TextStyle(
            color: AuthStyle.heading,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}
