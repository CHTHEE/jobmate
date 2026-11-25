import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/features/recommendations/recommendation_explanations.dart';
import 'package:jobmate/features/recommendations/supabase_recommendation_explanation_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('published feed retrieves remaining rows when exact count exceeds the first page', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'fixture-anon',
    );
    addTearDown(client.dispose);
    final requests = <(String?, String?, String?)>[];
    server.listen((request) async {
      await request.drain<void>();
      final params = request.uri.queryParameters;
      requests.add((
        params['order'],
        params['offset'],
        request.headers.value('prefer'),
      ));
      request.response.headers.contentType = ContentType.json;
      if (params['offset'] == null) {
        request.response.headers.set('content-range', '0-1/3');
        request.response.write('[{"job_id":"a"},{"job_id":"b"}]');
      } else {
        request.response.write('[{"job_id":"c"}]');
      }
      await request.response.close();
    });
    final result = await SupabasePublishedJobsSource(client).list();
    expect(result.total, 3);
    expect(result.rows.map((row) => row['job_id']), ['a', 'b', 'c']);
    expect(requests, [
      ('job_id.asc.nullslast', null, 'count=exact'),
      ('job_id.asc.nullslast', '2', null),
    ]);
  });

  test(
    'Supabase notes adapter sends IDs only and discards older sessions',
    () async {
      const firstUser = '00000000-0000-0000-0000-000000000001';
      const nextUser = '00000000-0000-0000-0000-000000000002';
      const jobId = '00000000-0000-0000-0000-000000000003';
      String segment(Map<String, Object> value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      String token(String id) => [
        segment({'alg': 'HS256'}),
        segment({
          'sub': id,
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        }),
        'fixture-signature',
      ].join('.');

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'fixture-anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final requests = <(String, String?, Object?)>[];
      final response = {
        'insights_version': 1,
        'insights': [
          {
            'job_id': jobId,
            'strong': {'why': 's', 'consider': 'r', 'next': 'p'},
            'partial': {'why': 'b', 'consider': 'g', 'next': 'u'},
            'limited': {'why': '0', 'consider': 'l', 'next': 'r'},
          },
        ],
      };
      final entered = Completer<void>();
      final release = Completer<void>();
      var pause = false;
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/auth/v1/token') {
          final id = (body as Map)['email'] == 'first@example.test'
              ? firstUser
              : nextUser;
          request.response.write(
            jsonEncode({
              'access_token': token(id),
              'refresh_token': 'fixture-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {'id': id, 'app_metadata': {}, 'user_metadata': {}},
            }),
          );
        } else {
          requests.add((
            request.uri.path,
            request.headers.value('authorization'),
            body,
          ));
          if (pause) {
            entered.complete();
            await release.future;
          }
          request.response.write(jsonEncode(response));
        }
        await request.response.close();
      });
      final adapter = SupabaseRecommendationExplanationSource(client);
      final job = ExplanationJob.fromJob(
        BrowseJob.published({'job_id': jobId}),
      );
      await expectLater(adapter.fetch([job]), throwsStateError);
      await client.auth.signInWithPassword(
        email: 'first@example.test',
        password: 'fixture-password',
      );
      await expectLater(adapter.fetch([]), throwsArgumentError);
      await expectLater(adapter.fetch([job, job]), throwsArgumentError);
      expect(requests, isEmpty);
      expect(await adapter.fetch([job]), response);
      final (path, bearer, body) = requests.single;
      expect(path, '/functions/v1/recommendation-insights');
      expect(bearer, startsWith('Bearer '));
      expect(body, {
        'job_ids': [jobId],
        'insights_version': 1,
      });

      pause = true;
      final stale = expectLater(adapter.fetch([job]), throwsStateError);
      await entered.future;
      await client.auth.signInWithPassword(
        email: 'second@example.test',
        password: 'fixture-password',
      );
      release.complete();
      await stale;
    },
  );
}
