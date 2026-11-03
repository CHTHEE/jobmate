import 'package:flutter/material.dart';

import 'app_routes.dart';

typedef WorkspaceDestination = (String path, String label, IconData icon);
Map<String, List<WorkspaceDestination>> workspaceDestinations(
  String role,
) => switch (role) {
  'employer' => {
    'WORKSPACE': [(AppRoutes.home, 'Dashboard', Icons.grid_view_rounded)],
    'JOB POSTS': [
      (AppRoutes.jobPostings, 'My Job Postings', Icons.work_outline),
      (AppRoutes.createJob, 'Create Job', Icons.add_circle_outline),
      (
        AppRoutes.jobLocationDemo,
        'Location Picker (demo)',
        Icons.add_location_alt_outlined,
      ),
    ],
    'APPLICATIONS': [
      (AppRoutes.applicants, 'Applications (demo)', Icons.people_outline),
    ],
    'WORKERS': [
      (
        AppRoutes.attendanceReview,
        'Attendance Review (demo)',
        Icons.fact_check_outlined,
      ),
      (
        AppRoutes.employerPayments,
        'Payments (demo)',
        Icons.receipt_long_outlined,
      ),
    ],
    'COMMUNICATION': [
      (
        AppRoutes.employerMessages,
        'Messages (demo)',
        Icons.chat_bubble_outline,
      ),
    ],
    'COMPANY & ACCOUNT': [
      (AppRoutes.company, 'Company profile', Icons.business_outlined),
      (
        AppRoutes.employerEvaluations,
        'Evaluations (demo)',
        Icons.rate_review_outlined,
      ),
      (AppRoutes.employerReputation, 'Reputation (demo)', Icons.stars_outlined),
      (AppRoutes.profile, 'Personal profile', Icons.person_outline),
      (AppRoutes.employerSettings, 'Account Settings', Icons.settings_outlined),
    ],
  },
  'administrator' => {
    'ADMINISTRATION': [
      (AppRoutes.home, 'Dashboard', Icons.grid_view_rounded),
      (AppRoutes.adminUsers, 'Real User Directory', Icons.people_outline),
      (AppRoutes.adminDemoJobs, 'Job Moderation (demo)', Icons.work_outline),
      (AppRoutes.adminDemoDisputes, 'Disputes (demo)', Icons.gavel_outlined),
      (AppRoutes.adminDemoReports, 'Reports (demo)', Icons.analytics_outlined),
    ],
    'PREVIEW & ACCOUNT': [
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
      (AppRoutes.profile, 'Personal profile', Icons.person_outline),
      (AppRoutes.adminSettings, 'Account Settings', Icons.settings_outlined),
    ],
  },
  _ => {
    'WORKSPACE': [(AppRoutes.home, 'Dashboard', Icons.grid_view_rounded)],
    if (role == 'job_seeker') ...{
      'FIND WORK': [
        (AppRoutes.browseJobs, 'Browse Jobs', Icons.search),
        (
          AppRoutes.recommendations,
          'For You (demo)',
          Icons.auto_awesome_outlined,
        ),
        (AppRoutes.nearbyJobs, 'Nearby Jobs (demo)', Icons.map_outlined),
      ],
      'APPLICATIONS': [
        (AppRoutes.applications, 'My Applications', Icons.assignment_outlined),
      ],
      'WORK': [
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
      'COMMUNICATION': [
        (AppRoutes.messages, 'Messages (demo)', Icons.chat_bubble_outline),
      ],
    },
    'PROFILE': [
      (AppRoutes.profile, 'Personal profile', Icons.person_outline),
      if (role == 'job_seeker') ...[
        (AppRoutes.reputation, 'Reputation (demo)', Icons.stars_outlined),
        (AppRoutes.payments, 'Payments (demo)', Icons.receipt_long_outlined),
      ],
      (AppRoutes.settings, 'Account Settings', Icons.settings_outlined),
    ],
  },
};
