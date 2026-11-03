import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/auth_layout.dart';
import '../../shared/widgets/auth_style.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/mobile_back_action.dart';
import '../../shared/navigation/app_routes.dart';

class VerifyPasswordPage extends StatefulWidget {
  final bool isForgorPassword;
  final String initialEmail;

  const VerifyPasswordPage({
    super.key,
    this.isForgorPassword = false,
    this.initialEmail = '',
  });

  @override
  State<VerifyPasswordPage> createState() => _VerifyPasswordPageState();
}

class _VerifyPasswordPageState extends State<VerifyPasswordPage> {
  final _auth = Supabase.instance.client.auth;
  final _user = Supabase.instance.client.auth.currentUser;

  final _initialUser = Supabase.instance.client.auth.currentUser;

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();

  bool _isBusy = false;
  bool _codeSent = false;
  bool _showOtp = false;

  String? _sentToEmail;
  DateTime? _lastSendAt;
  String _loadingMessage = 'Please Wait...';

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail.trim();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_isBusy) return;

    final email = widget.isForgorPassword
        ? _emailController.text.trim()
        : (_initialUser?.email ?? '');

    if (email.isEmpty) {
      _showMessage('Please enter your email');
      return;
    }

    if (!widget.isForgorPassword) {
      if (_initialUser == null || _auth.currentUser?.id != _initialUser.id) {
        _showMessage('Please log in again');
        return;
      }
    }

    final lastSendAt = _lastSendAt;

    if (lastSendAt != null) {
      final elapsed = DateTime.now().difference(lastSendAt).inSeconds;

      if (elapsed < 60) {
        _showMessage('Please wait ${60 - elapsed} seconds.');
        return;
      }
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isBusy = true;
      _loadingMessage = 'Sending verification code...';
    });

    try {
      await _auth.resetPasswordForEmail(email);

      if (!mounted) return;

      _codeController.clear();

      setState(() {
        _sentToEmail = email;
        _codeSent = true;
        _lastSendAt = DateTime.now();
      });

      _showMessage(
        'If this email is registered, a verification code '
        'will be sent. Please check your inbox',
      );
    } on AuthException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Unable to send the code. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    if (_isBusy || !_codeSent) return;

    final email = _sentToEmail;
    final code = _codeController.text.trim();

    if (email == null) {
      _showMessage('Request a verification code first.');
      return;
    }

    if (code.isEmpty) {
      _showMessage('Enter the code from your email.');
      return;
    }

    if (!widget.isForgorPassword) {
      if (_initialUser == null || _auth.currentUser?.id != _initialUser.id) {
        _showMessage('Please log in again.');
        return;
      }
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isBusy = true;
      _loadingMessage = 'Verifying code....';
    });

    try {
      final response = await _auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.recovery,
      );

      final session = response.session;

      if (session == null) {
        throw const AuthException('Unable to verify this account.');
      }

      if (!widget.isForgorPassword && session.user.id != _initialUser?.id) {
        throw const AuthException('The verified account does not match.');
      }

      if (!mounted) return;

      context.pushReplacement(AppRoutes.changePassword);
    } on AuthException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Unable to verify the code. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  void _changeEmail() {
    if (_isBusy) return;

    _codeController.clear();

    setState(() {
      _codeSent = false;
      _sentToEmail = null;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildForgotPassword() {
    return LoadingOverlay(
      isLoading: _isBusy,
      message: _loadingMessage,
      child: Scaffold(
        body: AuthLayout(
          branded: true,
          showMobileBackButton: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_codeSent) ...[
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 56,
                  color: AuthStyle.success,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Check your email',
                  style: AuthStyle.title,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'If $_sentToEmail is registered, password recovery instructions have been sent. Check your inbox and spam folder.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: _isBusy ? null : _sendCode,
                  child: const Text('Resend link'),
                ),
                TextButton(
                  onPressed: _isBusy
                      ? null
                      : () => setState(() => _showOtp = true),
                  child: const Text('Enter verification code'),
                ),
                TextButton(
                  onPressed: _isBusy ? null : _changeEmail,
                  child: const Text('Use another email'),
                ),
              ] else ...[
                const Text('Forgot password?', style: AuthStyle.title),
                const SizedBox(height: 8),
                const Text(
                  'Enter your email to receive password recovery instructions.',
                ),
                const SizedBox(height: 32),
                AuthField(
                  label: 'Email',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _isBusy ? null : _sendCode,
                  child: const Text('Send Reset Link'),
                ),
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isBusy ? null : () => context.go(AppRoutes.home),
                child: const Text('Back to login'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isForgorPassword && !_showOtp) return _buildForgotPassword();
    return LoadingOverlay(
      isLoading: _isBusy,
      message: _loadingMessage,
      child: Scaffold(
        appBar: ResponsivePageAppBar(
          enabled: !_isBusy,
          hasUnsavedChanges: () => _codeController.text.isNotEmpty,
          fallback: widget.isForgorPassword
              ? AppRoutes.home
              : AppRoutes.profile,
          returnLabel: widget.isForgorPassword ? 'Sign in' : 'My profile',
          title: Text(
            widget.isForgorPassword ? 'Forgot Password' : 'Verify Your Email',
          ),
        ),
        body: AuthLayout(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.isForgorPassword
                    ? 'Reset your password'
                    : 'Verify before changing your password',
                style: TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 16),

              if (widget.isForgorPassword) ...[
                TextField(
                  controller: _emailController,
                  enabled: !_isBusy && !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Registered email',
                    border: OutlineInputBorder(),
                  ),
                ),

                if (_codeSent)
                  TextButton(
                    onPressed: _isBusy ? null : _changeEmail,
                    child: const Text('Use another email'),
                  ),
              ] else
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
                const SizedBox(height: 24),
                TextField(
                  controller: _codeController,
                  enabled: !_isBusy,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Verification code',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isBusy ? null : _verifyCode,
                  child: const Text('Verify and continue'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
