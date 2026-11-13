import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/navigation/app_routes.dart';
import '../../applications/my_applications_repository.dart';
import '../../notifications/notifications_repository.dart';
import '../chat_pending_store.dart';
import '../chat_repository.dart';
import '../chat_source.dart';
import 'chat_runtime_controller.dart';
import 'chat_runtime_scope.dart';

ChatRuntimeController _authenticatedController() {
  final client = Supabase.instance.client;
  late ChatRuntimeController controller;
  final source = ScopedChatRuntimeSource(
    SupabaseChatSource(client),
    writePermit: () => controller.writesEnabled,
  );
  controller = ChatRuntimeController(
    repository: ChatRepository(
      source: source,
      pendingStore: LocalChatPendingStore(
        storage: SharedPreferencesGotrueAsyncStorage(),
        projectUrl: dotenv.env['SUPABASE_URL']!,
      ),
      requestId: () => approvedChatRequestId(client.auth.currentUser?.id),
    ),
    readAccount: () async {
      final actor = client.auth.currentUser?.id;
      if (actor == null) throw const ChatSessionChanged();
      return await client
          .from('users')
          .select('user_id, role, status')
          .eq('user_id', actor)
          .single();
    },
    readApplications: () async => (await SupabaseMyApplicationsSource(
      client,
    ).list()).map(MyJobApplication.new).toList(),
    readNotifications: () async => (await SupabaseNotificationsSource(
      client,
    ).list()).map(JobMateNotification.new).toList(),
    realtime: SupabaseChatRuntimeRealtime(client),
  );
  return controller;
}

/// Private debug route only; no normal Messages screen/navigation changes.
class ChatRuntimePage extends StatefulWidget {
  const ChatRuntimePage({super.key, this.controller});
  final ChatRuntimeController? controller;
  @override
  State<ChatRuntimePage> createState() => _ChatRuntimePageState();
}

class _ChatRuntimePageState extends State<ChatRuntimePage> {
  ChatRuntimeController? _controller;
  final _conversation = TextEditingController();
  String? _actor, _selectionError, _displayConversation;
  bool _copied = false;
  @override
  void initState() {
    super.initState();
    if (!chatRuntimeAcceptanceEnabled) return;
    _controller = widget.controller ?? _authenticatedController();
    _actor = _controller!.actorId;
    _controller!.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (_actor != _controller!.actorId) {
      _actor = _controller!.actorId;
      _conversation.clear();
      _selectionError = null;
    }
    if (_displayConversation != _controller!.selectedConversation) {
      _displayConversation = _controller!.selectedConversation;
      _conversation.text = _displayConversation ?? '';
    }
    setState(() {
      _copied = false;
    });
  }

  void _select(String value) {
    try {
      _controller!.selectConversation(value);
      _conversation.text = _controller!.selectedConversation!;
      setState(() {
        _selectionError = null;
      });
    } on FormatException {
      setState(() {
        _selectionError = 'Enter a valid existing conversation UUID.';
      });
    }
  }

  void _exit() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _write(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() {
          _selectionError = 'Write blocked by scope. Check account and approved conversation.';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    _controller?.dispose();
    _conversation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (!chatRuntimeAcceptanceEnabled || c == null) {
      return const SizedBox.shrink();
    }
    final available = !c.busy && c.actorId != null;
    final selected = available && c.selectedConversation != null;
    final writes = available && c.writesEnabled;
    final conversationWrites = available && c.canWriteConversation;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat runtime tester'),
        automaticallyImplyLeading: false,
        leading: kIsWeb ? null : BackButton(onPressed: _exit),
        actions: [
          TextButton(onPressed: _exit, child: const Text('Back / Home')),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'DEBUG ONLY · SCOPED CHAT QA ACCEPTANCE',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Real backend. CH/KZ approved only the QA application and two fixed messages. '
                  'Check account first. Loading history does not mark it read. Nothing sends automatically.',
                ),
                const SelectableText(
                  'Approved application: $approvedChatApplication',
                ),
                Text(
                  c.trialStopped
                      ? 'TRIAL STOPPED — access/read-only or scope failure. '
                            'Do not change business state to bypass it.'
                      : writes
                      ? 'Approved participant verified. Only the scoped controls below can write.'
                      : 'Writes locked: check the approved active participant account.',
                ),
                const SizedBox(height: 12),
                SelectableText(
                  'Account UUID: ${c.actorId ?? 'signed out'}\n'
                  'Role: ${c.role ?? 'not checked'} · Status: ${c.accountStatus ?? 'not checked'}',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: available ? c.loadIdentity : null,
                      child: const Text('Check account'),
                    ),
                    OutlinedButton(
                      onPressed: available ? () => c.loadConversations() : null,
                      child: const Text('Load conversations'),
                    ),
                    OutlinedButton(
                      onPressed:
                          available && c.conversationPage?.nextCursor != null
                          ? () => c.loadConversations(next: true)
                          : null,
                      child: const Text('Next conversations'),
                    ),
                    const Text('Page size'),
                    DropdownButton<int>(
                      value: c.limit,
                      items: [1, 10, 50]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text('$value'),
                            ),
                          )
                          .toList(),
                      onChanged: available
                          ? (value) => c.setLimit(value!)
                          : null,
                    ),
                  ],
                ),
                if (c.busy) const LinearProgressIndicator(),
                if (c.error != null)
                  SelectableText(
                    c.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (c.conversationPage != null) ...[
                  Text(
                    'Typed conversations: ${c.conversationPage!.items.length} · '
                    'next cursor: ${c.conversationPage!.nextCursor?.conversationId ?? 'none'}',
                  ),
                  if (c.conversationPage!.items.isEmpty)
                    const Text('Empty conversation page.'),
                  for (final row in c.conversationPage!.items)
                    Card(
                      child: ListTile(
                        selected: c.selectedConversation == row.id,
                        onTap: available ? () => _select(row.id) : null,
                        title: Text('${row.jobTitle} · ${row.companyName}'),
                        subtitle: Text(
                          '${row.id}\nApplication: ${row.applicationId}\n'
                          '${row.status.name} · canSend=${row.canSend} · '
                          'reason=${row.readOnlyReason} · unread=${row.unreadCount}\n'
                          'lastSequence=${row.lastSequence} · activity=${row.activityAt.toIso8601String()}',
                        ),
                        isThreeLine: false,
                      ),
                    ),
                ],
                const Divider(),
                TextField(
                  controller: _conversation,
                  enabled: available,
                  decoration: InputDecoration(
                    labelText:
                        'Existing conversation UUID (or foreign access probe)',
                    errorText: _selectionError,
                  ),
                  onSubmitted: available ? _select : null,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: available
                          ? () => _select(_conversation.text)
                          : null,
                      child: const Text('Select UUID'),
                    ),
                    OutlinedButton(
                      onPressed: selected
                          ? () => c.loadConversations(
                              filter: c.selectedConversation,
                            )
                          : null,
                      child: const Text('Filtered lookup'),
                    ),
                    OutlinedButton(
                      onPressed: selected ? () => c.loadMessages() : null,
                      child: const Text('Load history'),
                    ),
                    OutlinedButton(
                      onPressed:
                          selected && c.messagePage?.nextBeforeSequence != null
                          ? () => c.loadMessages(next: true)
                          : null,
                      child: const Text('Older messages'),
                    ),
                    OutlinedButton(
                      onPressed: selected
                          ? () => c.loadMessages(emptyBoundary: true)
                          : null,
                      child: const Text('Check empty boundary (before 1)'),
                    ),
                  ],
                ),
                SelectableText('Selected: ${c.selectedConversation ?? 'none'}'),
                if (c.messagePage != null) ...[
                  Text(
                    'Typed messages: ${c.messagePage!.items.length} · '
                    'next sequence: ${c.messagePage!.nextBeforeSequence ?? 'none'}',
                  ),
                  if (c.messagePage!.items.isEmpty)
                    const Text('Empty history page.'),
                  for (final row in c.messagePage!.items)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              '#${row.sequence} · ${row.id}\n'
                              'Sender: ${row.senderId} (${row.senderName})\n${row.sentAt.toIso8601String()}',
                            ),
                            SelectableText(row.body),
                            TextButton(
                              onPressed: conversationWrites
                                  ? () => _write(() => c.markRead(row.id))
                                  : null,
                              child: const Text('Mark my read cursor'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                const Divider(),
                const Text(
                  'Existing applications (only approved QA application can be used)',
                ),
                OutlinedButton(
                  onPressed: available && c.role == 'job_seeker'
                      ? c.loadApplications
                      : null,
                  child: const Text('Load my applications — seeker'),
                ),
                for (final application in c.applications)
                  ListTile(
                    selected: c.selectedApplication == application.id,
                    leading: Icon(
                      c.selectedApplication == application.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    onTap: available
                        ? () => setState(() {
                            c.selectedApplication = application.id;
                          })
                        : null,
                    title: Text(
                      '${application.jobTitle} · ${application.companyName}',
                    ),
                    subtitle: Text(
                      '${application.id} · ${application.status.name}',
                    ),
                  ),
                OutlinedButton(
                  onPressed: available && c.canCreateApproved
                      ? () => _write(c.createConversation)
                      : null,
                  child: const Text('Create / reuse approved conversation'),
                ),
                SelectableText(
                  'Fixed agreed message: ${c.agreedBody ?? 'unapproved participant'}',
                ),
                const Text(
                  'One request identity per participant, retained across reloads/devices. '
                  'Repeated Send or Retry reconciles the same message, never a new logical message.',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: conversationWrites
                          ? () => _write(() => c.send(c.agreedBody!))
                          : null,
                      child: const Text('Send agreed message'),
                    ),
                    OutlinedButton(
                      onPressed: conversationWrites && c.pending != null
                          ? () => _write(c.retry)
                          : null,
                      child: const Text('Retry same UUID/body'),
                    ),
                  ],
                ),
                const Divider(),
                Text('Realtime: ${c.realtimeStatus}'),
                const Text(
                  'Subscription status is not delivery proof. Events contain metadata only; '
                  'reload typed history to reconcile. No read-state subscription.',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: selected ? c.startRealtime : null,
                      child: const Text('Observe Realtime'),
                    ),
                    OutlinedButton(
                      onPressed: c.stopRealtime,
                      child: const Text('Stop observer'),
                    ),
                  ],
                ),
                const Divider(),
                OutlinedButton(
                  onPressed: available && c.readNotifications != null
                      ? c.loadNotifications
                      : null,
                  child: const Text('Snapshot my notifications (read-only)'),
                ),
                const Text(
                  'Snapshot before sends, after delivery and after retries. '
                  'First 50 only; quiet-window IDs support notification checks, not per-message proof.',
                ),
                const Text(
                  'Credential-free evidence — typed metadata, no bodies/names/tokens',
                ),
                OutlinedButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: c.evidenceJson),
                    );
                    if (mounted) {
                      setState(() {
                        _copied = true;
                      });
                    }
                  },
                  child: Text(
                    _copied ? 'Evidence copied' : 'Copy evidence JSON',
                  ),
                ),
                SelectableText(c.evidenceJson),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
