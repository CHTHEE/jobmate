import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/loading_overlay.dart';
import '../profile/profile_page.dart';
import '../company/create_company_page.dart';
import '../admin/invite_admin_page.dart';
import '../admin/admin_permissions_page.dart';

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

  @override
  void initState() {
    super.initState();
    _checkAdminAccess(showMessage: false);
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isLoadingOut,
      message: 'Logging out...',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('JobMate'),
          actions: [
            IconButton(
              tooltip: 'My profile',
              icon: const Icon(Icons.person_outline),
              onPressed: _isLoadingOut
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => const ProfilePage(),
                        ),
                      );
                    },
            ),
            IconButton(
              tooltip: 'My company',
              icon: const Icon(Icons.business_outlined),
              onPressed: _isLoadingOut
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => const CreateCompanyPage(),
                        ),
                      );
                    },
            ),
            TextButton(
              onPressed: _isLoadingOut ? null : _handleLogout,
              child: const Text('Log out'),
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Welcome to JobMate!\n${widget.email}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
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
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isLoadingOut
                        ? null
                        : () async {
                            await Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (context) => const InviteAdminPage(),
                              ),
                            );

                            if (!mounted) return;

                            await _checkAdminAccess(showMessage: false);
                          },
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Invite administrator'),
                  ),
                  if (_canManageAdminPermissions) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _isLoadingOut
                          ? null
                          : () async {
                              await Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (context) =>
                                      const AdminPermissionsPage(),
                                ),
                              );

                              if (!mounted) return;

                              await _checkAdminAccess(showMessage: false);
                            },
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: const Text('Manage admin permissions'),
                    ),
                  ],
                ],
              ],
            ),
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
