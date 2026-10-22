import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';

import '../../shared/widgets/auth_layout.dart';
import '../../shared/widgets/loading_overlay.dart';

class VerifyEmailPage extends StatefulWidget {
  final String email;
  final bool startWithCooldown;

  const VerifyEmailPage({
    super.key,
    required this.email,
    this.startWithCooldown = true,
  });

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  final _codeController = TextEditingController();

  Timer? _cooldownTimer;

  bool _isLoading = false;
  int _secondsRemaining = 0;
  String _loadingMessage = 'Verifying email...';

  @override
  void initState() {
    super.initState();
    if (widget.startWithCooldown) {
      _secondsRemaining = 60;
      _startCountdown();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isLoading,
      message: _loadingMessage,
      child: Scaffold(
        appBar: AppBar(title: const Text('Verify Email')),
        body: AuthLayout(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Check Your Email', style: TextStyle(fontSize: 24)),
              const SizedBox(height: 16),
              Text('Enter the confirmation code for ${widget.email}.'
              'You can request a new code below if you did not receive the email.'),
              const SizedBox(height: 24),
              TextField(
                controller: _codeController,
                enabled: !_isLoading,
                decoration: const InputDecoration(
                  labelText: 'Email verification code',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [
                  AutofillHints.oneTimeCode,
                ],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _verifyCode,
                child: const Text('Verify Email'),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _isLoading || _secondsRemaining > 0 ? null : _resendCode, child: Text(_secondsRemaining > 0 ? 'Resend in ${_secondsRemaining}s' : 'Resend code',))
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _verifyCode() async {
    if(_isLoading) return;

    final code = _codeController.text.trim();

    if(code.isEmpty){
      _showMessage('Please enter the code from your email.');
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Verifying email...' ;
    });

    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        email: widget.email, 
        token: code,
        type: OtpType.email
        );

      if(!mounted) return;

      if(response.session == null){
        _showMessage('No session returned. Plases try logging in.');
        return;
      }

      Navigator.of(context).popUntil(
        (route) => route.isFirst,
      );
    } on AuthException catch (error){
      _showMessage(error.message);
    } catch(_) {
      _showMessage('Unable to verify the code. Please try again.');
    } finally {
      if (mounted){
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

    Future<void> _resendCode() async {
      if(_isLoading || _secondsRemaining > 0 ) return;

      setState(() {
        _isLoading = true;
        _loadingMessage = 'Requesting a new code...';
      });

      try{
        await Supabase.instance.client.auth.resend(
          email: widget.email,
          type: OtpType.signup,
        );
      
        if(!mounted) return;

        _codeController.clear();

        setState(() {
          _secondsRemaining = 60;
        });

        _startCountdown();
        _showMessage('Check your email for a new code.');
      } on AuthException catch (error){
        _showMessage(error.message);
      } catch(_) {
        _showMessage('Unable to resend the code. Please try again.');
      } finally {
        if(mounted){
            setState(() {
            _isLoading = false;
          });
        }
      }
    }

      void _startCountdown(){
      _cooldownTimer?.cancel();

      _cooldownTimer = Timer.periodic(
        const Duration(seconds:1),
        (timer){
          if(!mounted) {
            timer.cancel();
            return;
          }

          setState(() {
            _secondsRemaining--;
          });

          if(_secondsRemaining <= 0){
            timer.cancel();
          }
        }
      );
    }

    void _showMessage(String message){
      if(!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
}

