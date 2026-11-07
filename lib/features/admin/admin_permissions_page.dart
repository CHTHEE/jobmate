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
  bool _userManagementAvailable = false;
  bool _disputeManagementAvailable = false;
  bool _companyRestrictionAvailable = false;
  bool _userReportsAvailable = false;
  bool _jobModerationAvailable = false;

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

      dynamic data;
      var schemaVersion = 0;
      const versions = [
        'list_admin_accounts_v8',
        'list_admin_accounts_v7',
        'list_admin_accounts_v6',
        'list_admin_accounts_v5',
        'list_admin_accounts_v4',
        'list_admin_accounts_v3',
        'list_admin_accounts_v2',
      ];
      for (var index = 0; index < versions.length; index++) {
        try {
          data = await _supabase.rpc(
            versions[index],
            params: {'p_limit': _pageSize + 1, 'p_offset': _offset},
          );
          schemaVersion = 8 - index;
          break;
        } on PostgrestException catch (error) {
          if (error.code != 'PGRST202' || index == versions.length - 1) {
            rethrow;
          }
        }
      }
      final userManagementAvailable = schemaVersion >= 3;
      var disputeManagementAvailable = false;
      var companyRestrictionAvailable = schemaVersion >= 5;
      var userReportsAvailable = schemaVersion == 6;
      var jobModerationAvailable = schemaVersion >= 7;

      if (!mounted) return;

      _checkSession();

      if (data is! List) {
        throw const FormatException('Unexpected administrator list.');
      }

      final rows = data
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (rows.any((row) => row.containsKey('dispute_management_available'))) {
        disputeManagementAvailable = rows.any(
          (row) => row['dispute_management_available'] == true,
        );
      } else if (rows.any((row) => row.containsKey('can_manage_disputes'))) {
        disputeManagementAvailable = rows.any(
          (row) => row['can_manage_disputes'] is bool,
        );
      }
      if (rows.any((row) => row.containsKey('user_reports_available'))) {
        userReportsAvailable = rows.any(
          (row) => row['user_reports_available'] == true,
        );
      } else if (schemaVersion >= 7) {
        userReportsAvailable = rows.any(
          (row) => row['can_manage_user_reports'] is bool,
        );
      }

      setState(() {
        _hasMore = rows.length > _pageSize;
        // Older deployed projections may still return Superadmins. Hide them
        // locally during rollout; v8 also filters before pagination.
        _admins = rows
            .where((row) => row['can_manage_admin_permissions'] != true)
            .take(_pageSize)
            .toList();
        _userManagementAvailable = userManagementAvailable;
        _disputeManagementAvailable = disputeManagementAvailable;
        _companyRestrictionAvailable = companyRestrictionAvailable;
        _userReportsAvailable = userReportsAvailable;
        _jobModerationAvailable =
            jobModerationAvailable &&
            rows.any((row) => row['can_manage_job_moderation'] is bool);
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
    final isUserManagement = permission == 'can_manage_user_accounts';
    final isDisputeManagement = permission == 'can_manage_disputes';
    final isCompanyRestriction =
        permission == 'can_manage_company_restrictions';
    final isUserReports = permission == 'can_manage_user_reports';
    final isJobModeration = permission == 'can_manage_job_moderation';
    final permissionName = isDisputeManagement
        ? 'Dispute Management permission'
        : isCompanyRestriction
        ? 'Company Management permission'
        : isUserReports
        ? 'User Reports Management permission'
        : isJobModeration
        ? 'Job Moderation permission'
        : isUserManagement
        ? 'User Management permission'
        : isReviewPermission
        ? 'Company review permission'
        : 'Invitation permission';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${enabled ? 'Grant' : 'Revoke'} $permissionName?'),
        content: Text(
          isDisputeManagement
              ? '${enabled ? 'Allow' : 'Remove permission for'} $name to investigate and resolve eligible disputes?'
              : isCompanyRestriction
              ? '${enabled ? 'Allow' : 'Remove permission for'} $name to restrict or restore companies?'
              : isUserReports
              ? '${enabled ? 'Allow' : 'Remove permission for'} $name to review user-submitted reports?'
              : isJobModeration
              ? '${enabled ? 'Allow' : 'Remove permission for'} $name to investigate and restrict eligible Job Postings?'
              : isUserManagement
              ? '${enabled ? 'Allow' : 'Remove permission for'} $name ${enabled ? 'to manage Job Seeker and Employer account restrictions?' : 'to manage account restrictions?'}'
              : enabled
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

      if (isDisputeManagement) {
        await _supabase.rpc(
          'set_dispute_admin_permission',
          params: {'p_target': admin['user_id'], 'p_granted': enabled},
        );
      } else if (isJobModeration) {
        await _supabase.rpc(
          'set_job_moderation_admin_permission',
          params: {
            'p_target_user_id': admin['user_id'],
            'p_can_manage': enabled,
          },
        );
      } else if (isCompanyRestriction) {
        await _supabase.rpc(
          'set_company_restriction_admin_permission',
          params: {
            'p_target_user_id': admin['user_id'],
            'p_can_manage': enabled,
          },
        );
      } else if (isUserReports) {
        await _supabase.rpc(
          'set_user_report_admin_permission',
          params: {
            'p_target_user_id': admin['user_id'],
            'p_can_manage': enabled,
          },
        );
      } else if (isUserManagement) {
        await _supabase.rpc(
          'set_admin_user_management_permission',
          params: {
            'p_target_user_id': admin['user_id'],
            'p_can_manage': enabled,
          },
        );
      } else {
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
      }

      if (!mounted) return;

      _checkSession();

      message = isDisputeManagement
          ? 'Dispute Management permission ${enabled ? 'granted' : 'revoked'}.'
          : isCompanyRestriction
          ? 'Company Management permission ${enabled ? 'granted' : 'revoked'}.'
          : isUserReports
          ? 'User Reports Management permission ${enabled ? 'granted' : 'revoked'}.'
          : isJobModeration
          ? 'Job Moderation permission ${enabled ? 'granted' : 'revoked'}.'
          : isUserManagement
          ? 'User Management permission ${enabled ? 'granted' : 'revoked'}.'
          : isReviewPermission
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
              title: const Text('Dispute Management permission'),
              subtitle: Text(
                _disputeManagementAvailable
                    ? 'Allows investigating eligible disputes. Conflict checks still apply.'
                    : 'This access is not available yet.',
              ),
              value: admin['can_manage_disputes'] == true,
              onChanged:
                  _isBusy || isCurrentAdmin || !_disputeManagementAvailable
                  ? null
                  : (value) =>
                        _changePermission(admin, 'can_manage_disputes', value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Job Moderation permission'),
              subtitle: Text(
                _jobModerationAvailable
                    ? 'Allows reviewing and restricting Job Postings. The Admin cannot review their own jobs or Companies they belong to.'
                    : 'This access is not available yet.',
              ),
              value: admin['can_manage_job_moderation'] == true,
              onChanged: _isBusy || isCurrentAdmin || !_jobModerationAvailable
                  ? null
                  : (value) => _changePermission(
                      admin,
                      'can_manage_job_moderation',
                      value,
                    ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Company Management permission'),
              subtitle: Text(
                _companyRestrictionAvailable
                    ? 'Allows restricting and restoring companies. Company verification remains separate.'
                    : 'This access is not available yet.',
              ),
              value: admin['can_manage_company_restrictions'] == true,
              onChanged:
                  _isBusy || isCurrentAdmin || !_companyRestrictionAvailable
                  ? null
                  : (value) => _changePermission(
                      admin,
                      'can_manage_company_restrictions',
                      value,
                    ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('User Reports Management permission'),
              subtitle: Text(
                _userReportsAvailable
                    ? 'Allows reviewing and responding to user reports. It does not change accounts, companies, jobs or payments.'
                    : 'This access is not available yet.',
              ),
              value: admin['can_manage_user_reports'] == true,
              onChanged: _isBusy || isCurrentAdmin || !_userReportsAvailable
                  ? null
                  : (value) => _changePermission(
                      admin,
                      'can_manage_user_reports',
                      value,
                    ),
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('User Management permission'),
              subtitle: Text(
                _userManagementAvailable
                    ? 'Allows reviewing and restricting Job Seeker and Employer accounts.'
                    : 'This access is not available yet.',
              ),
              value: admin['can_manage_user_accounts'] == true,
              onChanged: _isBusy || isCurrentAdmin || !_userManagementAvailable
                  ? null
                  : (value) => _changePermission(
                      admin,
                      'can_manage_user_accounts',
                      value,
                    ),
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
            'Administrator access',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Superadmins have access to Admin tools and are not listed here. '
            'Other Administrators can only receive access from a Superadmin and cannot change their own permissions.',
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isBusy ? null : _loadAdmins,
              child: const Text('Refresh'),
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
      message: 'Updating administrator permission...',
      child: AppWorkspace(
        title: 'Admin permissions',
        path: AppRoutes.adminPermissions,
        role: 'administrator',
        navigationLocked: _isBusy,
        navigationGroups: {
          ...workspaceDestinations('administrator'),
          'Admin tools': [
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
