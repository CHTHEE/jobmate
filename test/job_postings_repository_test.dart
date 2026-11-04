import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'job_postings_test.dart' show completeJob;

// Exercise the real RPC transport while isolating the unchanged account lookup.
class AuthorizedJobs extends JobPostingsRepository {
  AuthorizedJobs(super.client);
  JobAccess access = const JobAccess({'company_id': 'company-id'}, null);

  @override
  Future<JobAccess> loadAccess() async => access;
}

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late AuthorizedJobs repository;
  late List<(String, Map<String, dynamic>, String?)> requests;
  late Object? response;
  late int responseStatus;

  setUp(() async {
    requests = [];
    response = null;
    responseStatus = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      requests.add((
        request.uri.path,
        Map<String, dynamic>.from(body as Map),
        request.headers.value('accept'),
      ));
      request.response
        ..statusCode = responseStatus
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(response));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    repository = AuthorizedJobs(client);
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  Map<String, dynamic> posting(String id, String status) => {
    ...completeJob(),
    'job_id': id,
    'status': status,
    'ai_assisted': true,
    'created_at': '2026-11-04T01:00:00Z',
    'published_at': null,
    'latitude': 3.1,
    'future_field': {'retained': true},
  };

  test('List preserves server ordering and every returned field', () async {
    final rows = [posting('newer', 'published'), posting('older', 'draft')];
    response = rows;
    expect(await repository.list('company-id'), rows);
    expect(requests.single.$1, '/rest/v1/rpc/list_employer_job_postings');
    expect(requests.single.$2, {'p_company_id': 'company-id'});
    response = [];
    expect(await repository.list('company-id'), isEmpty);
  });

  test(
    'Create returns complete row and preserves protected-field filtering',
    () async {
      response = posting('new-id', 'draft');
      final values = {
        ...completeJob(),
        'status': 'draft',
        'company_id': 'spoofed',
        'created_by': 'spoofed',
        'job_id': 'spoofed',
        'created_at': 'spoofed',
        'published_at': 'spoofed',
      };
      expect(await repository.save(values), response);
      expect(values['company_id'], 'spoofed');
      expect(requests.single.$1, '/rest/v1/rpc/save_employer_job_posting');
      expect(requests.single.$2, {
        'p_company_id': 'company-id',
        'p_values': {...completeJob(), 'status': 'draft', 'ai_assisted': false},
        'p_job_id': null,
        'p_expected_status': 'draft',
      });
      expect(requests.single.$3, contains('application/vnd.pgrst.object+json'));
    },
  );

  test(
    'List publish sends only status, leaving omitted fields untouched',
    () async {
      response = posting('existing', 'published');
      expect(
        await repository.save({'status': 'published'}, jobId: 'existing'),
        response,
      );
      expect(requests.single.$2, {
        'p_company_id': 'company-id',
        'p_values': {'status': 'published'},
        'p_job_id': 'existing',
        'p_expected_status': 'draft',
      });
    },
  );

  test(
    'Published edit validates and keeps publication and AI fields',
    () async {
      response = posting('existing', 'published');
      final values = {...completeJob(), 'status': 'draft', 'ai_assisted': true};
      expect(
        await repository.save(
          values,
          jobId: 'existing',
          expectedStatus: 'published',
        ),
        response,
      );
      expect(requests.single.$2['p_expected_status'], 'published');
      expect(requests.single.$2['p_values'], {
        ...values,
        'status': 'published',
      });
      expect(values['status'], 'draft');
    },
  );

  test('Closed and invalid published edits fail before RPC', () async {
    await expectLater(
      repository.save({}, jobId: 'existing', expectedStatus: 'closed'),
      throwsStateError,
    );
    await expectLater(
      repository.save({}, jobId: 'existing', expectedStatus: 'published'),
      throwsStateError,
    );
    expect(requests, isEmpty);
  });

  test('Denied access blocks save and close before RPC', () async {
    repository.access = const JobAccess(null, 'Company verification required.');
    await expectLater(repository.save({}), throwsStateError);
    await expectLater(repository.close('existing'), throwsStateError);
    expect(requests, isEmpty);
  });

  test(
    'Close uses the authorized company and accepts the returned UUID',
    () async {
      response = 'existing';
      await repository.close('existing');
      expect(requests.single.$1, '/rest/v1/rpc/close_employer_job_posting');
      expect(requests.single.$2, {
        'p_company_id': 'company-id',
        'p_job_id': 'existing',
      });
    },
  );

  for (final operation in ['list', 'save', 'close']) {
    for (final code in ['42501', 'PGRST116', 'P0001']) {
      test(
        '$operation propagates $code without hiding server failures',
        () async {
          responseStatus = 400;
          response = {
            'code': code,
            'message': 'Posting unavailable or status changed.',
            'details': null,
            'hint': null,
          };
          final future = switch (operation) {
            'list' => repository.list('company-id'),
            'save' => repository.save({
              'status': 'published',
            }, jobId: 'existing'),
            _ => repository.close('existing'),
          };
          await expectLater(
            future,
            throwsA(
              isA<PostgrestException>().having((e) => e.code, 'code', code),
            ),
          );
          final message = jobError(
            PostgrestException(
              message: 'Posting unavailable or status changed.',
              code: code,
            ),
          );
          expect(
            message,
            contains(switch (code) {
              '42501' => 'Permission denied',
              'PGRST116' => 'may have changed',
              _ => 'Posting unavailable or status changed',
            }),
          );
        },
      );
    }
  }
}
