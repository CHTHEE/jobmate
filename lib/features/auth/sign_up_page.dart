import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/auth_layout.dart';
import '../../shared/widgets/auth_style.dart';
import '../../shared/widgets/loading_overlay.dart';
import 'verify_email_page.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _nameCrontroller = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _nameCrontroller.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final password = _passwordController.text;
    final strength = [
      password.length >= 8,
      RegExp(r'[A-Z]').hasMatch(password),
      RegExp(r'[0-9]').hasMatch(password),
      RegExp(r'[^a-zA-Z0-9]').hasMatch(password),
    ].where((met) => met).length;
    return LoadingOverlay(
      isLoading: _isLoading,
      message: 'Signing up...',
      child: Scaffold(
        body: AuthLayout(
          branded: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Create your account', style: AuthStyle.title),
              const SizedBox(height: 8),
              const Text('Start your journey with JobMate.'),
              const SizedBox(height: 32),
              AuthField(
                label: 'Full Name',
                controller: _nameCrontroller,
                keyboardType: TextInputType.name,
                maxLength: 100,
                autofillHints: const [AutofillHints.name],
              ),
              AuthField(
                label: 'Email',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
              AuthField(
                label: 'Password',
                controller: _passwordController,
                password: true,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) => setState(() {}),
              ),
              if (password.isNotEmpty) ...[
                Semantics(
                  label:
                      'Password strength: ${['Very weak', 'Weak', 'Fair', 'Good', 'Strong'][strength]}',
                  child: LinearProgressIndicator(
                    value: strength / 4,
                    color: strength < 2 ? AuthStyle.error : AuthStyle.teal,
                    backgroundColor: AuthStyle.border,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Password strength: ${['Very weak', 'Weak', 'Fair', 'Good', 'Strong'][strength]}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
              ],
              AuthField(
                label: 'Confirm Password',
                controller: _confirmPasswordController,
                password: true,
                autofillHints: const [AutofillHints.newPassword],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _acceptedTerms,
                onChanged: _isLoading
                    ? null
                    : (value) =>
                          setState(() => _acceptedTerms = value ?? false),
                title: const Text(
                  'I agree to the Terms and Privacy Policy',
                  style: TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isLoading || !_acceptedTerms ? null : _handleSignUp,
                child: Text(_isLoading ? 'Signing up...' : 'Create Account'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Already have an account? Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSignUp() async {
    if (_isLoading) return;

    final name = _nameCrontroller.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (name.isEmpty) {
      _showMessage('Please enter your full name');
      return;
    }
    if (name.length > 100) {
      _showMessage('Full name must not exceed 100 characters');
      return;
    }

    if (email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill  in all email and password fields'),
        ),
      );
      return;
    }

    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 8 characters long'),
        ),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await Supabase.instance.client.auth.signUp(
        password: password,
        email: email,
        data: {'name': name},
      );

      if (!mounted) return;

      if (response.session != null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (context) => VerifyEmailPage(email: email),
          ),
        );
      }
    } on AuthException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('An error occurred. Please try again.');
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
