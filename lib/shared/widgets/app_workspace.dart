import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:supabase_flutter/supabase_flutter.dart';

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
        final moreGroups = <String, List<WorkspaceDestination>>{};
        for (final group in groups.entries) {
          final visible = group.value
              .where(
                (item) =>
                    item.$1 != AppRoutes.home &&
                    item.$1 != AppRoutes.search &&
                    item.$1 != AppRoutes.browseJobs,
              )
              .toList();
          if (visible.isNotEmpty) moreGroups[group.key] = visible;
        }
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

        Widget navigation(
          BuildContext menuContext, {
          bool overlay = false,
          Widget? accountActions,
          bool moreSheet = false,
        }) => _WorkspaceMenu(
          groups: moreSheet ? moreGroups : groups,
          selected: selected,
          locked: navigationLocked,
          accountActions: accountActions,
          showBrand: !moreSheet,
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

        Future<void> signOut() async {
          try {
            if (onSignOut != null) {
              await onSignOut!();
            } else {
              await Supabase.instance.client.auth.signOut(
                scope: SignOutScope.local,
              );
            }
          } catch (_) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unable to sign out. Please retry.'),
              ),
            );
          }
        }

        final settingsPath = switch (role) {
          'employer' => AppRoutes.employerSettings,
          'administrator' || 'admin' => AppRoutes.adminSettings,
          _ => AppRoutes.settings,
        };

        Future<void> account() async {
          if (navigationLocked) return;
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            constraints: const BoxConstraints(maxWidth: 640),
            builder: (sheetContext) => ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * .8,
              ),
              child: SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: _MobileAccountAvatar(
                        name: accountName,
                        avatarUrl: accountAvatarUrl,
                      ),
                      title: Text(
                        accountName?.trim().isNotEmpty == true
                            ? accountName!.trim()
                            : 'Your account',
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('My profile'),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        navigate(AppRoutes.profile);
                      },
                    ),
                    if (role == 'employer')
                      ListTile(
                        leading: const Icon(Icons.stars_outlined),
                        title: const Text('Reputation (demo)'),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          navigate(AppRoutes.employerReputation);
                        },
                      ),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: const Text('Account settings'),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        navigate(settingsPath);
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          );
        }

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
              child: navigation(
                sheetContext,
                overlay: true,
                moreSheet: true,
                accountActions: showAccountMenu
                    ? Column(
                        children: [
                          const Divider(),
                          ListTile(
                            leading: const Icon(Icons.logout),
                            title: const Text('Sign out'),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              signOut();
                            },
                          ),
                        ],
                      )
                    : null,
              ),
            ),
          );
        }

        final primaryIndex = primary.indexWhere((item) => item.$1 == selected);
        final jobsIndex = primary.indexWhere(
          (item) => item.$1 == AppRoutes.browseJobs,
        );
        final accountSelected =
            selected == AppRoutes.profile ||
            selected == settingsPath ||
            (role == 'employer' && selected == AppRoutes.employerReputation);
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
                  selectedIndex: primaryIndex >= 0
                      ? primaryIndex
                      : selected == AppRoutes.search && jobsIndex >= 0
                      ? jobsIndex
                      : showAccountMenu && accountSelected
                      ? primary.length
                      : primary.length + (showAccountMenu ? 1 : 0),
                  onDestinationSelected: navigationLocked
                      ? null
                      : (index) {
                          if (showAccountMenu && index == primary.length) {
                            account();
                          } else if (index ==
                              primary.length + (showAccountMenu ? 1 : 0)) {
                            more();
                          } else {
                            navigate(primary[index].$1);
                          }
                        },
                  destinations: [
                    for (final item in primary)
                      NavigationDestination(
                        icon: Icon(
                          item.$1 == AppRoutes.browseJobs
                              ? Icons.work_outline
                              : item.$3,
                        ),
                        label: _primaryLabel(item.$1),
                      ),
                    if (showAccountMenu)
                      NavigationDestination(
                        icon: _MobileAccountAvatar(
                          name: accountName,
                          avatarUrl: accountAvatarUrl,
                        ),
                        label: 'Account',
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
              if (!showBottomBar &&
                  showAccountMenu &&
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
  AppRoutes.search => 'Jobs',
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
    this.accountActions,
    this.showBrand = true,
  });
  final Map<String, List<WorkspaceDestination>> groups;
  final String? selected;
  final bool locked;
  final ValueChanged<String> onSelected;
  final Widget? accountActions;
  final bool showBrand;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      child: ListView(
        key: const ValueKey('workspace-navigation'),
        scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
        children: [
          if (showBrand)
            Padding(
              padding: const EdgeInsets.all(12),
              child: InkWell(
                onTap: locked ? null : () => onSelected(AppRoutes.home),
                borderRadius: BorderRadius.circular(8),
                child: const Tooltip(
                  message: 'Go to dashboard',
                  child: AuthWordmark(compact: true),
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 20),
              child: Text(
                'More',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
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
          ?accountActions,
        ],
      ),
    ),
  );
}

class _MobileAccountAvatar extends StatefulWidget {
  const _MobileAccountAvatar({this.name, this.avatarUrl});
  final String? name;
  final String? avatarUrl;

  @override
  State<_MobileAccountAvatar> createState() => _MobileAccountAvatarState();
}

class _MobileAccountAvatarState extends State<_MobileAccountAvatar> {
  String? _name;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    if (widget.avatarUrl == null) _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      final row = await client
          .from('users')
          .select('name, profile_image_url')
          .eq('user_id', userId)
          .maybeSingle();
      if (!mounted || client.auth.currentUser?.id != userId) return;
      setState(() {
        _name = row?['name'] as String?;
        _avatarUrl = row?['profile_image_url'] as String?;
      });
    } catch (_) {
      // Navigation remains available if the optional photo cannot load.
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.name ?? _name ?? '').trim();
    final avatarUrl = widget.avatarUrl ?? _avatarUrl;
    return CircleAvatar(
      radius: 14,
      backgroundColor: JobMateTheme.teal100,
      child: avatarUrl == null || avatarUrl.isEmpty
          ? Text(name.isEmpty ? 'U' : name[0].toUpperCase())
          : ClipOval(
              child: Image.network(
                avatarUrl,
                width: 28,
                height: 28,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Text(name.isEmpty ? 'U' : name[0].toUpperCase()),
              ),
            ),
    );
  }
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
