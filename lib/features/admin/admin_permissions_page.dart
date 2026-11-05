import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/navigation/app_routes.dart';
import '../../shared/navigation/workspace_destinations.dart';
import '../../shared/widgets/responsive_layout.dart';

class AdminPermissionsPage extends StatefulWidget {
  const AdminPermissionsPage({super.key});

  @override
  State<AdminPermissionsPage> createState() => _AdminPermissionsPageState();
}

class _AdminPermissionsPageState extends State<AdminPermissionsPage> {
  final _supabase = Supabase.instance.client;
  final _actorId = Supabase.instance.client.auth.currentUser?.id;

  static const _pageSize = 20;

  List<Map<String, dynamic>> _admins = [];

  bool _isLoading = false;
  bool _isUpdating = false;
  bool _hasMore = false;

  int _offset = 0;
  String? _errorMessage;

  bool get _isBusy => _isLoading || _isUpdating;

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  void _checkSession() {
    if (_actorId == null || _supabase.auth.currentUser?.id != _actorId) {
      throw StateError(
        'Your account has changed. Close this page and sign in again.',
      );
    }
  }

  Future<void> _loadAdmins() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _checkSession();

      final data = await _supabase.rpc(
        'list_admin_accounts_v2',
        params: {'p_limit': _pageSize + 1, 'p_offset': _offset},
      );

      if (!mounted) return;

      _checkSession();

      if (data is! List) {
        throw const FormatException('Unexpected administrator list.');
      }

      final rows = data
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      setState(() {
        _hasMore = rows.length > _pageSize;
        _admins = rows.take(_pageSize).toList();
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) return;

      debugPrint('Admin list loading failed: $error');

      setState(() {
        _errorMessage = error is StateError
            ? error.message.toString()
            : 'Unable to load administrators. Please retry.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _changePermission(
    Map<String, dynamic> admin,
    String permission,
    bool enabled,
  ) async {
    if (_isBusy) return;

    final name = admin['name'] as String? ?? 'this administrator';

    final isReviewPermission = permission == 'can_review_companies';
    final permissionName = isReviewPermission
        ? 'Company review permission'
        : 'Invitation permission';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${enabled ? 'Grant' : 'Revoke'} $permissionName?'),
        content: Text(
          enabled
              ? isReviewPermission
                    ? 'Allow $name to review Company documents?'
                    : 'Allow $name to send administrator invitations?'
              : isReviewPermission
              ? 'Remove $name\'s access to Company review documents?'
              : '$name will no longer be able to send invitations. '
                    'Their unaccepted invitations will be revoked.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
            child: Text(enabled ? 'Grant' : 'Revoke'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() {
      _isUpdating = true;
    });

    String message;

    try {
      _checkSession();

      await _supabase.rpc(
        'set_admin_permissions',
        params: {
          'p_target_user_id': admin['user_id'],
          'p_can_invite_admins': permission == 'can_invite_admins'
              ? enabled
              : admin['can_invite_admins'] == true,
          'p_can_review_companies': permission == 'can_review_companies'
              ? enabled
              : admin['can_review_companies'] == true,
        },
      );

      if (!mounted) return;

      _checkSession();

      message = isReviewPermission
          ? enabled
                ? 'Company review permission granted.'
                : 'Company review permission revoked.'
          : enabled
          ? 'Invitation permission granted.'
          : 'Invitation permission revoked. Unaccepted invitations were revoked.';
    } on PostgrestException catch (error) {
      message = error.message;
    } on StateError catch (error) {
      message = error.message.toString();
    } catch (_) {
      message =
          'Unable to confirm the update. Reloading the saved permissions.';
    } finally {
      // 不在本地猜测开关结果，重新读取 Database。
      if (mounted) {
        await _loadAdmins();

        if (mounted) {
          setState(() {
            _isUpdating = false;
          });
        }
      }
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _changePage(int difference) {
    if (_isBusy) return;

    final nextOffset = _offset + difference;

    if (nextOffset < 0) return;

    setState(() {
      _offset = nextOffset;
    });

    _loadAdmins();
  }

  Widget _buildAdminCard(Map<String, dynamic> admin) {
    final name = admin['name'] as String? ?? 'Unnamed administrator';
    final email = admin['email'] as String? ?? 'No email';
    final status = admin['account_status'] as String? ?? 'unknown';

    final canInvite = admin['can_invite_admins'] == true;
    final canReviewCompanies = admin['can_review_companies'] == true;
    final isManager = admin['can_manage_admin_permissions'] == true;
    final isCurrentAdmin = admin['user_id'] == _actorId;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            SelectableText(email),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(label: Text(status)),
                if (isManager) const Chip(label: Text('Superadmin')),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Invitation permission'),
              subtitle: Text(
                isCurrentAdmin
                    ? 'You cannot change your own administrator permissions.'
                    : 'Sending invitations also requires an active account.',
              ),
              value: canInvite,
              onChanged: _isBusy || isCurrentAdmin
                  ? null
                  : (value) =>
                        _changePermission(admin, 'can_invite_admins', value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Company review permission'),
              subtitle: const Text(
                'Allows reviewing submitted Company documents.',
              ),
              value: canReviewCompanies,
              onChanged: _isBusy || isCurrentAdmin
                  ? null
                  : (value) =>
                        _changePermission(admin, 'can_review_companies', value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isBusy ? null : _loadAdmins,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return ResponsiveContent(
      maxWidth: 840,
      child: ListView(
        padding: ResponsiveLayout.pagePadding(context),
        children: [
          const Text(
            'Administrator permissions',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'The Superadmin assigns invitation and Company review access. '
            'Administrators cannot change their own permissions.',
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isBusy ? null : _loadAdmins,
              child: const Text('Check for updates'),
            ),
          ),
          const SizedBox(height: 24),
          if (_admins.isEmpty) const Text('No administrators on this page.'),
          for (final admin in _admins) _buildAdminCard(admin),
          const SizedBox(height: 8),
          ResponsivePagination(
            page: _offset ~/ _pageSize + 1,
            onPrevious: _isBusy || _offset == 0
                ? null
                : () => _changePage(-_pageSize),
            onNext: _isBusy || !_hasMore ? null : () => _changePage(_pageSize),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isUpdating,
      message: 'Updating invitation permission...',
      child: AppWorkspace(
        title: 'Admin permissions',
        path: AppRoutes.adminPermissions,
        role: 'administrator',
        navigationLocked: _isBusy,
        navigationGroups: {
          ...workspaceDestinations('administrator'),
          'ADMIN TOOLS': [
            (
              AppRoutes.adminPermissions,
              'Admin permissions',
              Icons.admin_panel_settings_outlined,
            ),
          ],
        },
        child: _buildBody(context),
      ),
    );
  }
}
