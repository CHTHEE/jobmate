import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_routes.dart';

typedef WorkspaceDestination = (String path, String label, IconData icon);
Map<String, List<WorkspaceDestination>> workspaceDestinations(
  String role,
) => switch (role) {
  'employer' => {
    'WORKSPACE': [(AppRoutes.home, 'Dashboard', Icons.grid_view_rounded)],
    'Job Management': [
      (AppRoutes.jobPostings, 'My Job Postings', Icons.work_outline),
      (AppRoutes.createJob, 'Create Job', Icons.add_circle_outline),
      (
        AppRoutes.jobLocationDemo,
        'Location Picker (demo)',
        Icons.add_location_alt_outlined,
      ),
      (AppRoutes.applicants, 'View Applicants', Icons.people_outline),
    ],
    'Work Management': [
      (
        AppRoutes.workVerification,
        'Work Verification',
        Icons.assignment_turned_in_outlined,
      ),
      (AppRoutes.workers, 'Workers (demo)', Icons.groups_outlined),
      (
        AppRoutes.employerPayments,
        'Payments (sandbox)',
        Icons.receipt_long_outlined,
      ),
    ],
    'Communication': [
      (AppRoutes.disputes, 'My disputes', Icons.gavel_outlined),
      (AppRoutes.userReports, 'My reports', Icons.flag_outlined),
      (
        AppRoutes.employerMessages,
        'Messages (demo)',
        Icons.chat_bubble_outline,
      ),
    ],
    'Company': [
      (AppRoutes.company, 'Company profile', Icons.business_outlined),
      (
        AppRoutes.employerSoftSkillEvaluations,
        'Evaluations',
        Icons.rate_review_outlined,
      ),
    ],
  },
  'administrator' || 'admin' => {
    'Administration': [
      (AppRoutes.home, 'Dashboard', Icons.grid_view_rounded),
      (AppRoutes.adminUsers, 'Users', Icons.people_outline),
      (AppRoutes.adminCompanies, 'Companies', Icons.business_outlined),
      (AppRoutes.adminReports, 'User Reports', Icons.flag_outlined),
      (AppRoutes.adminJobModeration, 'Job Moderation', Icons.work_outline),
      (AppRoutes.adminDemoDisputes, 'Disputes (demo)', Icons.gavel_outlined),
      (AppRoutes.adminDisputes, 'Disputes', Icons.gavel_outlined),
      (
        AppRoutes.adminDemoReports,
        'Reports Analytics (demo)',
        Icons.analytics_outlined,
      ),
      (
        AppRoutes.adminPayments,
        'Payments (sandbox)',
        Icons.receipt_long_outlined,
      ),
    ],
    'Preview': [
      (
        AppRoutes.adminPreview,
        'UI Sandbox (demo)',
        Icons.dashboard_customize_outlined,
      ),
    ],
  },
  _ => {
    'WORKSPACE': [(AppRoutes.home, 'Dashboard', Icons.grid_view_rounded)],
    if (role == 'job_seeker') ...{
      'Find Work': [
        (AppRoutes.search, 'Search', Icons.search),
        (AppRoutes.browseJobs, 'Browse Jobs', Icons.search),
        (
          AppRoutes.recommendations,
          'For You (demo)',
          Icons.auto_awesome_outlined,
        ),
        (AppRoutes.nearbyJobs, 'Nearby Jobs (demo)', Icons.map_outlined),
      ],
      'Applications': [
        (AppRoutes.applications, 'My Applications', Icons.assignment_outlined),
      ],
      'My Work': [
        (
          AppRoutes.workAttendance,
          'My Work Shifts',
          Icons.calendar_month_outlined,
        ),
        (
          AppRoutes.softSkillEvaluations,
          'Evaluations',
          Icons.rate_review_outlined,
        ),
        (AppRoutes.reputation, 'My Reputation', Icons.insights_outlined),
      ],
      'Communication': [
        (AppRoutes.disputes, 'My disputes', Icons.gavel_outlined),
        (AppRoutes.userReports, 'My reports', Icons.flag_outlined),
        (AppRoutes.messages, 'Messages (demo)', Icons.chat_bubble_outline),
      ],
    },
    if (role == 'job_seeker')
      'Payments': [
        (AppRoutes.payments, 'Payments (sandbox)', Icons.receipt_long_outlined),
      ],
  },
};

/// The Admin sidebar is derived from the signed-in Admin's own permission
/// row, so every Admin page shows the same destinations and fails closed while
/// a permission is unavailable or has not been deployed.
Map<String, List<WorkspaceDestination>> adminWorkspaceDestinations(
  Map<String, dynamic>? permissions,
) {
  bool has(String column) => permissions?[column] == true;

  return {
    'Administration': [
      (AppRoutes.home, 'Dashboard', Icons.grid_view_rounded),
      // Directory and safe detail reads are available to every active Admin.
      (AppRoutes.adminUsers, 'Users', Icons.people_outline),
      (AppRoutes.adminCompanies, 'Companies', Icons.business_outlined),
      if (has('can_manage_user_reports'))
        (AppRoutes.adminReports, 'User Reports', Icons.flag_outlined),
      if (has('can_manage_job_moderation'))
        (
          AppRoutes.adminJobModeration,
          'Job Moderation',
          Icons.work_outline,
        ),
      if (has('can_manage_disputes'))
        (AppRoutes.adminDisputes, 'Disputes', Icons.gavel_outlined),
      (
        AppRoutes.adminPayments,
        'Payments (sandbox)',
        Icons.receipt_long_outlined,
      ),
    ],
    'Admin tools': [
      if (has('can_review_companies'))
        (
          AppRoutes.companyReviews,
          'Company Verification',
          Icons.business_outlined,
        ),
      if (has('can_invite_admins'))
        (
          AppRoutes.inviteAdmin,
          'Invite administrator',
          Icons.person_add_alt_1_outlined,
        ),
      if (has('can_manage_admin_permissions'))
        (
          AppRoutes.adminPermissions,
          'Admin permissions',
          Icons.admin_panel_settings_outlined,
        ),
    ],
    'Preview': [
      (
        AppRoutes.adminPreview,
        'UI Sandbox (demo)',
        Icons.dashboard_customize_outlined,
      ),
    ],
  };
}

/// Native primary tabs are drawn from the same role configuration as Web.
/// Less frequent destinations remain available through the grouped More menu.
List<WorkspaceDestination> workspacePrimaryDestinations(String role) {
  final paths = switch (role) {
    'employer' => [AppRoutes.home, AppRoutes.jobPostings, AppRoutes.applicants],
    'administrator' ||
    'admin' => [AppRoutes.home, AppRoutes.adminUsers, AppRoutes.adminPayments],
    'job_seeker' => [
      AppRoutes.home,
      AppRoutes.browseJobs,
      AppRoutes.applications,
    ],
    _ => [AppRoutes.home],
  };
  final all = workspaceDestinations(role).values.expand((items) => items);
  return [for (final path in paths) all.firstWhere((item) => item.$1 == path)];
}

/// Exactly one destination matches, preferring the most specific nested path.
String? selectedWorkspacePath(
  String location,
  Iterable<WorkspaceDestination> destinations,
) {
  final path = Uri.parse(location).path;
  String? selected;
  for (final item in destinations) {
    final candidate = item.$1;
    if ((path == candidate ||
            (candidate != AppRoutes.home && path.startsWith('$candidate/'))) &&
        (selected == null || candidate.length > selected.length)) {
      selected = candidate;
    }
  }
  return selected;
}

/// Replacing the matched root avoids accumulating duplicate native root pages.
/// Web navigation remains URL/history based through GoRouter.
void openWorkspaceDestination(BuildContext context, String destination) {
  // Keep GoRouter's URL/history synchronization and route-exit guards.
  GoRouter.of(context).go(destination);
}

bool isWorkspaceRootPath(String path) =>
    path != AppRoutes.createJob &&
    (path == AppRoutes.adminPermissions ||
        path == AppRoutes.companyReviews ||
        ['job_seeker', 'employer', 'administrator'].any(
          (role) =>
              workspaceDestinations(role).values
                  .expand((items) => items)
                  .any((item) => item.$1 == path),
        ));
