import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/widgets/app_workspace.dart';
import 'payment_simulation_gateway.dart';

class PaymentRecipientSettings extends StatefulWidget {
  const PaymentRecipientSettings({super.key, required this.gateway});
  final PaymentSimulationGateway gateway;

  @override
  State<PaymentRecipientSettings> createState() =>
      _PaymentRecipientSettingsState();
}

class _PaymentRecipientSettingsState extends State<PaymentRecipientSettings> {
  late String? _actor = widget.gateway.actor;
  late Future<List<SimulationRecipient>> _rows = _load();
  late final StreamSubscription<String?> _subscription;
  bool _editing = false;

  Future<List<SimulationRecipient>> _load() async =>
      _actor == null ? [] : widget.gateway.recipients(_actor!);

  @override
  void initState() {
    super.initState();
    _subscription = widget.gateway.accountChanges.listen((actor) {
      if (mounted && actor != _actor) {
        setState(() {
          _actor = actor;
          _rows = _load();
        });
      }
    });
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  Future<void> _edit(
    SimulationMethod method,
    SimulationRecipient? saved,
  ) async {
    final actor = _actor;
    if (actor == null || _editing || widget.gateway.actor != actor) return;
    setState(() => _editing = true);
    try {
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RecipientEditor(
          actor: actor,
          gateway: widget.gateway,
          method: method,
          saved: saved,
        ),
      );
      if (changed == true && mounted && _actor == actor) {
        setState(() => _rows = _load());
      }
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) => WorkspaceCard(
    title: 'Payment Details',
    subtitle: 'Payment destination details shown only in authorized checkout and receipt views.',
    child: FutureBuilder<List<SimulationRecipient>>(
      key: ValueKey(_actor),
      future: _rows,
      builder: (context, snapshot) {
        if (_actor == null || _actor != widget.gateway.actor) {
          return const Text('Sign in to manage payment details.');
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const LinearProgressIndicator();
        }
        if (snapshot.hasError) {
          return Column(
            children: [
              const Text('Could not load payment details.'),
              TextButton(
                onPressed: () => setState(() => _rows = _load()),
                child: const Text('Retry'),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final method in SimulationMethod.values)
              Builder(
                builder: (context) {
                  final saved = snapshot.data
                      ?.where((row) => row.method == method)
                      .singleOrNull;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(method.label),
                    subtitle: Text(
                      saved == null
                          ? 'No details saved'
                          : [saved.name, ?saved.bank, saved.masked].join(' · '),
                    ),
                    trailing: TextButton(
                      onPressed: _editing ? null : () => _edit(method, saved),
                      child: Text(saved == null ? 'Add' : 'Update'),
                    ),
                  );
                },
              ),
          ],
        );
      },
    ),
  );
}

class _RecipientEditor extends StatefulWidget {
  const _RecipientEditor({
    required this.actor,
    required this.gateway,
    required this.method,
    this.saved,
  });
  final String actor;
  final PaymentSimulationGateway gateway;
  final SimulationMethod method;
  final SimulationRecipient? saved;

  @override
  State<_RecipientEditor> createState() => _RecipientEditorState();
}

class _RecipientEditorState extends State<_RecipientEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.saved?.name);
  late final _bank = TextEditingController(text: widget.saved?.bank);
  final _identifier = TextEditingController();
  late final StreamSubscription<String?> _subscription;
  bool _busy = false;
  bool _invalidated = false;
  String? _error;

  bool get _isBank => widget.method == SimulationMethod.bank;
  bool get _allowed => !_invalidated && widget.gateway.actor == widget.actor;

  @override
  void initState() {
    super.initState();
    _subscription = widget.gateway.accountChanges.listen((actor) {
      if (!mounted || actor == widget.actor) return;
      _name.clear();
      _bank.clear();
      _identifier.clear();
      setState(() => _invalidated = true);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _name.dispose();
    _bank.dispose();
    _identifier.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_allowed || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.gateway.save(
        widget.actor,
        widget.method,
        _name.text.trim(),
        _isBank ? _bank.text.trim() : null,
        _identifier.text.trim(),
      );
      if (mounted && _allowed) Navigator.pop(context, true);
    } catch (_) {
      if (mounted && _allowed) {
        setState(
          () => _error =
              'Could not save payment details. Check the fields and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy || !_allowed,
    child: AlertDialog(
      title: Text(widget.method.label),
      scrollable: true,
      content: !_allowed
          ? const Text('Session changed. Close this dialog to continue.')
          : Form(
              key: _form,
              child: SizedBox(
                width: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isBank)
                      TextFormField(
                        controller: _bank,
                        enabled: !_busy,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'Bank name',
                        ),
                        validator: _required,
                      ),
                    TextFormField(
                      controller: _name,
                      enabled: !_busy,
                      maxLength: 120,
                      decoration: InputDecoration(
                        labelText: _isBank
                            ? 'Account holder name'
                            : 'Registered recipient name',
                      ),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: _identifier,
                      enabled: !_busy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.phone,
                      maxLength: _isBank ? 34 : 16,
                      decoration: InputDecoration(
                        labelText: _isBank
                            ? 'Account number'
                            : 'Registered mobile number',
                        helperText: widget.saved == null
                            ? null
                            : 'Enter the complete number to update.',
                      ),
                      validator: (value) {
                        final pattern = _isBank
                            ? RegExp(r'^[0-9]{6,34}$')
                            : RegExp(r'^\+?[0-9]{8,15}$');
                        return pattern.hasMatch(value?.trim() ?? '')
                            ? null
                            : 'Enter a valid number.';
                      },
                    ),
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null) Text(_error!),
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: _busy && _allowed ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (_allowed)
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save details'),
          ),
      ],
    ),
  );
}
