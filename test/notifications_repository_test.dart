import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jobmate/features/notifications/notifications_repository.dart';

import 'fixtures/notifications_source.dart';

void main() {
  test('dispose cancels listener and discards a pending response', () async {
    final source = FakeNotificationsSource();
    final repo = NotificationsRepository(source);
    final pending = Completer<List<Map<String, dynamic>>>();
    source.onList = () => pending.future;
    final operation = repo.load();
    repo.dispose();
    expect(source.changes.hasListener, isFalse);
    pending.complete([notificationRow()]);
    await operation;
    expect(repo.notifications, isEmpty);
    await source.changes.close();
  });
  test(
    'exact deployed RPC names, overload parameters and boolean contract',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <(String, dynamic)>[];
      Object result = [notificationRow()];
      server.listen((request) async {
        requests.add((
          request.uri.path,
          jsonDecode(await utf8.decoder.bind(request).join()),
        ));
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      final source = SupabaseNotificationsSource(client);
      expect(await source.list(), hasLength(1));
      expect(requests.last.$1, '/rest/v1/rpc/list_my_notifications');
      expect(requests.last.$2, {'p_limit': 50, 'p_offset': 0});
      for (final value in [true, false]) {
        result = value;
        expect(await source.markRead('real-id'), value);
        expect(requests.last.$1, '/rest/v1/rpc/mark_notification_read');
        expect(requests.last.$2, {'p_notification_id': 'real-id'});
      }
      result = 'true';
      await expectLater(source.markRead('real-id'), throwsFormatException);
    },
  );

  test(
    'maps all six fields and timezone offsets; read is based on read_at',
    () {
      final item = JobMateNotification(notificationRow());
      expect(item.id, 'notification-1');
      expect(item.type, 'application_submitted');
      expect(item.title, 'Application received');
      expect(item.message, 'Server notification content');
      expect(item.createdAt.toUtc(), DateTime.utc(2026, 11, 4, 10, 11, 37));
      expect(item.readAt, isNull);
      expect(item.read, isFalse);
      expect(
        JobMateNotification(notificationRow(readAt: '2026-11-05T00:00:00Z'))
            .read,
        isTrue,
      );
    },
  );

  late FakeNotificationsSource source;
  late NotificationsRepository repo;
  setUp(() {
    source = FakeNotificationsSource();
    repo = NotificationsRepository(source);
  });
  tearDown(() async {
    repo.dispose();
    await source.changes.close();
  });

  test('loading, empty, error and retry; cap at 50', () async {
    expect(repo.loading, isTrue);
    source.rows = [];
    await repo.load();
    expect(repo.notifications, isEmpty);
    expect(repo.loading, isFalse);
    source.onList = () => Future.error(Exception('offline'));
    await repo.load();
    expect(repo.error, contains('Unable to load'));
    source.onList = null;
    source.rows = List.generate(55, (i) => notificationRow(id: '$i'));
    await repo.load();
    expect(repo.error, isNull);
    expect(repo.notifications, hasLength(50));
  });

  test(
    'true refreshes without optimism and duplicate requests are blocked',
    () async {
      await repo.load();
      final pending = Completer<bool>();
      source.onMark = () => pending.future;
      final operation = repo.markRead('notification-1');
      await repo.markRead('notification-1');
      expect(source.marks, 1);
      expect(repo.marking('notification-1'), isTrue);
      expect(repo.notifications.single.read, isFalse);
      source.rows = [notificationRow(readAt: '2026-11-05T00:00:00Z')];
      pending.complete(true);
      expect(await operation, isNull);
      expect(source.lists, 2);
      expect(repo.notifications.single.read, isTrue);
      expect(repo.marking('notification-1'), isFalse);
    },
  );

  test(
    'false refreshes and reports unavailable; failure retains previous state',
    () async {
      await repo.load();
      source.onMark = () async => false;
      expect(await repo.markRead('notification-1'), contains('unavailable'));
      expect(source.lists, 2);
      source.onMark = () async =>
          throw const PostgrestException(message: 'denied', code: '42501');
      expect(await repo.markRead('notification-1'), contains('denied'));
      expect(repo.notifications.single.read, isFalse);
      expect(repo.marking('notification-1'), isFalse);
    },
  );

  test('mutation refresh supersedes an older pending list', () async {
    await repo.load();
    final mutation = Completer<bool>();
    source.onMark = () => mutation.future;
    final operation = repo.markRead('notification-1');
    final older = Completer<List<Map<String, dynamic>>>();
    source.onList = () => older.future;
    final oldLoad = repo.load();
    source.onList = () async => [
      notificationRow(readAt: '2026-11-05T00:00:00Z'),
    ];
    mutation.complete(true);
    await operation;
    older.complete([notificationRow()]);
    await oldLoad;
    expect(repo.notifications.single.read, isTrue);
    expect(source.lists, 3);
  });

  test(
    'switch clears immediately; ignores stale lists and mutation errors',
    () async {
      await repo.load();
      final mutation = Completer<bool>();
      source.onMark = () => mutation.future;
      final operation = repo.markRead('notification-1');
      final older = Completer<List<Map<String, dynamic>>>();
      source.onList = () => older.future;
      final oldLoad = repo.load();
      source.onList = () async => [notificationRow(id: 'employer-only')];
      source.switchAccount('employer');
      expect(repo.notifications, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(repo.notifications.single.id, 'employer-only');
      older.completeError(Exception('old-account failure'));
      await oldLoad;
      mutation.completeError(Exception('old mutation failure'));
      expect(await operation, isNull);
      expect(repo.error, isNull);
      expect(repo.notifications.single.id, 'employer-only');
      source.switchAccount(null);
      expect(repo.notifications, isEmpty);
      expect(repo.error, contains('Sign in'));
    },
  );

  test('stale successful list cannot cross account boundary', () async {
    final pending = Completer<List<Map<String, dynamic>>>();
    source.onList = () => pending.future;
    final oldLoad = repo.load();
    source.onList = () async => [];
    source.switchAccount('employer');
    pending.complete([notificationRow()]);
    await oldLoad;
    expect(repo.notifications, isEmpty);
    expect(repo.error, isNull);
  });
}
