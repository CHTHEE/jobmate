import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/auth_layout.dart';
import '../../shared/widgets/loading_overlay.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _auth = Supabase.instance.client.auth;

  final _initialUser = Supabase.instance.client.auth.currentUser;

  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isBusy = false;
  bool _codeSent = false;
  bool _codeVerified = false;
  bool _passwordChanged = false;

  DateTime? _lastSendAt;

  String _loadingMessage = 'Please wait...';

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_isBusy || _passwordChanged) return;

    final email = _initialUser?.email;

    if (email == null || _auth.currentUser?.id != _initialUser?.id) {
      _showMessage('Please log in agian.');
      return;
    }

    final lastSendAt = _lastSendAt;

    if (lastSendAt != null) {
      final elapsed = DateTime.now().difference(lastSendAt).inSeconds;

      if (elapsed < 60) {
        _showMessage('Please wait ${60 - elapsed} seconds.');
        return;
      }
    }

    setState(() {
      _isBusy = true;
      _loadingMessage = 'Sending verification code...';
    });

    try {
      await _auth.resetPasswordForEmail(email);

      if (!mounted) return;

      setState(() {
        _codeSent = true;
        _codeVerified = false;
        _lastSendAt = DateTime.now();
      });

      _codeController.clear();
      _showMessage('Check your email for the code.');
    } on AuthException catch (error) {
      debugPrint(
        'Password email failed (${error.code}): '
        '${error.message}',
      );
    } catch (error) {
      debugPrint('Password email failed: $error');

      _showMessage('Unable to send the code. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _changePassword() async {
    if (_isBusy) return;

    final password = _passwordController.text;
    final confirmation = _confirmController.text;
    final code = _codeController.text.trim();

    if (!_passwordChanged) {
      if (!_codeSent) {
        _showMessage('Request a verification code first.');
        return;
      }

      if (!_codeVerified && code.isEmpty) {
        _showMessage('Enter the code from your email.');
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

      if (_auth.currentUser?.id != _initialUser?.id) {
        _showMessage('Please log in again.');
        return;
      }
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isBusy = true;
      _loadingMessage = _passwordChanged
          ? 'Signing out...'
          : 'Verifying and changing password...';
    });

    try {
      if (!_passwordChanged) {
        if (!_codeVerified) {
          final response = await _auth.verifyOTP(
            email: _initialUser!.email!,
            token: code,
            type: OtpType.recovery,
            // OtpType.email: email confirmation / email OTP.
            // OtpType.recovery: password recovery OTP.
          );

          if (response.session == null ||
              response.user?.id != _initialUser.id) {
            throw const AuthException('Unable to verify this account');
          }

          _codeVerified = true;
        }

        await _auth.updateUser(UserAttributes(password: password));

        _passwordChanged = true;

        if (mounted) {
          _codeController.clear();
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
        message: _loadingMessage,
        child: Scaffold(
          appBar: AppBar(title: const Text('Change Password')),
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
                  Text(
                    'Send a verification code to '
                    '${_initialUser?.email ?? 'your email'}.',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _isBusy ? null : _sendCode,
                    child: Text(_codeSent ? 'Resend code' : 'Send code'),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _codeController,
                      enabled: !_isBusy && !_codeVerified,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Verification code',
                        border: OutlineInputBorder(),
                      ),
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
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isBusy ? null : _changePassword,
                      child: const Text('Change password and sign out'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
