import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/auth_layout.dart';
import '../../shared/navigation/app_routes.dart';

abstract class SuspendedAccountGateway {
  Future<String?> reason();
  Future<List<Map<String, dynamic>>> assignments(int offset);
}

class SupabaseSuspendedAccountGateway implements SuspendedAccountGateway {
  SupabaseSuspendedAccountGateway(this.client, this.userId);
  final SupabaseClient client;
  final String userId;

  void _checkSession() {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('Your signed-in account changed.');
    }
  }

  @override
  Future<String?> reason() async {
    _checkSession();
    final data = await client.rpc('get_my_account_restriction');
    _checkSession();
    if (data == null) return null;
    if (data is! Map || (data['reason'] != null && data['reason'] is! String)) {
      throw const FormatException('Unexpected account restriction.');
    }
    return data['reason'] as String?;
  }

  @override
  Future<List<Map<String, dynamic>>> assignments(int offset) async {
    _checkSession();
    final data = await client.rpc(
      'list_my_suspended_assignment_history',
      params: {'p_limit': 21, 'p_offset': offset},
    );
    _checkSession();
    if (data is! List) {
      throw const FormatException('Unexpected assignment history.');
    }
    return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }
}

class SuspendedAccountPage extends StatefulWidget {
  const SuspendedAccountPage({
    super.key,
    required this.role,
    required this.gateway,
    required this.onRetry,
    required this.onSignOut,
  });

  final String role;
  final SuspendedAccountGateway gateway;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  State<SuspendedAccountPage> createState() => _SuspendedAccountPageState();
}

class _SuspendedAccountPageState extends State<SuspendedAccountPage> {
  String? _reason;
  bool _reasonError = false;
  bool _loadingHistory = false;
  bool _historyError = false;
  bool _more = false;
  int _offset = 0;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadReason();
    if (widget.role == 'job_seeker') _loadHistory();
  }

  Future<void> _loadReason() async {
    try {
      final reason = await widget.gateway.reason();
      if (mounted) setState(() => _reason = reason);
    } catch (_) {
      if (mounted) setState(() => _reasonError = true);
    }
  }

  Future<void> _loadHistory() async {
    if (_loadingHistory) return;
    setState(() {
      _loadingHistory = true;
      _historyError = false;
      _history = [];
    });
    try {
      final rows = await widget.gateway.assignments(_offset);
      if (mounted) {
        setState(() {
          _history = rows.take(20).toList();
          _more = rows.length > 20;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _historyError = true);
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  String _display(Object? value) => value?.toString() ?? 'Not available';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthLayout(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your account is suspended.',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text('Contact JobMate support for assistance.'),
            if (widget.role == 'job_seeker' || widget.role == 'employer')
              TextButton(
                onPressed: () => context.go(AppRoutes.disputes),
                child: const Text('View my disputes'),
              ),
            if (_reason != null && _reason!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Reason: $_reason'),
            ] else if (_reasonError) ...[
              const SizedBox(height: 12),
              const Text('The reason is temporarily unavailable.'),
            ],
            const SizedBox(height: 16),
            if (widget.role == 'job_seeker') ...[
              Text(
                'Your assignments',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (_loadingHistory)
                const Center(child: CircularProgressIndicator())
              else if (_historyError)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Assignment history is temporarily unavailable.',
                    ),
                    TextButton(
                      onPressed: _loadHistory,
                      child: const Text('Retry history'),
                    ),
                  ],
                )
              else if (_history.isEmpty)
                const Text('No assignments on this page.')
              else
                for (final item in _history)
                  Card.outlined(
                    child: ListTile(
                      title: Text(_display(item['job_title'])),
                      subtitle: Text(
                        '${_display(item['company_name'])}\n'
                        '${_display(item['scheduled_start'])} – ${_display(item['scheduled_end'])}\n'
                        'Status: ${_display(item['assignment_status'])} · '
                        'Verification: ${_display(item['verification_status'])}',
                      ),
                    ),
                  ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: _loadingHistory || _offset == 0
                        ? null
                        : () {
                            _offset -= 20;
                            _loadHistory();
                          },
                    child: const Text('Previous'),
                  ),
                  Text('Page ${_offset ~/ 20 + 1}'),
                  TextButton(
                    onPressed: _loadingHistory || !_more
                        ? null
                        : () {
                            _offset += 20;
                            _loadHistory();
                          },
                    child: const Text('Next'),
                  ),
                ],
              ),
            ],
            FilledButton(
              onPressed: widget.onRetry,
              child: const Text('Check account status'),
            ),
            TextButton(
              onPressed: widget.onSignOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
