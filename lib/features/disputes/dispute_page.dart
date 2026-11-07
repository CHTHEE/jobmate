import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import 'dispute_gateway.dart';
import 'dispute_submit_dialog.dart';

class DisputePage extends StatefulWidget {
  const DisputePage({
    super.key,
    required this.admin,
    this.disputeId,
    this.gateway,
    this.role,
  });
  final bool admin;
  final String? disputeId;
  final DisputeGateway? gateway;
  final String? role;
  @override
  State<DisputePage> createState() => _DisputePageState();
}

class _DisputePageState extends State<DisputePage> {
  static const pageSize = 20;
  late final DisputeGateway gateway =
      widget.gateway ?? SupabaseDisputeGateway(Supabase.instance.client);
  String role = 'job_seeker';
  String accountStatus = 'active';
  bool loading = true, evidenceBusy = false, hasMore = false;
  int offset = 0;
  String? error;
  List<Map<String, dynamic>> rows = [],
      history = [],
      evidence = [],
      evidenceEvents = [];
  Map<String, dynamic>? detail;
  String get root =>
      widget.admin ? AppRoutes.adminDisputes : AppRoutes.disputes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DisputePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.disputeId != widget.disputeId ||
        oldWidget.admin != widget.admin) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      var nextRole = widget.role;
      var nextStatus = 'active';
      if (nextRole == null) {
        final client = Supabase.instance.client;
        final id = client.auth.currentUser?.id;
        if (id == null) throw StateError('Sign in to view disputes.');
        final profile = await client
            .from('users')
            .select('role,status')
            .eq('user_id', id)
            .single();
        if (client.auth.currentUser?.id != id) {
          throw StateError('Your account changed.');
        }
        nextRole = profile['role'] as String;
        nextStatus = profile['status'] as String;
      }
      final id = widget.disputeId;
      final nextRows = id == null
          ? await gateway.list(
              widget.admin,
              limit: pageSize + 1,
              offset: offset,
            )
          : <Map<String, dynamic>>[];
      final nextDetail = id == null
          ? null
          : await gateway.details(id, widget.admin);
      final nextHistory = id == null
          ? <Map<String, dynamic>>[]
          : await gateway.history(id, widget.admin);
      final nextEvidence = id == null
          ? <Map<String, dynamic>>[]
          : await gateway.evidence(id, widget.admin);
      final nextEvidenceEvents = id == null
          ? <Map<String, dynamic>>[]
          : await gateway.evidenceHistory(id, widget.admin);
      if (!mounted) return;
      setState(() {
        role = nextRole!;
        accountStatus = nextStatus;
        rows = nextRows.take(pageSize).toList();
        hasMore = nextRows.length > pageSize;
        detail = nextDetail;
        history = nextHistory;
        evidence = nextEvidence;
        evidenceEvents = nextEvidenceEvents;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Unable to load disputes. The dispute service may not be available yet.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _edit({String? action}) async {
    if (action == null) {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DisputeSubmitDialog(gateway: gateway),
      );
      if (saved == true && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Dispute submitted.')));
        offset = 0;
        await _load();
      }
      return;
    }
    final note = TextEditingController();
    var busy = false;
    String? dialogError;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(action.replaceAll('_', ' ')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: note,
                  enabled: !busy,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Reason or information',
                  ),
                ),
                if (dialogError != null)
                  Text(
                    dialogError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (action != 'investigate' && note.text.trim().isEmpty) {
                        update(
                          () => dialogError = 'Complete the required fields.',
                        );
                        return;
                      }
                      update(() {
                        busy = true;
                        dialogError = null;
                      });
                      try {
                        await gateway.action(
                          widget.disputeId!,
                          action,
                          note.text.trim(),
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (_) {
                        update(() {
                          busy = false;
                          dialogError = 'Unable to save. Check the details and try again.';
                        });
                      }
                    },
              child: Text(busy ? 'Saving…' : 'Confirm'),
            ),
          ],
        ),
      ),
    );
    note.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Dispute saved.')));
      await _load();
    }
  }

  Future<void> _uploadEvidence() async {
    if (evidenceBusy || widget.disputeId == null) return;
    const types = XTypeGroup(
      label: 'Dispute evidence',
      extensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: ['application/pdf', 'image/jpeg', 'image/png', 'image/webp'],
    );
    final file = await openFile(acceptedTypeGroups: [types]);
    if (file == null) return;
    setState(() => evidenceBusy = true);
    try {
      final bytes = await file.readAsBytes();
      await gateway.uploadEvidence(
        widget.disputeId!,
        const Uuid().v4(),
        file.name,
        bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Evidence submitted.')));
      await _load();
    } on FormatException catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to submit evidence.')),
        );
      }
    } finally {
      if (mounted) setState(() => evidenceBusy = false);
    }
  }

  Future<void> _openEvidence(String path) async {
    try {
      final url = await gateway.evidenceUrl(path);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('Unable to open evidence.');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open this evidence.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = detail?['status'] as String?;
    final canAddEvidence =
        !widget.admin &&
        const {
          'open',
          'investigating',
          'pending_information',
        }.contains(status) &&
        (accountStatus == 'active' || status == 'pending_information');
    return AppWorkspace(
      title: widget.admin ? 'Dispute management' : 'My disputes',
      path: root,
      role: widget.admin ? 'administrator' : role,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  )
                : ListView(
                    children: [
                      if (widget.disputeId == null) ...[
                        if (!widget.admin && accountStatus == 'active')
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: () => _edit(),
                              icon: const Icon(Icons.add),
                              label: const Text('Submit dispute'),
                            ),
                          ),
                        if (rows.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('No disputes found.'),
                          ),
                        for (final row in rows)
                          Card(
                            child: ListTile(
                              title: Text('${row['category']} dispute'),
                              subtitle: Text(
                                '${row['status']} · ${row['created_at']}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  context.go('$root/${row['dispute_id']}'),
                            ),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: offset == 0
                                  ? null
                                  : () {
                                      offset -= pageSize;
                                      _load();
                                    },
                              child: const Text('Previous'),
                            ),
                            TextButton(
                              onPressed: !hasMore
                                  ? null
                                  : () {
                                      offset += pageSize;
                                      _load();
                                    },
                              child: const Text('Next'),
                            ),
                          ],
                        ),
                      ] else ...[
                        TextButton.icon(
                          onPressed: () => context.go(root),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('All disputes'),
                        ),
                        Text(
                          '${detail?['category']} dispute',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text('Status: $status'),
                        const SizedBox(height: 12),
                        Text('${detail?['description'] ?? ''}'),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (widget.admin && status == 'open')
                              FilledButton(
                                onPressed: () => _edit(action: 'investigate'),
                                child: const Text('Start investigation'),
                              ),
                            if (widget.admin && status == 'investigating') ...[
                              OutlinedButton(
                                onPressed: () =>
                                    _edit(action: 'request_information'),
                                child: const Text('Request information'),
                              ),
                              FilledButton(
                                onPressed: () => _edit(action: 'resolve'),
                                child: const Text('Resolve'),
                              ),
                              OutlinedButton(
                                onPressed: () => _edit(action: 'reject'),
                                child: const Text('Reject'),
                              ),
                            ],
                            if (!widget.admin &&
                                status == 'pending_information')
                              FilledButton(
                                onPressed: () =>
                                    _edit(action: 'respond_information'),
                                child: const Text('Submit information'),
                              ),
                            if (canAddEvidence)
                              OutlinedButton.icon(
                                onPressed: evidenceBusy
                                    ? null
                                    : _uploadEvidence,
                                icon: const Icon(Icons.attach_file),
                                label: Text(
                                  evidenceBusy ? 'Uploading…' : 'Add evidence',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Evidence',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (evidence.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('No evidence has been submitted.'),
                          ),
                        for (final item in evidence)
                          Card.outlined(
                            child: ListTile(
                              leading: Icon(
                                item['mime_type'] == 'application/pdf'
                                    ? Icons.picture_as_pdf_outlined
                                    : Icons.image_outlined,
                              ),
                              title: Text('${item['original_name']}'),
                              subtitle: Text(
                                '${item['size_bytes']} bytes · ${item['submitted_at']}',
                              ),
                              trailing: const Icon(Icons.open_in_new),
                              onTap: () =>
                                  _openEvidence(item['storage_path'] as String),
                            ),
                          ),
                        if (evidenceEvents.isNotEmpty) ...[
                          Text(
                            'Evidence submission history',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          for (final event in evidenceEvents)
                            ListTile(
                              dense: true,
                              title: Text('${event['action']}'),
                              subtitle: Text('${event['created_at']}'),
                            ),
                        ],
                        const SizedBox(height: 20),
                        Text(
                          'History',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        for (final event in history)
                          ListTile(
                            title: Text(
                              '${event['action']} · ${event['new_status']}',
                            ),
                            subtitle: Text(
                              '${event['note'] ?? ''}\n${event['created_at']}',
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
