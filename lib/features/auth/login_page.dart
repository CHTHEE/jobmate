import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sign_up_page.dart';
import '../profile/verify_password_page.dart';
import '../../shared/widgets/auth_layout.dart';
import '../../shared/widgets/auth_style.dart';
import '../../shared/widgets/loading_overlay.dart';
import 'verify_email_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isLoading,
      message: 'Logging in...',
      child: Scaffold(
        body: AuthLayout(
          branded: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Welcome back', style: AuthStyle.title),
              const SizedBox(height: 8),
              const Text('Sign in to your JobMate account.'),
              const SizedBox(height: 32),
              AuthField(
                label: 'Email',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
              ),
              AuthField(
                label: 'Password',
                controller: _passwordController,
                password: true,
                autofillHints: const [AutofillHints.password],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) => VerifyPasswordPage(
                                isForgorPassword: true,
                                initialEmail: _emailController.text.trim(),
                              ),
                            ),
                          );
                        },
                  child: const Text('Forgot Password?'),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isLoading ? null : _handleLogin,
                child: Text(_isLoading ? 'Signing in...' : 'Sign In'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => const SignUpPage(),
                          ),
                        );
                      },
                child: const Text('Don\'t have an account? Sign up'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Please enter both email and password.');
      return;
    }
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.session != null) {
        _showMessage('Login successful.');
      } else {
        _showMessage('No session was returned. Please try again.');
      }
    } on AuthException catch (error) {
      if (error.code == 'email_not_confirmed') {
        if (!mounted) return;

        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) =>
                VerifyEmailPage(email: email, startWithCooldown: false),
          ),
        );
      } else {
        _showMessage(error.message);
      }
    } catch (_) {
      _showMessage('Unable to log in. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
