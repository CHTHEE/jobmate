import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../applications/module2_widgets.dart';
import '../demo_work/demo_widgets.dart';
import '../demo_work/local_attachment.dart';
import '../demo_work/phase3_store.dart';
import '../jobs/job_display.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    this.employer = false,
    this.conversationId,
    this.store,
  });
  final bool employer;
  final String? conversationId;
  final Phase3Store? store;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final store = widget.store ?? Phase3Store.session;
  final search = TextEditingController();
  String get role => widget.employer ? 'employer' : 'job_seeker';
  String get root =>
      widget.employer ? AppRoutes.employerMessages : AppRoutes.messages;
  @override
  void initState() {
    super.initState();
    markRead();
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) markRead();
  }

  void markRead() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.conversationId != null) {
        store.read(widget.conversationId!, role);
      }
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final c = widget.conversationId == null
          ? null
          : store.conversation(widget.conversationId!);
      final rows = store.conversations
          .where(
            (c) => '${c.company} ${c.worker} ${c.job}'.toLowerCase().contains(
              search.text.trim().toLowerCase(),
            ),
          )
          .toList();
      final list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search demo conversations',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No matching conversations'))
                : ListView(
                    children: [
                      for (final item in rows)
                        Card(
                          child: ListTile(
                            selected: item.id == c?.id,
                            leading: const CircleAvatar(
                              child: Icon(Icons.person_outline),
                            ),
                            title: Text(
                              widget.employer ? item.worker : item.company,
                            ),
                            subtitle: Text(
                              '${item.job}\n${item.messages.isEmpty
                                  ? 'No messages yet'
                                  : item.messages.last.text.isEmpty
                                  ? 'Local attachment'
                                  : item.messages.last.text}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: (item.unread[role] ?? 0) > 0
                                ? Chip(label: Text('${item.unread[role]}'))
                                : null,
                            onTap: item.id == c?.id
                                ? null
                                : () => context.push('$root/${item.id}'),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      );
      final thread = c == null
          ? ModuleState(
              title: widget.conversationId == null
                  ? 'Choose a conversation'
                  : 'Conversation unavailable',
              message: 'These are fictional, job-specific conversations. No real private messages are accessed.',
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      widget.employer ? c.worker : c.company,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    TextButton(
                      onPressed: () => context.go(root),
                      child: const Text('Conversation list'),
                    ),
                  ],
                ),
                Text(
                  'Job: ${c.job} • Presence unavailable • Demo participants only',
                ),
                TextButton(
                  onPressed:
                      c.messages.any(
                        (m) => m.sender == role && m.receipt != 'Read',
                      )
                      ? () => store.simulateReceipts(c.id, role)
                      : null,
                  child: const Text('Advance simulated delivery/read receipts'),
                ),
                Flexible(
                  fit: FlexFit.loose,
                  child: c.messages.isEmpty
                      ? const Center(
                          child: Text(
                            'No messages yet. Start a demo conversation.',
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          primary: false,
                          reverse: true,
                          itemCount: c.messages.length,
                          itemBuilder: (context, index) {
                            final i = c.messages.length - 1 - index,
                                m = c.messages[i],
                                mine = m.sender == role;
                            final newDay =
                                i == 0 ||
                                jobDate(c.messages[i - 1].time) !=
                                    jobDate(m.time);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (newDay)
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text(
                                      jobDate(m.time),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                Align(
                                  alignment: mine
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 480,
                                    ),
                                    child: Card(
                                      color: mine
                                          ? const Color(0xFFCCFBF1)
                                          : Colors.white,
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              m.sender == 'employer'
                                                  ? 'Demo employer'
                                                  : 'Demo candidate',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall,
                                            ),
                                            if (m.text.isNotEmpty)
                                              SelectableText(m.text),
                                            for (final file in m.attachments)
                                              AttachmentTile(file),
                                            Text(
                                              '${demoTime(m.time)} • ${m.receipt} (simulated)',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                ChatComposer(
                  key: ValueKey('${c.id}:$role'),
                  conversation: c,
                  store: store,
                  role: role,
                ),
              ],
            );
      return AppWorkspace(
        title: 'Messages (demo)',
        path: root,
        role: role,
        leading: widget.conversationId != null && !kIsWeb
            ? BackButton(onPressed: () => moduleBack(context, root))
            : null,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = ResponsiveLayout.pagePaddingForWidth(
              constraints.maxWidth,
            );
            final availableWidth = constraints.maxWidth - padding.horizontal;
            final split = availableWidth >= 720;
            return SingleChildScrollView(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Phase3Notice(
                    'Fictional job conversations, local attachments and simulated receipts. No Supabase Realtime, actual presence, notifications or private messages between real accounts.',
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: JobMateTheme.divider),
                    ),
                    clipBehavior: Clip.antiAlias,
                    height: !split && widget.conversationId != null
                        ? null
                        : math.max(
                            520 *
                                (MediaQuery.textScalerOf(context).scale(14) /
                                    14),
                            constraints.maxHeight - 180,
                          ),
                    child: split
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: availableWidth >= 900 ? 320 : 288,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: list,
                                ),
                              ),
                              const VerticalDivider(width: 1),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: thread,
                                ),
                              ),
                            ],
                          )
                        : widget.conversationId == null
                        ? list
                        : thread,
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.conversation,
    required this.store,
    required this.role,
  });
  final DemoConversation conversation;
  final Phase3Store store;
  final String role;
  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  late final text = TextEditingController(
    text: widget.conversation.drafts[widget.role] ?? '',
  );
  bool reading = false;
  String? error;
  List<LocalAttachment> get files =>
      widget.conversation.attachmentDrafts.putIfAbsent(widget.role, () => []);
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> choose() async {
    final generation = widget.store.generation;
    setState(() {
      reading = true;
      error = null;
    });
    try {
      final selected = await pickDemoFiles();
      if (!mounted || generation != widget.store.generation) return;
      if (files.length + selected.length > 5) {
        throw const FormatException('Choose at most five attachments.');
      }
      setState(() => files.addAll(selected));
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not read the attachment. Retry the picker; your message is preserved.',
        );
      }
    } finally {
      if (mounted) setState(() => reading = false);
    }
  }

  void send() {
    if (reading) return;
    try {
      widget.store.send(widget.conversation.id, widget.role);
      text.clear();
      setState(() => error = null);
    } on StateError catch (e) {
      setState(() => error = e.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(),
      if (files.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 140),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final file in files)
                  AttachmentTile(
                    file,
                    onRemove: reading
                        ? null
                        : () => setState(() => files.remove(file)),
                  ),
              ],
            ),
          ),
        ),
      CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.enter): send},
        child: TextField(
          controller: text,
          enabled: !reading,
          maxLength: 2000,
          minLines: 1,
          maxLines: 4,
          onChanged: (v) {
            widget.conversation.drafts[widget.role] = v;
            setState(() {});
          },
          decoration: const InputDecoration(
            labelText: 'Message (demo)',
            hintText: 'Enter sends • Shift+Enter adds a line',
          ),
        ),
      ),
      if (reading) const LinearProgressIndicator(),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: reading ? null : choose,
            icon: const Icon(Icons.attach_file),
            label: Text(
              error == null ? 'Attach local file' : 'Retry attachment picker',
            ),
          ),
          FilledButton.icon(
            onPressed: reading || (text.text.trim().isEmpty && files.isEmpty)
                ? null
                : send,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Send (demo)'),
          ),
        ],
      ),
      const Text(
        'Unsent text and attachments stay in this session. Nothing is uploaded.',
        style: TextStyle(fontSize: 12),
      ),
    ],
  );
}
