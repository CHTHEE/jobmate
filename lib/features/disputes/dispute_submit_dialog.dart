import 'package:flutter/material.dart';

import 'dispute_gateway.dart';

class DisputeSubmitDialog extends StatefulWidget {
  const DisputeSubmitDialog({super.key, required this.gateway});
  final DisputeGateway gateway;

  @override
  State<DisputeSubmitDialog> createState() => _DisputeSubmitDialogState();
}

class _DisputeSubmitDialogState extends State<DisputeSubmitDialog> {
  static const pageSize = 20;
  final description = TextEditingController();
  String category = 'recruitment';
  String? relatedId;
  List<Map<String, dynamic>> records = [];
  int offset = 0;
  bool loading = true, saving = false, hasMore = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
      relatedId = null;
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

  String _label(Map<String, dynamic> row) {
    final date = DateTime.tryParse(row['related_at']?.toString() ?? '');
    final dateText = date == null
        ? 'Date unavailable'
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '${row['job_title']} · ${row['company_name']} · $dateText · ${row['related_status']}';
  }

  Future<void> _submit() async {
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
      await widget.gateway.submit(category, relatedId!, text);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Unable to submit this dispute. It may already have an active case.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Submit dispute'),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: const [
                DropdownMenuItem(
                  value: 'recruitment',
                  child: Text('Recruitment'),
                ),
                DropdownMenuItem(
                  value: 'work',
                  child: Text('Work completion / attendance'),
                ),
                DropdownMenuItem(value: 'payment', child: Text('Payment')),
              ],
              onChanged: saving
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
            else if (records.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('No eligible records on this page.'),
              )
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
            TextField(
              controller: description,
              enabled: !saving,
              maxLines: 5,
              maxLength: 4000,
              decoration: const InputDecoration(
                labelText: 'Describe the dispute',
              ),
            ),
            if (error != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving || loading ? null : _submit,
        child: Text(saving ? 'Submitting…' : 'Submit'),
      ),
    ],
  );
}
