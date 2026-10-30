import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/auth_layout.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/mobile_back_action.dart';

class ChangePasswordPage extends StatefulWidget {
  final String expectedUserId;

  const ChangePasswordPage({super.key, required this.expectedUserId});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _auth = Supabase.instance.client.auth;

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isBusy = false;
  bool _passwordChanged = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_isBusy) return;

    final password = _passwordController.text;
    final confirmation = _confirmController.text;

    if (!_passwordChanged) {
      if (_auth.currentSession == null ||
          _auth.currentUser?.id != widget.expectedUserId) {
        _showMessage('Your login has changed. Please verify again.');
        return;
      }

      if (password.length < 8) {
        _showMessage('Use a password with at least 8 characters.');
        return;
      }

      if (password != confirmation) {
        _showMessage('The passwords do not match.');
        return;
      }
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isBusy = true;
    });

    try {
      if (!_passwordChanged) {
        await _auth.updateUser(UserAttributes(password: password));

        _passwordChanged = true;

        if (mounted) {
          _passwordController.clear();
          _confirmController.clear();
        }
      }

      await _auth.signOut(
        scope: SignOutScope.global,
        // global: current session + all other sessions.
        // local: current session only.
        // others: other sessions; keep current session
      );

      if (!mounted) return;

      final message = ScaffoldMessenger.of(context);

      Navigator.of(context).popUntil((route) => route.isFirst);

      message.showSnackBar(
        const SnackBar(content: Text('Password change. Please log in again.')),
      );
    } on AuthException catch (error) {
      _showMessage(
        _passwordChanged
            ? 'Passowrd changed, but signing out failed.'
                  'Tap Retry sign-out.'
            : error.message,
      );
    } catch (_) {
      _showMessage(
        _passwordChanged
            ? 'Passowrd changed, but signing out failed.'
                  'Tap Retry sign-out.'
            : 'Unable to change your password. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isBusy && !_passwordChanged,
      child: LoadingOverlay(
        isLoading: _isBusy,
        message: _passwordChanged ? 'Signing out...' : 'Changing password...',
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: mobileBackLeading(context),
            title: const Text('Change Password'),
          ),
          body: AuthLayout(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_passwordChanged) ...[
                  const Text(
                    'Your password has changed.'
                    'Complete sign-out before continuing.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _isBusy ? null : _changePassword,
                    child: const Text('Retry sign-out'),
                  ),
                ] else ...[
                  const Text(
                    'Create a New password',
                    style: TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    enabled: !_isBusy,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _confirmController,
                    enabled: !_isBusy,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isBusy ? null : _changePassword,
                    child: const Text('Change password and sign out'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
