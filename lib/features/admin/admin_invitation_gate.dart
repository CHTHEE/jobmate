import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/auth_layout.dart';

import 'admin_dashboard_page.dart';
import '../home/home_page.dart';
import 'accept_admin_invitation_page.dart';

class AdminInvitationGate extends StatefulWidget {
  final String userId;
  final String email;

  const AdminInvitationGate({
    super.key,
    required this.userId,
    required this.email,
  });

  @override
  State<AdminInvitationGate> createState() => _AdminInvitationGateState();
}

class _AdminInvitationGateState extends State<AdminInvitationGate> {
  final _supabase = Supabase.instance.client;

  late Future<Map<String, dynamic>?> _invitationFuture;
  late Future<Map<String, dynamic>> _accountFuture;

  @override
  void initState() {
    super.initState();
    _invitationFuture = _loadInvitation();
    _accountFuture = _loadAccount();
  }

  Future<Map<String, dynamic>> _loadAccount() async {
    if (_supabase.auth.currentUser?.id != widget.userId) {
      throw StateError('The signed-in account has changed.');
    }

    final account = await _supabase
        .from('users')
        .select('role, status')
        .eq('user_id', widget.userId)
        .single();

    if (_supabase.auth.currentUser?.id != widget.userId) {
      throw StateError('The signed-in account has changed.');
    }

    return Map<String, dynamic>.from(account);
  }

  Future<Map<String, dynamic>?> _loadInvitation() async {
    try {
      if (_supabase.auth.currentUser?.id != widget.userId) {
        throw StateError('The signed-in account has changed.');
      }

      final data = await _supabase.rpc('get_my_admin_invitation');

      if (_supabase.auth.currentUser?.id != widget.userId) {
        throw StateError('The signed-in account has changed.');
      }

      if (data == null) return null;

      if (data is! Map ||
          data['invitationId'] is! String ||
          data['status'] is! String) {
        throw const FormatException('Unexpected invitation response.');
      }

      return Map<String, dynamic>.from(data);
    } catch (error) {
      debugPrint('Admin invitation lookup failed: $error');
      rethrow;
    }
  }

  void _reload() {
    if (!mounted) return;

    setState(() {
      _invitationFuture = _loadInvitation();
      _accountFuture = _loadAccount();
    });
  }

  Widget _signedInPage() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _accountFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return _statusPage('Unable to load your account. Please retry.');
        }

        final account = snapshot.data!;
        if (account['role'] == 'administrator') {
          if (account['status'] != 'active') {
            return _statusPage(
              'This administrator account is not active. Contact the '
              'Superadmin for help.',
            );
          }
          return AdminDashboardPage(email: widget.email);
        }

        return HomePage(email: widget.email);
      },
    );
  }

  Future<void> _signOut() async {
    try {
      await _supabase.auth.signOut(
        scope: SignOutScope.local,
        // Other options: global, others.
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to sign out. Please retry.')),
      );
    }
  }

  Widget _statusPage(String message) {
    return Scaffold(
      body: AuthLayout(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _reload, child: const Text('Retry')),
            TextButton(onPressed: _signOut, child: const Text('Sign out')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _invitationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return _statusPage('Unable to check your invitation. Please retry.');
        }

        final invitation = snapshot.data;

        if (invitation?['status'] == 'preparing') {
          return _statusPage(
            'Your invitation is still being prepared. '
            'Try again shortly. If this continues, '
            'ask the inviter to retry the original request.',
          );
        }

        if (invitation?['status'] == 'pending') {
          return AcceptAdminInvitationPage(
            key: ValueKey(
              '${widget.userId}:'
              '${invitation!['invitationId']}',
            ),
            userId: widget.userId,
            invitation: invitation,
            onAccepted: _reload,
            onSignOut: _signOut,
          );
        }

        // Invitation acceptance and administrator role are checked separately.
        // An email link by itself never grants administrator access.
        return _signedInPage();
      },
    );
  }
}
