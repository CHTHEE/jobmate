import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/hiring_membership_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late SupabaseAtomicHiringMembershipGateway gateway;
  late List<(String, dynamic)> requests;
  late Object? response;
  late int status;
  late Completer<void> received;
  Completer<void>? hold;

  Future<void> signIn(String id) => client.auth.setInitialSession(
    jsonEncode({
      'access_token': 'local-test-token',
      'token_type': 'bearer',
      'user': {'id': id},
    }),
  );

  setUp(() async {
    requests = [];
    response = 'hired';
    status = 200;
    received = Completer<void>();
    hold = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add((
        request.uri.path,
        jsonDecode(await utf8.decoder.bind(request).join()),
      ));
      if (!received.isCompleted) received.complete();
      expect(request.method, 'POST');
      expect(request.headers.value('authorization'), 'Bearer local-test-token');
      if (hold != null) await hold!.future;
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(response));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'local-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    gateway = SupabaseAtomicHiringMembershipGateway.forApprovedBackend(client);
  });

  tearDown(() async {
    if (hold != null && !hold!.isCompleted) hold!.complete();
    await client.dispose();
    await server.close(force: true);
  });

  test(
    'exact existing RPC and text result; application identity only',
    () async {
      await signIn('worker-a');
      expect(await gateway.acceptOffer('application-a'), 'hired');
      expect(requests, hasLength(1));
      expect(requests.single.$1, '/rest/v1/rpc/respond_to_job_application');
      expect(requests.single.$2, {
        'p_application_id': 'application-a',
        'p_action': 'accept_offer',
      });
    },
  );

  test('unsigned session and empty identity dispatch nothing', () async {
    await expectLater(gateway.acceptOffer('application-a'), throwsStateError);
    await signIn('worker-a');
    await expectLater(gateway.acceptOffer('  '), throwsStateError);
    expect(requests, isEmpty);
  });

  test(
    'flag is OFF by default and composition remains legacy unless opted in',
    () {
      expect(hiringMembershipEnabled, isFalse);
      expect(
        createMyApplicationsSource(client),
        isNot(isA<HiringMembershipApplicationsSource>()),
      );
      expect(
        createMyApplicationsSource(client, enableHiringMembership: true),
        isA<HiringMembershipApplicationsSource>(),
      );
    },
  );

  test('membership read is scoped to caller/application and rejects foreign response', () async {
    await signIn('worker-a');
    response = {
      'contract_version': 1,
      'application_id': 'application-a',
      'user_id': 'worker-a',
      'company_id': 'company-a',
      'member_role': 'member',
      'membership_status': 'active',
      'acceptance_recorded': true,
    };
    final result = await gateway.loadMembership('application-a');
    expect(result.companyId, 'company-a');
    expect(requests.single.$1, '/rest/v1/rpc/get_my_hiring_membership');
    expect(requests.single.$2, {'p_application_id': 'application-a'});
    response = {...response as Map, 'user_id': 'other'};
    await expectLater(
      gateway.loadMembership('application-a'),
      throwsFormatException,
    );
  });

  test(
    'approved composition shares the client and makes one acceptance call',
    () async {
      await signIn('worker-a');
      final source = HiringMembershipApplicationsSource.forApprovedBackend(
        client,
      );
      expect(source.userId, gateway.userId);
      expect(await source.respond('application-a', 'accept_offer'), 'hired');
      expect(requests, hasLength(1));
      expect(requests.single.$2, {
        'p_application_id': 'application-a',
        'p_action': 'accept_offer',
      });
    },
  );

  test('non-text result is rejected without any secondary write', () async {
    await signIn('worker-a');
    response = {'status': 'hired', 'membership': 'unverified'};
    await expectLater(
      gateway.acceptOffer('application-a'),
      throwsFormatException,
    );
    expect(requests, hasLength(1));
  });

  for (final failure in [(403, '42501'), (409, 'P0001'), (503, 'PGRST000')]) {
    test(
      'HTTP ${failure.$1} propagates once without automatic retry',
      () async {
        await signIn('worker-a');
        status = failure.$1;
        response = {
          'code': failure.$2,
          'message': 'Local simulated backend failure',
        };
        await expectLater(
          gateway.acceptOffer('application-a'),
          throwsA(
            isA<PostgrestException>().having((e) => e.code, 'code', failure.$2),
          ),
        );
        expect(requests, hasLength(1));
      },
    );
  }

  test(
    'account change while request is pending rejects late acknowledgement',
    () async {
      await signIn('worker-a');
      hold = Completer<void>();
      final operation = gateway.acceptOffer('application-a');
      final assertion = expectLater(operation, throwsStateError);
      await received.future.timeout(const Duration(seconds: 5));
      await signIn('worker-b');
      hold!.complete();
      await assertion;
      expect(requests, hasLength(1));
    },
  );
}
