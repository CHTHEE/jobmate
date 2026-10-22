import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/loading_overlay.dart';
import '../profile/profile_page.dart';

class HomePage extends StatefulWidget {
  final String email;

  const HomePage({super.key, required this.email});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoadingOut = false;
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
            TextButton(
              onPressed: _isLoadingOut ? null : _handleLogout,
              child: const Text('Log out'),
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Welcome to JobMate!\n${widget.email}',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
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
