import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/auth_layout.dart';
import '../../shared/widgets/auth_style.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/mobile_back_action.dart';
import '../../shared/navigation/app_routes.dart';

class ChangePasswordPage extends StatefulWidget {
  final String expectedUserId;

  const ChangePasswordPage({super.key, required this.expectedUserId});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  static const _allowedPasswordSymbols =
      r"""!@#$%^&*()_+-=[]{};':"\|<>?,./`~""";
  final _auth = Supabase.instance.client.auth;

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isBusy = false;
  bool _passwordChanged = false;

  Map<String, bool> _passwordRequirements(String password) => {
    'At least 8 characters': password.length >= 8,
    'One uppercase letter': RegExp(r'[A-Z]').hasMatch(password),
    'One lowercase letter': RegExp(r'[a-z]').hasMatch(password),
    'One number': RegExp(r'[0-9]').hasMatch(password),
    'One symbol': password.split('').any(_allowedPasswordSymbols.contains),
  };

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

      final requirements = _passwordRequirements(password);
      if (requirements.values.any((met) => !met)) {
        _showMessage('Meet all password strength requirements.');
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

      context.go(AppRoutes.home);

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
          appBar: ResponsivePageAppBar(
            enabled: !_isBusy && !_passwordChanged,
            showWebDashboardLink: false,
            showSessionActions: false,
            hasUnsavedChanges: () =>
                _passwordController.text.isNotEmpty ||
                _confirmController.text.isNotEmpty,
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
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'New password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  _passwordStrengthIndicator(_passwordController.text),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _confirmController,
                    enabled: !_isBusy,
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_confirmController.text.isNotEmpty &&
                      _confirmController.text != _passwordController.text)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Passwords do not match yet.',
                          style: TextStyle(color: AuthStyle.error),
                        ),
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

  Widget _passwordStrengthIndicator(String password) {
    final requirements = _passwordRequirements(password);
    final passed = requirements.values.where((met) => met).length;
    final label = switch (passed) {
      0 || 1 => 'Weak',
      2 || 3 => 'Fair',
      4 => 'Good',
      _ => 'Strong',
    };
    final color = passed == requirements.length
        ? AuthStyle.success
        : passed <= 1
        ? AuthStyle.error
        : Colors.orange.shade700;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: passed / requirements.length,
            color: color,
            backgroundColor: AuthStyle.border,
            minHeight: 5,
          ),
          const SizedBox(height: 5),
          Text('Password strength: $label', style: TextStyle(color: color)),
          for (final entry in requirements.entries)
            Text(
              '${entry.value ? '✓' : '○'} ${entry.key}',
              style: TextStyle(
                color: entry.value ? AuthStyle.success : AuthStyle.body,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}
