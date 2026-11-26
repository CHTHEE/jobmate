import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/job_discovery_place_search.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'seeker client sends the session bearer and parses place responses',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      const userId = '12345678-1234-1234-1234-123456789012';
      String segment(Map<String, Object> json) =>
          base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
      final jwt = [
        segment({'alg': 'HS256'}),
        segment({
          'sub': userId,
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        }),
        'test-signature',
      ].join('.');
      const place = {
        'name': 'Mid Valley Megamall',
        'address': 'Kuala Lumpur, Malaysia',
        'latitude': 3.118,
        'longitude': 101.677,
      };
      Object payload = {
        'places': [place],
      };
      var status = 200;
      final functionRequests = <(String, String?, Object?)>[];
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/auth/v1/token') {
          request.response.write(
            jsonEncode({
              'access_token': jwt,
              'refresh_token': 'test-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {'id': userId, 'app_metadata': {}, 'user_metadata': {}},
            }),
          );
        } else {
          functionRequests.add((
            request.uri.path,
            request.headers.value('authorization'),
            body,
          ));
          request.response.statusCode = status;
          request.response.write(jsonEncode(payload));
        }
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      Future<List<DiscoveryPlace>> search() =>
          searchJobDiscoveryPlaces('  Mid Valley  ', client: client);
      await expectLater(search(), throwsException);
      expect(functionRequests, isEmpty);
      await client.auth.signInWithPassword(
        email: 'seeker@example.test',
        password: 'test-password',
      );
      expect((await search()).single, (
        name: place['name'],
        address: place['address'],
        coordinates: (latitude: 3.118, longitude: 101.677),
      ));
      final (path, bearer, body) = functionRequests.single;
      expect(path, '/functions/v1/search-job-discovery-places');
      expect(bearer, 'Bearer $jwt');
      expect(body, {'query': 'Mid Valley'});

      payload = {'places': []};
      expect(await search(), isEmpty);
      payload = {'places': 'invalid'};
      await expectLater(search(), throwsFormatException);
      payload = {
        'places': [
          {...place, 'longitude': 181},
        ],
      };
      await expectLater(search(), throwsFormatException);
      for (final code in [401, 403, 404, 429, 503, 504]) {
        status = code;
        payload = {'error': 'test-error'};
        await expectLater(
          search(),
          throwsA(
            isA<FunctionException>().having(
              (error) => error.status,
              'status',
              code,
            ),
          ),
        );
      }
    },
  );
}
