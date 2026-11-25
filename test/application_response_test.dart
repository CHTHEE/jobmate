import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';

import 'fixtures/my_applications_source.dart';

void main() {
  test('disposed repository ignores a pending successful mutation', () async {
    final source = TestMyApplicationsSource()
      ..rows = [applicationRow('test-application', status: 'interview')];
    final repo = MyApplicationDetailsRepository(source, 'test-application');
    await repo.load();
    final pending = Completer<String>();
    source.sendResponse = (_, _) => pending.future;
    final operation = repo.respond(repo.application!, 'withdraw');
    repo.dispose();
    pending.complete('withdrawn');
    await operation;
    expect(source.calls, 1);
    expect(source.changes.hasListener, isFalse);
    await source.changes.close();
  });
  test('legacy acceptance checks for a versioned offer first', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <(String, String, dynamic)>[];
    server.listen((request) async {
      requests.add((
        request.method,
        request.uri.path,
        jsonDecode(await utf8.decoder.bind(request).join()),
      ));
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          request.uri.path.endsWith(
                '/get_my_current_application_compensation_offer_v1',
              )
              ? null
              : 'hired',
        ),
      );
      await request.response.close();
    });
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    final source = SupabaseMyApplicationsSource(client);
    expect(await source.respond('test-application', 'accept_offer'), 'hired');
    await expectLater(
      source.respond('test-application', 'hire'),
      throwsStateError,
    );
    expect(requests.map((request) => [request.$1, request.$2, request.$3]), [
      [
        'POST',
        '/rest/v1/rpc/get_my_current_application_compensation_offer_v1',
        {'p_application_id': 'test-application'},
      ],
      [
        'POST',
        '/rest/v1/rpc/respond_to_job_application',
        {'p_application_id': 'test-application', 'p_action': 'accept_offer'},
      ],
    ]);
  });

  test('exact-version acceptance sends the displayed identity and rejects a mismatched acknowledgement', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    const appId = '11111111-1111-4111-8111-111111111111';
    const offerId = '22222222-2222-4222-8222-222222222222';
    final requests = <List<Object?>>[];
    var acknowledgedVersion = 2;
    server.listen((request) async {
      requests.add([
        request.method,
        request.uri.path,
        jsonDecode(await utf8.decoder.bind(request).join()),
      ]);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'application_id': appId,
          'offer_id': offerId,
          'offer_version': acknowledgedVersion,
          'status': 'hired',
          'accepted': true,
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
    final source = SupabaseMyApplicationsSource(client);
    await source.acceptCompensationOffer(appId, offerId, 2);
    acknowledgedVersion = 3;
    await expectLater(
      source.acceptCompensationOffer(appId, offerId, 2),
      throwsFormatException,
    );
    expect(requests, [
      for (var attempt = 0; attempt < 2; attempt++)
        [
          'POST',
          '/rest/v1/rpc/accept_application_compensation_offer_v1',
          {
            'p_application_id': appId,
            'p_offer_id': offerId,
            'p_offer_version': 2,
          },
        ],
    ]);
  });
  late TestMyApplicationsSource source;
  late MyApplicationDetailsRepository repo;
  setUp(() {
    source = TestMyApplicationsSource();
    repo = MyApplicationDetailsRepository(source, 'test-application');
  });
  tearDown(() async {
    repo.dispose();
    await source.changes.close();
  });

  test('all status/action combinations are validated', () async {
    for (final status in MyApplicationStatus.values) {
      source.rows = [applicationRow('test-application', status: status.name)];
      await repo.load();
      final allowed = status == MyApplicationStatus.offered
          ? ApplicationResponseAction.values
          : [
              MyApplicationStatus.submitted,
              MyApplicationStatus.shortlisted,
              MyApplicationStatus.interview,
            ].contains(status)
          ? [ApplicationResponseAction.withdraw]
          : <ApplicationResponseAction>[];
      for (final action in ApplicationResponseAction.values) {
        expect(action.allowed(status), allowed.contains(action));
        if (!allowed.contains(action)) {
          await expectLater(
            repo.respond(repo.application!, action.wireName),
            throwsStateError,
          );
        }
      }
    }
    expect(source.responses, isEmpty);
  });
  for (final action in ApplicationResponseAction.values) {
    test(
      '${action.wireName} refreshes server status and history without optimism',
      () async {
        source.rows = [applicationRow('test-application', status: 'offered')];
        await repo.load();
        final pending = Completer<String>();
        source.sendResponse = (_, _) => pending.future;
        final operation = repo.respond(repo.application!, action.wireName);
        expect(repo.responding, isTrue);
        expect(repo.application!.status, MyApplicationStatus.offered);
        await expectLater(
          repo.respond(repo.application!, action.wireName),
          throwsStateError,
        );
        source.rows = [
          applicationRow('test-application', status: action.result.name),
        ];
        source.historyRows = [
          historyRow('changed', status: action.result.name),
        ];
        pending.complete(action.result.name);
        await operation;
        expect(source.responses, [('test-application', action.wireName)]);
        expect(repo.application!.status, action.result);
        expect(repo.events.single.newStatus, action.result);
        expect(source.calls, 2);
        expect(source.historyCalls, hasLength(2));
        expect(repo.responding, isFalse);
      },
    );
  }
  test(
    'conflict refreshes concurrent status and history, reports no success',
    () async {
      source.rows = [applicationRow('test-application', status: 'interview')];
      await repo.load();
      source.sendResponse = (_, _) async {
        source.rows = [applicationRow('test-application', status: 'rejected')];
        source.historyRows = [historyRow('rejection', status: 'rejected')];
        throw const PostgrestException(message: 'Invalid transition');
      };
      await repo.respond(repo.application!, 'withdraw');
      expect(repo.application!.status, MyApplicationStatus.rejected);
      expect(repo.events.single.newStatus, MyApplicationStatus.rejected);
      expect(repo.responseError, isNotNull);
      expect(repo.responding, isFalse);
    },
  );
  for (final account in [null, 'seeker-b']) {
    test(
      'account change to $account discards late mutation and error',
      () async {
        source.rows = [applicationRow('test-application', status: 'interview')];
        await repo.load();
        final pending = Completer<String>();
        source.sendResponse = (_, _) => pending.future;
        final operation = repo.respond(repo.application!, 'withdraw');
        source.rows = [];
        source.switchAccount(account);
        pending.completeError(Exception('old account'));
        await operation;
        expect(repo.application, isNull);
        expect(repo.responseError, isNull);
        expect(repo.events, isEmpty);
      },
    );
  }
  test(
    'refresh failure releases mutation lock and exposes honest errors',
    () async {
      source.rows = [applicationRow('test-application', status: 'offered')];
      await repo.load();
      source.sendResponse = (_, _) async => 'hired';
      source.fetch = () async => throw Exception('offline');
      await repo.respond(repo.application!, 'accept_offer');
      expect(repo.application, isNull);
      expect(repo.error, isNotNull);
      expect(repo.responding, isFalse);
    },
  );
  test('stale snapshot and unknown action cannot submit', () async {
    source.rows = [applicationRow('test-application', status: 'offered')];
    await repo.load();
    final stale = repo.application!;
    source.rows = [applicationRow('test-application', status: 'interview')];
    await repo.load();
    await expectLater(repo.respond(stale, 'accept_offer'), throwsStateError);
    await expectLater(
      repo.respond(repo.application!, 'hire'),
      throwsStateError,
    );
    expect(source.responses, isEmpty);
  });
}
