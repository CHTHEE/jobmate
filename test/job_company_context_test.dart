import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late List<Uri> reads;
  late List<Map<String, dynamic>> mutations;
  late Map<String, dynamic> profile;
  late List<Map<String, dynamic>> memberships;
  late bool verified;
  late bool denied;

  setUp(() async {
    reads = [];
    mutations = [];
    profile = {'role': 'employer', 'status': 'active'};
    memberships = [
      {'company_id': 'company-a', 'member_role': 'owner'},
    ];
    verified = true;
    denied = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      reads.add(request.uri);
      final body = await utf8.decoder.bind(request).join();
      Object? result;
      var status = 200;
      switch (request.uri.path) {
        case '/rest/v1/users':
          result = profile;
        case '/rest/v1/company_memberships':
          final filter = request.uri.queryParameters['company_id'];
          final matches = memberships
              .where((m) => filter == null || filter == 'eq.${m['company_id']}')
              .toList();
          if (matches.length > 1 || denied) {
            status = denied ? 403 : 406;
            result = {
              'code': denied ? '42501' : 'PGRST116',
              'message': denied ? 'Permission denied' : 'Multiple rows',
              'details': 'The result contains ${matches.length} rows',
            };
          } else {
            result = matches.isEmpty ? null : matches.single;
          }
        case '/rest/v1/companies':
          result = {
            'company_id': request.uri.queryParameters['company_id']!.substring(
              3,
            ),
            'company_name': 'Test company',
            'verification_status': verified ? 'verified' : 'pending',
            'logo_storage_path': null,
          };
        default:
          final parameters = Map<String, dynamic>.from(jsonDecode(body) as Map);
          mutations.add(parameters);
          result = request.uri.path.endsWith('list_employer_job_postings')
              ? []
              : {'job_id': 'job', 'company_id': parameters['p_company_id']};
      }
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(result));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'test-token',
        'token_type': 'bearer',
        'user': {'id': 'employer-a'},
      }),
    );
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test(
    'legacy single authorized Employer resolves without a company filter',
    () async {
      final access = await JobPostingsRepository(client).loadAccess();
      expect(access.allowed, isTrue);
      expect(access.company!['company_id'], 'company-a');
      expect(reads[1].queryParameters['company_id'], isNull);
    },
  );

  test('no membership denies access', () async {
    memberships.clear();
    expect((await JobPostingsRepository(client).loadAccess()).allowed, isFalse);
  });

  test('multiple memberships without context fail closed', () async {
    memberships.add({'company_id': 'company-b', 'member_role': 'employer'});
    await expectLater(
      JobPostingsRepository(client).loadAccess(),
      throwsA(isA<PostgrestException>()),
    );
    expect(reads.any((uri) => uri.path == '/rest/v1/companies'), isFalse);
  });

  test(
    'Job Seeker ordinary membership cannot manage even with context',
    () async {
      profile['role'] = 'job_seeker';
      memberships.single['member_role'] = 'member';
      final repo = JobPostingsRepository(client, companyContext: 'company-a');
      expect((await repo.loadAccess()).allowed, isFalse);
      await expectLater(repo.save({}), throwsStateError);
      await expectLater(repo.close('job'), throwsStateError);
      expect(mutations, isEmpty);
      expect(reads.every((uri) => uri.path == '/rest/v1/users'), isTrue);
    },
  );

  test(
    'ordinary Employer membership and unverified company remain denied',
    () async {
      final repo = JobPostingsRepository(client, companyContext: 'company-a');
      memberships.single['member_role'] = 'member';
      expect((await repo.loadAccess()).allowed, isFalse);
      memberships.single['member_role'] = 'employer';
      verified = false;
      expect((await repo.loadAccess()).allowed, isFalse);
      verified = true;
      profile['status'] = 'suspended';
      expect((await repo.loadAccess()).allowed, isFalse);
    },
  );

  test(
    'explicit company selection never falls back to another membership',
    () async {
      final repo = JobPostingsRepository(client, companyContext: 'company-b');
      expect((await repo.loadAccess()).allowed, isFalse);
      expect(reads[1].queryParameters['company_id'], 'eq.company-b');
    },
  );

  test('revoked membership is reread before save and close', () async {
    final repo = JobPostingsRepository(client, companyContext: 'company-a');
    expect((await repo.loadAccess()).allowed, isTrue);
    memberships.clear();
    await expectLater(repo.save({}), throwsStateError);
    await expectLater(repo.close('job'), throwsStateError);
    expect(mutations, isEmpty);
  });

  test('backend membership denial is propagated without a mutation', () async {
    denied = true;
    await expectLater(
      JobPostingsRepository(client).save({}),
      throwsA(isA<PostgrestException>()),
    );
    expect(mutations, isEmpty);
  });

  test('immutable repository contexts do not leak across operations', () async {
    memberships.add({'company_id': 'company-b', 'member_role': 'employer'});
    final a = JobPostingsRepository(client, companyContext: 'company-a');
    final b = JobPostingsRepository(client, companyContext: 'company-b');
    await a.save({'company_id': 'spoofed'});
    await b.close('job-b');
    await a.close('job-a');
    expect(mutations.map((m) => m['p_company_id']), [
      'company-a',
      'company-b',
      'company-a',
    ]);
    expect(
      (mutations.first['p_values'] as Map).containsKey('company_id'),
      isFalse,
    );
    await expectLater(a.list('company-b'), throwsStateError);
    expect(mutations, hasLength(3));
    expect(await a.list('company-a'), isEmpty);
    expect(mutations.last['p_company_id'], 'company-a');
  });

  test(
    'empty explicit context is rejected rather than using default company',
    () {
      expect(
        () => JobPostingsRepository(client, companyContext: '  '),
        throwsArgumentError,
      );
    },
  );
}
