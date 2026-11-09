import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

import '../navigation/app_routes.dart';
import '../theme/jobmate_theme.dart';
import 'responsive_layout.dart';

enum _AccountAction { profile, reputation, settings, signOut }

/// Account entry point on workspace pages, including direct URLs.
class WorkspaceAccountMenu extends StatefulWidget {
  const WorkspaceAccountMenu({
    super.key,
    required this.role,
    required this.onNavigate,
    this.name,
    this.avatarUrl,
    this.onSignOut,
    this.locked = false,
  });

  final String role;
  final ValueChanged<String> onNavigate;
  final String? name;
  final String? avatarUrl;
  final Future<void> Function()? onSignOut;
  final bool locked;

  @override
  State<WorkspaceAccountMenu> createState() => _WorkspaceAccountMenuState();
}

class _WorkspaceAccountMenuState extends State<WorkspaceAccountMenu> {
  String? _loadedName;
  String? _loadedAvatarUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    // Dashboard supplies its already loaded profile; other pages read only the
    // two fields needed for the header. Widget previews may have no Supabase.
    if (widget.name?.trim().isNotEmpty == true) return;
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      final profile = await client
          .from('users')
          .select('name, profile_image_url')
          .eq('user_id', userId)
          .maybeSingle();
      if (!mounted || client.auth.currentUser?.id != userId) return;
      setState(() {
        _loadedName = profile?['name'] as String?;
        _loadedAvatarUrl = profile?['profile_image_url'] as String?;
      });
    } catch (_) {
      // The account menu still provides navigation and sign-out if this
      // optional header read fails.
    }
  }

  Future<void> _signOut() async {
    // Capture the root router before auth listeners dispose this nested page.
    // Do not call its page-specific navigation callback, which may push Home
    // onto the still-protected detail stack instead of replacing that stack.
    final router = GoRouter.maybeOf(context);
    try {
      if (widget.onSignOut != null) {
        await widget.onSignOut!();
      } else {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      }
      router?.go(AppRoutes.home);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to sign out. Please retry.')),
      );
    }
  }

  String get _name {
    final value = widget.name?.trim();
    return value != null && value.isNotEmpty
        ? value
        : (_loadedName?.trim().isNotEmpty == true
              ? _loadedName!.trim()
              : 'Your account');
  }

  String get _initials {
    if (_name == 'Your account') return 'U';
    final parts = _name.split(RegExp(r'\s+'));
    return parts.length > 1
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : parts.first
              .substring(0, parts.first.length.clamp(1, 2))
              .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = widget.avatarUrl ?? _loadedAvatarUrl;
    final showLabel =
        ResponsiveLayout.usesSidebar(MediaQuery.sizeOf(context).width) &&
        MediaQuery.textScalerOf(context).scale(14) <= 18;
    return PopupMenuButton<_AccountAction>(
      key: const ValueKey('workspace-account-menu'),
      tooltip: 'Account menu',
      enabled: !widget.locked,
      onSelected: (action) {
        switch (action) {
          case _AccountAction.profile:
            widget.onNavigate(AppRoutes.profile);
          case _AccountAction.reputation:
            widget.onNavigate(
              widget.role == 'employer'
                  ? AppRoutes.employerReputation
                  : AppRoutes.reputation,
            );
          case _AccountAction.settings:
            widget.onNavigate(
              widget.role == 'employer'
                  ? AppRoutes.employerSettings
                  : widget.role == 'administrator' || widget.role == 'admin'
                  ? AppRoutes.adminSettings
                  : AppRoutes.settings,
            );
          case _AccountAction.signOut:
            _signOut();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _AccountAction.profile,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline),
              SizedBox(width: 12),
              Flexible(child: Text('My profile')),
            ],
          ),
        ),
        if (widget.role == 'employer') ...[
          const PopupMenuItem(
            value: _AccountAction.reputation,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stars_outlined),
                SizedBox(width: 12),
                Flexible(child: Text('Company Reputation')),
              ],
            ),
          ),
        ],
        const PopupMenuItem(
          value: _AccountAction.settings,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.settings_outlined),
              SizedBox(width: 12),
              Flexible(child: Text('Account settings')),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _AccountAction.signOut,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout),
              SizedBox(width: 12),
              Flexible(child: Text('Sign out')),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: JobMateTheme.teal100,
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        avatarUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Text(_initials),
                      ),
                    )
                  : Text(_initials),
            ),
            if (showLabel) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      widget.role == 'employer'
                          ? 'Employer'
                          : widget.role == 'administrator' ||
                                widget.role == 'admin'
                          ? 'Administrator'
                          : 'Job Seeker',
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 12,
                        color: JobMateTheme.body,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 20),
          ],
        ),
      ),
    );
  }
}
