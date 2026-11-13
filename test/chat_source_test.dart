import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/chat/chat_models.dart';
import 'package:jobmate/features/chat/chat_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const id = '20000000-0000-0000-0000-000000000001';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late SupabaseChatSource source;
  late List<(String, Object?)> requests;
  late int status;
  late Object? response;
  late Completer<void> received;
  Completer<void>? hold;
  setUp(() async {
    requests = [];
    status = 200;
    response = [];
    hold = null;
    received = Completer<void>();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add((
        request.uri.path,
        jsonDecode(await utf8.decoder.bind(request).join()),
      ));
      expect(request.method, 'POST');
      expect(request.headers.value('authorization'), 'Bearer local-test-token');
      if (!received.isCompleted) received.complete();
      if (hold != null) await hold!.future;
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(response));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'local-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    source = SupabaseChatSource(client);
  });
  Future<void> signIn(String userId) => client.auth.setInitialSession(
    jsonEncode({
      'access_token': 'local-test-token',
      'token_type': 'bearer',
      'user': {'id': userId},
    }),
  );
  tearDown(() async {
    if (hold != null && !hold!.isCompleted) hold!.complete();
    await client.dispose();
    await server.close(force: true);
  });

  test('explicit attachment capability uses basic history without changing other text contracts', () async {
    await signIn(actor);
    final basic = SupabaseChatSource(client, attachmentsEnabled: true);
    await basic.messages(id, limit: 1, beforeSequence: 2);
    expect(requests.single.$1, '/rest/v1/rpc/list_chat_messages_basic_v1');
    expect(requests.single.$2, {
      'p_conversation_id': id,
      'p_limit': 1,
      'p_before_sequence': 2,
    });
  });
  test('five exact RPC names and parameters use current session, no sender parameter', () async {
    await signIn(actor);
    response = id;
    expect(await source.getOrCreate(id), id);
    await source.conversations(
      limit: 25,
      before: ChatConversationCursor(DateTime.utc(2026, 11, 12), id),
      conversationId: id,
    );
    await source.messages(id, limit: 25, beforeSequence: 12);
    await source.send(
      PendingChatSend(
        actorId: actor,
        conversationId: id,
        requestId: id,
        body: 'Exact body 😀',
      ),
    );
    response = 12;
    expect(await source.markRead(id, id), 12);
    final expected = <(String, Map<String, Object?>)>[
      (
        '/rest/v1/rpc/get_or_create_chat_conversation',
        {'p_application_id': id},
      ),
      (
        '/rest/v1/rpc/list_my_chat_conversations',
        {
          'p_limit': 25,
          'p_before_activity_at': '2026-11-12T00:00:00.000Z',
          'p_before_conversation_id': id,
          'p_conversation_id': id,
        },
      ),
      (
        '/rest/v1/rpc/list_chat_messages',
        {'p_conversation_id': id, 'p_limit': 25, 'p_before_sequence': 12},
      ),
      (
        '/rest/v1/rpc/send_chat_message',
        {
          'p_conversation_id': id,
          'p_client_request_id': id,
          'p_body': 'Exact body 😀',
        },
      ),
      (
        '/rest/v1/rpc/mark_chat_conversation_read',
        {'p_conversation_id': id, 'p_message_id': id},
      ),
    ];
    expect(requests.length, expected.length);
    for (var i = 0; i < expected.length; i++) {
      expect(requests[i].$1, expected[i].$1);
      expect(requests[i].$2, expected[i].$2);
    }
  });

  test('unsigned and foreign pending calls dispatch nothing', () async {
    await expectLater(source.getOrCreate(id), throwsA(isA<AuthException>()));
    await signIn(actor);
    await expectLater(
      source.send(
        PendingChatSend(
          actorId: id,
          conversationId: id,
          requestId: id,
          body: 'message',
        ),
      ),
      throwsA(isA<AuthException>()),
    );
    expect(requests, isEmpty);
  });

  test('HTTP failures are not retried by transport', () async {
    await signIn(actor);
    status = 503;
    response = {'code': '503', 'message': 'local failure'};
    await expectLater(
      source.send(
        PendingChatSend(
          actorId: actor,
          conversationId: id,
          requestId: id,
          body: 'message',
        ),
      ),
      throwsA(isA<PostgrestException>()),
    );
    expect(requests, hasLength(1));
  });

  test('session change during HTTP response discards result', () async {
    await signIn(actor);
    hold = Completer<void>();
    final fetching = source.conversations(limit: 50);
    final assertion = expectLater(fetching, throwsA(isA<AuthException>()));
    await received.future;
    await signIn(id);
    hold!.complete();
    await assertion;
  });
}
