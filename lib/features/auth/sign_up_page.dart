import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/auth_layout.dart';
import '../../shared/widgets/auth_style.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/mobile_back_action.dart';
import '../../shared/navigation/app_routes.dart';
import 'terms_privacy_page.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  static const _allowedPasswordSymbols =
      r"""!@#$%^&*()_+-=[]{};':"\|<>?,./`~""";

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _acceptedTerms = false;
  String _selectedRole = 'job_seeker';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final passwordRequirements = _passwordRequirements(password);
    final strength = passwordRequirements.values.where((met) => met).length;
    return LoadingOverlay(
      isLoading: _isLoading,
      message: 'Signing up...',
      child: Scaffold(
        body: AuthLayout(
          branded: true,
          showMobileBackButton: true,
          contentMaxWidth: 820,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Create your account', style: AuthStyle.title),
              const SizedBox(height: 8),
              const Text(
                'Choose an account type and enter the details you will use to sign in.',
              ),
              const SizedBox(height: 24),
              _sectionHeading(
                icon: Icons.person_outline,
                title: 'Account type',
                subtitle: 'Choose the option that best describes you.',
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final jobSeekerCard = _accountTypeCard(
                    value: 'job_seeker',
                    title: 'Job Seeker',
                    description: 'Find and apply for available jobs.',
                    icon: Icons.search_rounded,
                  );
                  final employerCard = _accountTypeCard(
                    value: 'employer',
                    title: 'Employer',
                    description: 'Register and manage one Company.',
                    icon: Icons.business_outlined,
                  );

                  if (constraints.maxWidth < 700) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        jobSeekerCard,
                        const SizedBox(height: 10),
                        employerCard,
                      ],
                    );
                  }

                  return Row(
                    // This Row is inside a vertical scroll view, so its height
                    // is unbounded. Stretch would try to fill infinite height.
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: jobSeekerCard),
                      const SizedBox(width: 12),
                      Expanded(child: employerCard),
                    ],
                  );
                },
              ),
              if (_selectedRole == 'employer') ...[
                const SizedBox(height: 12),
                _buildEmployerNotice(),
              ],
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              _sectionHeading(
                icon: Icons.account_circle_outlined,
                title: 'Your account details',
                subtitle: 'Use these details to sign in to JobMate.',
              ),
              const SizedBox(height: 16),
              AuthField(
                label: 'Full name',
                hintText: 'Enter your name',
                controller: _nameController,
                keyboardType: TextInputType.name,
                maxLength: 100,
                showCounter: false,
                autofillHints: const [AutofillHints.name],
              ),
              AuthField(
                label: 'Email address',
                hintText: 'you@example.com',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
              AuthField(
                label: 'Password',
                hintText: 'Create a password',
                controller: _passwordController,
                password: true,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) => setState(() {}),
              ),
              if (password.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Use at least 8 characters, including uppercase and '
                    'lowercase letters, a number, and a symbol.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              if (password.isNotEmpty) ...[
                _buildPasswordRequirements(passwordRequirements, strength),
                const SizedBox(height: 16),
              ],
              AuthField(
                label: 'Confirm password',
                hintText: 'Enter your password again',
                controller: _confirmPasswordController,
                password: true,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) => setState(() {}),
              ),
              if (confirmPassword.isNotEmpty && confirmPassword != password)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 18,
                        color: AuthStyle.error,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Passwords do not match yet.',
                          style: TextStyle(color: AuthStyle.error),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _acceptedTerms,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: _isLoading
                        ? null
                        : (value) {
                            setState(() => _acceptedTerms = value ?? false);
                          },
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 0,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('I agree to the'),
                          _policyLink('Terms of Service', PolicySection.terms),
                          const Text('and'),
                          _policyLink('Privacy Policy', PolicySection.privacy),
                          const Text('.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isLoading || !_acceptedTerms ? null : _handleSignUp,
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(
                  _isLoading ? 'Creating account...' : 'Create account',
                ),
              ),
              if (!_acceptedTerms) ...[
                const SizedBox(height: 8),
                Text(
                  'Please accept the Terms and Privacy Policy to continue.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => returnToPage(context, AppRoutes.home),
                child: const Text('Already have an account? Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeading({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AuthStyle.teal),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AuthStyle.heading,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _policyLink(String label, PolicySection section) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      onPressed: _isLoading
          ? null
          : () {
              context.push<void>(
                section == PolicySection.terms
                    ? AppRoutes.terms
                    : AppRoutes.privacy,
              );
            },
      child: Text(label),
    );
  }

  Widget _accountTypeCard({
    required String value,
    required String title,
    required String description,
    required IconData icon,
  }) {
    final selected = _selectedRole == value;
    final colors = Theme.of(context).colorScheme;

    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? AuthStyle.teal : AuthStyle.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: RadioListTile<String>(
        value: value,
        groupValue: _selectedRole,
        selected: selected,
        activeColor: AuthStyle.teal,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        secondary: Icon(
          icon,
          color: selected ? AuthStyle.teal : colors.outline,
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: AuthStyle.heading,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(description),
        onChanged: _isLoading
            ? null
            : (newValue) {
                if (newValue != null) {
                  setState(() => _selectedRole = newValue);
                }
              },
      ),
    );
  }

  Widget _buildEmployerNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'To create a Company, submit its details and a supporting '
                  'document after verifying your email. An administrator '
                  'will review the submission.',
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'Your account will be the permanent Company Owner. Ownership '
            'cannot be transferred to another Employer.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Map<String, bool> _passwordRequirements(String password) => {
    'At least 8 characters': password.length >= 8,
    'One uppercase letter (A–Z)': RegExp(r'[A-Z]').hasMatch(password),
    'One lowercase letter (a–z)': RegExp(r'[a-z]').hasMatch(password),
    'One number (0–9)': RegExp(r'[0-9]').hasMatch(password),
    'One symbol (for example ! or #)': password
        .split('')
        .any(_allowedPasswordSymbols.contains),
  };

  Widget _buildPasswordRequirements(
    Map<String, bool> requirements,
    int strength,
  ) {
    const strengthLabels = [
      'Very weak',
      'Weak',
      'Fair',
      'Good',
      'Strong',
      'Strong',
    ];
    final strengthLabel = strengthLabels[strength];
    final strengthColor = strength == requirements.length
        ? AuthStyle.success
        : strength <= 1
        ? AuthStyle.error
        : Colors.orange.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Password strength: $strengthLabel',
          child: LinearProgressIndicator(
            value: strength / requirements.length,
            color: strengthColor,
            backgroundColor: AuthStyle.border,
            minHeight: 5,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Password strength: $strengthLabel',
          style: TextStyle(
            color: strengthColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        for (final requirement in requirements.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  requirement.value
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: requirement.value
                      ? AuthStyle.success
                      : AuthStyle.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    requirement.key,
                    style: TextStyle(
                      fontSize: 12,
                      color: requirement.value
                          ? AuthStyle.success
                          : AuthStyle.body,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _handleSignUp() async {
    if (_isLoading) return;

    final name = _nameController.text.trim();
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
          content: Text('Please enter your email, password, and confirmation.'),
        ),
      );
      return;
    }

    final requirements = _passwordRequirements(password);

    if (requirements.values.any((met) => !met)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please meet all the password requirements shown.'),
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
        data: {'name': name, 'requested_role': _selectedRole},
      );

      if (!mounted) return;

      if (response.session != null) {
        context.go(AppRoutes.home);
      } else {
        AppRoutes.pendingAuthEmail = email;
        AppRoutes.pendingEmailCooldown = true;
        context.pushReplacement(AppRoutes.verifyEmail);
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
