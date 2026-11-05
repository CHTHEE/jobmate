import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jobmate/features/work_attendance/work_evidence_preview.dart';

void main() {
  test('private preview uses exact authorization RPC and 90-second private signing, never public URLs', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    final path = '$id/file.pdf';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <(String, Map<String, dynamic>)>[];
    var missing = false;
    server.listen((request) async {
      expect(request.method, 'POST');
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      requests.add((request.uri.path, body));
      request.response.headers.contentType = ContentType.json;
      final isPermission = request.uri.path.endsWith(
        'can_read_work_evidence_file',
      );
      request.response.statusCode = missing && !isPermission ? 404 : 200;
      request.response.write(
        jsonEncode(
          isPermission
              ? true
              : missing
              ? {
                  'statusCode': '404',
                  'error': 'Not Found',
                  'message': 'Missing file',
                }
              : {'signedURL': '/object/sign/work-evidence/$path?token=fake'},
        ),
      );
      await request.response.close();
    });
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });
    final source = SupabaseWorkEvidencePreviewSource(client);
    expect(await source.canRead(path), isFalse);
    await expectLater(source.sign(path, 90), throwsA(isA<AuthException>()));
    expect(requests, isEmpty);
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'fake-token',
        'token_type': 'bearer',
        'user': {'id': id},
      }),
    );
    expect(await source.canRead(path), isTrue);
    final uri = await source.sign(path, 90);
    expect(requests.first.$1, '/rest/v1/rpc/can_read_work_evidence_file');
    expect(requests.first.$2, {'p_storage_path': path});
    expect(requests.last.$1, '/storage/v1/object/sign/work-evidence/$path');
    expect(requests.last.$2['expiresIn'], 90);
    expect(uri.host, '127.0.0.1');
    expect(uri.path, contains('/object/sign/work-evidence/'));
    expect(uri.path, isNot(contains('/object/public/')));
    missing = true;
    await expectLater(source.sign(path, 90), throwsA(isA<StorageException>()));
  });
}
