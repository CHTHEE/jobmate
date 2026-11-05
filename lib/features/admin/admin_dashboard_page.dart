import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/navigation/workspace_destinations.dart';
import '../phase4/phase4_store.dart';
import '../notifications/notifications_page.dart';
import '../../shared/widgets/responsive_layout.dart';

enum _AdminProfileAction { profile, settings, refresh, signOut }

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key, required this.email});

  final String email;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  bool _loadingAccess = true;
  bool _canInviteAdmins = false;
  bool _canManageAdminPermissions = false;
  bool _canReviewCompanies = false;
  int? _registeredUsers;
  int? _pendingCompanyReviews;
  int? _administratorAccounts;
  String _adminName = 'Administrator';
  String? _avatarUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAccess();
    _loadAdminProfile();
  }

  Future<void> _openCompanyReviews() async {
    if (_loadingAccess || !_canReviewCompanies) return;
    await context.push<void>(AppRoutes.companyReviews);
    if (mounted) await _loadAccess();
  }

  Future<void> _loadAdminProfile() async {
    final client = Supabase.instance.client;
    final actorId = client.auth.currentUser?.id;
    if (actorId == null) return;

    try {
      final profile = await client
          .from('users')
          .select('name, profile_image_url')
          .eq('user_id', actorId)
          .maybeSingle();
      if (!mounted ||
          client.auth.currentUser?.id != actorId ||
          profile == null) {
        return;
      }

      final name = profile['name'] as String?;
      setState(() {
        if (name != null && name.trim().isNotEmpty) {
          _adminName = name.trim();
        }
        _avatarUrl = profile['profile_image_url'] as String?;
      });
    } catch (error) {
      debugPrint('Admin profile header load failed: $error');
      // Keep the fallback name and initials if profile data cannot be loaded.
    }
  }

  Future<void> _loadAccess() async {
    final actorId = Supabase.instance.client.auth.currentUser?.id;
    if (actorId == null) {
      setState(() {
        _loadingAccess = false;
        _canInviteAdmins = false;
        _canManageAdminPermissions = false;
        _canReviewCompanies = false;
        _error = 'Sign in again to view administrator tools.';
      });
      return;
    }
    var checkingDatabase = false;

    setState(() {
      _loadingAccess = true;
      _canInviteAdmins = false;
      _canManageAdminPermissions = false;
      _canReviewCompanies = false;
      _error = null;
    });

    try {
      final result = await Supabase.instance.client.functions.invoke(
        'admin-invitations',
        body: {'action': 'check_access'},
      );

      if (!mounted ||
          Supabase.instance.client.auth.currentUser?.id != actorId) {
        return;
      }

      final data = result.data;
      if (data is! Map ||
          data['canInviteAdmins'] is! bool ||
          data['canManageAdminPermissions'] is! bool) {
        throw const FormatException('Unexpected administrator access data.');
      }

      checkingDatabase = true;
      final client = Supabase.instance.client;
      final ownPermissions = await client
          .from('administrator_profiles')
          .select('can_review_companies')
          .eq('user_id', actorId)
          .single();
      final summaryData = await client.rpc('get_admin_dashboard_summary');

      if (!mounted || client.auth.currentUser?.id != actorId) return;
      if (summaryData is! List ||
          summaryData.isEmpty ||
          summaryData.first is! Map) {
        throw const FormatException('Unexpected dashboard summary data.');
      }
      final summary = Map<String, dynamic>.from(summaryData.first as Map);

      setState(() {
        _canInviteAdmins = data['canInviteAdmins'] == true;
        _canManageAdminPermissions = data['canManageAdminPermissions'] == true;
        _canReviewCompanies = ownPermissions['can_review_companies'] == true;
        _registeredUsers = _intValue(summary['registered_users']);
        _pendingCompanyReviews = _intValue(summary['pending_company_reviews']);
        _administratorAccounts = _intValue(summary['administrator_accounts']);
      });
    } catch (error) {
      debugPrint('Admin dashboard access check failed: $error');
      if (!mounted) return;
      setState(() {
        _error = checkingDatabase
            ? 'Platform information is temporarily unavailable. Retry, or '
                  'contact the system owner if the problem continues.'
            : 'Unable to verify administrator access. Retry, or sign in again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingAccess = false;
        });
      }
    }
  }

  int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Widget _buildAdminAvatar() {
    final url = _avatarUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Text(_initials),
        ),
      );
    }
    return Text(
      _initials,
      style: const TextStyle(
        color: Color(0xFF0F766E),
        fontWeight: FontWeight.bold,
      ),
    );
  }

  String get _initials {
    final parts = _adminName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'A';
    if (parts.length == 1) {
      final name = parts.first;
      return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    } catch (error) {
      debugPrint('Admin sign out failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to sign out. Please retry.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrowPhone = MediaQuery.sizeOf(context).width < 420;
    final groups = workspaceDestinations('administrator');
    if (!_loadingAccess && _error == null) {
      groups['ADMIN TOOLS'] = [
        if (_canReviewCompanies)
          (
            AppRoutes.companyReviews,
            'Company Verification',
            Icons.business_outlined,
          ),
        if (_canInviteAdmins)
          (
            AppRoutes.inviteAdmin,
            'Invite administrator',
            Icons.person_add_alt_1_outlined,
          ),
        if (_canManageAdminPermissions)
          (
            AppRoutes.adminPermissions,
            'Admin permissions',
            Icons.admin_panel_settings_outlined,
          ),
      ];
    }
    return AppWorkspace(
      title: narrowPhone ? 'Admin' : 'JobMate Admin',
      path: AppRoutes.home,
      role: 'administrator',
      showAccountMenu: false,
      navigationGroups: groups,
      actions: [
        IconButton(
          tooltip: 'Notifications',
          onPressed: () => kIsWeb
              ? showNotificationsPanel(context)
              : context.push<void>(AppRoutes.notifications),
          icon: const Icon(Icons.notifications_none_outlined),
        ),
        PopupMenuButton<_AdminProfileAction>(
          tooltip: 'Admin profile and account actions',
          onSelected: (action) {
            if (action == _AdminProfileAction.profile) {
              context.push<void>(AppRoutes.profile);
            } else if (action == _AdminProfileAction.settings) {
              context.push<void>(AppRoutes.adminSettings);
            } else if (action == _AdminProfileAction.refresh) {
              _loadAccess();
            } else {
              _signOut();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _AdminProfileAction.profile,
              child: Row(
                children: [
                  Icon(Icons.person_outline),
                  SizedBox(width: 12),
                  Text('My profile'),
                ],
              ),
            ),
            PopupMenuItem(
              value: _AdminProfileAction.settings,
              child: Row(
                children: [
                  Icon(Icons.settings_outlined),
                  SizedBox(width: 12),
                  Text('Account settings'),
                ],
              ),
            ),
            PopupMenuItem(
              value: _AdminProfileAction.refresh,
              child: Text('Refresh dashboard'),
            ),
            PopupMenuItem(
              value: _AdminProfileAction.signOut,
              child: Row(
                children: [
                  Icon(Icons.logout),
                  SizedBox(width: 12),
                  Text('Sign out'),
                ],
              ),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFCCFBF1),
                  child: _buildAdminAvatar(),
                ),
                if (ResponsiveLayout.usesSidebar(
                      MediaQuery.sizeOf(context).width,
                    ) &&
                    MediaQuery.textScalerOf(context).scale(14) <= 18) ...[
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admin - $_adminName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        const Text(
                          'System Administrator',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            height: 1.2,
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
        ),
        const SizedBox(width: 8),
      ],
      child: WorkspaceContent(
        maxWidth: 1280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeading(
              title: 'Platform overview',
              description: 'Manage accounts, review companies and keep JobMate running smoothly.',
              eyebrow: 'Administration',
            ),
            if (_error != null) _buildError(context),
            _buildOverview(context),
            const SizedBox(height: 24),
            if (!_loadingAccess && _error == null)
              BrandPanel(
                title: 'A clear view of your platform',
                description: 'Real user and company metrics appear above. Job moderation, disputes and reports below remain a separate demo workspace.',
                icon: Icons.admin_panel_settings_outlined,
              ),
            const SizedBox(height: 20),
            if (!_loadingAccess && _error == null)
              ListenableBuilder(
                listenable: Phase4Store.session,
                builder: (context, _) => StatGrid(
                  children: [
                    StatTile(
                      label: 'Job moderation',
                      value: '${Phase4Store.session.jobs.length}',
                      icon: Icons.work_outline,
                      note: 'DEMO posts',
                    ),
                    StatTile(
                      label: 'Open disputes',
                      value:
                          '${Phase4Store.session.disputes.where((d) => !d.state.terminal).length}',
                      icon: Icons.gavel_outlined,
                      note: 'DEMO cases',
                    ),
                    StatTile(
                      label: 'Review history',
                      value: '${Phase4Store.session.audit.length}',
                      icon: Icons.history,
                      note: 'DEMO local actions',
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 28),
            Text('Admin tools', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _buildTools(context),
          ],
        ),
      ),
    );
  }

  Widget _buildOverview(BuildContext context) {
    final cards = [
      _OverviewItem(
        title: 'Registered users',
        value: _registeredUsers?.toString() ?? (_loadingAccess ? '...' : '--'),
        detail: 'Job Seekers and Employers',
        icon: Icons.people_outline,
        accent: const Color(0xFF0F766E),
      ),
      _OverviewItem(
        title: 'Company reviews',
        value:
            _pendingCompanyReviews?.toString() ??
            (_loadingAccess ? '...' : '--'),
        detail: 'Documents waiting for review',
        icon: Icons.business_outlined,
        accent: const Color(0xFFD97706),
      ),
      _OverviewItem(
        title: 'Admin accounts',
        value:
            _administratorAccounts?.toString() ??
            (_loadingAccess ? '...' : '--'),
        detail: 'Administrator accounts',
        icon: Icons.admin_panel_settings_outlined,
        accent: const Color(0xFF2563EB),
      ),
    ];

    return ResponsiveGrid(
      minItemWidth: 240,
      children: [
        for (final item in cards)
          _OverviewCard(item: item, loading: _loadingAccess),
      ],
    );
  }

  Widget _buildTools(BuildContext context) {
    final actions = <Widget>[];
    if (!_loadingAccess && _error == null) {
      actions.add(
        _ToolCard(
          icon: Icons.dashboard_customize_outlined,
          title: 'UI Sandbox (demo)',
          description: 'Preview missing account actions, job moderation, disputes and reports using fictional session data only.',
          onTap: () => context.push<void>(AppRoutes.adminPreview),
        ),
      );
      actions.add(
        _ToolCard(
          icon: Icons.settings_outlined,
          title: 'Account Settings',
          description: 'Existing account/security links and clearly separated settings presentation.',
          onTap: () => context.push<void>(AppRoutes.adminSettings),
        ),
      );
    }
    if (_canInviteAdmins) {
      actions.add(
        _ToolCard(
          icon: Icons.person_add_alt_1_outlined,
          title: 'Invite administrator',
          description: 'Invite an unregistered person to join the admin team.',
          onTap: () => context.push<void>(AppRoutes.inviteAdmin),
        ),
      );
    }
    actions.add(
      _ToolCard(
        icon: Icons.people_outline,
        title: 'View users',
        description: 'Browse and filter Job Seeker and Employer accounts.',
        onTap: () => context.push<void>(AppRoutes.adminUsers),
      ),
    );
    if (_canReviewCompanies) {
      actions.add(
        _ToolCard(
          icon: Icons.business_outlined,
          title: 'Company Verification',
          description: 'Review Company documents and proposed logo changes.',
          onTap: _openCompanyReviews,
        ),
      );
    }
    if (_canManageAdminPermissions) {
      actions.add(
        _ToolCard(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Manage administrator permissions',
          description:
              'Control who can invite administrators and review Companies.',
          onTap: () => context.push<void>(AppRoutes.adminPermissions),
        ),
      );
    }

    if (_loadingAccess) {
      return const Center(child: CircularProgressIndicator());
    }
    if (actions.isEmpty) {
      return const Card.outlined(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text(
            'Your account has no additional admin tools assigned. '
            'Contact the Superadmin if you need access.',
          ),
        ),
      );
    }

    return ResponsiveGrid(minItemWidth: 360, maxColumns: 2, children: actions);
  }

  Widget _buildError(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: const Color(0xFFFFF7ED),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFFB45309)),
              const SizedBox(width: 12),
              Expanded(child: Text(_error!)),
              TextButton(onPressed: _loadAccess, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewItem {
  const _OverviewItem({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String value;
  final String detail;
  final IconData icon;
  final Color accent;
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.item, required this.loading});

  final _OverviewItem item;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: item.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(item.icon, color: item.accent),
            ),
            const SizedBox(height: 16),
            Text(item.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              loading ? '...' : item.value,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: item.accent, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(item.detail),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(
                icon,
                size: 30,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(description),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
