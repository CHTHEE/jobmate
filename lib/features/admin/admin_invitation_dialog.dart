import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../shared/widgets/loading_overlay.dart';
import 'admin_invitation_gateway.dart';

Future<void> showAdminInvitationDialog(
  BuildContext context, {
  AdminInvitationGateway? gateway,
}) => showDialog<void>(
  context: context,
  builder: (_) => _AdminInvitationDialog(gateway: gateway),
);

class _AdminInvitationDialog extends StatefulWidget {
  const _AdminInvitationDialog({this.gateway});

  final AdminInvitationGateway? gateway;

  @override
  State<_AdminInvitationDialog> createState() => _AdminInvitationDialogState();
}

class _AdminInvitationDialogState extends State<_AdminInvitationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _client = Supabase.instance.client;
  late final String? _actorId = _client.auth.currentUser?.id;
  Map<String, String>? _attempt;
  AdminInvitationReceipt? _receipt;
  String? _error;
  var _submitting = false;
  var _sessionChanged = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _checkSession() {
    if (_actorId == null || _client.auth.currentUser?.id != _actorId) {
      throw StateError(
        'Your signed-in account has changed. Close and sign in again.',
      );
    }
  }

  Future<void> _submit() async {
    if (_submitting || _receipt != null || _sessionChanged) return;
    if (_attempt == null && !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final attempt =
        _attempt ??
        Map<String, String>.unmodifiable({
          'id': const Uuid().v4(),
          'name': _name.text.trim(),
          'email': _email.text.trim().toLowerCase(),
        });
    setState(() {
      _attempt = attempt;
      _submitting = true;
      _error = null;
    });
    try {
      _checkSession();
      final receipt =
          await (widget.gateway ?? SupabaseAdminInvitationGateway(_client))
              .sendInvitation(
                invitationId: attempt['id']!,
                name: attempt['name']!,
                email: attempt['email']!,
              );
      if (!mounted) return;
      _checkSession();
      setState(() => _receipt = receipt);
    } on FunctionException catch (error) {
      if (!mounted) return;
      final details = error.details;
      final message = details is Map
          ? (details['error'] ?? 'Unable to send invitation.').toString()
          : 'Request failed (${error.status}).';
      setState(() {
        _error = message;
        if (error.status == 400 || error.status == 403 || error.status == 409) {
          _attempt = null;
        }
      });
    } on StateError catch (error) {
      if (mounted) {
        setState(() {
          _sessionChanged = true;
          _error = error.message.toString();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to confirm the result. Check your connection and retry the same invitation.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _startAnother() {
    setState(() {
      _attempt = null;
      _receipt = null;
      _error = null;
      _name.clear();
      _email.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: LoadingOverlay(
          isLoading: _submitting,
          message: 'Sending invitation...',
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: receipt == null
                ? Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Invite Administrator',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _name,
                          enabled:
                              !_submitting &&
                              !_sessionChanged &&
                              _attempt == null,
                          maxLength: 100,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                          ),
                          validator: (value) => (value?.trim().isEmpty ?? true)
                              ? 'Please enter a name.'
                              : (value!.runes.length > 100
                                    ? 'Name must not exceed 100 characters.'
                                    : null),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          enabled:
                              !_submitting &&
                              !_sessionChanged &&
                              _attempt == null,
                          maxLength: 254,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email Address',
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                        .hasMatch(email) &&
                                    email.length <= 254
                                ? null
                                : 'Please enter a valid email.';
                          },
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _submitting
                                  ? null
                                  : () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _submitting || _sessionChanged
                                  ? null
                                  : _submit,
                              child: Text(
                                _attempt == null
                                    ? 'Send Invitation'
                                    : 'Retry same invitation',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Invitation sent',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Invitation expires: ${receipt.expiresAt.toLocal().toString().split('.').first}',
                      ),
                      const SizedBox(height: 4),
                      SelectableText('Invitation ID: ${receipt.invitationId}'),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _startAnother,
                            child: const Text('Invite another'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
