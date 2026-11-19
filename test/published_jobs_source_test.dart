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
    var includeTotal = true;
    server.listen((request) async {
      paths.add(request.uri.path);
      expect(request.method, 'POST');
      if (includeTotal) {
        expect(request.headers.value('prefer'), contains('count=exact'));
        request.response.headers.set('content-range', '0-6/7');
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode([
          for (var index = 0; index < 7; index++) {'job_id': 'job-$index'},
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
    final result = await SupabasePublishedJobsSource(client).list();
    expect(result.rows, hasLength(7));
    expect(result.total, 7);
    expect(paths, ['/rest/v1/rpc/list_published_jobs']);
    includeTotal = false;
    final unverified = await SupabasePublishedJobsSource(client).list();
    expect(unverified.rows, hasLength(7));
    expect(unverified.total, isNull);
    expect(paths, everyElement('/rest/v1/rpc/list_published_jobs'));
  });
}
