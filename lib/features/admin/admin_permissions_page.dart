import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/navigation/app_routes.dart';
import '../../shared/navigation/workspace_destinations.dart';
import '../../shared/widgets/responsive_layout.dart';
import 'admin_internal_trust_permission_control.dart';
import 'admin_internal_trust_permission_gateway.dart';
import 'admin_invitation_dialog.dart';
import 'admin_scoring_gateway.dart' show adminScoringEnabled;

class AdminPermissionsPage extends StatefulWidget {
  const AdminPermissionsPage({
    super.key,
    this.internalTrustPermissionGateway,
    this.internalTrustPermissionEnabledForTesting,
  });

  final AdminInternalTrustPermissionGateway? internalTrustPermissionGateway;

  /// Test-only injection; profile/release builds remain disabled by [kDebugMode].
  final bool? internalTrustPermissionEnabledForTesting;

  @override
  State<AdminPermissionsPage> createState() => _AdminPermissionsPageState();
}

class _AdminPermissionsPageState extends State<AdminPermissionsPage> {
  final _supabase = Supabase.instance.client;
  final _actorId = Supabase.instance.client.auth.currentUser?.id;
  StreamSubscription<dynamic>? _authStateSubscription;

  static const _pageSize = 5;

  List<Map<String, dynamic>> _admins = [];
  final _listController = ScrollController();
  Map<String, dynamic>? _selectedAdmin;
  String _searchText = '';
  bool _canInviteAdmins = false;

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isUpdating = false;
  bool _hasMore = false;
  bool _userManagementAvailable = false;
  bool _disputeManagementAvailable = false;
  bool _companyRestrictionAvailable = false;
  bool _userReportsAvailable = false;
  bool _jobModerationAvailable = false;
  bool _superadminListAuthorized = false;
  bool _delegatedManagementAuthorized = false;
  bool _administratorManagementBackendAvailable = false;
  bool _internalTrustPermissionProjectionAvailable = false;
  int _adminListRequestGeneration = 0;

  int _offset = 0;
  String? _errorMessage;
  String? _loadMoreError;

  bool get _isBusy => _isLoading || _isUpdating;
  bool get _internalTrustPermissionEnabled =>
      kDebugMode &&
      (widget.internalTrustPermissionEnabledForTesting ?? adminScoringEnabled);

  @override
  void initState() {
    super.initState();
    _listController.addListener(_onListScroll);
    _authStateSubscription = _supabase.auth.onAuthStateChange.listen((state) {
      if (state.session?.user.id != _actorId) {
        _invalidateForAccountChange();
      }
    });
    unawaited(_loadInvitePermission());
    _loadAdmins();
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    _listController
      ..removeListener(_onListScroll)
      ..dispose();
    super.dispose();
  }

  void _invalidateForAccountChange() {
    _adminListRequestGeneration++;
    if (!mounted) return;
    setState(() {
      _admins = [];
      _selectedAdmin = null;
      _offset = 0;
      _hasMore = false;
      _canInviteAdmins = false;
      _superadminListAuthorized = false;
      _delegatedManagementAuthorized = false;
      _administratorManagementBackendAvailable = false;
      _internalTrustPermissionProjectionAvailable = false;
    });
  }

  void _onListScroll() {
    if (!_listController.hasClients ||
        _isLoading ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }
    if (_listController.position.extentAfter < 220) {
      _loadAdmins(loadMore: true);
    }
  }

  void _checkSession() {
    if (_actorId == null || _supabase.auth.currentUser?.id != _actorId) {
      throw StateError(
        'Your account has changed. Close this page and sign in again.',
      );
    }
  }

  Future<void> _loadAdmins({bool loadMore = false}) async {
    if (_isLoading || _isLoadingMore || (loadMore && !_hasMore)) return;

    setState(() {
      if (loadMore) {
        _isLoadingMore = true;
        _loadMoreError = null;
      } else {
        _isLoading = true;
        _loadMoreError = null;
      }
      _errorMessage = null;
    });

    try {
      final requestGeneration = ++_adminListRequestGeneration;
      _checkSession();
      final requestOffset = loadMore ? _offset : 0;

      dynamic data;
      Map<String, dynamic>? managementAccess;
      var schemaVersion = 0;
      // The additive management contract gives every active Administrator a
      // minimal directory. Fall back only when that reviewed contract has not
      // been deployed; never use a Superadmin-only list as an ordinary-Admin
      // directory.
      try {
        final access = await _supabase.rpc(
          'get_my_administrator_management_access_v1',
        );
        if (access is! List || access.length != 1 || access.first is! Map) {
          throw const FormatException(
            'Unexpected administrator access response.',
          );
        }
        managementAccess = Map<String, dynamic>.from(access.first as Map);
        if (managementAccess['is_active_superadmin'] is! bool ||
            managementAccess['can_manage_administrator_permissions'] is! bool ||
            managementAccess['can_invite_administrators'] is! bool) {
          throw const FormatException('Invalid administrator access response.');
        }
        // Superadmins retain the established v9/v10 projection and dedicated
        // setters. The new common directory is intentionally for delegated
        // and read-only Administrators, where permission columns must not be
        // disclosed.
        if (managementAccess['is_active_superadmin'] != true) {
          data = await _supabase.rpc(
            'list_administrator_directory_v1',
            params: {
              'p_search': _searchText.trim().isEmpty
                  ? null
                  : _searchText.trim(),
              'p_limit': _pageSize + 1,
              'p_offset': requestOffset,
            },
          );
          schemaVersion = 11;
        }
      } on PostgrestException catch (error) {
        if (error.code != 'PGRST202') rethrow;
      }
      // v10 is queried only for the Debug-only Internal Trust control. Its
      // absence falls back to v9 without treating a missing value as false.
      if (schemaVersion == 0) {
        final versions = adminPermissionListRpcVersions(
          includeInternalTrustProjection: _internalTrustPermissionEnabled,
        );
        for (var index = 0; index < versions.length; index++) {
          try {
            data = await _supabase.rpc(
              versions[index].name,
              params: {'p_limit': _pageSize + 1, 'p_offset': requestOffset},
            );
            schemaVersion = versions[index].schemaVersion;
            break;
          } on PostgrestException catch (error) {
            if (error.code != 'PGRST202' || index == versions.length - 1) {
              rethrow;
            }
          }
        }
      }
      final userManagementAvailable = schemaVersion >= 3;
      var disputeManagementAvailable = false;
      var companyRestrictionAvailable = schemaVersion >= 5;
      var userReportsAvailable = schemaVersion == 6;
      var jobModerationAvailable = schemaVersion >= 7;

      if (!mounted || requestGeneration != _adminListRequestGeneration) return;

      _checkSession();

      if (data is! List) {
        throw const FormatException('Unexpected administrator list.');
      }

      final rows = schemaVersion == 10
          ? validateAdminPermissionListV10(data)
          : data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
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
        // Older deployed projections may still return Superadmins. Hide them
        // locally during rollout; v8 also filters before pagination.
        final page = rows
            .where((row) => row['can_manage_admin_permissions'] != true)
            .take(_pageSize)
            .toList();
        if (loadMore) {
          final existingIds = _admins.map((row) => row['user_id']).toSet();
          _admins.addAll(
            page.where((row) => !existingIds.contains(row['user_id'])),
          );
        } else {
          _admins = page;
        }
        _offset =
            requestOffset + (rows.length > _pageSize ? _pageSize : rows.length);
        _hasMore = rows.length > _pageSize;
        final selectedId = _selectedAdmin?['user_id'];
        Map<String, dynamic>? selected;
        for (final row in _admins) {
          if (row['user_id'] == selectedId) selected = row;
        }
        _selectedAdmin = selected ?? (_admins.isEmpty ? null : _admins.first);
        _userManagementAvailable = userManagementAvailable;
        _disputeManagementAvailable = disputeManagementAvailable;
        _companyRestrictionAvailable = companyRestrictionAvailable;
        _userReportsAvailable = userReportsAvailable;
        _jobModerationAvailable =
            jobModerationAvailable &&
            rows.any((row) => row['can_manage_job_moderation'] is bool);
        _superadminListAuthorized = schemaVersion == 11
            ? managementAccess!['is_active_superadmin'] as bool
            : true;
        _delegatedManagementAuthorized =
            schemaVersion == 11 &&
            managementAccess!['can_manage_administrator_permissions'] == true;
        _administratorManagementBackendAvailable = managementAccess != null;
        _internalTrustPermissionProjectionAvailable = schemaVersion == 10;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        _superadminListAuthorized = false;
        _delegatedManagementAuthorized = false;
        _administratorManagementBackendAvailable = false;
        _internalTrustPermissionProjectionAvailable = false;
        if (loadMore) {
          _loadMoreError = 'Could not load more administrators. Retry.';
        } else {
          _errorMessage = error.code == '42501'
              ? 'Administrator directory access is unavailable until the reviewed Administrator Management backend is deployed.'
              : error.message;
        }
      });
    } catch (error) {
      if (!mounted) return;

      debugPrint('Admin list loading failed: $error');

      setState(() {
        _superadminListAuthorized = false;
        _delegatedManagementAuthorized = false;
        _administratorManagementBackendAvailable = false;
        _internalTrustPermissionProjectionAvailable = false;
        if (error is StateError) {
          _admins = [];
          _selectedAdmin = null;
          _offset = 0;
          _hasMore = false;
        }
        final message = error is StateError
            ? error.message.toString()
            : 'Unable to load administrators. Please retry.';
        if (loadMore) {
          _loadMoreError = message;
        } else {
          _errorMessage = message;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadInvitePermission() async {
    final actorId = _actorId;
    if (actorId == null) return;
    try {
      final response = await _supabase.functions.invoke(
        'admin-invitations',
        body: const {'action': 'check_access'},
      );
      if (!mounted || _supabase.auth.currentUser?.id != actorId) return;
      final data = response.data;
      if (data is! Map ||
          data['isAdmin'] != true ||
          data['canInviteAdmins'] is! bool ||
          data['canManageAdminPermissions'] is! bool) {
        throw const FormatException(
          'Unexpected administrator access response.',
        );
      }
      setState(
        () => _canInviteAdmins =
            data['canInviteAdmins'] == true ||
            data['canManageAdminPermissions'] == true,
      );
    } catch (error) {
      debugPrint('Admin invitation permission lookup failed: $error');
      if (mounted) setState(() => _canInviteAdmins = false);
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

      if (_administratorManagementBackendAvailable &&
          _delegatedManagementAuthorized &&
          !_superadminListAuthorized) {
        final operationalPermissions = <String, bool>{
          'can_review_companies': admin['can_review_companies'] == true,
          'can_manage_user_accounts': admin['can_manage_user_accounts'] == true,
          'can_manage_disputes': admin['can_manage_disputes'] == true,
          'can_manage_company_restrictions':
              admin['can_manage_company_restrictions'] == true,
          'can_manage_user_reports': admin['can_manage_user_reports'] == true,
          'can_manage_job_moderation':
              admin['can_manage_job_moderation'] == true,
        }..[permission] = enabled;
        await _supabase.rpc(
          'set_delegated_admin_operational_permissions_v1',
          params: {
            'p_target_user_id': admin['user_id'],
            ...operationalPermissions,
          },
        );
      } else if (isDisputeManagement) {
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

  Future<void> _changeInternalTrustPermission(
    Map<String, dynamic> admin,
    bool enabled,
  ) async {
    if (_isBusy || !_superadminListAuthorized) return;

    final targetUserId = admin['user_id'];
    if (targetUserId is! String ||
        targetUserId.isEmpty ||
        targetUserId == _actorId ||
        admin['account_status'] != 'active' ||
        admin['can_view_internal_trust_scores'] is! bool) {
      return;
    }

    final name = admin['name'] as String? ?? 'this administrator';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${enabled ? 'Grant' : 'Revoke'} Internal Trust access?'),
        content: Text(
          enabled
              ? 'Allow $name to view provisional Job Seeker Internal Trust Scores?'
              : 'Remove $name\'s access to provisional Job Seeker Internal Trust Scores?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(enabled ? 'Grant' : 'Revoke'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _isUpdating = true);
    var message = enabled
        ? 'Internal Trust access granted.'
        : 'Internal Trust access revoked.';
    try {
      _checkSession();
      final gateway =
          widget.internalTrustPermissionGateway ??
          SupabaseAdminInternalTrustPermissionGateway(_supabase);
      await gateway.setPermission(targetUserId: targetUserId, canView: enabled);
      _checkSession();
    } catch (error) {
      message = internalTrustPermissionFailureMessage(error);
    } finally {
      if (mounted) {
        // Never retain an optimistic or stale sensitive-permission value.
        await _loadAdmins();
        if (mounted) setState(() => _isUpdating = false);
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeDelegatedManagementPermission(
    Map<String, dynamic> admin,
    bool enabled,
  ) async {
    if (_isBusy ||
        !_superadminListAuthorized ||
        !_administratorManagementBackendAvailable) {
      return;
    }
    final targetUserId = admin['user_id'];
    if (targetUserId is! String ||
        targetUserId.isEmpty ||
        targetUserId == _actorId ||
        admin['account_status'] != 'active' ||
        admin['can_manage_other_admin_permissions'] is! bool) {
      return;
    }
    final name = admin['name'] as String? ?? 'this administrator';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${enabled ? 'Grant' : 'Revoke'} delegated management?'),
        content: Text(
          enabled
              ? 'Allow $name to manage only the reviewed operational permissions of eligible ordinary administrators?'
              : 'Remove $name\'s delegated administrator-management access?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(enabled ? 'Grant' : 'Revoke'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _isUpdating = true);
    var message = enabled
        ? 'Delegated administrator-management access granted.'
        : 'Delegated administrator-management access revoked.';
    try {
      _checkSession();
      await _supabase.rpc(
        'set_admin_delegated_management_permission_v1',
        params: {'p_target_user_id': targetUserId, 'p_can_manage': enabled},
      );
      _checkSession();
    } on PostgrestException catch (error) {
      message = error.code == '42501'
          ? 'You are not authorized to change delegated administrator access.'
          : error.message;
    } on StateError catch (error) {
      message = error.message.toString();
    } catch (_) {
      message = 'Unable to confirm the delegated access update.';
    } finally {
      if (mounted) {
        await _loadAdmins();
        if (mounted) setState(() => _isUpdating = false);
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildPermissionControls(Map<String, dynamic> admin) {
    final name = admin['name'] as String? ?? 'Unnamed administrator';
    final email = admin['email'] as String?;
    final status = admin['account_status'] as String? ?? 'unknown';

    final canInvite = admin['can_invite_admins'] == true;
    final canReviewCompanies = admin['can_review_companies'] == true;
    final isManager = admin['can_manage_admin_permissions'] == true;
    final isCurrentAdmin = admin['user_id'] == _actorId;
    final canManageTarget =
        _superadminListAuthorized ||
        (_administratorManagementBackendAvailable &&
            _delegatedManagementAuthorized);
    final delegatedManager = canManageTarget && !_superadminListAuthorized;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (email?.isNotEmpty == true) ...[
              SelectableText(email!),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(label: Text(status)),
                if (isManager) const Chip(label: Text('Superadmin')),
              ],
            ),
            if (canManageTarget && !delegatedManager)
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
            if (canManageTarget)
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
                    : (value) => _changePermission(
                        admin,
                        'can_manage_disputes',
                        value,
                      ),
              ),
            if (canManageTarget)
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
            if (canManageTarget)
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
            if (canManageTarget)
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
            if (canManageTarget)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Company review permission'),
                subtitle: const Text(
                  'Allows reviewing submitted Company documents.',
                ),
                value: canReviewCompanies,
                onChanged: _isBusy || isCurrentAdmin
                    ? null
                    : (value) => _changePermission(
                        admin,
                        'can_review_companies',
                        value,
                      ),
              ),
            if (canManageTarget)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('User Management permission'),
                subtitle: Text(
                  _userManagementAvailable
                      ? 'Allows reviewing and restricting Job Seeker and Employer accounts.'
                      : 'This access is not available yet.',
                ),
                value: admin['can_manage_user_accounts'] == true,
                onChanged:
                    _isBusy || isCurrentAdmin || !_userManagementAvailable
                    ? null
                    : (value) => _changePermission(
                        admin,
                        'can_manage_user_accounts',
                        value,
                      ),
              ),
            if (canManageTarget && !delegatedManager)
              AdminInternalTrustPermissionControl(
                featureEnabled: _internalTrustPermissionEnabled,
                isAuthorizedSuperadmin: _superadminListAuthorized,
                isCurrentAdmin: isCurrentAdmin,
                isTargetActive: status == 'active',
                value:
                    _internalTrustPermissionProjectionAvailable &&
                        admin['can_view_internal_trust_scores'] is bool
                    ? admin['can_view_internal_trust_scores'] as bool
                    : null,
                busy: _isBusy,
                onChanged: (value) =>
                    unawaited(_changeInternalTrustPermission(admin, value)),
              ),
            if (_superadminListAuthorized &&
                _administratorManagementBackendAvailable &&
                !isCurrentAdmin &&
                status == 'active' &&
                admin['can_manage_other_admin_permissions'] is bool)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Delegated administrator management'),
                subtitle: const Text(
                  'Allows only the reviewed operational permission whitelist.',
                ),
                value: admin['can_manage_other_admin_permissions'] as bool,
                onChanged: _isBusy
                    ? null
                    : (value) =>
                          _changeDelegatedManagementPermission(admin, value),
              ),
          ],
        ),
      ),
    );
  }

  Widget _administratorRow(Map<String, dynamic> admin) {
    final name = admin['name'] as String? ?? 'Unnamed administrator';
    final selected = admin['user_id'] == _selectedAdmin?['user_id'];
    final imageUrl = admin['profile_image_url'] as String?;
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        selected: selected,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF9AF3E4),
          foregroundImage: imageUrl?.trim().isNotEmpty == true
              ? NetworkImage(imageUrl!)
              : null,
          child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
        ),
        title: Text(name),
        subtitle: Text('ID: ${admin['user_id'] ?? 'Unavailable'}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => setState(() => _selectedAdmin = admin),
      ),
    );
  }

  Future<void> _openPermissions(Map<String, dynamic> admin) async {
    var editableAdmin = admin;
    if (_administratorManagementBackendAvailable && _superadminListAuthorized) {
      final targetId = admin['user_id'];
      if (targetId is! String || targetId.isEmpty || targetId == _actorId) {
        return;
      }
      try {
        _checkSession();
        final delegated = await _supabase.rpc(
          'get_admin_delegated_management_permission_v1',
          params: {'p_target_user_id': targetId},
        );
        if (!mounted) return;
        _checkSession();
        if (delegated is! bool) {
          throw const FormatException('Invalid delegated permission response.');
        }
        editableAdmin = {
          ...editableAdmin,
          'can_manage_other_admin_permissions': delegated,
        };
      } on PostgrestException catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.code == '42501'
                  ? 'This administrator is not eligible for permission management.'
                  : 'Unable to load delegated administrator access.',
            ),
          ),
        );
        return;
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load delegated administrator access.'),
          ),
        );
        return;
      }
    }
    if (_administratorManagementBackendAvailable &&
        _delegatedManagementAuthorized &&
        !_superadminListAuthorized) {
      final targetId = admin['user_id'];
      if (targetId is! String || targetId.isEmpty || targetId == _actorId) {
        return;
      }
      try {
        _checkSession();
        final response = await _supabase.rpc(
          'get_administrator_operational_permissions_v1',
          params: {'p_target_user_id': targetId},
        );
        if (!mounted) return;
        _checkSession();
        if (response is! List ||
            response.length != 1 ||
            response.first is! Map) {
          throw const FormatException(
            'Invalid administrator permission response.',
          );
        }
        final permissions = Map<String, dynamic>.from(response.first as Map);
        const columns = [
          'can_review_companies',
          'can_manage_user_accounts',
          'can_manage_disputes',
          'can_manage_company_restrictions',
          'can_manage_user_reports',
          'can_manage_job_moderation',
        ];
        if (columns.any((column) => permissions[column] is! bool)) {
          throw const FormatException(
            'Invalid administrator permission response.',
          );
        }
        editableAdmin = {...admin, ...permissions};
      } on PostgrestException catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.code == '42501'
                  ? 'This administrator is not eligible for delegated permission management.'
                  : 'Unable to load editable administrator permissions.',
            ),
          ),
        );
        return;
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load editable administrator permissions.'),
          ),
        );
        return;
      }
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Manage permissions — ${editableAdmin['name'] ?? 'Administrator'}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(),
                _buildPermissionControls(editableAdmin),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showActionHistoryNotice() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Administrator action history'),
      content: const Text(
        'A unified administrator permission history is not available from the current database RPCs.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  void _setAdminSearch(String value) {
    setState(() {
      _searchText = value;
      final query = value.trim().toLowerCase();
      final matches = _admins.where(
        (admin) =>
            query.isEmpty ||
            (admin['name']?.toString().toLowerCase().contains(query) ?? false),
      );
      if (!matches.any(
        (admin) => admin['user_id'] == _selectedAdmin?['user_id'],
      )) {
        _selectedAdmin = matches.isEmpty ? null : matches.first;
      }
    });
    if (_administratorManagementBackendAvailable) {
      unawaited(_loadAdmins());
    }
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading && _admins.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _admins.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Administrator Management',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (_canInviteAdmins) ...[
                FilledButton.icon(
                  onPressed: _isBusy
                      ? null
                      : () => showAdminInvitationDialog(context),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Invite Administrator'),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                onPressed: _isBusy ? null : _loadAdmins,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final filteredAdmins = _admins.where((admin) {
      final query = _searchText.trim().toLowerCase();
      return query.isEmpty ||
          (admin['name']?.toString().toLowerCase().contains(query) ?? false);
    }).toList();
    final selected = _selectedAdmin;
    final selectedName = selected?['name'] as String? ?? '?';
    final canManageSelected =
        selected != null &&
        (_administratorManagementBackendAvailable && !_superadminListAuthorized
            ? selected['can_manage_permissions'] == true
            : _superadminListAuthorized &&
                  selected['user_id'] != _actorId &&
                  selected['account_status'] == 'active');

    return LayoutBuilder(
      builder: (context, constraints) => ResponsiveContent(
        maxWidth: 1320,
        child: SizedBox(
          height: constraints.maxHeight,
          child: Padding(
            padding: ResponsiveLayout.pagePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Administrator Management',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'View administrators and manage their access based on your permissions.',
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, searchConstraints) {
                    final search = TextField(
                      enabled: !_isBusy,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search administrator name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _setAdminSearch,
                    );
                    final invite = _canInviteAdmins
                        ? FilledButton.icon(
                            onPressed: _isBusy
                                ? null
                                : () => showAdminInvitationDialog(context),
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Invite Administrator'),
                          )
                        : null;
                    if (searchConstraints.maxWidth < 640) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          search,
                          if (invite != null) ...[
                            const SizedBox(height: 8),
                            invite,
                          ],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: search),
                        if (invite != null) ...[
                          const SizedBox(width: 12),
                          invite,
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, panes) {
                      final leftPane = Card.outlined(
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                              child: Row(
                                children: [
                                  const Expanded(child: Text('Administrators')),
                                  IconButton(
                                    tooltip: 'Refresh administrators',
                                    onPressed: _isBusy ? null : _loadAdmins,
                                    icon: const Icon(Icons.refresh),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: filteredAdmins.isEmpty && !_hasMore
                                  ? Center(
                                      child: Text(
                                        _admins.isEmpty
                                            ? 'No administrators found.'
                                            : 'No administrators match this search.',
                                        textAlign: TextAlign.center,
                                      ),
                                    )
                                  : ListView(
                                      key: const ValueKey(
                                        'admin-administrators-list',
                                      ),
                                      controller: _listController,
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.all(8),
                                      children: [
                                        if (filteredAdmins.isEmpty)
                                          const Padding(
                                            padding: EdgeInsets.all(20),
                                            child: Text(
                                              'No loaded administrator matches yet.',
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        for (final admin in filteredAdmins)
                                          _administratorRow(admin),
                                        if (_loadMoreError != null)
                                          Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                              children: [
                                                Text(
                                                  _loadMoreError!,
                                                  textAlign: TextAlign.center,
                                                ),
                                                TextButton(
                                                  onPressed: _isLoadingMore
                                                      ? null
                                                      : () => _loadAdmins(
                                                          loadMore: true,
                                                        ),
                                                  child: const Text('Retry'),
                                                ),
                                              ],
                                            ),
                                          )
                                        else if (_isLoadingMore)
                                          const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: Center(
                                              child: SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      );
                      final rightPane = Card.outlined(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                              child: Text('Administrator details'),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: selected == null
                                  ? const Center(
                                      child: Text('Select an administrator.'),
                                    )
                                  : ListView(
                                      key: const ValueKey(
                                        'admin-detail-pane-scroll',
                                      ),
                                      padding: const EdgeInsets.all(20),
                                      children: [
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 34,
                                              backgroundColor: const Color(
                                                0xFF9AF3E4,
                                              ),
                                              foregroundImage:
                                                  (selected['profile_image_url']
                                                              as String?)
                                                          ?.trim()
                                                          .isNotEmpty ==
                                                      true
                                                  ? NetworkImage(
                                                      selected['profile_image_url']
                                                          as String,
                                                    )
                                                  : null,
                                              child: Text(
                                                selectedName.isEmpty
                                                    ? '?'
                                                    : selectedName[0]
                                                          .toUpperCase(),
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    selectedName,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleLarge,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'ID: ${selected['user_id'] ?? 'Unavailable'}',
                                                  ),
                                                  Text(
                                                    'Account: ${selected['account_status'] ?? 'unknown'}',
                                                  ),
                                                  if ((selected['email']
                                                              as String?)
                                                          ?.isNotEmpty ==
                                                      true)
                                                    Text(
                                                      selected['email']
                                                          as String,
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                        if (canManageSelected ||
                                            _superadminListAuthorized)
                                          Wrap(
                                            spacing: 12,
                                            runSpacing: 8,
                                            children: [
                                              if (canManageSelected)
                                                FilledButton.icon(
                                                  onPressed: _isBusy
                                                      ? null
                                                      : () => _openPermissions(
                                                          selected,
                                                        ),
                                                  icon: const Icon(Icons.tune),
                                                  label: const Text(
                                                    'Manage permissions',
                                                  ),
                                                ),
                                              if (_superadminListAuthorized)
                                                OutlinedButton.icon(
                                                  onPressed:
                                                      _showActionHistoryNotice,
                                                  icon: const Icon(
                                                    Icons.history,
                                                  ),
                                                  label: const Text(
                                                    'View action history',
                                                  ),
                                                ),
                                            ],
                                          ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      );
                      if (panes.maxWidth < 760) {
                        return Column(
                          children: [
                            Expanded(flex: 5, child: leftPane),
                            const SizedBox(height: 10),
                            Expanded(flex: 4, child: rightPane),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 5, child: leftPane),
                          const SizedBox(width: 12),
                          Expanded(flex: 6, child: rightPane),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isUpdating,
      message: 'Updating administrator permission...',
      child: AppWorkspace(
        title: 'Administrator Management',
        titleWidget: const SizedBox.shrink(),
        path: AppRoutes.adminPermissions,
        role: 'administrator',
        navigationLocked: _isBusy,
        navigationGroups: {
          ...workspaceDestinations('administrator'),
          'Admin tools': [
            (
              AppRoutes.adminPermissions,
              'Administrator Management',
              Icons.admin_panel_settings_outlined,
            ),
          ],
        },
        child: _buildBody(context),
      ),
    );
  }
}
