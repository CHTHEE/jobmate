import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_models.dart';
import 'chat_realtime.dart';
import 'chat_repository.dart';
import 'chat_read_events.dart';

class ChatUiController extends ChangeNotifier {
  ChatUiController({required this.repository, this.realtime}) {
    _actor = repository.source.userId;
    _auth = repository.source.accountChanges.listen((actor) {
      if (!_disposed && actor != _actor) _reset(actor);
    });
  }
  final ChatRepository repository;
  final ChatRealtime? realtime;
  late final StreamSubscription<String?> _auth;
  String? _actor;
  int _session = 0, _thread = 0, _listRequest = 0, _historyRequest = 0;
  final Map<String, int> _readThrough = {};
  bool _disposed = false, _visible = true;
  String? get actorId => _actor;
  String? selectedId;
  ChatConversation? selected;
  List<ChatConversation> conversations = [];
  List<ChatMessage> messages = []; // Descending sequence, deduplicated by ID.
  ChatConversationCursor? nextConversation;
  int? nextSequence;
  String? listError, threadError, sendError;
  String? readError;
  bool loadingList = false,
      loadingThread = false,
      sending = false,
      reading = false;
  bool recoveryFailed = false, _historyLoaded = false;
  final Map<String, String> _drafts = {};
  List<PendingChatSend> _pending = [];
  String get draft => _drafts[selectedId] ?? '';
  PendingChatSend? get pending =>
      _pending.where((row) => row.conversationId == selectedId).firstOrNull;
  int get pendingCount => _pending.length;
  bool get needsExitConfirmation =>
      repository.source.userId == _actor &&
      (sending || _drafts.values.any((value) => value.isNotEmpty));
  bool _current(int session, [int? thread]) =>
      !_disposed &&
      session == _session &&
      _actor != null &&
      repository.source.userId == _actor &&
      (thread == null || thread == _thread);

  void _reset(String? actor) {
    _actor = actor;
    ++_session;
    ++_thread;
    ++_listRequest;
    ++_historyRequest;
    _drafts.clear();
    _readThrough.clear();
    _pending = [];
    conversations = [];
    messages = [];
    selectedId = null;
    selected = null;
    nextConversation = null;
    nextSequence = null;
    listError = threadError = sendError = null;
    readError = null;
    loadingList = loadingThread = sending = reading = false;
    recoveryFailed = false;
    _historyLoaded = false;
    unawaited(realtime?.stop());
    notifyListeners();
  }

  Future<void> start([String? conversationId]) async {
    final session = _session;
    try {
      await repository.restorePending();
      if (!_current(session)) return;
      _pending = repository.pendingSends;
      recoveryFailed = false;
      for (final row in _pending) {
        _drafts[row.conversationId] = row.body;
      }
    } catch (_) {
      if (_current(session)) {
        recoveryFailed = true;
        sendError = 'Saved message recovery failed. Sending is disabled until recovery succeeds.';
      }
    }
    if (!_current(session)) return;
    await loadConversations();
    if (!_current(session)) return;
    if (conversationId != null) {
      await open(conversationId);
    } else {
      await _subscribe();
    }
  }

  void setDraft(String value) {
    if (selectedId == null || pending != null || sending) return;
    _drafts[selectedId!] = value;
    sendError = null;
    notifyListeners();
  }

  Future<void> loadConversations({bool older = false}) async {
    if (_actor == null ||
        _disposed ||
        older && (loadingList || nextConversation == null)) {
      return;
    }
    final session = _session, request = ++_listRequest;
    final cursor = older ? nextConversation : null;
    loadingList = true;
    listError = null;
    notifyListeners();
    try {
      final page = await repository.conversations(before: cursor);
      if (!_current(session) || request != _listRequest) return;
      final rows = <String, ChatConversation>{
        if (older)
          for (final row in conversations) row.id: row,
        for (final row in page.items) row.id: row,
      };
      conversations = rows.values.toList()
        ..sort((a, b) {
          final activity = b.activityAt.compareTo(a.activityAt);
          return activity != 0 ? activity : b.id.compareTo(a.id);
        });
      nextConversation = page.nextCursor;
    } catch (failure) {
      if (_current(session) && request == _listRequest) {
        listError = chatError(failure);
        if (failure is PostgrestException && failure.code == '42501') {
          conversations = [];
          nextConversation = null;
        }
      }
    } finally {
      if (_current(session) && request == _listRequest) {
        loadingList = false;
        notifyListeners();
      }
    }
  }

  Future<void> open(String id) async {
    final session = _session;
    try {
      id = chatUuid(id);
    } catch (_) {
      ++_thread;
      selectedId = null;
      selected = null;
      messages = [];
      nextSequence = null;
      threadError = 'Conversation unavailable.';
      notifyListeners();
      return;
    }
    ++_thread;
    ++_historyRequest;
    selectedId = id;
    selected = null;
    messages = [];
    nextSequence = null;
    _historyLoaded = false;
    threadError = null;
    sendError = null;
    readError = null;
    reading = false;
    sending = false;
    await refreshThread();
    if (_current(session)) await _subscribe();
  }

  Future<void> refreshThread({bool older = false}) async {
    final id = selectedId;
    if (id == null ||
        _actor == null ||
        _disposed ||
        older && (loadingThread || nextSequence == null)) {
      return;
    }
    final session = _session, thread = _thread, request = ++_historyRequest;
    final before = older ? nextSequence : null;
    loadingThread = true;
    threadError = null;
    notifyListeners();
    try {
      // Filtered lookup also works for direct URLs outside the first list page.
      final context = await repository.conversations(
        conversationId: id,
        limit: 1,
      );
      if (!_current(session, thread) || request != _historyRequest) return;
      if (context.items.length != 1) {
        throw const PostgrestException(message: 'Unavailable', code: '42501');
      }
      selected = context.items.single;
      final page = await repository.messages(id, beforeSequence: before);
      if (!_current(session, thread) || request != _historyRequest) return;
      final oldIds = messages.map((row) => row.id).toSet();
      final gap =
          !older &&
          messages.isNotEmpty &&
          page.nextBeforeSequence != null &&
          page.items.isNotEmpty &&
          page.items.last.sequence > messages.first.sequence &&
          !page.items.any((row) => oldIds.contains(row.id));
      if (gap || !older && page.items.isEmpty) {
        messages = [];
        nextSequence = null;
        _historyLoaded = false;
      }
      final rows = <String, ChatMessage>{
        if (older || messages.isNotEmpty)
          for (final row in messages) row.id: row,
        for (final row in page.items) row.id: row,
      };
      messages = rows.values.toList()
        ..sort((a, b) => b.sequence.compareTo(a.sequence));
      // A first-page reconcile retains any older pages already loaded.
      if (older || !_historyLoaded) nextSequence = page.nextBeforeSequence;
      _historyLoaded = true;
    } catch (failure) {
      if (_current(session, thread) && request == _historyRequest) {
        threadError = chatError(failure);
        if (failure is PostgrestException && failure.code == '42501') {
          selected = null;
          messages = [];
          nextSequence = null;
          _historyLoaded = false;
        }
      }
    } finally {
      if (_current(session, thread) && request == _historyRequest) {
        loadingThread = false;
        notifyListeners();
      }
    }
  }

  Future<void> send({bool retry = false}) async {
    if (sending ||
        recoveryFailed ||
        selected == null ||
        !retry && threadError != null ||
        !retry && !selected!.canSend) {
      return;
    }
    final id = selectedId!, session = _session, thread = _thread;
    final existing = pending;
    if (retry && existing == null) return;
    if (existing == null) {
      try {
        validateChatBody(draft);
      } on FormatException {
        sendError = 'Enter a nonblank message of at most 4000 characters.';
        notifyListeners();
        return;
      }
    }
    sending = true;
    sendError = null;
    notifyListeners();
    try {
      final saved = existing ?? await repository.prepareSend(id, draft);
      if (!_current(session, thread)) return;
      _pending = repository.pendingSends;
      notifyListeners();
      final receipt = await repository.sendPending(saved);
      if (!_current(session, thread)) return;
      _pending = repository.pendingSends;
      _drafts[id] = receipt.retryRecordRetained ? saved.body : '';
      if (receipt.retryRecordRetained) sendError = 'Message confirmed. Saved retry record remains; retry only to reconcile it.';
      // A validated receipt is persisted; reload canonical history for sender name.
      await refreshThread();
      await loadConversations();
    } catch (failure) {
      if (_current(session, thread)) {
        _pending = repository.pendingSends;
        sendError = chatError(failure, sending: true);
        if (failure is PostgrestException &&
            {'42501', '55000'}.contains(failure.code)) {
          await refreshThread();
        }
      }
    } finally {
      if (_current(session, thread)) {
        sending = false;
        notifyListeners();
      }
    }
  }

  Future<void> markRead(ChatMessage message) async {
    if (reading ||
        !_visible ||
        message.senderId == _actor ||
        message.sequence <= (_readThrough[message.conversationId] ?? 0) ||
        selected == null ||
        message.conversationId != selectedId ||
        !messages.any((row) => row.id == message.id)) {
      return;
    }
    final session = _session, thread = _thread;
    reading = true;
    readError = null;
    notifyListeners();
    try {
      await repository.markRead(message.conversationId, message.id);
      if (_current(session, thread)) {
        _readThrough[message.conversationId] = message.sequence;
        chatReadInvalidations.value++;
        await loadConversations();
      }
    } catch (failure) {
      if (_current(session, thread)) readError = chatError(failure);
    } finally {
      if (_current(session, thread)) {
        reading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    final session = _session;
    await loadConversations();
    if (_current(session) && selectedId != null) await refreshThread();
  }

  Future<void> _subscribe() async {
    if (!_visible || _disposed || _actor == null) return;
    final session = _session, thread = _thread;
    await realtime?.listen(selectedId, () {
      if (_current(session, thread) && _visible) unawaited(refresh());
    });
  }

  void setVisible(bool value) {
    if (_visible == value || _disposed) return;
    _visible = value;
    if (value) {
      unawaited(_subscribe());
      unawaited(refresh());
    } else {
      unawaited(realtime?.stop());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _drafts.clear();
    _pending = [];
    conversations = [];
    messages = [];
    selected = null;
    selectedId = null;
    ++_session;
    ++_thread;
    unawaited(_auth.cancel());
    unawaited(realtime?.stop());
    repository.dispose();
    super.dispose();
  }
}
