import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/auth_layout.dart';
import '../../shared/widgets/loading_overlay.dart';
import 'change_password_page.dart';

class VerifyPasswordPage extends StatefulWidget {
  final bool isForgorPassword;
  final String initialEmail;

  const VerifyPasswordPage({super.key, this.isForgorPassword = false, this.initialEmail = ''});

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

  String? _sentToEmail;
  DateTime? _lastSendAt;
  String _loadingMessage = 'Please Wait...';

  @override
  void initState(){
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

    final email = widget.isForgorPassword ? _emailController.text.trim() : (_initialUser?.email ?? '');

    if(email.isEmpty) {
      _showMessage('Please enter your email');
      return;
    }

    if(!widget.isForgorPassword){
      if(_initialUser == null || _auth.currentUser?.id != _initialUser.id) {
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

      _showMessage('If this email is registered, a verification code '
      'will be sent. Please check your inbox');
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

    if(!widget.isForgorPassword){
      if(_initialUser == null || _auth.currentUser?.id != _initialUser.id) {
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

      if(!widget.isForgorPassword && session.user.id != _initialUser?.id) {
        throw const AuthException('The verified account does not match.');
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => ChangePasswordPage(
            expectedUserId: session.user.id,
          ),
        ),
      );
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

  void _changeEmail(){
    if(_isBusy) return;

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

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isBusy,
      message: _loadingMessage,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.isForgorPassword ? 'Forgot Password' : 'Verify Your Email')),
        body: AuthLayout(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.isForgorPassword ? 'Reset your password' :
                'Verify before changing your password',
                style: TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 16),

              if(widget.isForgorPassword)...[
                TextField(
                  controller: _emailController,
                  enabled: !_isBusy && !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const[AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Registered email',
                    border: OutlineInputBorder(),
                  ),
                ),

                if(_codeSent)
                  TextButton(onPressed: _isBusy ? null : _changeEmail, child: const Text('Use another email'),),
              ]else 
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
