import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/chat/chat_models.dart';
import 'package:jobmate/features/chat/chat_pending_store.dart';
import 'package:jobmate/features/chat/chat_repository.dart';
import 'package:jobmate/features/chat/chat_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const other = '10000000-0000-0000-0000-000000000002';
const conversation = '20000000-0000-0000-0000-000000000001';
const request = '30000000-0000-0000-0000-000000000001';
const message = '40000000-0000-0000-0000-000000000001';

Map<String, dynamic> messageRow({int sequence = 1, bool history = false}) => {
  'message_id': message,
  'conversation_id': conversation,
  'sender_id': actor,
  if (history) 'sender_name': 'Worker',
  'body': ' hello 😀 ',
  'sent_at': '2026-11-12T01:00:00+00:00',
  'sequence': sequence,
};

Map<String, dynamic> conversationRow() => {
  'conversation_id': conversation,
  'application_id': request,
  'job_id': message,
  'job_title': 'Existing job',
  'company_name': 'Company',
  'worker_name': 'Worker',
  'application_status': 'submitted',
  'created_at': '2026-11-12T00:00:00Z',
  'activity_at': '2026-11-12T00:00:00Z',
  'last_message_preview': null,
  'last_message_at': null,
  'last_sequence': 0,
  'unread_count': 0,
  'can_send': true,
  'read_only_reason': null,
};

class MemoryStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  bool dropWrites = false;
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    if (!dropWrites) values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

class FakeSource implements ChatSource {
  @override
  String? userId = actor;
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get accountChanges => changes.stream;
  void switchTo(String? id) {
    userId = id;
    changes.add(id);
  }

  Object? conversationResult = [conversationRow()];
  Object? messageResult = [messageRow(history: true)];
  Future<Object?> Function(PendingChatSend)? onSend;
  Future<Object?> Function()? onConversations;
  int sends = 0, reads = 0;
  int? beforeSequence;
  ChatConversationCursor? before;
  @override
  Future<Object?> getOrCreate(String applicationId) async => conversation;
  @override
  Future<Object?> conversations({
    required int limit,
    ChatConversationCursor? before,
    String? conversationId,
  }) async {
    reads++;
    this.before = before;
    return onConversations == null
        ? conversationResult
        : await onConversations!();
  }

  @override
  Future<Object?> messages(
    String conversationId, {
    required int limit,
    int? beforeSequence,
  }) async {
    this.beforeSequence = beforeSequence;
    return messageResult;
  }

  @override
  Future<Object?> send(PendingChatSend pending) async {
    sends++;
    return onSend == null ? [messageRow()] : await onSend!(pending);
  }

  @override
  Future<Object?> markRead(String conversationId, String messageId) async => 1;
}

void main() {
  late FakeSource source;
  late MemoryStorage disk;
  late LocalChatPendingStore store;
  late ChatRepository repository;
  LocalChatPendingStore newStore() => LocalChatPendingStore(
    storage: disk,
    projectUrl: 'https://existing-project.supabase.co',
  );

  setUp(() {
    source = FakeSource();
    disk = MemoryStorage();
    store = newStore();
    repository = ChatRepository(
      source: source,
      pendingStore: store,
      requestId: () => request,
      delay: (_) async {},
    );
  });
  tearDown(() async {
    repository.dispose();
    await source.changes.close();
  });

  test('strict nullable conversation fields and send/history contracts', () {
    final row = conversationRow();
    expect(ChatConversation.fromRow(row).lastMessageAt, isNull);
    expect(
      ChatMessage.fromRow(messageRow(), sentResult: true).senderName,
      isNull,
    );
    expect(() => ChatMessage.fromRow(messageRow()), throwsFormatException);
    for (final key in row.keys) {
      expect(
        () => ChatConversation.fromRow({...row}..remove(key)),
        throwsFormatException,
        reason: 'missing $key',
      );
    }
    expect(
      () => ChatConversation.fromRow({...row, 'can_send': 'true'}),
      throwsFormatException,
    );
    expect(
      () => ChatConversation.fromRow({...row, 'application_status': 'future'}),
      throwsFormatException,
    );
    expect(() => chatInteger(1.0), throwsFormatException);
    expect(() => chatInteger(9007199254740992), throwsFormatException);
    expect(() => chatTime('2026-11-12'), throwsFormatException);
    expect(() => chatTime('2026-02-30T00:00:00Z'), throwsFormatException);
    expect(() => chatTime('2026-11-12T24:00:00Z'), throwsFormatException);
    expect(() => chatRows({}, 50), throwsFormatException);
  });

  test(
    'Unicode counts codepoints, preserves body and rejects blank/invalid text',
    () {
      validateChatBody(List.filled(4000, '😀').join());
      validateChatBody(' hello 😀 ');
      for (final body in [
        '',
        '\t\n\u0085\u00a0\u1680\u200a\u202f\u3000',
        List.filled(4001, '😀').join(),
        '\u0000',
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
      ]) {
        expect(() => validateChatBody(body), throwsFormatException);
      }
    },
  );

  test(
    'conversation paired cursor, page boundaries and invalid order',
    () async {
      final page = await repository.conversations(limit: 1);
      expect(page.nextCursor!.conversationId, conversation);
      source.conversationResult = [];
      expect(
        (await repository.conversations(before: page.nextCursor)).nextCursor,
        isNull,
      );
      expect(source.before, same(page.nextCursor));
      source.conversationResult = [conversationRow()];
      await expectLater(
        repository.conversations(before: page.nextCursor),
        throwsFormatException,
      );
      source.conversationResult = [conversationRow(), conversationRow()];
      await expectLater(repository.conversations(), throwsFormatException);
      await expectLater(
        repository.conversations(limit: 0),
        throwsArgumentError,
      );
    },
  );

  test('message sequence paging rejects duplicates, wrong conversation and scalar result', () async {
    source.messageResult = [
      messageRow(sequence: 3, history: true),
      {...messageRow(sequence: 2, history: true), 'message_id': request},
    ];
    final page = await repository.messages(
      conversation,
      limit: 2,
      beforeSequence: 4,
    );
    expect(page.nextBeforeSequence, 2);
    expect(source.beforeSequence, 4);
    source.messageResult = [messageRow(sequence: 3, history: true)];
    await expectLater(
      repository.messages(conversation, beforeSequence: 3),
      throwsFormatException,
    );
    source.messageResult = [
      {...messageRow(history: true), 'conversation_id': other},
    ];
    await expectLater(repository.messages(conversation), throwsFormatException);
    source.messageResult = 'wrong';
    await expectLater(repository.messages(conversation), throwsFormatException);
  });

  test(
    'persistent before send; retry after restart keeps exact UUID/body',
    () async {
      final pending = await repository.prepareSend(conversation, ' hello 😀 ');
      source.onSend = (row) async {
        expect(
          (await newStore().load(actor)).single.toJson(),
          pending.toJson(),
        );
        throw TimeoutException('simulated lost response');
      };
      await expectLater(
        repository.sendPending(pending),
        throwsA(isA<TimeoutException>()),
      );
      expect(source.sends, 1);
      repository.dispose();
      repository = ChatRepository(
        source: source,
        pendingStore: newStore(),
        requestId: () => other,
      );
      await repository.restorePending();
      expect(source.sends, 1); // Restore never replays.
      final restored = await repository.prepareSend(conversation, ' hello 😀 ');
      expect(restored.requestId, request);
      await expectLater(
        repository.prepareSend(conversation, 'changed'),
        throwsStateError,
      );
      source.onSend = null;
      final receipt = await repository.sendPending(restored);
      expect(receipt.message.body, ' hello 😀 ');
      expect(receipt.retryRecordRetained, isFalse);
      expect(await newStore().load(actor), isEmpty);
    },
  );

  test(
    'only lock and serialization failures retry, at most three identical sends',
    () async {
      final pending = await repository.prepareSend(conversation, ' hello 😀 ');
      for (final code in ['55P03', '40001', '42501', '55000', '22023']) {
        source.sends = 0;
        source.onSend = (row) async {
          expect(row.toJson(), pending.toJson());
          throw PostgrestException(message: 'simulated', code: code);
        };
        await expectLater(
          repository.sendPending(pending),
          throwsA(isA<PostgrestException>()),
        );
        expect(source.sends, {'55P03', '40001'}.contains(code) ? 3 : 1);
      }
    },
  );

  test(
    'account switch clears state, hides owner disk, invalidates A-B-A read',
    () async {
      await repository.prepareSend(conversation, ' hello 😀 ');
      final held = Completer<Object?>();
      source.onConversations = () => held.future;
      final reading = repository.conversations();
      final assertion = expectLater(
        reading,
        throwsA(isA<ChatSessionChanged>()),
      );
      source.switchTo(other);
      expect(repository.pendingSends, isEmpty);
      await repository.restorePending();
      expect(repository.pendingSends, isEmpty);
      source.switchTo(actor);
      held.complete([conversationRow()]);
      await assertion;
      await repository.restorePending();
      expect(repository.pendingSends.single.actorId, actor);
      source.switchTo(null);
      expect(repository.pendingSends, isEmpty);
      await expectLater(
        repository.messages(conversation),
        throwsA(isA<ChatSessionChanged>()),
      );
    },
  );

  test(
    'failed persistence and corrupt owner records fail before network',
    () async {
      disk.dropWrites = true;
      await expectLater(
        repository.prepareSend(conversation, ' hello 😀 '),
        throwsStateError,
      );
      expect(source.sends, 0);
      disk.dropWrites = false;
      await repository.prepareSend(conversation, ' hello 😀 ');
      disk.values.updateAll(
        (_, value) => jsonEncode({
          'version': 1,
          'pending': [
            {
              ...PendingChatSend(
                actorId: other,
                conversationId: conversation,
                requestId: request,
                body: ' hello 😀 ',
              ).toJson(),
            },
          ],
        }),
      );
      await expectLater(repository.restorePending(), throwsFormatException);
      expect(source.sends, 0);
    },
  );

  test('invalid send response retains retry record; failed cleanup reports confirmed receipt', () async {
    final pending = await repository.prepareSend(conversation, ' hello 😀 ');
    source.onSend = (_) async => [
      {...messageRow(), 'body': 'wrong'},
    ];
    await expectLater(repository.sendPending(pending), throwsFormatException);
    expect((await store.load(actor)).single.requestId, request);
    source.onSend = (_) async {
      disk.dropWrites = true;
      return [messageRow()];
    };
    final receipt = await repository.sendPending(pending);
    expect(receipt.retryRecordRetained, isTrue);
    expect(receipt.message.id, message);
  });

  test('account switch during retry delay prevents another dispatch', () async {
    repository.dispose();
    repository = ChatRepository(
      source: source,
      pendingStore: store,
      requestId: () => request,
      delay: (_) async => source.switchTo(other),
    );
    final pending = await repository.prepareSend(conversation, ' hello 😀 ');
    source.onSend = (_) async =>
        throw const PostgrestException(message: 'busy', code: '55P03');
    await expectLater(
      repository.sendPending(pending),
      throwsA(isA<ChatSessionChanged>()),
    );
    expect(source.sends, 1);
    expect(repository.pendingSends, isEmpty);
    expect((await store.load(actor)).single.requestId, request);
  });

  test(
    'late confirmed send after logout does not surface or clear pending',
    () async {
      final pending = await repository.prepareSend(conversation, ' hello 😀 ');
      final held = Completer<Object?>(), dispatched = Completer<void>();
      source.onSend = (_) {
        dispatched.complete();
        return held.future;
      };
      final sending = repository.sendPending(pending);
      final assertion = expectLater(
        sending,
        throwsA(isA<ChatSessionChanged>()),
      );
      await dispatched.future;
      source.switchTo(null);
      held.complete([messageRow()]);
      await assertion;
      expect(repository.pendingSends, isEmpty);
      expect((await store.load(actor)).single.requestId, request);
    },
  );

  test(
    'contention recovery returns confirmed result with same identity',
    () async {
      final pending = await repository.prepareSend(conversation, ' hello 😀 ');
      source.onSend = (row) async {
        expect(row.requestId, pending.requestId);
        if (source.sends < 3) {
          throw const PostgrestException(message: 'busy', code: '40001');
        }
        return [messageRow()];
      };
      expect((await repository.sendPending(pending)).message.id, message);
      expect(source.sends, 3);
      expect(await store.load(actor), isEmpty);
    },
  );

  test(
    'foreign pending cannot dispatch; read marking uses scalar cursor',
    () async {
      await expectLater(
        repository.sendPending(
          PendingChatSend(
            actorId: other,
            conversationId: conversation,
            requestId: request,
            body: ' hello 😀 ',
          ),
        ),
        throwsA(isA<ChatSessionChanged>()),
      );
      expect(source.sends, 0);
      expect(await repository.markRead(conversation, message), 1);
      expect(await repository.getOrCreate(request), conversation);
    },
  );
}
