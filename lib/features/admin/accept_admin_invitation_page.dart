import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/auth_layout.dart';
import '../../shared/widgets/auth_style.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/mobile_back_action.dart';

class AcceptAdminInvitationPage extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> invitation;
  final VoidCallback onAccepted;
  final VoidCallback onSignOut;

  const AcceptAdminInvitationPage({
    super.key,
    required this.userId,
    required this.invitation,
    required this.onAccepted,
    required this.onSignOut,
  });

  @override
  State<AcceptAdminInvitationPage> createState() =>
      _AcceptAdminInvitationPageState();
}

class _AcceptAdminInvitationPageState extends State<AcceptAdminInvitationPage> {
  static const _allowedPasswordSymbols =
      r"""!@#$%^&*()_+-=[]{};':"\|<>?,./`~""";
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isBusy = false;
  bool _passwordReady = false;
  bool _accepted = false;

  String? _confirmedName;
  String? _errorMessage;

  Map<String, bool> _passwordRequirements(String password) => {
    'At least 8 characters': password.length >= 8,
    'One uppercase letter': RegExp(r'[A-Z]').hasMatch(password),
    'One lowercase letter': RegExp(r'[a-z]').hasMatch(password),
    'One number': RegExp(r'[0-9]').hasMatch(password),
    'One symbol': password.split('').any(_allowedPasswordSymbols.contains),
  };

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.invitation['name'] as String? ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _checkSession() {
    if (_supabase.auth.currentUser?.id != widget.userId) {
      throw StateError(
        'Your signed-in account has changed. '
        'Please sign in with the invited account.',
      );
    }
  }

  Future<void> _acceptInvitation() async {
    if (_isBusy || _accepted) return;

    if (!_passwordReady && !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    try {
      _checkSession();

      if (!_passwordReady) {
        final name = _nameController.text.trim();

        try {
          await _supabase.auth.updateUser(
            UserAttributes(password: _passwordController.text),
          );
        } on AuthException catch (error) {
          // 上次设置可能已成功，只是返回结果时断网。
          if (error.code != 'same_password') rethrow;
        }

        if (!mounted) return;

        _checkSession();

        setState(() {
          _confirmedName = name;
          _passwordReady = true;
          _passwordController.clear();
          _confirmController.clear();
        });
      }

      final result = await _supabase.rpc(
        'accept_admin_invitation',
        params: {
          'p_invitation_id': widget.invitation['invitationId'],
          'p_name': _confirmedName,
        },
      );

      if (!mounted) return;

      _checkSession();

      if (result is! Map || result['status'] != 'accepted') {
        throw const FormatException('Unexpected invitation response.');
      }

      setState(() {
        _accepted = true;
      });
    } on AuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.message;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.message;
      });
    } on StateError catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.message.toString();
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Unable to confirm the result. '
            'Please retry accepting the invitation.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isBusy,
      message: _passwordReady
          ? 'Accepting invitation...'
          : 'Setting up your account...',
      child: Scaffold(
        appBar: ResponsivePageAppBar(
          showReturnAction: false,
          title: const Text('Accept admin invitation'),
          actions: [
            TextButton(
              onPressed: _isBusy ? null : widget.onSignOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
        body: AuthLayout(
          child: _accepted
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Your administrator account is ready.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: widget.onAccepted,
                      child: const Text('Continue'),
                    ),
                  ],
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Complete your account',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(widget.invitation['email'] as String? ?? ''),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _nameController,
                        readOnly: _isBusy || _passwordReady,
                        maxLength: 100,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                        validator: (value) {
                          final name = value?.trim() ?? '';

                          if (name.isEmpty || name.runes.length > 100) {
                            return 'Enter a name of 1 to 100 characters.';
                          }

                          return null;
                        },
                      ),
                      if (!_passwordReady) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          readOnly: _isBusy,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (_passwordRequirements(value ?? '').values
                                .any((met) => !met)) {
                              return 'Meet all password strength requirements.';
                            }

                            return null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                        _passwordStrengthIndicator(_passwordController.text),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmController,
                          readOnly: _isBusy,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value != _passwordController.text) {
                              return 'The passwords do not match.';
                            }

                            return null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                        if (_confirmController.text.isNotEmpty &&
                            _confirmController.text != _passwordController.text)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Passwords do not match yet.',
                                style: TextStyle(color: AuthStyle.error),
                              ),
                            ),
                          ),
                      ] else ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Your password is set. '
                          'Retry continues the invitation acceptance.',
                        ),
                      ],
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _isBusy ? null : _acceptInvitation,
                        child: Text(
                          _passwordReady
                              ? 'Retry accepting invitation'
                              : 'Set password and accept',
                        ),
                      ),
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
