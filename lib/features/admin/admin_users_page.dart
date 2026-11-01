import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/mobile_back_action.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  static const _pageSize = 30;
  final _supabase = Supabase.instance.client;
  final _actorId = Supabase.instance.client.auth.currentUser?.id;

  List<Map<String, dynamic>> _users = [];
  String _role = 'all';
  String _status = 'all';
  int _offset = 0;
  bool _loading = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_actorId == null || _supabase.auth.currentUser?.id != _actorId) {
        throw StateError('Your signed-in account has changed.');
      }
      final result = await _supabase.rpc(
        'list_user_accounts',
        params: {
          'p_role': _role == 'all' ? null : _role,
          'p_status': _status == 'all' ? null : _status,
          'p_limit': _pageSize + 1,
          'p_offset': _offset,
        },
      );
      if (!mounted) return;
      if (_supabase.auth.currentUser?.id != _actorId) {
        throw StateError('Your signed-in account has changed.');
      }
      if (result is! List) {
        throw const FormatException('Unexpected user list response.');
      }
      final rows = result
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      setState(() {
        _users = rows.take(_pageSize).toList();
        _hasMore = rows.length > _pageSize;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      debugPrint('Admin users load failed: $error');
      if (!mounted) return;
      setState(() {
        _error = error is StateError
            ? error.message.toString()
            : 'Unable to load user accounts. Please retry.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeFilter({String? role, String? status}) {
    setState(() {
      if (role != null) _role = role;
      if (status != null) _status = status;
      _offset = 0;
      _users = [];
      _hasMore = false;
    });
    _loadUsers();
  }

  void _changePage(int amount) {
    if (_loading) return;
    final next = _offset + amount;
    if (next < 0 || (amount > 0 && !_hasMore)) return;
    setState(() {
      _offset = next;
      _users = [];
    });
    _loadUsers();
  }

  String _display(String? value) {
    if (value == null || value.isEmpty) return 'Not provided';
    return value.replaceAll('_', ' ');
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final name = user['name'] as String? ?? 'Unnamed user';
    final role = _display(user['role'] as String?);
    final status = _display(user['account_status'] as String?);
    final verification =
        _display(user['verification_status'] as String?);
    final created = user['created_at']?.toString();

    return Card.outlined(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
        title: Text(name),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Chip(label: Text(role)),
              Chip(label: Text(status)),
              Chip(label: Text('Verification: $verification')),
              if (created != null)
                Chip(label: Text('Joined: ${created.split('T').first}')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: mobileBackLeading(context),
        title: const Text('Users'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadUsers,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: 210,
                      child: DropdownButtonFormField<String>(
                        initialValue: _role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All users')),
                          DropdownMenuItem(value: 'job_seeker', child: Text('Job seeker')),
                          DropdownMenuItem(value: 'employer', child: Text('Employer')),
                        ],
                        onChanged: _loading
                            ? null
                            : (value) {
                                if (value != null) _changeFilter(role: value);
                              },
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'Account status'),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All statuses')),
                          DropdownMenuItem(value: 'active', child: Text('Active')),
                          DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                          DropdownMenuItem(value: 'deactivated', child: Text('Deactivated')),
                        ],
                        onChanged: _loading
                            ? null
                            : (value) {
                                if (value != null) _changeFilter(status: value);
                              },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _loadUsers,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _users.isEmpty
                    ? const Center(child: Text('No users match these filters.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        itemCount: _users.length,
                        itemBuilder: (context, index) =>
                            _buildUserCard(_users[index]),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _loading || _offset == 0
                          ? null
                          : () => _changePage(-_pageSize),
                      child: const Text('Previous'),
                    ),
                    Text('Page ${_offset ~/ _pageSize + 1}'),
                    TextButton(
                      onPressed: _loading || !_hasMore
                          ? null
                          : () => _changePage(_pageSize),
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
