import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_models.dart';
import 'chat_source.dart';
import 'chat_realtime.dart';
import 'chat_read_events.dart';

/// A dot means at least one incoming unread message, across all list pages.
/// No message retrieval or read-cursor writes happen from navigation.
class ChatUnreadController extends ChangeNotifier {
  ChatUnreadController(this.source, {this.realtime}) {
    _actor = source.userId;
    _auth = source.accountChanges.listen((actor) {
      if (_disposed || actor == _actor) return;
      _actor = actor;
      ++_request;
      hasUnread = false;
      notifyListeners();
      unawaited(start());
    });
    chatReadInvalidations.addListener(_invalidate);
  }
  final ChatSource source;
  final ChatRealtime? realtime;
  late final StreamSubscription<String?> _auth;
  String? _actor;
  bool hasUnread = false, _disposed = false;
  int _request = 0;
  void _invalidate() => unawaited(refresh());
  Future<void> start() async {
    await realtime?.stop();
    if (_disposed || _actor == null) return;
    await realtime?.listen(null, _invalidate);
    await refresh();
  }

  Future<void> refresh() async {
    final actor = _actor, request = ++_request;
    bool current() =>
        !_disposed &&
        request == _request &&
        actor != null &&
        actor == _actor &&
        actor == source.userId;
    if (!current()) return;
    try {
      ChatConversationCursor? cursor;
      final visited = <String>{};
      bool found = false;
      do {
        final rows = chatRows(
          await source.conversations(limit: 100, before: cursor),
          100,
        ).map(ChatConversation.fromRow).toList();
        if (!current()) return;
        found = rows.any((row) => row.unreadCount > 0);
        if (found || rows.length < 100) break;
        final next = rows.last.cursor;
        if (!visited.add(
          '${next.activityAt.toIso8601String()}/${next.conversationId}',
        )) {
          throw const FormatException('Invalid conversation cursor');
        }
        cursor = next;
      } while (true);
      if (current() && hasUnread != found) {
        hasUnread = found;
        notifyListeners();
      }
    } catch (_) {
      /* Keep last known same-account indicator; never log rows. */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_request;
    chatReadInvalidations.removeListener(_invalidate);
    unawaited(_auth.cancel());
    unawaited(realtime?.stop());
    super.dispose();
  }
}

class ChatUnreadIcon extends StatefulWidget {
  const ChatUnreadIcon({super.key, required this.icon});
  final IconData icon;
  @override
  State<ChatUnreadIcon> createState() => _ChatUnreadIconState();
}

class _ChatUnreadIconState extends State<ChatUnreadIcon>
    with WidgetsBindingObserver {
  ChatUnreadController? _controller;
  Timer? _repair;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      final client = Supabase.instance.client;
      _controller = ChatUnreadController(
        SupabaseChatSource(client),
        realtime: SupabaseChatRealtime(client),
      );
      _controller!.addListener(_changed);
      unawaited(_controller!.start());
      // Read-state changes in another tab are not published by the existing SQL.
      _repair = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(_controller!.refresh()),
      );
    } catch (_) {
      /* Unconfigured previews/tests have no authenticated backend. */
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_controller?.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _repair?.cancel();
    _controller?.removeListener(_changed);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: _controller?.hasUnread == true,
    smallSize: 7,
    child: Semantics(
      label: _controller?.hasUnread == true ? 'Unread messages' : 'Messages',
      child: Icon(widget.icon, size: 20),
    ),
  );
}
