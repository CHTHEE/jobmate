import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

  int _offset = 0;
  String? _errorMessage;
  String? _loadMoreError;

  bool get _isBusy => _isLoading || _isUpdating;

  @override
  void initState() {
    super.initState();
    _listController.addListener(_onListScroll);
    _loadAdmins();
  }

  @override
  void dispose() {
    _listController
      ..removeListener(_onListScroll)
      ..dispose();
    super.dispose();
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
      _checkSession();
      final requestOffset = loadMore ? _offset : 0;

      dynamic data;
      var schemaVersion = 0;
      const versions = [
        'list_admin_accounts_v9',
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
            params: {'p_limit': _pageSize + 1, 'p_offset': requestOffset},
          );
          schemaVersion = 9 - index;
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
      });
      if (!loadMore) _loadInvitePermission();
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        if (loadMore) {
          _loadMoreError = 'Could not load more administrators. Retry.';
        } else {
          _errorMessage = error.message;
        }
      });
    } catch (error) {
      if (!mounted) return;

      debugPrint('Admin list loading failed: $error');

      setState(() {
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
      final row = await _supabase
          .from('administrator_profiles')
          .select('can_invite_admins')
          .eq('user_id', actorId)
          .maybeSingle();
      if (!mounted || _supabase.auth.currentUser?.id != actorId) return;
      setState(() => _canInviteAdmins = row?['can_invite_admins'] == true);
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

  Widget _buildPermissionControls(Map<String, dynamic> admin) {
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
                        'Manage permissions — ${admin['name'] ?? 'Administrator'}',
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
                _buildPermissionControls(admin),
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

    final filteredAdmins = _admins.where((admin) {
      final query = _searchText.trim().toLowerCase();
      return query.isEmpty ||
          (admin['name']?.toString().toLowerCase().contains(query) ?? false);
    }).toList();
    final selected = _selectedAdmin;
    final selectedName = selected?['name'] as String? ?? '?';

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
                  'Administrator access',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Superadmins have access to Admin tools and are not listed here. '
                  'Other Administrators can only receive access from a Superadmin and cannot change their own permissions.',
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
                                : () => context.push(AppRoutes.inviteAdmin),
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Invite administrator'),
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
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 8,
                                          children: [
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
                                            OutlinedButton.icon(
                                              onPressed:
                                                  _showActionHistoryNotice,
                                              icon: const Icon(Icons.history),
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
        title: 'Admin permissions',
        titleWidget: const SizedBox.shrink(),
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
