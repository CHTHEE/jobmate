import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_page.dart';
import '../admin/admin_invitation_gate.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = Supabase.instance.client.auth;

  late final Stream<AuthState> _authChanges;

  @override
  void initState() {
    super.initState();
    _authChanges = _auth.onAuthStateChange;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authChanges,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        _auth.currentSession,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text(
                'Unable to update authentication status. '
                'Check your connection and restart the app.',
              ),
            ),
          );
        }

        final session = snapshot.data?.session;

        if (session == null) {
          return const LoginPage();
        }

        return AdminInvitationGate(
          key: ValueKey(session.user.id),
          userId: session.user.id,
          email: session.user.email ?? 'No email available',
        );
      },
    );
  }
}
