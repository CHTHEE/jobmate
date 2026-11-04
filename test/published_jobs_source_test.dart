import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'Logo signing uses the private bucket with a 300-second lifetime',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      final bodies = <dynamic>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'signedURL': '/object/sign/logo?token=test'}),
        );
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final url = await SupabasePublishedJobsSource(client)
          .signLogo('owner/profile/logo.png');
      expect(url, contains('/object/sign/logo?token=test'));
      expect(paths, [
        '/storage/v1/object/sign/jobmate-company-logos/owner/profile/logo.png',
      ]);
      expect(bodies.single, {'expiresIn': 300});
    },
  );
  test('Supabase source calls only the published jobs RPC', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final paths = <String>[];
    server.listen((request) async {
      paths.add(request.uri.path);
      expect(request.method, 'POST');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode([
          {'job_id': 'real-id'},
        ]),
      );
      await request.response.close();
    });
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    final rows = await SupabasePublishedJobsSource(client).list();
    expect(rows.single['job_id'], 'real-id');
    expect(paths, ['/rest/v1/rpc/list_published_jobs']);
  });
}
