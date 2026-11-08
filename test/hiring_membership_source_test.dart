import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/hiring_membership_source.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';

import 'fixtures/my_applications_source.dart';

class AtomicGateway implements AtomicHiringMembershipGateway {
  @override
  String? userId = 'seeker-a';
  final calls = <String>[];
  late Future<String> Function(String) accept;
  @override
  Future<String> acceptOffer(String applicationId) {
    calls.add(applicationId);
    return accept(applicationId);
  }
}

void main() {
  late TestMyApplicationsSource legacy;
  late AtomicGateway gateway;
  late HiringMembershipApplicationsSource source;
  late MyApplicationDetailsRepository details;

  setUp(() {
    legacy = TestMyApplicationsSource()
      ..rows = [applicationRow('offer', status: 'offered')]
      ..sendResponse = (_, _) async => 'legacy acknowledgement';
    gateway = AtomicGateway()..accept = (_) async => 'atomic acknowledgement';
    source = HiringMembershipApplicationsSource(legacy, gateway: gateway);
    details = MyApplicationDetailsRepository(source, 'offer');
  });

  tearDown(() async {
    details.dispose();
    await legacy.changes.close();
  });

  test(
    'default unavailable integration never dispatches legacy acceptance',
    () async {
      final unavailable = HiringMembershipApplicationsSource(legacy);
      await expectLater(
        unavailable.respond('offer', 'accept_offer'),
        throwsStateError,
      );
      expect(legacy.responses, isEmpty);
      expect(gateway.calls, isEmpty);
    },
  );

  test(
    'reads and pre-hire non-accept responses retain existing contracts',
    () async {
      expect(await source.list(), legacy.rows);
      expect(await source.history('offer'), legacy.historyRows);
      expect(
        await source.respond('offer', 'decline_offer'),
        'legacy acknowledgement',
      );
      expect(
        await source.respond('offer', 'withdraw'),
        'legacy acknowledgement',
      );
      expect(legacy.responses, [
        ('offer', 'decline_offer'),
        ('offer', 'withdraw'),
      ]);
      expect(gateway.calls, isEmpty);
    },
  );

  test(
    'atomic acceptance sends application identity only and uses owned refresh',
    () async {
      gateway.accept = (_) async {
        legacy.rows = [applicationRow('offer', status: 'hired')];
        legacy.historyRows = [historyRow('accepted', status: 'hired')];
        return 'opaque server acknowledgement';
      };
      await details.load();
      await details.respond(details.application!, 'accept_offer');
      expect(gateway.calls, ['offer']);
      expect(legacy.responses, isEmpty);
      expect(details.application!.status, MyApplicationStatus.hired);
      expect(details.events.single.newStatus, MyApplicationStatus.hired);
      await expectLater(
        details.respond(details.application!, 'accept_offer'),
        throwsStateError,
      );
      expect(gateway.calls, hasLength(1));
    },
  );

  test(
    'text acknowledgement alone never establishes Hired or enrollment',
    () async {
      await details.load();
      await details.respond(details.application!, 'accept_offer');
      expect(details.application!.status, MyApplicationStatus.offered);
      expect(details.events, isEmpty);
      expect(legacy.responses, isEmpty);
    },
  );

  test(
    'lost response reconciles committed Hired without fallback or retry',
    () async {
      gateway.accept = (_) async {
        legacy.rows = [applicationRow('offer', status: 'hired')];
        throw TimeoutException('response lost');
      };
      await details.load();
      await details.respond(details.application!, 'accept_offer');
      expect(details.application!.status, MyApplicationStatus.hired);
      expect(details.responseError, isNotNull);
      expect(gateway.calls, ['offer']);
      expect(legacy.responses, isEmpty);
    },
  );

  test(
    'inactive membership conflict leaves Offered and never falls back',
    () async {
      gateway.accept = (_) async =>
          throw StateError('inactive membership conflict');
      await details.load();
      await details.respond(details.application!, 'accept_offer');
      expect(details.application!.status, MyApplicationStatus.offered);
      expect(details.responseError, isNotNull);
      expect(legacy.responses, isEmpty);
      expect(gateway.calls, ['offer']);
    },
  );

  test(
    'unsigned or mismatched integration session dispatches nothing',
    () async {
      gateway.userId = 'other-worker';
      await expectLater(
        source.respond('offer', 'accept_offer'),
        throwsStateError,
      );
      legacy.actor = null;
      await expectLater(
        source.respond('offer', 'accept_offer'),
        throwsStateError,
      );
      expect(gateway.calls, isEmpty);
      expect(legacy.responses, isEmpty);
    },
  );

  test(
    'account switch away and back invalidates pending acknowledgement',
    () async {
      final pending = Completer<String>();
      gateway.accept = (_) => pending.future;
      final operation = source.respond('offer', 'accept_offer');
      final assertion = expectLater(operation, throwsStateError);
      legacy.switchAccount('other-worker');
      legacy.switchAccount('seeker-a');
      pending.complete('accepted');
      await assertion;
      expect(gateway.calls, hasLength(1));
      expect(legacy.responses, isEmpty);
    },
  );

  test(
    'duplicate clicks are blocked and failed dispatch releases local lock',
    () async {
      final pending = Completer<String>();
      gateway.accept = (_) => pending.future;
      final operation = source.respond('offer', 'accept_offer');
      await expectLater(
        source.respond('offer', 'accept_offer'),
        throwsStateError,
      );
      await expectLater(source.respond('offer', 'withdraw'), throwsStateError);
      pending.complete('accepted');
      await operation;
      expect(gateway.calls, hasLength(1));
      gateway.accept = (_) async => throw StateError('denied');
      await expectLater(
        source.respond('offer', 'accept_offer'),
        throwsStateError,
      );
      expect(
        await source.respond('offer', 'decline_offer'),
        'legacy acknowledgement',
      );
      expect(gateway.calls, hasLength(2));
    },
  );

  test('unknown actions and empty IDs never reach either transport', () async {
    await expectLater(source.respond('offer', 'enroll'), throwsStateError);
    await expectLater(source.respond(' ', 'accept_offer'), throwsStateError);
    expect(gateway.calls, isEmpty);
    expect(legacy.responses, isEmpty);
  });

  test(
    'unavailable integration surfaces an error after owned refresh',
    () async {
      final unavailable = MyApplicationDetailsRepository(
        HiringMembershipApplicationsSource(legacy),
        'offer',
      );
      addTearDown(unavailable.dispose);
      await unavailable.load();
      final reads = legacy.calls;
      await unavailable.respond(unavailable.application!, 'accept_offer');
      expect(unavailable.application!.status, MyApplicationStatus.offered);
      expect(unavailable.responseError, isNotNull);
      expect(legacy.calls, reads + 1);
      expect(legacy.responses, isEmpty);
    },
  );

  test(
    'failed authoritative refresh hides status and prevents blind retry',
    () async {
      await details.load();
      gateway.accept = (_) async {
        legacy.fetch = () async => throw StateError('refresh unavailable');
        return 'hired';
      };
      final selected = details.application!;
      await details.respond(selected, 'accept_offer');
      expect(details.application, isNull);
      expect(details.error, isNotNull);
      expect(details.responding, isFalse);
      await expectLater(
        details.respond(selected, 'accept_offer'),
        throwsStateError,
      );
      expect(gateway.calls, hasLength(1));
      expect(legacy.responses, isEmpty);
    },
  );

  test(
    'refresh keeps mutation locked and cannot dispatch a second action',
    () async {
      await details.load();
      final pending = Completer<List<Map<String, dynamic>>>();
      gateway.accept = (_) async {
        legacy.fetch = () => pending.future;
        return 'hired';
      };
      final selected = details.application!;
      final operation = details.respond(selected, 'accept_offer');
      await Future<void>.delayed(Duration.zero);
      expect(details.responding, isTrue);
      await expectLater(
        details.respond(selected, 'decline_offer'),
        throwsStateError,
      );
      pending.complete([applicationRow('offer', status: 'hired')]);
      await operation;
      expect(details.responding, isFalse);
      expect(details.application!.status, MyApplicationStatus.hired);
      expect(gateway.calls, hasLength(1));
      expect(legacy.responses, isEmpty);
    },
  );
}
