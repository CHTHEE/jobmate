import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/responsive_layout.dart';
import 'user_account_details_dialog.dart';
import 'admin_accounts_repository.dart';
import 'user_management_gateway.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({
    super.key,
    this.directoryRepository,
    this.accountGateway,
  });

  final AdminAccountsRepository? directoryRepository;
  final UserManagementGateway? accountGateway;

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  static const _pageSize = 5;
  final _supabase = Supabase.instance.client;
  final _actorId = Supabase.instance.client.auth.currentUser?.id;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  late final AdminAccountsRepository _directory =
      widget.directoryRepository ?? SupabaseAdminAccountsRepository(_supabase);
  late final UserManagementGateway _accountGateway =
      widget.accountGateway ?? SupabaseUserManagementGateway(_supabase);

  List<Map<String, dynamic>> _users = [];
  String? _selectedUserId;
  Timer? _searchDebounce;
  int _requestGeneration = 0;
  int _totalCount = 0;
  String _search = '';
  String _role = 'all';
  String _status = 'all';
  bool _loading = false;
  bool _loadingMore = false;
  bool _permissionLoaded = false;
  bool _canManageAccounts = false;
  bool _hasMore = false;
  String? _error;
  String? _pageError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadAccountManagementPermission();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        !_hasMore ||
        _pageError != null) {
      return;
    }
    if (_scrollController.position.extentAfter < 240) {
      _loadUsers(loadMore: true);
    }
  }

  Future<void> _loadAccountManagementPermission() async {
    final actorId = _actorId;
    if (actorId == null || _supabase.auth.currentUser?.id != actorId) {
      if (mounted) setState(() => _permissionLoaded = true);
      return;
    }
    try {
      final profile = await _supabase
          .from('administrator_profiles')
          .select('*')
          .eq('user_id', actorId)
          .maybeSingle();
      if (!mounted || _supabase.auth.currentUser?.id != actorId) return;
      setState(() {
        _canManageAccounts = profile?['can_manage_user_accounts'] == true;
        _permissionLoaded = true;
      });
    } catch (error) {
      debugPrint('User Management permission lookup failed: $error');
      if (mounted) {
        // Permission lookup failures must never expose account controls.
        setState(() {
          _canManageAccounts = false;
          _permissionLoaded = true;
        });
      }
    }
  }

  Future<void> _loadUsers({bool loadMore = false}) async {
    if (_loading || _loadingMore || (loadMore && !_hasMore)) return;
    final generation = _requestGeneration;
    final offset = loadMore ? _users.length : 0;
    setState(() {
      if (loadMore) {
        _loadingMore = true;
        _pageError = null;
      } else {
        _loading = true;
        _error = null;
        _pageError = null;
      }
    });
    try {
      if (_actorId == null && widget.directoryRepository == null ||
          _actorId != null && _supabase.auth.currentUser?.id != _actorId) {
        throw StateError('Your signed-in account has changed.');
      }
      final result = await _directory.fetchPage(
        role: _role == 'all' ? null : _role,
        status: _status == 'all' ? null : _status,
        search: _search,
        limit: _pageSize,
        offset: offset,
      );
      if (!mounted || generation != _requestGeneration) return;
      if (_actorId != null && _supabase.auth.currentUser?.id != _actorId) {
        throw StateError('Your signed-in account has changed.');
      }
      setState(() {
        if (loadMore) {
          final existingIds = _users.map((user) => user['user_id']).toSet();
          _users.addAll(
            result.accounts.where(
              (user) => !existingIds.contains(user['user_id']),
            ),
          );
        } else {
          _users = result.accounts;
          if (!_users.any(
            (user) => user['user_id']?.toString() == _selectedUserId,
          )) {
            _selectedUserId = _users.isEmpty
                ? null
                : _users.first['user_id']?.toString();
          }
        }
        _totalCount = result.totalCount;
        _hasMore = result.hasMore;
      });
    } on PostgrestException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        final message = error.code == 'PGRST202'
            ? 'The user directory is temporarily unavailable. Please try again later.'
            : 'We could not load user accounts. Please try again.';
        if (loadMore) {
          _pageError = message;
        } else {
          _error = message;
        }
      });
    } catch (error) {
      debugPrint('Admin users load failed: $error');
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        final message = error is StateError
            ? error.message.toString()
            : 'Unable to load user accounts. Please retry.';
        if (loadMore) {
          _pageError = message;
        } else {
          _error = message;
        }
      });
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _changeFilter({String? role, String? status}) {
    _requestGeneration++;
    setState(() {
      if (role != null) _role = role;
      if (status != null) _status = status;
      _users = [];
      _selectedUserId = null;
      _hasMore = false;
      _totalCount = 0;
      _loading = false;
      _loadingMore = false;
    });
    _loadUsers();
  }

  void _changeSearch(String value) {
    _searchDebounce?.cancel();
    _requestGeneration++;
    setState(() {
      _loading = false;
      _loadingMore = false;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _search = value.trim();
        _users = [];
        _selectedUserId = null;
        _hasMore = false;
        _totalCount = 0;
      });
      _loadUsers();
    });
  }

  String _display(String? value) {
    if (value == null || value.isEmpty) return 'Not provided';
    return value.replaceAll('_', ' ');
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final name = user['name'] as String? ?? 'Unnamed user';
    final selected = user['user_id']?.toString() == _selectedUserId;
    final imageUrl = user['profile_image_url']?.toString();

    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minVerticalPadding: 18,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: const Color(0xFF9AF3E4),
          foregroundColor: const Color(0xFF075E58),
          foregroundImage: imageUrl?.trim().isNotEmpty == true
              ? NetworkImage(imageUrl!)
              : null,
          child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
        ),
        title: Text(name),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('ID: ${user['user_id'] ?? 'Unavailable'}'),
        ),
        selected: selected,
        selectedTileColor: const Color(0xFFE8F8F5),
        trailing: Icon(
          Icons.chevron_right,
          color: selected ? const Color(0xFF087F75) : null,
        ),
        onTap: () =>
            setState(() => _selectedUserId = user['user_id']?.toString()),
      ),
    );
  }

  Widget _buildUserDetails() {
    Map<String, dynamic>? selected;
    for (final user in _users) {
      if (user['user_id']?.toString() == _selectedUserId) selected = user;
    }
    final user = selected;
    if (user == null) {
      return const Center(
        child: Text('Select an account to view its details.'),
      );
    }
    final name = user['name']?.toString() ?? 'Unnamed user';
    final imageUrl = user['profile_image_url']?.toString();
    return ListView(
      key: const ValueKey('admin-user-details-scroll'),
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: const Color(0xFF9AF3E4),
              foregroundColor: const Color(0xFF075E58),
              foregroundImage: imageUrl?.trim().isNotEmpty == true
                  ? NetworkImage(imageUrl!)
                  : null,
              child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(_display(user['role']?.toString())),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _detailRow('User ID', user['user_id']),
        _detailRow(
          'Account status',
          _display(user['account_status']?.toString()),
        ),
        _detailRow(
          'Verification status',
          _display(user['verification_status']?.toString()),
        ),
        _detailRow('Joined', user['created_at']?.toString().split('T').first),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: user['user_id'] is String
                ? () => _showUserDetails(user)
                : null,
            icon: const Icon(Icons.open_in_new),
            label: const Text('View account details'),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, Object? value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: SelectableText(value?.toString() ?? 'Not provided')),
      ],
    ),
  );

  Future<void> _showUserDetails(Map<String, dynamic> user) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UserAccountDetailsDialog(
        userId: user['user_id'] as String,
        gateway: _accountGateway,
        canManage: _permissionLoaded && _canManageAccounts,
      ),
    );
    if (mounted) await _loadUsers();
  }

  Widget _buildFilters(BuildContext context) {
    final roleSelector = DropdownButtonFormField<String>(
      initialValue: _role,
      decoration: const InputDecoration(labelText: 'Role'),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('All users')),
        DropdownMenuItem(value: 'job_seeker', child: Text('Job seeker')),
        DropdownMenuItem(value: 'employer', child: Text('Employer')),
      ],
      onChanged: (value) {
        if (value != null) _changeFilter(role: value);
      },
    );
    final statusSelector = DropdownButtonFormField<String>(
      initialValue: _status,
      decoration: const InputDecoration(labelText: 'Account status'),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('All statuses')),
        DropdownMenuItem(value: 'active', child: Text('Active')),
        DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
        DropdownMenuItem(value: 'deactivated', child: Text('Deactivated')),
      ],
      onChanged: (value) {
        if (value != null) _changeFilter(status: value);
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              roleSelector,
              const SizedBox(height: 10),
              statusSelector,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: roleSelector),
            const SizedBox(width: 12),
            Expanded(child: statusSelector),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppWorkspace(
      title: 'Users',
      titleWidget: const SizedBox.shrink(),
      path: AppRoutes.adminUsers,
      role: 'administrator',
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => ResponsiveContent(
            maxWidth: 1050,
            child: SizedBox(
              height: constraints.maxHeight,
              child: Padding(
                padding: ResponsiveLayout.pagePadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PageHeading(
                      title: 'User management',
                      description: 'Browse Job Seeker and Employer accounts.',
                    ),
                    TextField(
                      controller: _searchController,
                      enabled: true,
                      onChanged: _changeSearch,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search user name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildFilters(context),
                    const SizedBox(height: 12),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, paneConstraints) {
                          final listPane = Card.outlined(
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    8,
                                    8,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text('Accounts ($_totalCount)'),
                                      ),
                                      IconButton(
                                        tooltip: 'Refresh accounts',
                                        onPressed: _loading ? null : _loadUsers,
                                        icon: const Icon(Icons.refresh),
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: _error != null && _users.isEmpty
                                      ? Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                _error!,
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 12),
                                              FilledButton(
                                                onPressed: _loading
                                                    ? null
                                                    : _loadUsers,
                                                child: const Text('Retry'),
                                              ),
                                            ],
                                          ),
                                        )
                                      : _users.isEmpty && _loading
                                      ? const Center(
                                          child: CircularProgressIndicator(),
                                        )
                                      : _users.isEmpty
                                      ? const Center(
                                          child: Text(
                                            'No users match these filters.',
                                          ),
                                        )
                                      : ListView(
                                          key: const ValueKey(
                                            'admin-accounts-list',
                                          ),
                                          controller: _scrollController,
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          padding: const EdgeInsets.all(8),
                                          children: [
                                            for (final user in _users)
                                              _buildUserCard(user),
                                            if (_pageError != null)
                                              Padding(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                child: Column(
                                                  children: [
                                                    Text(
                                                      _pageError!,
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                    TextButton(
                                                      onPressed: _loadingMore
                                                          ? null
                                                          : () => _loadUsers(
                                                              loadMore: true,
                                                            ),
                                                      child: const Text(
                                                        'Retry loading users',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            else if (_loadingMore)
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
                          final detailPane = Card.outlined(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                                  child: Text('Account details'),
                                ),
                                const Divider(height: 1),
                                Expanded(child: _buildUserDetails()),
                              ],
                            ),
                          );
                          if (paneConstraints.maxWidth < 760) {
                            return Column(
                              children: [
                                Expanded(flex: 5, child: listPane),
                                const SizedBox(height: 10),
                                Expanded(flex: 4, child: detailPane),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 5, child: listPane),
                              const SizedBox(width: 12),
                              Expanded(flex: 6, child: detailPane),
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
        ),
      ),
    );
  }
}
