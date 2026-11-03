import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../shared/widgets/auth_layout.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/mobile_back_action.dart';

class InviteAdminPage extends StatefulWidget {
  const InviteAdminPage({super.key});

  @override
  State<InviteAdminPage> createState() => _InviteAdminPageState();
}

class _InviteAdminPageState extends State<InviteAdminPage> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  final _actorId = Supabase.instance.client.auth.currentUser?.id;

  Map<String, String>? _attempt;

  bool _isSending = false;
  bool _sent = false;
  bool _sessionChanged = false;

  String? _errorMessage;
  DateTime? _expiresAt;

  bool get _canEdit =>
      !_isSending && !_sent && !_sessionChanged && _attempt == null;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _checkSession() {
    final currentId = _supabase.auth.currentUser?.id;

    if (_actorId == null || currentId != _actorId) {
      throw StateError(
        'Your signed-in account has changed. '
        'Close this page and sign in again.',
      );
    }
  }

  Future<void> _sendInvitation() async {
    if (_isSending || _sent || _sessionChanged) return;

    // 只有第一次提交时，才从 Form 建立新的请求。
    if (_attempt == null) {
      final valid = _formKey.currentState?.validate() ?? false;

      if (!valid) return;
    }

    final attempt =
        _attempt ??
        Map<String, String>.unmodifiable({
          'id': const Uuid().v4(),
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim().toLowerCase(),
        });

    setState(() {
      _attempt = attempt;
      _isSending = true;
      _errorMessage = null;
    });

    try {
      _checkSession();

      final response = await _supabase.functions.invoke(
        'admin-invitations',
        body: {
          'action': 'send_invitation',
          'invitation_id': attempt['id'],
          'name': attempt['name'],
          'email': attempt['email'],
        },
      );

      if (!mounted) return;

      _checkSession();

      final data = response.data;

      if (data is! Map ||
          data['status'] != 'pending' ||
          data['invitationId'] != attempt['id']) {
        throw const FormatException('Unexpected server response.');
      }

      final expiresValue = data['expiresAt'];
      final expiresAt = expiresValue is String
          ? DateTime.tryParse(expiresValue)
          : null;

      if (expiresAt == null) {
        throw const FormatException('Invalid invitation expiry.');
      }

      setState(() {
        _sent = true;
        _expiresAt = expiresAt;
      });
    } on FunctionException catch (error) {
      if (!mounted) return;

      final details = error.details;
      final message = details is Map
          ? (details['error'] ?? 'Unable to send invitation.').toString()
          : 'Request failed (${error.status}).';

      setState(() {
        _errorMessage = message;

        // 对应当前 Backend 的明确拒绝结果：
        // 可以解除锁定，让用户修改资料。
        if (error.status == 400 || error.status == 403 || error.status == 409) {
          _attempt = null;
        }

        // 429、500 等情况保留原请求，供 Retry 使用。
      });
    } on StateError catch (error) {
      if (!mounted) return;

      setState(() {
        _sessionChanged = true;
        _errorMessage = error.message.toString();
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Unable to confirm the result. '
            'Check your connection and retry the same invitation.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _startAnotherInvitation() {
    if (_isSending || !_sent) return;

    setState(() {
      _attempt = null;
      _sent = false;
      _expiresAt = null;
      _errorMessage = null;
      _nameController.clear();
      _emailController.clear();
    });
  }

  Widget _buildSuccess() {
    final attempt = _attempt!;
    final localExpiry = _expiresAt!.toLocal();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.mark_email_read_outlined,
              size: 56,
              color: Colors.green,
            ),
            const SizedBox(height: 16),
            const Text(
              'Invitation sent',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text('Name: ${attempt['name']}'),
            const SizedBox(height: 8),
            Text('Email: ${attempt['email']}'),
            const SizedBox(height: 8),
            Text(
              'Invitation expires: '
              '${localExpiry.toString().split('.').first}',
            ),
            const SizedBox(height: 16),
            const Text(
              'The recipient must verify their email and accept '
              'the invitation before receiving administrator access.',
            ),
            const SizedBox(height: 16),
            SelectableText(
              'Invitation ID: ${attempt['id']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _startAnotherInvitation,
              child: const Text('Invite another person'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Invite an administrator',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Enter the name and email of someone who '
                'has not registered with JobMate.',
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                readOnly: !_canEdit,
                maxLength: 100,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';

                  if (name.isEmpty) {
                    return 'Please enter a name.';
                  }

                  if (name.runes.length > 100) {
                    return 'Name must not exceed 100 characters.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                readOnly: !_canEdit,
                maxLength: 254,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';

                  if (email.isEmpty) {
                    return 'Please enter an email.';
                  }

                  final validEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                      .hasMatch(email);

                  if (!validEmail || email.length > 254) {
                    return 'Please enter a valid email.';
                  }

                  return null;
                },
              ),
              if (_attempt != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'These details are locked while the request '
                  'result is uncertain. Retry continues the same invitation.',
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isSending || _sessionChanged
                    ? null
                    : _sendInvitation,
                icon: const Icon(Icons.send_outlined),
                label: Text(
                  _attempt == null
                      ? 'Send invitation'
                      : 'Retry same invitation',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isSending,
      message: 'Sending invitation...',
      child: Scaffold(
        appBar: ResponsivePageAppBar(
          enabled: !_isSending,
          hasUnsavedChanges: () =>
              !_sent &&
              (_nameController.text.isNotEmpty ||
                  _emailController.text.isNotEmpty),
          title: const Text('Admin invitation'),
        ),
        body: AuthLayout(child: _sent ? _buildSuccess() : _buildForm()),
      ),
    );
  }
}
