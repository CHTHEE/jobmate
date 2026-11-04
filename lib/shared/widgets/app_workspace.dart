import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../navigation/app_routes.dart';
import 'auth_style.dart';
import '../theme/jobmate_theme.dart';
import '../navigation/workspace_destinations.dart';
import 'responsive_layout.dart';
import 'mobile_back_action.dart';
import 'workspace_account_menu.dart';

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
    this.focused = false,
    this.navigationGroups,
    this.accountName,
    this.accountAvatarUrl,
    this.onSignOut,
    this.showAccountMenu = true,
  });
  final String title;
  final String path;
  final String role;
  final Widget child;
  final List<Widget> actions;
  final Widget? leading;
  final ValueChanged<String>? onNavigate;
  final bool navigationLocked;

  /// Details and focused forms retain native Back instead of primary tabs.
  final bool focused;
  final Map<String, List<WorkspaceDestination>>? navigationGroups;
  final String? accountName;
  final String? accountAvatarUrl;
  final Future<void> Function()? onSignOut;
  final bool showAccountMenu;

  @override
  Widget build(BuildContext context) => Theme(
    data: JobMateTheme.apply(Theme.of(context)),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Platform chooses the navigation family; constraints choose its size.
        final sidebar =
            kIsWeb && ResponsiveLayout.usesSidebar(constraints.maxWidth);
        final groups = navigationGroups ?? workspaceDestinations(role);
        final all = groups.values.expand((items) => items).toList();
        final selected = selectedWorkspacePath(path, all);
        final primary = workspacePrimaryDestinations(role)
            .where((item) => all.any((entry) => entry.$1 == item.$1))
            .toList();
        final detail = focused || leading != null;
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        // Keep short landscape forms usable while the software keyboard is up.
        final showBottomBar =
            !kIsWeb && !detail && !keyboardOpen && primary.isNotEmpty;

        void navigate(String destination) {
          if (navigationLocked || destination == path) return;
          if (onNavigate != null) {
            onNavigate!(destination);
          } else {
            openWorkspaceDestination(context, destination);
          }
        }

        Widget navigation(BuildContext menuContext, {bool overlay = false}) =>
            _WorkspaceMenu(
              groups: groups,
              selected: selected,
              locked: navigationLocked,
              onSelected: (destination) {
                if (navigationLocked) return;
                if (overlay) {
                  if (kIsWeb) {
                    Scaffold.of(menuContext).closeDrawer();
                  } else {
                    Navigator.of(menuContext).pop();
                  }
                }
                navigate(destination);
              },
            );

        Future<void> more() async {
          if (navigationLocked) return;
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            constraints: const BoxConstraints(maxWidth: 640),
            builder: (sheetContext) => SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .8,
              child: navigation(sheetContext, overlay: true),
            ),
          );
        }

        final primaryIndex = primary.indexWhere((item) => item.$1 == selected);
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        return Scaffold(
          drawer: kIsWeb && !sidebar
              ? Drawer(
                  width: constraints.maxWidth < 360 ? 280 : 288,
                  child: Builder(
                    builder: (drawerContext) =>
                        navigation(drawerContext, overlay: true),
                  ),
                )
              : null,
          drawerEnableOpenDragGesture: !navigationLocked,
          bottomNavigationBar: showBottomBar
              ? NavigationBar(
                  key: const ValueKey('workspace-bottom-navigation'),
                  height: 80 + 32 * (textScale - 1).clamp(0.0, 2.0),
                  selectedIndex: primaryIndex < 0
                      ? primary.length
                      : primaryIndex,
                  onDestinationSelected: navigationLocked
                      ? null
                      : (index) {
                          if (index == primary.length) {
                            more();
                          } else {
                            navigate(primary[index].$1);
                          }
                        },
                  destinations: [
                    for (final item in primary)
                      NavigationDestination(
                        icon: Icon(item.$3),
                        label: _primaryLabel(item.$1),
                      ),
                    const NavigationDestination(
                      icon: Icon(Icons.more_horiz),
                      label: 'More',
                    ),
                  ],
                )
              : null,
          appBar: AppBar(
            toolbarHeight: 56,
            shape: const Border(
              bottom: BorderSide(color: JobMateTheme.divider),
            ),
            automaticallyImplyLeading: false,
            leading: kIsWeb
                ? (sidebar
                      ? null
                      : Builder(
                          builder: (scaffoldContext) => IconButton(
                            tooltip: 'Open navigation menu',
                            onPressed: navigationLocked
                                ? null
                                : () =>
                                      Scaffold.of(scaffoldContext).openDrawer(),
                            icon: const Icon(Icons.menu),
                          ),
                        ))
                : (leading ??
                      (detail
                          ? IconButton(
                              tooltip: 'Back',
                              onPressed: navigationLocked
                                  ? null
                                  : () => returnToPage(context, AppRoutes.home),
                              icon: const Icon(Icons.arrow_back),
                            )
                          : null)),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            actions: [
              ...actions,
              if (showAccountMenu &&
                  (role == 'job_seeker' ||
                      role == 'employer' ||
                      role == 'administrator' ||
                      role == 'admin'))
                WorkspaceAccountMenu(
                  role: role,
                  name: accountName,
                  avatarUrl: accountAvatarUrl,
                  locked: navigationLocked,
                  onNavigate: navigate,
                  onSignOut: onSignOut,
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sidebar)
                SizedBox(
                  key: const ValueKey('workspace-sidebar'),
                  width: JobMateTheme.sidebarWidth,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(
                        right: BorderSide(color: JobMateTheme.divider),
                      ),
                    ),
                    child: navigation(context),
                  ),
                ),
              Expanded(child: SafeArea(child: child)),
            ],
          ),
        );
      },
    ),
  );
}

String _primaryLabel(String path) => switch (path) {
  AppRoutes.home => 'Home',
  AppRoutes.browseJobs => 'Jobs',
  AppRoutes.jobPostings => 'Posts',
  AppRoutes.applications || AppRoutes.applicants => 'Applications',
  AppRoutes.adminUsers => 'Users',
  AppRoutes.adminPayments => 'Payments',
  _ => 'Profile',
};

/// One grouped menu shared by wide Web, narrow Web and the native More sheet.
class _WorkspaceMenu extends StatelessWidget {
  const _WorkspaceMenu({
    required this.groups,
    required this.selected,
    required this.locked,
    required this.onSelected,
  });
  final Map<String, List<WorkspaceDestination>> groups;
  final String? selected;
  final bool locked;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      child: ListView(
        key: const ValueKey('workspace-navigation'),
        scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: AuthWordmark(compact: true),
          ),
          if (locked)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Finish or cancel your current changes before navigating.',
              ),
            ),
          for (final group in groups.values)
            for (final item in group)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  minTileHeight: 48,
                  selected: selected == item.$1,
                  selectedTileColor: JobMateTheme.teal50,
                  selectedColor: JobMateTheme.darkTeal,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  minLeadingWidth: 24,
                  leading: Icon(item.$3, size: 20),
                  title: Text(item.$2),
                  enabled: !locked,
                  onTap: () => onSelected(item.$1),
                ),
              ),
        ],
      ),
    ),
  );
}

class WorkspaceContent extends StatelessWidget {
  const WorkspaceContent({super.key, required this.child, this.maxWidth = 672});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: ResponsiveLayout.pagePaddingForWidth(constraints.maxWidth),
      child: ResponsiveContent(maxWidth: maxWidth, child: child),
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
      padding: const EdgeInsets.all(JobMateTheme.space16),
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
