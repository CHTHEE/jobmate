import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/loading_overlay.dart';
import '../../shared/navigation/app_routes.dart';

class HomePage extends StatefulWidget {
  final String email;

  const HomePage({super.key, required this.email});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoadingOut = false;
  bool _canInviteAdmins = false;
  bool _checkingAdminAccess = false;
  bool _canManageAdminPermissions = false;
  String _accountRole = '';
  bool _hasCompanyMembership = false;

  @override
  void initState() {
    super.initState();
    _checkAdminAccess(showMessage: false);
    _loadAccountRole();
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isLoadingOut,
      message: 'Logging out...',
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('JobMate'),
          actions: [
            IconButton(
              tooltip: 'Notifications',
              icon: const Icon(Icons.notifications_none_outlined),
              onPressed: _isLoadingOut
                  ? null
                  : () => context.push<void>(AppRoutes.notifications),
            ),
            IconButton(
              tooltip: 'My profile',
              icon: const Icon(Icons.person_outline),
              onPressed: _isLoadingOut
                  ? null
                  : () {
                      context.push<void>(AppRoutes.profile);
                    },
            ),
            if (_accountRole == 'employer')
              IconButton(
                tooltip: 'My company',
                icon: const Icon(Icons.business_outlined),
                onPressed: _isLoadingOut ? null : _openCompanyPage,
              ),
            TextButton(
              onPressed: _isLoadingOut ? null : _handleLogout,
              child: const Text('Log out'),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;

              return SingleChildScrollView(
                padding: EdgeInsets.all(compact ? 16 : 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Card.outlined(
                      child: Padding(
                        padding: EdgeInsets.all(compact ? 20 : 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Welcome to JobMate!',
                              style: Theme.of(context).textTheme.headlineMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(widget.email, textAlign: TextAlign.center),
                            const SizedBox(height: 24),
                            if (_accountRole == 'employer' &&
                                !_hasCompanyMembership) ...[
                              Card.outlined(
                                margin: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.business_outlined),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Next step: set up your Company',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Enter your Company details and submit '
                                        'a supporting document for administrator '
                                        'review. Your account will be its '
                                        'permanent Owner.',
                                      ),
                                      const SizedBox(height: 16),
                                      FilledButton.icon(
                                        onPressed: _isLoadingOut
                                            ? null
                                            : _openCompanyPage,
                                        icon: const Icon(
                                          Icons.business_center_outlined,
                                        ),
                                        label: const Text('Set up Company'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                            OutlinedButton(
                              onPressed: _isLoadingOut || _checkingAdminAccess
                                  ? null
                                  : () => _checkAdminAccess(),
                              child: Text(
                                _checkingAdminAccess
                                    ? 'Checking access...'
                                    : 'Check admin access',
                              ),
                            ),
                            if (_canInviteAdmins) ...[
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _isLoadingOut
                                    ? null
                                    : () async {
                                        await context.push<void>(
                                          AppRoutes.inviteAdmin,
                                        );

                                        if (!mounted) return;

                                        await _checkAdminAccess(
                                          showMessage: false,
                                        );
                                      },
                                icon: const Icon(
                                  Icons.person_add_alt_1_outlined,
                                ),
                                label: const Text('Invite administrator'),
                              ),
                              if (_canManageAdminPermissions) ...[
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _isLoadingOut
                                      ? null
                                      : () async {
                                          await context.push<void>(
                                            AppRoutes.adminPermissions,
                                          );

                                          if (!mounted) return;

                                          await _checkAdminAccess(
                                            showMessage: false,
                                          );
                                        },
                                  icon: const Icon(
                                    Icons.admin_panel_settings_outlined,
                                  ),
                                  label: const Text(
                                    'Manage admin permissions',
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _checkAdminAccess({bool showMessage = true}) async {
    if (_checkingAdminAccess) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;

    setState(() {
      _checkingAdminAccess = true;
      _canInviteAdmins = false;
      _canManageAdminPermissions = false;
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'admin-invitations',
        body: {'action': 'check_access'},
      );

      if (!mounted) return;

      if (Supabase.instance.client.auth.currentUser?.id != userId) {
        return;
      }

      final data = response.data;

      if (data is! Map ||
          data['canInviteAdmins'] is! bool ||
          data['canManageAdminPermissions'] is! bool) {
        throw const FormatException('Unexpected access response.');
      }

      setState(() {
        _canInviteAdmins = data['canInviteAdmins'] == true;
        _canManageAdminPermissions = data['canManageAdminPermissions'] == true;
      });

      if (showMessage) {
        _showMessage(data.toString());
      }
    } on FunctionException catch (error) {
      if (!mounted) return;

      final details = error.details;
      final message = details is Map
          ? (details['error'] ?? 'Unable to check access.').toString()
          : 'Request failed (${error.status}).';

      if (showMessage) {
        _showMessage(message);
      }
    } catch (_) {
      if (showMessage) {
        _showMessage('Unable to check administrator access.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _checkingAdminAccess = false;
        });
      }
    }
  }

  Future<void> _loadAccountRole() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) return;

    try {
      final client = Supabase.instance.client;
      final profile = await client
          .from('users')
          .select('role')
          .eq('user_id', userId)
          .single();

      if (!mounted || Supabase.instance.client.auth.currentUser?.id != userId) {
        return;
      }

      final role = profile['role'];

      if (role is! String) {
        throw const FormatException('Unexpected account role.');
      }

      var hasCompanyMembership = false;

      if (role == 'employer') {
        final membership = await client
            .from('company_memberships')
            .select('company_id')
            .eq('user_id', userId)
            .maybeSingle();

        if (!mounted || client.auth.currentUser?.id != userId) return;

        hasCompanyMembership = membership != null;
      }

      setState(() {
        _accountRole = role;
        _hasCompanyMembership = hasCompanyMembership;
      });
    } catch (error) {
      debugPrint('Account role load failed: $error');
    }
  }

  Future<void> _openCompanyPage() async {
    await context.push<void>(AppRoutes.company);

    if (!mounted) return;

    await _loadAccountRole();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleLogout() async {
    if (_isLoadingOut) return;

    setState(() {
      _isLoadingOut = true;
    });

    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to log out. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingOut = false;
        });
      }
    }
  }
}
