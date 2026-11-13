import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'chat_models.dart';
import 'chat_pending_store.dart';
import 'chat_source.dart';

class ChatSessionChanged implements Exception {
  const ChatSessionChanged();
}

/// Safe UI text: never display raw server details, tokens or saved message text.
String chatError(Object error, {bool sending = false}) {
  if (error is ChatSessionChanged || error is AuthException) {
    return 'Sign in again to access Chat.';
  }
  if (error is PostgrestException) {
    return switch (error.code) {
      '42501' => 'This conversation is unavailable.',
      '55000' => 'This conversation is read-only. Refresh its status.',
      '22023' =>
        'The message or request is invalid. Keep the saved retry identity.',
      '55P03' ||
      '40001' => 'Chat is busy. Try again with the same saved message.',
      _ =>
        sending
            ? 'Send not confirmed. Keep the saved message and retry identity.'
            : 'Chat could not be loaded. Try again.',
    };
  }
  return sending
      ? 'Send not confirmed. Keep the saved message and retry identity.'
      : 'Chat could not be loaded. Try again.';
}

class ChatSendReceipt {
  const ChatSendReceipt(this.message, {required this.retryRecordRetained});
  final ChatMessage message;
  final bool retryRecordRetained;
}

/// No automatic fetch, conversation creation, restored-send replay or table writes.
class ChatRepository extends ChangeNotifier {
  ChatRepository({
    required this.source,
    required this.pendingStore,
    String Function()? requestId,
    Future<void> Function(Duration)? delay,
  }) : _requestId = requestId ?? const Uuid().v4,
       _delay = delay ?? Future<void>.delayed {
    _actor = source.userId;
    _subscription = source.accountChanges.listen(_setAccount);
  }

  factory ChatRepository.authenticated(
    SupabaseClient client, {
    required String projectUrl,
  }) => ChatRepository(
    source: SupabaseChatSource(client),
    pendingStore: LocalChatPendingStore(
      storage: SharedPreferencesGotrueAsyncStorage(),
      projectUrl: projectUrl,
    ),
  );

  final ChatSource source;
  final ChatPendingStore pendingStore;
  final String Function() _requestId;
  final Future<void> Function(Duration) _delay;
  late final StreamSubscription<String?> _subscription;
  String? _actor;
  int _generation = 0;
  bool _disposed = false;
  List<PendingChatSend> _pending = [];
  final Set<String> _sending = {};

  List<PendingChatSend> get pendingSends {
    _syncAccount();
    return List.unmodifiable(_pending);
  }

  void _syncAccount() {
    _setAccount(source.userId);
  }

  void _setAccount(String? actor) {
    if (_disposed || _actor == actor) return;
    _actor = actor;
    _generation++;
    _pending = [];
    _sending.clear();
    notifyListeners();
  }

  ({String actor, int generation}) _session() {
    _syncAccount();
    if (_disposed || _actor == null) throw const ChatSessionChanged();
    return (actor: chatUuid(_actor), generation: _generation);
  }

  void _check(({String actor, int generation}) session) {
    _syncAccount();
    if (_disposed ||
        session.actor != _actor ||
        session.generation != _generation) {
      throw const ChatSessionChanged();
    }
  }

  Future<Object?> _call(
    ({String actor, int generation}) session,
    Future<Object?> Function() action,
  ) async {
    for (var attempt = 0; ; attempt++) {
      _check(session);
      try {
        final result = await action();
        _check(session);
        return result;
      } on PostgrestException catch (error) {
        _check(session);
        if (!{'55P03', '40001'}.contains(error.code) || attempt >= 2) rethrow;
        await _delay(Duration(milliseconds: 100 * (attempt + 1)));
      }
    }
  }

  void _limit(int limit) {
    if (limit < 1 || limit > 100) throw ArgumentError.value(limit, 'limit');
  }

  Future<String> getOrCreate(String applicationId) async {
    final session = _session();
    final id = chatUuid(applicationId);
    return chatUuid(await _call(session, () => source.getOrCreate(id)));
  }

  Future<ChatConversationPage> conversations({
    int limit = 50,
    ChatConversationCursor? before,
    String? conversationId,
  }) async {
    _limit(limit);
    final session = _session();
    final filter = conversationId == null ? null : chatUuid(conversationId);
    if (before != null) chatUuid(before.conversationId);
    final rows = chatRows(
      await _call(
        session,
        () => source.conversations(
          limit: limit,
          before: before,
          conversationId: filter,
        ),
      ),
      limit,
    ).map(ChatConversation.fromRow).toList();
    final ids = <String>{};
    ChatConversationCursor? previous = before;
    for (final row in rows) {
      final cursor = previous;
      if (!ids.add(row.id) ||
          filter != null && row.id != filter ||
          cursor != null &&
              (row.activityAt.isAfter(cursor.activityAt) ||
                  row.activityAt.isAtSameMomentAs(cursor.activityAt) &&
                      row.id.compareTo(chatUuid(cursor.conversationId)) >= 0)) {
        throw const FormatException('Invalid Chat conversation order.');
      }
      previous = row.cursor;
    }
    return ChatConversationPage(
      rows,
      rows.length == limit ? rows.last.cursor : null,
    );
  }

  Future<ChatMessagePage> messages(
    String conversationId, {
    int limit = 50,
    int? beforeSequence,
  }) async {
    _limit(limit);
    final session = _session();
    final id = chatUuid(conversationId);
    if (beforeSequence != null) chatInteger(beforeSequence, minimum: 1);
    final rows = chatRows(
      await _call(
        session,
        () => source.messages(id, limit: limit, beforeSequence: beforeSequence),
      ),
      limit,
    ).map((row) => ChatMessage.fromRow(row)).toList();
    final ids = <String>{};
    int? previous = beforeSequence;
    for (final row in rows) {
      if (row.conversationId != id ||
          !ids.add(row.id) ||
          previous != null && row.sequence >= previous) {
        throw const FormatException('Invalid Chat history order.');
      }
      previous = row.sequence;
    }
    return ChatMessagePage(
      rows,
      rows.length == limit ? rows.last.sequence : null,
    );
  }

  Future<void> restorePending() async {
    final session = _session();
    final rows = await pendingStore.load(session.actor);
    _check(session);
    _pending = rows;
    notifyListeners();
  }

  Future<PendingChatSend> prepareSend(
    String conversationId,
    String body,
  ) async {
    final session = _session();
    final saved = await pendingStore.prepare(
      PendingChatSend(
        actorId: session.actor,
        conversationId: conversationId,
        requestId: _requestId(),
        body: body,
      ),
    );
    _check(session);
    await restorePending();
    _check(session);
    return saved;
  }

  /// Any exception before a validated response leaves the immutable retry record.
  /// In particular a transport/parse failure can have an unknown commit outcome.
  Future<ChatSendReceipt> sendPending(PendingChatSend pending) async {
    final session = _session();
    if (pending.actorId != session.actor) throw const ChatSessionChanged();
    final operation = '${session.generation}:${pending.requestId}';
    if (!_sending.add(operation)) {
      throw StateError('Message send is already running.');
    }
    try {
      final saved = await pendingStore.load(session.actor);
      _check(session);
      if (!saved.any(
        (row) =>
            row.requestId == pending.requestId &&
            row.conversationId == pending.conversationId &&
            row.body == pending.body,
      )) {
        throw StateError('Save the exact message before sending.');
      }
      final rows = chatRows(
        await _call(session, () => source.send(pending)),
        1,
      );
      if (rows.length != 1) {
        throw const FormatException('Missing Chat send result.');
      }
      final message = ChatMessage.fromRow(rows.single, sentResult: true);
      if (message.senderId != session.actor ||
          message.conversationId != pending.conversationId ||
          message.body != pending.body) {
        throw const FormatException('Mismatched Chat send result.');
      }
      var retained = false;
      try {
        await pendingStore.remove(pending);
      } catch (_) {
        retained = true;
      }
      _check(session);
      if (!retained) {
        _pending = _pending
            .where((row) => row.requestId != pending.requestId)
            .toList();
        notifyListeners();
      }
      return ChatSendReceipt(message, retryRecordRetained: retained);
    } finally {
      _sending.remove(operation);
    }
  }

  Future<int> markRead(String conversationId, String messageId) async {
    final session = _session();
    final conversation = chatUuid(conversationId),
        message = chatUuid(messageId);
    return chatInteger(
      await _call(session, () => source.markRead(conversation, message)),
      minimum: 1,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _pending = [];
    _sending.clear();
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
