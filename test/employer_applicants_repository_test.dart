import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/employer_applicants_repository.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/employer_applicants_source.dart';

void main() {
  test(
    'Resume function POST uses application_id and the SDK session JWT',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <String>[];
      server.listen((request) async {
        requests.add(request.uri.path);
        expect(request.method, 'POST');
        expect(
          request.headers.value('authorization'),
          'Bearer mock-session-token',
        );
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'application_id': 'mock-application',
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'signed_url': 'https://example.test/pdf',
            'expires_in': 60,
          }),
        );
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'mock-session-token',
          'token_type': 'bearer',
          'user': {'id': 'employer-a'},
        }),
      );
      final response = await SupabaseEmployerApplicantsSource(client)
          .viewResume('mock-application');
      expect(response.data['expires_in'], 60);
      expect(requests, ['/functions/v1/view-application-resume']);
    },
  );
  test(
    'Status RPC sends only application UUID, status and nullable note',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <(String, dynamic)>[];
      server.listen((request) async {
        requests.add((
          request.uri.path,
          jsonDecode(await utf8.decoder.bind(request).join()),
        ));
        request.response.statusCode = 204;
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final source = SupabaseEmployerApplicantsSource(client);
      await source.updateStatus(
        'mock-application-id',
        MyApplicationStatus.shortlisted,
        null,
      );
      await source.updateStatus(
        'mock-application-id',
        MyApplicationStatus.rejected,
        'Employer note',
      );
      expect(
        requests.map((r) => r.$1),
        everyElement('/rest/v1/rpc/update_job_application_status'),
      );
      expect(requests.first.$2, {
        'p_application_id': 'mock-application-id',
        'p_new_status': 'shortlisted',
        'p_note': null,
      });
      expect(requests.last.$2['p_note'], 'Employer note');
    },
  );
  test('Uses existing authorized posting reads and list_job_applicants with real ID', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <(String, dynamic)>[];
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add((request.uri.path, body.isEmpty ? null : jsonDecode(body)));
      final data = switch (request.uri.path) {
        '/rest/v1/users' => {'role': 'employer', 'status': 'active'},
        '/rest/v1/company_memberships' => {
          'company_id': 'company-id',
          'member_role': 'owner',
        },
        '/rest/v1/companies' => {
          'company_id': 'company-id',
          'company_name': 'ABC Company',
          'verification_status': 'verified',
          'logo_storage_path': null,
        },
        '/rest/v1/rpc/list_employer_job_postings' => [
          {
            'job_id': 'real-job-id',
            'title': 'Part-Time Cafe Crew',
            'company_id': 'company-id',
            'status': 'published',
          },
        ],
        '/rest/v1/rpc/list_job_applicants' => [
          applicantRow('real-application-id'),
        ],
        _ => throw StateError('Unexpected endpoint'),
      };
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(data));
      await request.response.close();
    });
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'test-token',
        'token_type': 'bearer',
        'user': {'id': 'employer-a'},
      }),
    );
    final repo = EmployerApplicantsRepository(
      SupabaseEmployerApplicantsSource(client),
      'real-job-id',
    );
    addTearDown(repo.dispose);
    await repo.load();
    expect(repo.error, isNull);
    expect(repo.job!['title'], 'Part-Time Cafe Crew');
    expect(repo.applicants.single.name, 'Alex Thee');
    expect(requests.last.$1, '/rest/v1/rpc/list_job_applicants');
    expect(requests.last.$2, {'p_job_id': 'real-job-id'});
    expect(requests.any((r) => r.$1 == '/rest/v1/job_postings'), isFalse);
  });
}
