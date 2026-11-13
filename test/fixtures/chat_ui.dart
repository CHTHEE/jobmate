import 'dart:async';

import 'package:jobmate/features/chat/chat_models.dart';
import 'package:jobmate/features/chat/chat_pending_store.dart';
import 'package:jobmate/features/chat/chat_realtime.dart';
import 'package:jobmate/features/chat/chat_repository.dart';
import 'package:jobmate/features/chat/chat_source.dart';
import 'package:jobmate/features/chat/chat_ui_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String chatId(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
final chatActor = chatId(1),
    chatOther = chatId(2),
    chatConversation = chatId(3),
    chatApplication = chatId(4);
Map<String, dynamic> conversationRow({
  int id = 3,
  int last = 2,
  bool canSend = true,
}) => {
  'conversation_id': chatId(id),
  'application_id': chatApplication,
  'job_id': chatId(5),
  'job_title': 'Event assistant',
  'company_name': 'Example company',
  'worker_name': 'Example worker',
  'application_status': canSend ? 'hired' : 'withdrawn',
  'created_at': '2026-11-13T00:00:00Z',
  'activity_at': '2026-11-13T00:01:00Z',
  'last_message_preview': last == 0 ? null : 'Message $last',
  'last_message_at': last == 0 ? null : '2026-11-13T00:01:00Z',
  'last_sequence': last,
  'unread_count': last == 0 ? 0 : 1,
  'can_send': canSend,
  'read_only_reason': canSend ? null : 'application_terminal',
};
Map<String, dynamic> messageRow(int sequence) => {
  'message_id': chatId(1000 + sequence),
  'conversation_id': chatConversation,
  'sender_id': sequence.isEven ? chatActor : chatOther,
  'sender_name': 'Participant',
  'body': 'Message $sequence',
  'sent_at': '2026-11-13T00:01:00Z',
  'sequence': sequence,
};

class ChatFixtureSource implements ChatSource {
  @override
  String? userId = chatActor;
  final accounts = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get accountChanges => accounts.stream;
  List<Map<String, dynamic>> inbox = [conversationRow()];
  List<Map<String, dynamic>> history = [messageRow(2), messageRow(1)];
  final sends = <PendingChatSend>[];
  final commits = <String, Map<String, dynamic>>{};
  int creates = 0, reads = 0, marks = 0;
  int? lastBefore;
  ChatConversationCursor? lastCursor;
  PostgrestException? failure;
  Completer<Object?>? hold;
  Future<Object?> Function(PendingChatSend)? onSend;
  @override
  Future<Object?> conversations({
    required int limit,
    ChatConversationCursor? before,
    String? conversationId,
  }) async {
    reads++;
    lastCursor = before;
    if (failure != null) throw failure!;
    if (hold != null) return hold!.future;
    final rows =
        inbox
            .where(
              (row) =>
                  (conversationId == null ||
                      row['conversation_id'] == conversationId) &&
                  (before == null ||
                      (row['conversation_id'] as String).compareTo(
                            before.conversationId,
                          ) <
                          0),
            )
            .toList()
          ..sort(
            (a, b) => (b['conversation_id'] as String).compareTo(
              a['conversation_id'] as String,
            ),
          );
    return rows.take(limit).toList();
  }

  @override
  Future<Object?> messages(
    String conversationId, {
    required int limit,
    int? beforeSequence,
  }) async {
    reads++;
    lastBefore = beforeSequence;
    if (failure != null) throw failure!;
    return history
        .where(
          (row) =>
              beforeSequence == null ||
              (row['sequence'] as int) < beforeSequence,
        )
        .take(limit)
        .toList();
  }

  Map<String, dynamic> commit(PendingChatSend request) =>
      commits.putIfAbsent(request.requestId, () {
        final sequence = history.isEmpty
            ? 1
            : (history.first['sequence'] as int) + 1;
        final row = {
          ...messageRow(sequence),
          'sender_id': request.actorId,
          'body': request.body,
        };
        history.insert(0, row);
        inbox = [conversationRow(last: sequence)];
        return row;
      });
  @override
  Future<Object?> send(PendingChatSend request) async {
    sends.add(request);
    if (onSend != null) return onSend!(request);
    return [commit(request)];
  }

  @override
  Future<Object?> getOrCreate(String applicationId) async {
    creates++;
    return chatConversation;
  }

  @override
  Future<Object?> markRead(String conversationId, String messageId) async {
    if (failure != null) throw failure!;
    marks++;
    inbox = inbox.map((row) => {...row, 'unread_count': 0}).toList();
    return 2;
  }

  void changeAccount(String? id) {
    userId = id;
    accounts.add(id);
  }
}

class ChatFixtureStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  final pending = <String, List<PendingChatSend>>{};
  bool fail = false;
  @override
  Future<String?> getItem({required String key}) async {
    if (fail) throw StateError('storage unavailable');
    return values[key];
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

class ChatFixturePendingStore implements ChatPendingStore {
  ChatFixturePendingStore(this.storage);
  final ChatFixtureStorage storage;
  @override
  Future<List<PendingChatSend>> load(String actorId) async {
    if (storage.fail) throw StateError('storage unavailable');
    return [...storage.pending[actorId] ?? []];
  }

  @override
  Future<PendingChatSend> prepare(PendingChatSend row) async {
    final rows = await load(row.actorId);
    final old = rows
        .where((item) => item.conversationId == row.conversationId)
        .firstOrNull;
    if (old != null) {
      if (old.body != row.body) throw StateError('Resolve saved message.');
      return old;
    }
    storage.pending[row.actorId] = [...rows, row];
    return row;
  }

  @override
  Future<void> remove(PendingChatSend row) async {
    storage.pending[row.actorId] = (await load(row.actorId))
        .where((item) => item.requestId != row.requestId)
        .toList();
  }
}

class ChatFixtureFeed implements ChatRealtime {
  void Function()? callback;
  int subscriptions = 0, stops = 0;
  @override
  Future<void> listen(String? id, void Function() reconcile) async {
    subscriptions++;
    callback = reconcile;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

ChatUiController fixtureChatUi({
  ChatFixtureSource? source,
  ChatFixtureStorage? storage,
  ChatFixtureFeed? feed,
}) {
  final actor = source ?? ChatFixtureSource();
  return ChatUiController(
    repository: ChatRepository(
      source: actor,
      pendingStore: ChatFixturePendingStore(storage ?? ChatFixtureStorage()),
      delay: (_) async {},
    ),
    realtime: feed,
  );
}
