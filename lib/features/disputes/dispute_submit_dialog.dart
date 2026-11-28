import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dispute_gateway.dart';
import 'dispute_presentation.dart';
import 'dispute_submission_context.dart';

Future<String?> showDisputeSubmitDialog(
  BuildContext context, {
  required DisputeGateway gateway,
  DisputeSubmissionContext? submissionContext,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => DisputeSubmitDialog(
    gateway: gateway,
    submissionContext: submissionContext,
  ),
);

class DisputeSubmitDialog extends StatefulWidget {
  const DisputeSubmitDialog({
    super.key,
    required this.gateway,
    this.submissionContext,
  });

  final DisputeGateway gateway;
  final DisputeSubmissionContext? submissionContext;

  @override
  State<DisputeSubmitDialog> createState() => _DisputeSubmitDialogState();
}

class _DisputeSubmitDialogState extends State<DisputeSubmitDialog> {
  static const pageSize = 20;
  final description = TextEditingController();
  late String category = widget.submissionContext?.category ?? 'recruitment';
  late String? relatedId = widget.submissionContext?.relatedId;
  List<Map<String, dynamic>> records = [];
  int offset = 0;
  late bool loading = widget.submissionContext == null;
  bool saving = false, hasMore = false;
  String? error;
  bool _confirmingDiscard = false;
  bool _sessionEnded = false;
  StreamSubscription<AuthState>? _authSubscription;

  bool get contextual => widget.submissionContext != null;

  @override
  void initState() {
    super.initState();
    if (widget.gateway case final SupabaseDisputeGateway source) {
      final actor = source.client.auth.currentUser?.id;
      _authSubscription = source.client.auth.onAuthStateChange.listen((event) {
        if (!mounted || event.session?.user.id == actor) return;
        description.clear();
        setState(() {
          _sessionEnded = true;
          saving = false;
        });
      });
    }
    if (!contextual) _load();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
      relatedId = null;
      records = [];
      hasMore = false;
    });
    try {
      final result = await widget.gateway.eligible(
        category,
        limit: pageSize + 1,
        offset: offset,
      );
      if (!mounted) return;
      setState(() {
        records = result.take(pageSize).toList();
        hasMore = result.length > pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to load eligible records.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _label(Map<String, dynamic> row) =>
      '${row['job_title']} - ${row['company_name']} - '
      '${disputeDateTime(row['related_at'])} - ${row['related_status']}';

  String _submitError(Object value) {
    if (value is PostgrestException) {
      if (value.code == '23505' ||
          value.message.toLowerCase().contains('active dispute')) {
        return 'An active dispute already exists for this record and category.';
      }
      if (const {'42501', '28000'}.contains(value.code)) {
        return 'You are not authorized to submit a dispute for this record.';
      }
    }
    if (value is StateError) {
      return 'Your account changed. Close this form and sign in again.';
    }
    return 'Unable to submit this dispute. Check the details and try again.';
  }

  Future<void> _submit() async {
    if (saving || _sessionEnded) return;
    final text = description.text.trim();
    if (relatedId == null || text.isEmpty) {
      setState(
        () => error = 'Choose a related record and describe the dispute.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final id = await widget.gateway.submit(category, relatedId!, text);
      if (mounted && !_sessionEnded) Navigator.pop(context, id);
    } catch (value) {
      if (mounted && !_sessionEnded) {
        setState(() {
          saving = false;
          error = _submitError(value);
        });
      }
    }
  }

  Widget _contextSummary(BuildContext context) {
    final data = widget.submissionContext!;
    final values = <String>[
      data.jobTitle,
      if (data.companyName?.trim().isNotEmpty == true) data.companyName!,
      if (data.workerName?.trim().isNotEmpty == true)
        'Worker: ${data.workerName}',
      if (data.recordLabel?.trim().isNotEmpty == true) data.recordLabel!,
    ];
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              disputeCategoryLabel(category),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            for (final value in values) Text(value),
            const SizedBox(height: 6),
            Text(
              'This dispute will be linked to this exact record.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _form(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (contextual)
        _contextSummary(context)
      else ...[
        DropdownButtonFormField<String>(
          initialValue: category,
          decoration: const InputDecoration(labelText: 'Dispute type'),
          items: const [
            DropdownMenuItem(
              value: 'recruitment',
              child: Text('Recruitment dispute'),
            ),
            DropdownMenuItem(
              value: 'work',
              child: Text('Work and attendance dispute'),
            ),
            DropdownMenuItem(value: 'payment', child: Text('Payment dispute')),
          ],
          onChanged: saving || loading
              ? null
              : (value) {
                  category = value!;
                  offset = 0;
                  _load();
                },
        ),
        const SizedBox(height: 12),
        if (loading)
          const LinearProgressIndicator()
        else if (records.isEmpty && error != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(onPressed: _load, child: const Text('Retry')),
          )
        else if (records.isEmpty)
          const Text('No eligible records on this page.')
        else
          DropdownButtonFormField<String>(
            initialValue: relatedId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: category == 'recruitment'
                  ? 'Job application'
                  : 'Work assignment',
            ),
            items: [
              for (final row in records)
                DropdownMenuItem(
                  value: row['related_id'] as String,
                  child: Text(_label(row), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: saving
                ? null
                : (value) => setState(() => relatedId = value),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: loading || saving || offset == 0
                  ? null
                  : () {
                      offset -= pageSize;
                      _load();
                    },
              child: const Text('Previous'),
            ),
            TextButton(
              onPressed: loading || saving || !hasMore
                  ? null
                  : () {
                      offset += pageSize;
                      _load();
                    },
              child: const Text('Next'),
            ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: description,
        enabled: !saving,
        minLines: 4,
        maxLines: 7,
        maxLength: 4000,
        textInputAction: TextInputAction.newline,
        decoration: const InputDecoration(
          labelText: 'Describe the dispute',
          hintText: 'Explain what happened and the outcome you are seeking.',
          alignLabelWithHint: true,
        ),
      ),
      if (error != null)
        Semantics(
          liveRegion: true,
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );

  List<Widget> _actions(BuildContext context) => [
    TextButton(onPressed: saving ? null : _cancel, child: const Text('Cancel')),
    FilledButton.icon(
      onPressed: saving || loading || (!contextual && records.isEmpty)
          ? null
          : _submit,
      icon: saving
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.send_outlined),
      label: Text(saving ? 'Submitting...' : 'Submit dispute'),
    ),
  ];

  @override
  Widget build(BuildContext context) => PopScope<String>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _cancel();
    },
    child: _dialog(context),
  );

  Future<void> _cancel() async {
    if (saving || _confirmingDiscard) return;
    if (description.text.trim().isNotEmpty) {
      _confirmingDiscard = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard this dispute draft?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      _confirmingDiscard = false;
      if (!mounted || discard != true) return;
    }
    Navigator.pop(context);
  }

  Widget _dialog(BuildContext context) {
    if (_sessionEnded) {
      return AlertDialog(
        title: const Text('Account changed'),
        content: const Text('Close this form and reopen it from your account.'),
        actions: [TextButton(onPressed: _cancel, child: const Text('Close'))],
      );
    }
    final compact = MediaQuery.sizeOf(context).width < 600;
    if (compact) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('Submit dispute'),
            actions: [
              IconButton(
                tooltip: 'Close',
                onPressed: saving ? null : _cancel,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _form(context),
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.end,
                children: _actions(context),
              ),
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      title: const Text('Submit dispute'),
      content: SizedBox(
        width: 660,
        child: SingleChildScrollView(child: _form(context)),
      ),
      actions: _actions(context),
    );
  }
}
