import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/app_workspace.dart';
import '../applications/module2_widgets.dart';
import 'chat_dependencies.dart';
import 'chat_attachment_draft.dart';
import 'chat_models.dart';
import 'chat_ui_controller.dart';
import 'chat_attachment_models.dart';
import 'chat_attachments.dart';
import 'chat_attachment_card.dart';
import 'chat_download.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    this.employer = false,
    this.conversationId,
    this.controller,
    this.pickAttachment,
    this.attachments,
  });
  final bool employer;
  final String? conversationId;
  final ChatUiController? controller;
  final Future<XFile?> Function()? pickAttachment;
  final ChatAttachmentsController? attachments;
  @override
  State<ChatPage> createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  late final ChatUiController _chat;
  ChatAttachmentsController? _files;
  List<ChatAttachment> _recoverable = [];
  String? _fileRecoveryError;
  final _text = TextEditingController(), _search = TextEditingController();
  bool _foreground = true;
  bool _picking = false;
  int _selectionGeneration = 0;
  ChatAttachmentDraft? _attachment;
  String? _attachmentError;
  String? _actor;
  final _historyViewport = GlobalKey();
  final _messageKeys = <String, GlobalKey>{};
  final _displayedImages = <String>{};
  bool _readScheduled = false;
  String? _attemptedRead;

  void _scheduleDisplayedRead() {
    if (_readScheduled || !mounted) return;
    _readScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readScheduled = false;
      if (!mounted ||
          !_foreground ||
          !chatDocumentVisible() ||
          !(ModalRoute.of(context)?.isCurrent ?? true) ||
          _chat.loadingThread ||
          _chat.reading ||
          _chat.threadError != null ||
          (_chat.selected?.unreadCount ?? 0) == 0) {
        return;
      }
      final viewport = _historyViewport.currentContext?.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize || !viewport.attached) {
        return;
      }
      final screen = MediaQuery.sizeOf(context);
      final bounds = (viewport.localToGlobal(Offset.zero) & viewport.size)
          .intersect(
            Rect.fromLTRB(
              0,
              MediaQuery.paddingOf(context).top,
              screen.width,
              screen.height - MediaQuery.viewInsetsOf(context).bottom,
            ),
          );
      ChatMessage? latest;
      for (final message in _chat.messages) {
        if (message.senderId == _chat.actorId) continue;
        if (message.attachment?.isImage == true &&
            _files != null &&
            !_displayedImages.contains(message.attachment!.id)) {
          continue;
        }
        final box = _messageKeys[message.id]?.currentContext
            ?.findRenderObject();
        if (box is! RenderBox || !box.hasSize || !box.attached) continue;
        final bubble = box.localToGlobal(Offset.zero) & box.size;
        final visiblePart = bubble.intersect(bounds);
        if ((bubble.top >= bounds.top ||
                bubble.height > bounds.height && visiblePart.height >= 48) &&
            bubble.bottom <= bounds.bottom &&
            bubble.overlaps(bounds) &&
            (latest == null || message.sequence > latest.sequence)) {
          latest = message;
        }
      }
      if (latest == null) return;
      final identity = '${_chat.actorId}/${latest.conversationId}/${latest.id}';
      if (_attemptedRead == identity) return;
      _attemptedRead = identity;
      _chat.setVisible(true);
      unawaited(_chat.markRead(latest));
    });
  }

  String get _root =>
      widget.employer ? AppRoutes.employerMessages : AppRoutes.messages;
  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _chat = widget.controller ?? authenticatedChatUi();
    _files =
        widget.attachments ??
        // Injected Chat controllers must also inject their attachment gateway;
        // never attach the global authenticated client to another data source.
        (chatAttachmentsEnabled && widget.controller == null
            ? ChatAttachmentsController(
                SupabaseChatAttachmentGateway(
                  Supabase.instance.client,
                  enabled: true,
                ),
              )
            : null);
    _files?.addListener(_filesChanged);
    _actor = _chat.actorId;
    _chat.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  void _filesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    await _chat.start(widget.conversationId);
    await _loadPendingFiles();
  }

  Future<void> _loadPendingFiles() async {
    final id = _chat.selectedId, actor = _chat.actorId;
    if (_files == null || id == null) return;
    try {
      final rows = await _files!.gateway.pending(id);
      if (mounted && actor == _chat.actorId && id == _chat.selectedId) {
        setState(() => _recoverable = rows);
      }
    } catch (_) {
      if (mounted && actor == _chat.actorId && id == _chat.selectedId) {
        setState(
          () => _fileRecoveryError =
              'Saved attachment requests could not be loaded.',
        );
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_actor != _chat.actorId) {
      _messageKeys.clear();
      _displayedImages.clear();
      _attemptedRead = null;
      ++_selectionGeneration;
      _attachment = null;
      _recoverable = [];
      _fileRecoveryError = null;
      _files?.clear();
      _attachmentError = null;
      _picking = false;
      _actor = _chat.actorId;
      _search.clear();
      // Do not reuse a role-gated route after its authenticated owner changes.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) GoRouter.maybeOf(context)?.go(AppRoutes.home);
      });
    }
    if (_text.text != _chat.draft) {
      _text.value = TextEditingValue(
        text: _chat.draft,
        selection: TextSelection.collapsed(offset: _chat.draft.length),
      );
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.conversationId != oldWidget.conversationId &&
        widget.conversationId != null) {
      _messageKeys.clear();
      _displayedImages.clear();
      _attemptedRead = null;
      ++_selectionGeneration;
      _attachment = null;
      _recoverable = [];
      _fileRecoveryError = null;
      _files?.clear();
      _attachmentError = null;
      _picking = false;
      unawaited(
        _chat.open(widget.conversationId!).then((_) => _loadPendingFiles()),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _chat.setVisible(
      _foreground && (ModalRoute.of(context)?.isCurrent ?? true),
    );
    if (_foreground) {
      _attemptedRead = null;
      _scheduleDisplayedRead();
    }
  }

  Future<bool> confirmExit() async {
    if (!_chat.needsExitConfirmation &&
        _attachment == null &&
        !_picking &&
        _files?.needsExit != true) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leave this conversation?'),
            content: const Text(
              'Unsent text and selected files will be discarded. Any saved send awaiting confirmation '
              'will remain available for recovery; it will not be sent automatically.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(_root);
    }
  }

  @override
  void dispose() {
    ++_selectionGeneration;
    _attachment = null;
    _files?.removeListener(_filesChanged);
    _files?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _chat.removeListener(_changed);
    _chat.dispose();
    _text.dispose();
    _search.dispose();
    super.dispose();
  }

  bool get _validText {
    try {
      validateChatBody(_text.text);
      return true;
    } on FormatException {
      return false;
    }
  }

  void _sendText() {
    if (_files != null && (_attachment != null || _files!.hasIdentity)) {
      unawaited(_sendAttachment());
      return;
    }
    // Never silently send just the caption when a file is selected.
    if (_attachment != null || _picking || !_validText) return;
    unawaited(_chat.send());
  }

  Future<void> _sendAttachment() async {
    final files = _files, id = _chat.selectedId, actor = _chat.actorId;
    if (files == null || id == null || _chat.sending || _chat.pending != null) {
      return;
    }
    try {
      await files.run(id, _text.text);
      if (!mounted || actor != _chat.actorId || id != _chat.selectedId) return;
      if (files.receipt != null) {
        setState(() => _attachment = null);
        files.clear();
        _chat.setDraft('');
        await _chat.refresh();
        await _loadPendingFiles();
      }
    } on FormatException {
      if (mounted) {
        setState(
          () => _attachmentError =
              'Use an optional caption of at most 4000 characters.',
        );
      }
    }
  }

  Future<void> _chooseAttachment() async {
    if (_picking ||
        _chat.sending ||
        _chat.pending != null ||
        _chat.selected?.canSend != true) {
      return;
    }
    final actor = _chat.actorId;
    final conversation = _chat.selectedId;
    final generation = ++_selectionGeneration;
    bool current() =>
        mounted &&
        generation == _selectionGeneration &&
        actor == _chat.actorId &&
        actor == _chat.repository.source.userId &&
        conversation == _chat.selectedId;
    setState(() {
      _picking = true;
      _attachmentError = null;
    });
    try {
      final file =
          await (widget.pickAttachment?.call() ??
              openFile(
                acceptedTypeGroups: [
                  const XTypeGroup(
                    label: 'Chat images and documents',
                    extensions: ChatAttachmentDraft.extensions,
                    mimeTypes: [
                      'image/jpeg',
                      'image/png',
                      'application/pdf',
                      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                    ],
                    uniformTypeIdentifiers: [
                      'public.jpeg',
                      'public.png',
                      'com.adobe.pdf',
                      'org.openxmlformats.wordprocessingml.document',
                      'org.openxmlformats.spreadsheetml.sheet',
                    ],
                  ),
                ],
              ));
      if (!current() || file == null) return;
      if (await file.length() > ChatAttachmentDraft.maximumBytes) {
        throw const FormatException(
          'Choose a file of at most 5 MB (5,242,880 bytes).',
        );
      }
      if (!current()) return;
      final bytes = await file.readAsBytes();
      if (!current()) return;
      final selected = ChatAttachmentDraft.select(file.name, bytes);
      _files?.select(selected);
      setState(() => _attachment = _files == null ? selected : _files!.file);
    } catch (error) {
      if (current()) {
        setState(
          () => _attachmentError = error is FormatException
              ? error.message.toString()
              : 'Unable to open this file. Try again.',
        );
      }
    } finally {
      if (current()) setState(() => _picking = false);
    }
  }

  String _timestamp(DateTime value) {
    final local = value.toLocal();
    final today = DateTime.now();
    final l = MaterialLocalizations.of(context);
    return local.year == today.year &&
            local.month == today.month &&
            local.day == today.day
        ? l.formatTimeOfDay(TimeOfDay.fromDateTime(local))
        : l.formatShortDate(local);
  }

  Widget _error(String title, String message, VoidCallback retry) => Padding(
    padding: const EdgeInsets.all(12),
    child: ModuleState(
      title: title,
      message: message,
      action: retry,
      actionLabel: 'Retry',
    ),
  );

  String _participant(ChatConversation row) =>
      widget.employer ? row.workerName : row.companyName;

  Widget _avatar(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final initials = words.isEmpty
        ? '?'
        : (words.length == 1
                  ? words.first.characters.take(2).toString()
                  : '${words.first.characters.first}${words.last.characters.first}')
              .toUpperCase();
    return CircleAvatar(
      radius: 20,
      backgroundColor: JobMateTheme.teal100,
      foregroundColor: JobMateTheme.darkTeal,
      child: Text(
        initials,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _jobLabel(String title) => Container(
    margin: const EdgeInsets.symmetric(vertical: 5),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: JobMateTheme.teal50,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.work_outline, size: 12, color: JobMateTheme.darkTeal),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: JobMateTheme.darkTeal),
          ),
        ),
      ],
    ),
  );

  Widget _emptyThread() => ColoredBox(
    color: JobMateTheme.background,
    child: Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: JobMateTheme.teal100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.forum_outlined,
                  size: 40,
                  color: JobMateTheme.darkTeal,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select a conversation',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: const Text(
                  'Use messaging for job arrangements, attendance queries, payment questions, and professional communication.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: JobMateTheme.body),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _list() {
    final query = _search.text.trim().toLowerCase();
    final rows = _chat.conversations
        .where(
          (row) => '${row.jobTitle} ${row.companyName} ${row.workerName}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Search conversations',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        if (_chat.pendingCount > 0)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${_chat.pendingCount} saved send(s) awaiting confirmation. Open the conversation to recover.',
            ),
          ),
        if (_chat.loadingList) const LinearProgressIndicator(),
        if (_chat.listError != null)
          _error(
            'Unable to load conversations',
            _chat.listError!,
            () => _chat.loadConversations(),
          ),
        Expanded(
          child: rows.isEmpty && !_chat.loadingList && _chat.listError == null
              ? Center(
                  child: Text(
                    query.isEmpty
                        ? 'No conversations yet. Open an application and choose Message.'
                        : 'No matching conversations.',
                  ),
                )
              : ListView(
                  children: [
                    for (final row in rows) ...[
                      Material(
                        color: row.id == _chat.selectedId
                            ? JobMateTheme.teal50
                            : Colors.white,
                        child: InkWell(
                          onTap: row.id == widget.conversationId
                              ? null
                              : () => context.push<void>('$_root/${row.id}'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _avatar(_participant(row)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _participant(row),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _timestamp(row.activityAt),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: JobMateTheme.body,
                                                ),
                                          ),
                                        ],
                                      ),
                                      _jobLabel(row.jobTitle),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              row.lastMessagePreview ??
                                                  'No messages yet',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: JobMateTheme.body,
                                                  ),
                                            ),
                                          ),
                                          if (row.unreadCount > 0) ...[
                                            const SizedBox(width: 6),
                                            Badge(
                                              label: Text('${row.unreadCount}'),
                                              backgroundColor:
                                                  JobMateTheme.darkTeal,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1, color: JobMateTheme.divider),
                    ],
                    if (_chat.nextConversation != null)
                      TextButton(
                        onPressed: _chat.loadingList
                            ? null
                            : () => _chat.loadConversations(older: true),
                        child: const Text('More conversations'),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _thread() {
    final row = _chat.selected;
    final compose =
        row != null &&
        row.canSend &&
        !_chat.loadingThread &&
        _chat.threadError == null &&
        !_chat.sending &&
        _chat.pending == null &&
        !_chat.recoveryFailed &&
        !_picking &&
        _files?.busy != true &&
        _files?.hasIdentity != true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              _avatar(row == null ? 'Conversation' : _participant(row)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row == null ? 'Conversation' : _participant(row),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (row != null) ...[
                      Text(
                        row.jobTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: JobMateTheme.body),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: JobMateTheme.teal50,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          row.status.label,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: JobMateTheme.darkTeal),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (MediaQuery.sizeOf(context).width < 840)
                IconButton(
                  tooltip: 'Conversations',
                  onPressed: () => context.go(_root),
                  icon: const Icon(Icons.forum_outlined),
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: JobMateTheme.divider),
        if (_chat.loadingThread) const LinearProgressIndicator(),
        if (_chat.threadError != null)
          _error(
            'Conversation unavailable',
            _chat.threadError!,
            () => _chat.refreshThread(),
          ),
        if (row != null && !row.canSend)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Read-only history · ${_readOnlyReason(row.readOnlyReason)}',
            ),
          ),
        Expanded(
          key: _historyViewport,
          child: ColoredBox(
            color: JobMateTheme.background,
            child: _chat.messages.isEmpty
                ? Center(
                    child: Text(
                      _chat.loadingThread
                          ? 'Loading messages…'
                          : row == null
                          ? 'Choose an available conversation.'
                          : 'No messages yet.',
                    ),
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: (_) {
                      _scheduleDisplayedRead();
                      return false;
                    },
                    child: ListView.builder(
                      key: ValueKey(_chat.selectedId),
                      reverse: true,
                      itemCount:
                          _chat.messages.length +
                          (_chat.nextSequence != null ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _chat.messages.length) {
                          return TextButton(
                            onPressed: _chat.loadingThread
                                ? null
                                : () => _chat.refreshThread(older: true),
                            child: const Text('Older messages'),
                          );
                        }
                        final message = _chat.messages[index];
                        final mine = message.senderId == _chat.actorId;
                        final firstOfDay =
                            index == _chat.messages.length - 1 ||
                            !DateUtils.isSameDay(
                              message.sentAt.toLocal(),
                              _chat.messages[index + 1].sentAt.toLocal(),
                            );
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (firstOfDay)
                              Padding(
                                key: ValueKey(
                                  'chat-date-${DateUtils.dateOnly(message.sentAt.toLocal()).toIso8601String()}',
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text(
                                  MaterialLocalizations.of(
                                    context,
                                  ).formatMediumDate(message.sentAt.toLocal()),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: JobMateTheme.body),
                                ),
                              ),
                            Align(
                              key: _messageKeys.putIfAbsent(
                                message.id,
                                GlobalKey.new,
                              ),
                              alignment: mine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      (MediaQuery.sizeOf(context).width * .76)
                                          .clamp(180.0, 440.0),
                                ),
                                child: Card(
                                  elevation: 0,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 3,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: mine
                                        ? BorderSide.none
                                        : const BorderSide(
                                            color: JobMateTheme.divider,
                                          ),
                                  ),
                                  color: mine
                                      ? JobMateTheme.darkTeal
                                      : Colors.white,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (message.attachment == null ||
                                            _files == null)
                                          SelectableText(
                                            message.body,
                                            style: TextStyle(
                                              color: mine
                                                  ? Colors.white
                                                  : JobMateTheme.heading,
                                            ),
                                            textWidthBasis:
                                                TextWidthBasis.longestLine,
                                          )
                                        else ...[
                                          if (message.attachment!.caption !=
                                              null)
                                            SelectableText(
                                              message.attachment!.caption!,
                                              style: TextStyle(
                                                color: mine
                                                    ? Colors.white
                                                    : JobMateTheme.heading,
                                              ),
                                              textWidthBasis:
                                                  TextWidthBasis.longestLine,
                                            ),
                                          ChatAttachmentCard(
                                            key: ValueKey(
                                              '${_chat.actorId}-${message.attachment!.id}',
                                            ),
                                            attachment: message.attachment!,
                                            gateway: _files!.gateway,
                                            foregroundColor: mine
                                                ? Colors.white
                                                : JobMateTheme.body,
                                            onImageDisplayed: () {
                                              _displayedImages.add(
                                                message.attachment!.id,
                                              );
                                              _scheduleDisplayedRead();
                                            },
                                          ),
                                        ],
                                        Text(
                                          MaterialLocalizations.of(context)
                                              .formatTimeOfDay(
                                                TimeOfDay.fromDateTime(
                                                  message.sentAt.toLocal(),
                                                ),
                                              ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: mine
                                                    ? Colors.white
                                                    : JobMateTheme.body,
                                              ),
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
          ),
        ),
        if (_chat.sendError != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _chat.sendError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_chat.readError != null)
          Text(
            'Read status not confirmed. Refresh to retry.',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        if (_chat.recoveryFailed)
          TextButton(
            onPressed: () => _chat.start(_chat.selectedId),
            child: const Text('Recover saved sends'),
          ),
        if (row != null) ...[
          const Divider(),
          if (_files case final files?) ...[
            if (_fileRecoveryError != null)
              TextButton(
                onPressed: () {
                  setState(() => _fileRecoveryError = null);
                  unawaited(_loadPendingFiles());
                },
                child: Text('$_fileRecoveryError Retry'),
              ),
            if (files.hasIdentity || files.busy) Text(files.phase),
            if (files.busy)
              LinearProgressIndicator(
                value: files.phase == 'Uploading' ? files.progress : null,
              ),
            if (files.error.isNotEmpty) Text(files.error),
            if (files.busy)
              TextButton(
                onPressed: files.cancel,
                child: const Text('Cancel transfer'),
              ),
            if (files.hasIdentity && !files.busy)
              TextButton(
                onPressed: _sendAttachment,
                child: const Text('Retry same attachment request'),
              ),
            if (files.reservation?.state == 'rejected' ||
                files.reservation?.state == 'expired')
              TextButton(
                onPressed: () {
                  files.clear();
                  setState(() => _attachment = null);
                },
                child: const Text('Dismiss rejected or expired attachment'),
              ),
            if (!files.hasIdentity && _attachment == null)
              for (final saved in _recoverable)
                TextButton(
                  onPressed: () {
                    files.recover(saved);
                    _chat.setDraft(saved.caption ?? '');
                  },
                  child: Text('Recover ${saved.name} (${saved.state})'),
                ),
          ],
          if (_attachmentError != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _attachmentError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_attachment case final attachment?)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (attachment.isImage)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Image.memory(
                              attachment.bytes,
                              width: 48,
                              height: 48,
                              cacheWidth: 96,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(Icons.description_outlined),
                          ),
                        Expanded(
                          child: Text(
                            '${attachment.name} · ${attachment.sizeLabel}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove selected file',
                          onPressed: _files?.hasIdentity == true
                              ? null
                              : () => setState(() {
                                  _attachment = null;
                                  _files?.clear();
                                  _attachmentError = null;
                                }),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    if (_files == null)
                      const Text(ChatAttachmentDraft.unavailable),
                  ],
                ),
              ),
            ),
          if (_chat.pending != null)
            const Text(
              'Saved send awaiting confirmation. Retry uses the original message and request identity.',
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (kDebugMode || _files != null)
                IconButton(
                  tooltip: _files == null
                      ? 'Preview attachment (upload unavailable)'
                      : 'Attach file',
                  onPressed:
                      compose ||
                          (_files?.hasIdentity == true &&
                              _files?.file == null &&
                              _files?.busy == false)
                      ? _chooseAttachment
                      : null,
                  icon: _picking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.attach_file),
                ),
              const Tooltip(
                message: 'JPG, PNG, PDF, DOCX and XLSX up to 5 MB. Type/content validation is not antivirus scanning. Share trusted files only.',
                triggerMode: TooltipTriggerMode.tap,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.info_outline, size: 18),
                ),
              ),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      control: true,
                    ): () =>
                        _sendText(),
                  },
                  child: TextField(
                    controller: _text,
                    enabled: compose,
                    minLines: 1,
                    maxLines: 4,
                    onChanged: _chat.setDraft,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      hintText: 'Message or caption',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: JobMateTheme.darkTeal,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: JobMateTheme.divider,
                  disabledForegroundColor: JobMateTheme.body,
                ),
                tooltip: _attachment != null && _files == null
                    ? 'Attachment sending is unavailable'
                    : 'Send',
                onPressed:
                    compose &&
                        (_validText && _attachment == null ||
                            _files != null &&
                                _attachment != null &&
                                (_text.text.isEmpty || _validText))
                    ? _sendText
                    : null,
                icon: _chat.sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${_text.text.runes.length}/4000 characters'),
              if (_chat.pending != null)
                OutlinedButton(
                  onPressed: _chat.sending || _attachment != null || _picking
                      ? null
                      : () => _chat.send(retry: true),
                  child: const Text('Retry saved message'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleDisplayedRead();
    final visible = _foreground && (ModalRoute.of(context)?.isCurrent ?? true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chat.setVisible(visible);
    });
    return AppWorkspace(
      title: 'Messages',
      path: widget.conversationId == null
          ? _root
          : '$_root/${widget.conversationId}',
      role: widget.employer ? 'employer' : 'job_seeker',
      focused: widget.conversationId != null,
      backFallback: _root,
      leading: !kIsWeb && widget.conversationId != null
          ? BackButton(onPressed: _back)
          : null,
      actions: [
        IconButton(
          tooltip: 'Refresh messages',
          onPressed: () {
            _attemptedRead = null;
            unawaited(_chat.refresh());
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final split = constraints.maxWidth >= 840;
          final panel = Padding(
            padding: const EdgeInsets.all(12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: JobMateTheme.divider),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: split
                    ? Row(
                        children: [
                          SizedBox(width: 300, child: _list()),
                          const VerticalDivider(width: 24),
                          Expanded(
                            child: widget.conversationId == null
                                ? _emptyThread()
                                : _thread(),
                          ),
                        ],
                      )
                    : widget.conversationId == null
                    ? _list()
                    : _thread(),
              ),
            ),
          );
          final minimumHeight = MediaQuery.textScalerOf(context).scale(
            440 +
                (_attachment != null ? 150 : 0) +
                (_files?.hasIdentity == true ? 260 : 0) +
                (_files?.hasIdentity != true && _attachment == null
                    ? _recoverable.length * 56
                    : 0),
          );
          if (constraints.maxHeight < minimumHeight) {
            return SingleChildScrollView(
              child: SizedBox(
                height: minimumHeight,
                width: constraints.maxWidth,
                child: panel,
              ),
            );
          }
          return panel;
        },
      ),
    );
  }
}

String _readOnlyReason(String? reason) => switch (reason) {
  'application_terminal' => 'This application is no longer active.',
  'recruitment_restricted' =>
    'Messaging is currently restricted for this application.',
  'company_unverified' => 'Company verification is required to send.',
  _ => 'Sending is currently unavailable. Your existing messages remain here.',
};
