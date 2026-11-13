import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/chat/chat_attachment_draft.dart';
import 'package:jobmate/features/chat/chat_attachments.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/chat_ui.dart';

void main() {
  test('installed Supabase SDK sends real binary chunk/query/identity and parses typed attachment receipt (loopback only)', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'local-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'local-test-token',
        'token_type': 'bearer',
        'user': {'id': chatActor},
      }),
    );
    final files = ChatAttachmentsController(
      SupabaseChatAttachmentGateway(client, enabled: true),
    );
    final draft = ChatAttachmentDraft.select(
      'a.pdf',
      Uint8List.fromList([37, 80, 68, 70, 45]),
    );
    Map<String, dynamic>? row;
    var binary = 0, commits = 0;
    final rpcNames = <String>[];
    server.listen((request) async {
      final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(request.headers.value('authorization'), 'Bearer local-test-token');
      Object? response;
      if (request.uri.path.endsWith('/reserve_chat_attachment_basic_v1')) {
        final args = jsonDecode(utf8.decode(bytes)) as Map;
        expect(args['p_sha256'], draft.digest);
        row = {
          'attachment_id': args['p_attachment_id'],
          'conversation_id': chatConversation,
          'sender_id': chatActor,
          'client_request_id': args['p_client_request_id'],
          'message_id': null,
          'original_name': 'a.pdf',
          'mime_type': 'application/pdf',
          'size_bytes': 5,
          'expected_sha256': draft.digest,
          'caption': null,
          'storage_path': null,
          'state': 'pending',
          'validation_scope': 'basic-type-validation-no-antivirus-v1',
        };
        response = row;
      } else if (request.uri.path == '/functions/v1/chat-basic-attachments') {
        expect(request.headers.value('x-attachment-id'), row!['attachment_id']);
        if (request.uri.queryParameters['op'] == 'upload') {
          expect(bytes, draft.bytes);
          expect(request.headers.value('x-chunk-index'), '0');
          expect(
            request.headers.contentType!.mimeType,
            'application/octet-stream',
          );
          binary++;
          response = {'received': 5};
        } else {
          expect(request.uri.queryParameters['op'], 'validate');
          row!['state'] = 'validated';
          response = row;
        }
      } else if (request.uri.path.endsWith('/send_chat_attachment_basic_v1')) {
        commits++;
        row!['state'] = 'committed';
        row!['message_id'] = chatId(77);
        row!['storage_path'] =
            '$chatConversation/$chatActor/${row!['attachment_id']}/file';
        response = {
          ...messageRow(3),
          'message_id': chatId(77),
          'sender_id': chatActor,
          'body': 'Attachment: a.pdf',
          'caption': null,
          'attachment': row,
        };
      } else {
        expect(
          request.uri.path.endsWith('/get_chat_attachment_basic_v1'),
          true,
        );
        response = row;
      }
      rpcNames.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    try {
      files.select(draft);
      await files.run(chatConversation, '');
      expect(files.error, isEmpty);
      expect(files.receipt!.attachment!.name, 'a.pdf');
      expect(binary, 1);
      expect(commits, 1);
      expect(rpcNames.length, 5);
    } finally {
      files.dispose();
      await client.dispose();
      await server.close(force: true);
    }
  });
  test('disabled gateway fails before network access', () async {
    final client = SupabaseClient(
      'http://127.0.0.1:1',
      'local-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    try {
      await expectLater(
        SupabaseChatAttachmentGateway(client, enabled: false).status(chatId(1)),
        throwsStateError,
      );
    } finally {
      await client.dispose();
    }
  });
}
