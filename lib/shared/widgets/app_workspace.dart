import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../navigation/app_routes.dart';
import 'auth_style.dart';

const upcomingModules = <(String, IconData)>[
  ('Job Posting', Icons.work_outline),
  ('Applications', Icons.assignment_outlined),
  ('AI Recommendations', Icons.auto_awesome_outlined),
  ('Attendance', Icons.event_available_outlined),
  ('Chat', Icons.chat_bubble_outline),
  ('Location Discovery', Icons.map_outlined),
];

/// A presentation shell around existing GoRouter pages; no auth or data writes.
class AppWorkspace extends StatelessWidget {
  const AppWorkspace({
    super.key,
    required this.title,
    required this.path,
    required this.role,
    required this.child,
    this.actions = const [],
    this.onNavigate,
    this.navigationLocked = false,
  });
  final String title;
  final String path;
  final String role;
  final Widget child;
  final List<Widget> actions;
  final ValueChanged<String>? onNavigate;
  final bool navigationLocked;

  @override
  Widget build(BuildContext context) {
    final base = AuthStyle.theme(context);
    return Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: AuthStyle.background,
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: AuthStyle.heading,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 1024;
          void navigate(String destination) {
            if (navigationLocked) return;
            if (!desktop) Navigator.of(context).pop();
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
                        onTap: () => navigate(item.$1),
                      ),
                    ),
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
                  for (final module in upcomingModules)
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
              ),
            ),
          );
          return Scaffold(
            drawer: desktop ? null : Drawer(child: navigation),
            drawerEnableOpenDragGesture: !navigationLocked,
            appBar: AppBar(
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
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 32),
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
