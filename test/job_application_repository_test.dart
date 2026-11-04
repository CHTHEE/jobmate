import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/job_application_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late SupabaseJobApplicationGateway gateway;
  late List<(String, Map<String, dynamic>)> requests;
  late dynamic result;
  late int status;
  Future<void> session(String id) => client.auth.setInitialSession(
    jsonEncode({
      'access_token': 'test-token',
      'token_type': 'bearer',
      'user': {'id': id},
    }),
  );
  setUp(() async {
    requests = [];
    status = 200;
    result = '11111111-1111-4111-8111-111111111111';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add((
        request.uri.path,
        body.isEmpty ? {} : Map<String, dynamic>.from(jsonDecode(body) as Map),
      ));
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/rest/v1/users') {
        request.response.write(
          jsonEncode({'role': 'job_seeker', 'status': 'active'}),
        );
      } else {
        request.response.statusCode = status;
        request.response.write(jsonEncode(result));
      }
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await session('seeker-a');
    gateway = SupabaseJobApplicationGateway(client);
  });
  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test('Submits actual IDs and nullable note/resume via RPC only', () async {
    expect(
      await gateway.submit(
        'job-id',
        resumeId: 'resume-id',
        coverNote: ' Note ',
      ),
      result,
    );
    expect(requests.single.$1, '/rest/v1/rpc/submit_job_application');
    expect(requests.single.$2, {
      'p_job_id': 'job-id',
      'p_resume_id': 'resume-id',
      'p_cover_note': 'Note',
    });
    requests.clear();
    await gateway.submit('another-job', coverNote: '   ');
    expect(requests.single.$2, {
      'p_job_id': 'another-job',
      'p_resume_id': null,
      'p_cover_note': null,
    });
  });

  test(
    'Reuses resume response contract including original filenames',
    () async {
      result = [
        {
          'resume_id': 'resume-id',
          'storage_path': 'seeker-a/file.pdf',
          'original_name': 'Original filename.pdf',
          'size_bytes': 123,
          'bucket_id': 'jobmate-resumes',
          'uploaded_at': '2026-11-04T01:00:00Z',
          'legacy': false,
        },
      ];
      final files = await gateway.listResumes();
      expect(files.single.name, 'Original filename.pdf');
      expect(files.single.id, 'resume-id');
      expect(requests.last.$1, '/rest/v1/rpc/list_personal_resumes');
      expect(requests.last.$2, {'p_limit': 10});
    },
  );

  test('Account changes and overlong notes fail before submission', () async {
    await expectLater(
      gateway.submit('job-id', coverNote: 'x' * 1001),
      throwsStateError,
    );
    await session('seeker-b');
    await expectLater(
      gateway.submit('job-id', resumeId: 'resume-id'),
      throwsStateError,
    );
    expect(requests, isEmpty);
  });

  test('Server errors propagate; malformed success is not accepted', () async {
    status = 400;
    result = {'code': 'P0001', 'message': 'Application deadline has passed'};
    await expectLater(
      gateway.submit('job-id'),
      throwsA(isA<PostgrestException>()),
    );
    expect(
      jobApplicationError(
        const PostgrestException(
          message: 'Application deadline has passed',
          code: 'P0001',
        ),
      ),
      'Application deadline has passed',
    );
    status = 200;
    result = null;
    await expectLater(gateway.submit('job-id'), throwsStateError);
  });
}
