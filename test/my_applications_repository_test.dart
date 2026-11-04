import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/my_applications_source.dart';

void main() {
  test(
    'History RPC receives the real application UUID and maps returned rows',
    () async {
      const applicationId = 'bc697799-463f-4251-b6be-8888551c3712';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      final bodies = <dynamic>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode([historyRow('initial')]));
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final rows = await SupabaseMyApplicationsSource(client)
          .history(applicationId);
      expect(paths, ['/rest/v1/rpc/list_application_history']);
      expect(bodies.single, {'p_application_id': applicationId});
      expect(
        ApplicationHistoryEvent(rows.single).newStatus,
        MyApplicationStatus.submitted,
      );
    },
  );
  Map<String, dynamic> row(String id, {String status = 'submitted'}) =>
      applicationRow(id, status: status);
  test('All database statuses retain distinct labels and terminal states', () {
    for (final status in MyApplicationStatus.values) {
      final application = MyJobApplication(row('real-id', status: status.name));
      expect(application.status, status);
    }
    expect(MyApplicationStatus.submitted.label, 'Applied');
    expect(MyApplicationStatus.shortlisted.label, 'Shortlisted');
    expect(MyApplicationStatus.declined, isNot(MyApplicationStatus.withdrawn));
    expect(MyApplicationStatus.declined.completed, isTrue);
    expect(MyApplicationStatus.withdrawn.completed, isTrue);
    expect(MyApplicationStatus.offered.completed, isFalse);
    expect(
      () => MyJobApplication(row('real-id', status: 'unknown')),
      throwsFormatException,
    );
  });
  test('Model preserves RPC fields without manufacturing values', () {
    final fields = {...row('real-id'), 'rpc_extra': 'server-value'};
    final application = MyJobApplication(fields);
    expect(application.id, 'real-id');
    expect(application.jobId, 'real-job-id');
    expect(application.fields, fields);
    expect(application.jobTitle, 'Part-Time Cafe Crew');
    expect(application.companyName, 'ABC Company');
    expect(application.appliedAt, DateTime.parse('2026-11-04T10:11:37.58546Z'));
    expect(application.updatedAt, application.appliedAt);
    expect(application.resumeId, isNull);
    expect(application.coverNote, isNull);
    expect(application.withdrawnAt, isNull);
    final withdrawn = MyJobApplication({
      ...row('withdrawn-id', status: 'withdrawn'),
      'resume_id': 'resume-id',
      'cover_note': 'My note',
      'withdrawn_at': '2026-11-05T01:00:00Z',
    });
    expect(withdrawn.resumeId, 'resume-id');
    expect(withdrawn.coverNote, 'My note');
    expect(withdrawn.withdrawnAt, DateTime.parse('2026-11-05T01:00:00Z'));
  });
  test(
    'Search, tabs, exact status and date/ID ordering use real rows',
    () async {
      final source = TestMyApplicationsSource()
        ..rows = [
          row('a'),
          row('b', status: 'declined'),
          row('c', status: 'withdrawn'),
          {
            ...row('old', status: 'shortlisted'),
            'job_title': 'Different role',
            'applied_at': '2026-10-01T01:00:00Z',
          },
        ];
      final repo = MyApplicationsRepository(source);
      addTearDown(repo.dispose);
      addTearDown(source.changes.close);
      await repo.load();
      expect(repo.search().map((a) => a.id), ['c', 'b', 'a', 'old']);
      expect(repo.search(sort: 'Oldest').first.id, 'old');
      expect(repo.search(tab: 'Completed').length, 2);
      expect(repo.search(tab: 'Active').length, 2);
      expect(repo.search(status: 'declined').single.id, 'b');
      expect(repo.search(status: 'withdrawn').single.id, 'c');
      expect(repo.search(query: 'different').single.id, 'old');
      expect(repo.search(query: 'ABC Company').length, 4);
    },
  );
  test(
    'Loads fresh results, errors do not fall back, retry supports empty',
    () async {
      final source = TestMyApplicationsSource()..rows = [row('one')];
      final repository = MyApplicationsRepository(source);
      addTearDown(repository.dispose);
      addTearDown(source.changes.close);
      await repository.load();
      expect(repository.applications.single.id, 'one');
      source.rows = [row('two')];
      await repository.load();
      expect(repository.applications.single.id, 'two');
      source.fetch = () => Future.error(StateError('Service unavailable'));
      await repository.load();
      expect(repository.error, 'Service unavailable');
      expect(repository.applications, isEmpty);
      source.fetch = () async => [];
      await repository.load();
      expect(repository.loaded, isTrue);
      expect(repository.error, isNull);
      expect(repository.applications, isEmpty);
    },
  );
  test(
    'Previous account results are discarded during switch and logout',
    () async {
      final source = TestMyApplicationsSource();
      final repository = MyApplicationsRepository(source);
      addTearDown(repository.dispose);
      addTearDown(source.changes.close);
      final previous = Completer<List<Map<String, dynamic>>>();
      source.fetch = () => previous.future;
      final request = repository.load();
      source.fetch = () async => [row('new-account')];
      source.switchAccount('seeker-b');
      previous.complete([row('previous-account')]);
      await request;
      await Future<void>.delayed(Duration.zero);
      expect(repository.applications.single.id, 'new-account');
      source.switchAccount(null);
      expect(repository.applications, isEmpty);
      await repository.load();
      expect(repository.error, contains('Sign in'));
    },
  );
  test(
    'Calls only list_my_job_applications RPC without candidate parameters',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        expect(request.method, 'POST');
        final body = await utf8.decoder.bind(request).join();
        expect(body.isEmpty ? null : jsonDecode(body), anyOf(isNull, isEmpty));
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode([row('rpc-id')]));
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final rows = await SupabaseMyApplicationsSource(client).list();
      expect(rows.single['application_id'], 'rpc-id');
      expect(paths, ['/rest/v1/rpc/list_my_job_applications']);
    },
  );
}
