import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:go_router/go_router.dart';

import '../navigation/app_routes.dart';
import 'auth_style.dart';
import '../theme/jobmate_theme.dart';
import '../navigation/workspace_destinations.dart';

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
    final base = JobMateTheme.apply(Theme.of(context));
    return Theme(
      data: base,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 768;
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
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      key: const ValueKey('workspace-navigation'),
                      scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
                      padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: AuthWordmark(compact: true),
                        ),
                        const SizedBox(height: 12),
                        for (final group in workspaceDestinations(
                          role,
                        ).entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 20, 8, 10),
                            child: Text(
                              group.key,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AuthStyle.body,
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          for (final item in group.value)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: ListTile(
                                dense: true,
                                minTileHeight: kIsWeb ? 40 : 48,
                                minVerticalPadding: 0,
                                selected: path == item.$1,
                                selectedTileColor: const Color(0xFFF0FDFA),
                                selectedColor: AuthStyle.darkTeal,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                minLeadingWidth: 24,
                                leading: Icon(item.$3, size: 18),
                                title: Text(
                                  item.$2,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                enabled: !navigationLocked,
                                onTap: () =>
                                    navigate(item.$1, closeDrawer: true),
                              ),
                            ),
                        ],
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
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    leading: const CircleAvatar(
                      radius: 16,
                      backgroundColor: JobMateTheme.teal100,
                      child: Icon(
                        Icons.person_outline,
                        size: 18,
                        color: JobMateTheme.teal,
                      ),
                    ),
                    title: const Text(
                      'Your account',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      workspaceLabel(role),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 16),
                    enabled: !navigationLocked,
                    onTap: () => navigate(
                      role == 'employer'
                          ? AppRoutes.company
                          : role == 'admin' || role == 'administrator'
                          ? AppRoutes.adminSettings
                          : AppRoutes.profile,
                      closeDrawer: true,
                    ),
                  ),
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
            drawer: desktop ? null : Drawer(width: 256, child: navigation),
            drawerEnableOpenDragGesture: !navigationLocked,
            appBar: AppBar(
              toolbarHeight: 56,
              shape: const Border(
                bottom: BorderSide(color: JobMateTheme.divider),
              ),
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
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: actions,
            ),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (desktop) SizedBox(width: 240, child: navigation),
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
  const WorkspaceContent({super.key, required this.child, this.maxWidth = 672});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.symmetric(
      horizontal: MediaQuery.sizeOf(context).width >= 768 ? 24 : 16,
      vertical: MediaQuery.sizeOf(context).width >= 768 ? 32 : 24,
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
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
    this.leading,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AuthStyle.heading,
                  ),
                ),
              ),
            ],
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
      'verified' || 'active' || 'published' => AuthStyle.darkTeal,
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
    child: LayoutBuilder(
      builder: (context, box) {
        final heading = Text(
          label,
          style: const TextStyle(fontSize: 12, color: AuthStyle.body),
        );
        final content = SelectableText(
          value.isEmpty ? 'Not provided' : value,
          style: const TextStyle(
            color: AuthStyle.heading,
            fontWeight: FontWeight.w500,
            height: 1.5,
          ),
        );
        return box.maxWidth >= 500
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 160, child: heading),
                  Expanded(child: content),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 4), content],
              );
      },
    ),
  );
}
