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
        AppRoutes.attendanceReview,
        'Attendance Review (demo)',
        Icons.fact_check_outlined,
      ),
      (
        AppRoutes.employerPayments,
        'Payments (sandbox)',
        Icons.receipt_long_outlined,
      ),
    ],
    'Communication': [
      (
        AppRoutes.employerMessages,
        'Messages (demo)',
        Icons.chat_bubble_outline,
      ),
    ],
    'Company': [
      (AppRoutes.company, 'Company profile', Icons.business_outlined),
      (
        AppRoutes.employerEvaluations,
        'Evaluations (demo)',
        Icons.rate_review_outlined,
      ),
    ],
  },
  'administrator' || 'admin' => {
    'ADMINISTRATION': [
      (AppRoutes.home, 'Dashboard', Icons.grid_view_rounded),
      (AppRoutes.adminUsers, 'Users', Icons.people_outline),
      (AppRoutes.adminDemoJobs, 'Job Moderation (demo)', Icons.work_outline),
      (AppRoutes.adminDemoDisputes, 'Disputes (demo)', Icons.gavel_outlined),
      (AppRoutes.adminDemoReports, 'Reports (demo)', Icons.analytics_outlined),
      (
        AppRoutes.adminPayments,
        'Payments (sandbox)',
        Icons.receipt_long_outlined,
      ),
    ],
    'PREVIEW': [
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
          AppRoutes.attendance,
          'Attendance (demo)',
          Icons.event_available_outlined,
        ),
        (
          AppRoutes.evaluations,
          'Evaluations (demo)',
          Icons.rate_review_outlined,
        ),
      ],
      'Communication': [
        (AppRoutes.messages, 'Messages (demo)', Icons.chat_bubble_outline),
      ],
    },
    if (role == 'job_seeker')
      'Payments': [
        (AppRoutes.payments, 'Payments (sandbox)', Icons.receipt_long_outlined),
      ],
  },
};

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
