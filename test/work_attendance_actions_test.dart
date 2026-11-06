import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/work_attendance_pages.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';

import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, id, other;

// Widget binding blocks HTTP by default. Only this local-server contract test
// uses a real client, pointed exclusively at its ephemeral loopback mock.
class _LocalHttpOverrides extends HttpOverrides {}

void main() {
  test(
    'RPC contract uses unavailable and explicit null coordinates; timestamp must be server UTC',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <(String, dynamic)>[];
      Object result = '2026-11-05T09:00:00+08:00';
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
      final source = SupabaseWorkAttendanceSource(client);
      await expectLater(source.checkIn(id), throwsA(isA<AuthException>()));
      expect(requests, isEmpty);
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'test-token',
          'token_type': 'bearer',
          'user': {'id': id},
        }),
      );
      expect(await source.checkIn(id), DateTime.utc(2026, 11, 5, 1));
      expect(await source.checkOut(id), DateTime.utc(2026, 11, 5, 1));
      expect(requests.map((r) => r.$1), [
        '/rest/v1/rpc/check_in_work_assignment',
        '/rest/v1/rpc/check_out_work_assignment',
      ]);
      for (final request in requests) {
        expect(request.$2, {
          'p_assignment_id': id,
          'p_location_status': 'unavailable',
          'p_latitude': null,
          'p_longitude': null,
        });
      }
      for (final invalid in [true, 'not a timestamp', '2026-11-05T09:00:00']) {
        result = invalid;
        await expectLater(source.checkIn(id), throwsFormatException);
      }
    }, _LocalHttpOverrides()),
  );

  group('repository attendance actions', () {
    late FakeSource source;
    late WorkAttendanceRepository repo;
    setUp(() {
      source = FakeSource();
      repo = WorkAttendanceRepository(source);
    });
    tearDown(() async {
      repo.dispose();
      await source.changes.close();
    });

    test('success blocks duplicate taps and waits for authoritative refresh without optimism', () async {
      await repo.loadWorkerAssignments();
      final pending = Completer<DateTime>();
      source.onCheckIn = (assignmentId) {
        expect(assignmentId, id);
        return pending.future;
      };
      final operation = repo.checkIn(id);
      await repo.checkIn(id);
      await repo.checkOut(id);
      expect(source.checkIns, 1);
      expect(source.checkOuts, 0);
      expect(repo.acting, isTrue);
      expect(repo.worker.rows.single.checkInAt, isNull);
      final refreshed = Completer<List<Map<String, dynamic>>>();
      source.workerRead = () => refreshed.future;
      pending.complete(DateTime.utc(2026, 11, 5, 1));
      await Future<void>.delayed(Duration.zero);
      expect(repo.acting, isTrue);
      expect(repo.actionMessage, isNull);
      refreshed.complete([
        assignment()
          ..['assignment_status'] = 'active'
          ..['check_in_at'] = '2026-11-05T02:00:00Z',
      ]);
      await operation;
      expect(repo.acting, isFalse);
      expect(repo.worker.rows.single.checkInAt, DateTime.utc(2026, 11, 5, 2));
      expect(repo.actionMessage, 'You’re checked in!');
      source.workerRead = () async => [
        assignment()
          ..['assignment_status'] = 'awaiting_verification'
          ..['check_in_at'] = '2026-11-05T02:00:00Z'
          ..['check_out_at'] = '2026-11-05T09:00:00Z',
      ];
      await repo.checkOut(id);
      expect(source.checkOuts, 1);
      expect(repo.worker.rows.single.checkOutAt, DateTime.utc(2026, 11, 5, 9));
      expect(repo.actionMessage, 'You’re checked out!');
    });

    test('server rejection, auth expiry and network uncertainty reconcile without resubmitting', () async {
      for (final (failure, message) in <(Object, String)>[
        (
          const PostgrestException(
            message: 'Check-in is outside the allowed shift window.',
            code: 'P0001',
          ),
          'Check-in is outside the allowed shift window.',
        ),
        (
          const PostgrestException(
            message: 'You must be signed in.',
            code: 'P0001',
          ),
          'Your session has expired.',
        ),
        (const AuthException('expired'), 'Your session has expired.'),
        (const SocketException('offline'), 'Could not confirm'),
      ]) {
        source.onCheckIn = (_) async => throw failure;
        final before = source.calls;
        await repo.checkIn(id);
        expect(source.calls, before + 1);
        expect(repo.actionFailed, isTrue);
        expect(repo.actionMessage, contains(message));
        expect(repo.acting, isFalse);
        expect(repo.worker.rows.single.checkInAt, isNull);
      }
    });

    test(
      'success with failed refresh reports uncertainty without invented state',
      () async {
        source.workerRead = () async => throw const SocketException('offline');
        await repo.checkIn(id);
        expect(repo.actionFailed, isTrue);
        expect(repo.actionMessage, contains('list could not be refreshed'));
        expect(repo.worker.rows, isEmpty);
      },
    );

    for (final fail in [false, true]) {
      test(
        'account switch suppresses old action completion/error ($fail)',
        () async {
          final pending = Completer<DateTime>();
          source.onCheckIn = (_) => pending.future;
          final operation = repo.checkIn(id);
          source.switchAccount(other);
          await repo.loadWorkerAssignments();
          if (fail) {
            pending.completeError(const SocketException('old'));
          } else {
            pending.complete(DateTime.utc(2026));
          }
          await operation;
          expect(repo.actionMessage, isNull);
          expect(repo.acting, isFalse);
          expect(source.calls, 1);
          source.switchAccount(null);
          await repo.checkOut(id);
          expect(source.checkOuts, 0);
        },
      );
    }

    test('new authoritative refresh supersedes older list', () async {
      final older = Completer<List<Map<String, dynamic>>>();
      source.workerRead = () => older.future;
      final load = repo.loadWorkerAssignments();
      source.workerRead = () async => [
        assignment()..['check_in_at'] = '2026-11-05T01:00:00Z',
      ];
      await repo.checkIn(id);
      older.complete([assignment()]);
      await load;
      expect(repo.worker.rows.single.checkInAt, isNotNull);
    });
  });

  group('worker action widgets', () {
    late FakeSource source;
    late WorkAttendanceRepository repo;
    setUp(() {
      source = FakeSource();
      repo = WorkAttendanceRepository(source);
    });
    tearDown(() async {
      repo.dispose();
      await source.changes.close();
    });
    Future<void> show(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WorkAttendancePage(
            repository: repo,
            captureLocation: () async =>
                const WorkAttendanceLocation.unavailable(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapAction(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    testWidgets('GPS fallback and cancellation never submit attendance', (
      tester,
    ) async {
      await show(tester);
      await tapAction(tester, 'Check in');
      expect(
        find.textContaining('Your device location is unavailable.'),
        findsOneWidget,
      );
      expect(find.text('Retry GPS'), findsOneWidget);
      expect(find.text('Continue without GPS'), findsOneWidget);
      expect(source.checkIns, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(source.checkIns, 0);
    });

    testWidgets('checkout is red and cancellation stops before GPS capture', (
      tester,
    ) async {
      source.workerRead = () async => [
        assignment()
          ..['assignment_status'] = 'active'
          ..['check_in_at'] = '2026-11-05T02:10:00Z',
      ];
      await show(tester);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Check out'),
      );
      final context = tester.element(
        find.widgetWithText(FilledButton, 'Check out'),
      );
      expect(
        button.style!.backgroundColor!.resolve({}),
        Theme.of(context).colorScheme.error,
      );
      await tapAction(tester, 'Check out');
      expect(find.text('Confirm Check-Out?'), findsOneWidget);
      expect(
        find.text(
          'Once you check out, you cannot check in again for this shift. Are you sure you want to continue?',
        ),
        findsOneWidget,
      );
      await tapAction(tester, 'Cancel');
      expect(find.text('Continue without GPS'), findsNothing);
      expect(source.checkOuts, 0);
    });

    testWidgets(
      'confirmed action locks duplicates and displays only refreshed server timestamps',
      (tester) async {
        await show(tester);
        final pending = Completer<DateTime>();
        source.onCheckIn = (_) => pending.future;
        await tapAction(tester, 'Check in');
        await tester.tap(
          find.widgetWithText(FilledButton, 'Continue without GPS'),
        );
        await tester.pump();
        expect(source.checkIns, 1);
        expect(find.textContaining('Checked in:'), findsNothing);
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Check in'),
        );
        expect(button.onPressed, isNull);
        source.workerRead = () async => [
          assignment()
            ..['assignment_status'] = 'active'
            ..['check_in_at'] = '2026-11-05T02:10:00Z',
        ];
        pending.complete(DateTime.utc(2026, 11, 5, 1));
        await tester.pumpAndSettle();
        expect(find.text('Checked in: 05/11/2026 10:10 MYT'), findsOneWidget);
        expect(find.text('Checked in successfully!'), findsOneWidget);
        await tapAction(tester, 'Check out');
        await tapAction(tester, 'Confirm Check-Out');
        source.workerRead = () async => [
          assignment()
            ..['assignment_status'] = 'awaiting_verification'
            ..['check_in_at'] = '2026-11-05T02:10:00Z'
            ..['check_out_at'] = '2026-11-05T09:00:00Z',
        ];
        await tester.tap(
          find.widgetWithText(FilledButton, 'Continue without GPS'),
        );
        await tester.pumpAndSettle();
        expect(source.checkOuts, 1);
        expect(find.text('Checked out: 05/11/2026 17:00 MYT'), findsOneWidget);
      },
    );

    testWidgets(
      'rejection is shown without a success timestamp or local time-window gate',
      (tester) async {
        source.workerRead = () async => [
          assignment()
            ..['scheduled_start'] = '2099-01-01T00:00:00Z'
            ..['scheduled_end'] = '2099-01-01T08:00:00Z',
        ];
        source.onCheckIn = (_) async => throw const PostgrestException(
          message: 'Check-in is outside the allowed shift window.',
          code: 'P0001',
        );
        await show(tester);
        await tapAction(tester, 'Check in');
        await tester.tap(
          find.widgetWithText(FilledButton, 'Continue without GPS'),
        );
        await tester.pumpAndSettle();
        expect(source.checkIns, 1);
        expect(
          find.text('Check-in is outside the allowed shift window.'),
          findsOneWidget,
        );
        expect(find.textContaining('Checked in:'), findsNothing);
      },
    );

    testWidgets(
      'account switch during confirmation cannot submit for another account',
      (tester) async {
        await show(tester);
        await tapAction(tester, 'Check in');
        source.switchAccount(other);
        await tester.pumpAndSettle();
        expect(find.textContaining('Your account changed.'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'Continue without GPS'),
          findsNothing,
        );
        expect(find.widgetWithText(TextButton, 'Retry GPS'), findsNothing);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(source.checkIns, 0);
      },
    );

    testWidgets('account switch during request suppresses stale feedback', (
      tester,
    ) async {
      await show(tester);
      final pending = Completer<DateTime>();
      source.onCheckIn = (_) => pending.future;
      await tapAction(tester, 'Check in');
      await tester.tap(
        find.widgetWithText(FilledButton, 'Continue without GPS'),
      );
      await tester.pump();
      source.workerRead = () async => [];
      source.switchAccount(other);
      pending.completeError(const SocketException('old account'));
      await tester.pumpAndSettle();
      expect(find.text('No work assignments'), findsOneWidget);
      expect(find.textContaining('Could not confirm'), findsNothing);
      expect(find.textContaining('recorded by the server'), findsNothing);
    });
  });
}
