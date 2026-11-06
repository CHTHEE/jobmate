import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_gps.dart';
import 'package:jobmate/features/work_attendance/work_attendance_location_dialog.dart';
import 'package:jobmate/features/work_attendance/work_attendance_models.dart';
import 'package:jobmate/features/work_attendance/work_attendance_pages.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_verification_pages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_repository_test.dart'
    show id, other, FakeSource, assignment;

Map<String, dynamic> gpsRow({String? status = 'granted'}) => {
  'assignment_id': id,
  'company_id': other,
  'check_in_at': '2026-11-06T01:00:00Z',
  'check_in_location_status': status,
  'check_in_latitude': status == 'granted' ? 3.139 : null,
  'check_in_longitude': status == 'granted' ? 101.6869 : null,
  'check_out_at': null,
  'check_out_location_status': null,
  'check_out_latitude': null,
  'check_out_longitude': null,
};

class GpsSource implements WorkAttendanceGpsSource {
  @override
  String? userId = id;
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get accountChanges => changes.stream;
  Future<List<Map<String, dynamic>>> Function() response = () async => [
    gpsRow(),
  ];
  int calls = 0;
  @override
  Future<List<Map<String, dynamic>>> read(
    String companyId,
    String assignmentId,
  ) {
    expect(companyId, other);
    expect(assignmentId, id);
    calls++;
    return response();
  }

  void account(String? value) {
    userId = value;
    changes.add(value);
  }
}

class _LocalHttpOverrides extends HttpOverrides {}

class RecordingAttendanceSource extends FakeSource {
  WorkAttendanceLocation? received;
  @override
  Future<DateTime> checkIn(
    String assignmentId, {
    WorkAttendanceLocation location =
        const WorkAttendanceLocation.unavailable(),
  }) {
    received = location;
    return super.checkIn(assignmentId, location: location);
  }

  @override
  Future<DateTime> checkOut(
    String assignmentId, {
    WorkAttendanceLocation location =
        const WorkAttendanceLocation.unavailable(),
  }) {
    received = location;
    return super.checkOut(assignmentId, location: location);
  }
}

void main() {
  group('employer GPS repository', () {
    late GpsSource source;
    late WorkAttendanceGpsRepository repository;
    setUp(() {
      source = GpsSource();
      repository = WorkAttendanceGpsRepository(source, other, id);
    });
    tearDown(() async {
      repository.dispose();
      await source.changes.close();
    });

    for (final status in ['granted', 'denied', 'unavailable', null]) {
      test('reads $status and constructs maps only for coordinates', () async {
        source.response = () async => [gpsRow(status: status)];
        await repository.load();
        expect(repository.error, isNull);
        expect(repository.record!.checkIn.status, status);
        expect(
          repository.record!.checkIn.mapsLink != null,
          status == 'granted',
        );
        expect(repository.record!.checkOut.label, 'Not recorded yet');
        expect(repository.record!.checkOut.mapsLink, isNull);
      });
    }
    test('granted without coordinates is truthful and has no map', () async {
      source.response = () async => [
        gpsRow()
          ..['check_in_latitude'] = null
          ..['check_in_longitude'] = null,
      ];
      await repository.load();
      expect(
        repository.record!.checkIn.label,
        contains('coordinates unavailable'),
      );
      expect(repository.record!.checkIn.mapsLink, isNull);
    });
    test(
      'malformed, incomplete, foreign and duplicate records fail closed',
      () async {
        for (final rows in [
          [gpsRow()..['company_id'] = id],
          [gpsRow()..['assignment_id'] = other],
          [gpsRow()..remove('check_in_location_status')],
          [gpsRow()..['check_in_latitude'] = double.nan],
          [gpsRow()..['check_in_longitude'] = 181],
          [gpsRow()..['check_in_location_status'] = 'denied'],
          [gpsRow()..['check_in_at'] = null],
          [gpsRow()..['check_out_at'] = '2026-11-05T01:00:00Z'],
          [gpsRow(), gpsRow()],
          <Map<String, dynamic>>[],
        ]) {
          source.response = () async => rows;
          await repository.load();
          expect(repository.record, isNull);
          expect(repository.error, isNotNull);
        }
      },
    );
    test('permission denial and missing RPC never expose cached GPS', () async {
      await repository.load();
      expect(repository.record, isNotNull);
      for (final code in ['42501', 'PGRST202']) {
        source.response = () async => throw PostgrestException(
          message: 'private backend details',
          code: code,
        );
        await repository.load();
        expect(repository.record, isNull);
        expect(repository.error, isNot(contains('private backend details')));
      }
    });
    test(
      'account away-and-back rejects stale results and cannot reopen old view',
      () async {
        final pending = Completer<List<Map<String, dynamic>>>();
        source.response = () => pending.future;
        final load = repository.load();
        source.account(other);
        source.account(id);
        pending.complete([gpsRow()]);
        await load;
        expect(repository.record, isNull);
        expect(repository.current, isFalse);
        await repository.load();
        expect(source.calls, 1);
      },
    );
    test('silent account change hides loaded data immediately', () async {
      await repository.load();
      source.userId = other;
      expect(repository.record, isNull);
    });
  });

  test(
    'attendance RPCs transmit granted, denied and unavailable payloads for both actions',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <(String, dynamic)>[];
      server.listen((request) async {
        requests.add((
          request.uri.path,
          jsonDecode(await utf8.decoder.bind(request).join()),
        ));
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode('2026-11-06T01:00:00Z'));
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'fake-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'fake-token',
          'token_type': 'bearer',
          'user': {'id': id},
        }),
      );
      final source = SupabaseWorkAttendanceSource(client);
      for (final location in [
        WorkAttendanceLocation.granted(latitude: 3.139, longitude: 101.6869),
        const WorkAttendanceLocation.denied(),
        const WorkAttendanceLocation.unavailable(),
      ]) {
        expect(
          await source.checkIn(id, location: location),
          DateTime.utc(2026, 11, 6, 1),
        );
        expect(
          await source.checkOut(id, location: location),
          DateTime.utc(2026, 11, 6, 1),
        );
        for (final request in requests.skip(requests.length - 2)) {
          expect(request.$2, {
            'p_assignment_id': id,
            'p_location_status': location.status,
            'p_latitude': location.latitude,
            'p_longitude': location.longitude,
          });
        }
      }
      expect(requests.map((r) => r.$1).toSet(), {
        '/rest/v1/rpc/check_in_work_assignment',
        '/rest/v1/rpc/check_out_work_assignment',
      });
      expect(requests.length, 6);
    }, _LocalHttpOverrides()),
  );

  test(
    'GPS adapter uses scoped RPC and propagates denied access',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var denied = false;
      var calls = 0;
      server.listen((request) async {
        calls++;
        expect(
          request.uri.path,
          '/rest/v1/rpc/read_employer_work_attendance_gps',
        );
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'p_company_id': other,
          'p_assignment_id': id,
        });
        request.response.headers.contentType = ContentType.json;
        request.response.statusCode = denied ? 403 : 200;
        request.response.write(
          jsonEncode(
            denied ? {'message': 'denied', 'code': '42501'} : [gpsRow()],
          ),
        );
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'fake-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      final source = SupabaseWorkAttendanceGpsSource(client);
      await expectLater(source.read(other, id), throwsA(isA<AuthException>()));
      expect(calls, 0);
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'fake-token',
          'token_type': 'bearer',
          'user': {'id': id},
        }),
      );
      expect((await source.read(other, id)).single['assignment_id'], id);
      denied = true;
      await expectLater(
        source.read(other, id),
        throwsA(isA<PostgrestException>()),
      );
      expect(calls, 2);
    }, _LocalHttpOverrides()),
  );

  for (final status in ['granted', 'denied', 'unavailable']) {
    for (final checkingIn in [true, false]) {
      testWidgets(
        'worker $status reaches ${checkingIn ? 'check-in' : 'check-out'} repository unchanged',
        (tester) async {
          final source = RecordingAttendanceSource();
          final repository = WorkAttendanceRepository(source);
          addTearDown(() async {
            repository.dispose();
            await source.changes.close();
          });
          if (!checkingIn) {
            source.workerRead = () async => [
              assignment()
                ..['assignment_status'] = 'active'
                ..['check_in_at'] = '2026-11-05T01:00:00Z',
            ];
          }
          final location = status == 'granted'
              ? WorkAttendanceLocation.granted(
                  latitude: 3.139,
                  longitude: 101.6869,
                )
              : status == 'denied'
              ? const WorkAttendanceLocation.denied()
              : const WorkAttendanceLocation.unavailable();
          await tester.pumpWidget(
            MaterialApp(
              home: WorkAttendancePage(
                repository: repository,
                captureLocation: () async => location,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.text(checkingIn ? 'Check in' : 'Check out'),
          );
          await tester.tap(find.text(checkingIn ? 'Check in' : 'Check out'));
          await tester.pumpAndSettle();
          if (!checkingIn) {
            await tester.tap(find.text('Confirm Check-Out'));
          }
          await tester.pumpAndSettle();
          expect(source.received, isNull);
          await tester.tap(
            find.widgetWithText(
              FilledButton,
              status == 'granted'
                  ? checkingIn
                        ? 'Confirm check-in'
                        : 'Confirm check-out'
                  : 'Continue without GPS',
            ),
          );
          await tester.pumpAndSettle();
          expect(source.received, same(location));
          expect(source.checkIns + source.checkOuts, 1);
        },
      );
    }
    testWidgets('worker GPS $status preserves confirmation and fallback', (
      tester,
    ) async {
      WorkAttendanceLocation? result;
      final location = status == 'granted'
          ? WorkAttendanceLocation.granted(latitude: 3.139, longitude: 101.6869)
          : status == 'denied'
          ? const WorkAttendanceLocation.denied()
          : const WorkAttendanceLocation.unavailable();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<WorkAttendanceLocation>(
                    context: context,
                    builder: (_) => WorkAttendanceLocationDialog(
                      jobTitle: 'Synthetic shift',
                      checkingIn: true,
                      canContinue: () => true,
                      captureLocation: () async => location,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('Retry GPS'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          status == 'granted' ? 'Confirm check-in' : 'Continue without GPS',
        ),
      );
      await tester.pumpAndSettle();
      expect(result, same(location));
    });
  }

  for (final status in ['granted', 'denied', 'unavailable']) {
    testWidgets('employer displays both $status attendance locations', (
      tester,
    ) async {
      final source = GpsSource();
      source.response = () async => [
        gpsRow(status: status)
          ..['check_out_at'] = '2026-11-06T09:00:00Z'
          ..['check_out_location_status'] = status
          ..['check_out_latitude'] = status == 'granted' ? 3.14 : null
          ..['check_out_longitude'] = status == 'granted' ? 101.68 : null,
      ];
      final repository = WorkAttendanceGpsRepository(source, other, id);
      addTearDown(() async {
        repository.dispose();
        await source.changes.close();
      });
      await tester.pumpWidget(
        MaterialApp(home: WorkAttendanceGpsDialog(repository: repository)),
      );
      await tester.pumpAndSettle();
      final label = status == 'granted'
          ? 'Captured'
          : status == 'denied'
          ? 'Permission denied'
          : 'Unavailable';
      expect(find.text('Check-in GPS: $label'), findsOneWidget);
      expect(find.text('Check-out GPS: $label'), findsOneWidget);
      expect(
        find.textContaining('in Google Maps'),
        status == 'granted' ? findsNWidgets(2) : findsNothing,
      );
    });
  }

  testWidgets(
    'employer GPS maps link, refresh denial and account switching clear coordinates',
    (tester) async {
      final source = GpsSource();
      final repository = WorkAttendanceGpsRepository(source, other, id);
      addTearDown(() async {
        repository.dispose();
        await source.changes.close();
      });
      Uri? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: WorkAttendanceGpsDialog(
            repository: repository,
            openMap: (uri) async {
              opened = uri;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Check-in GPS: Captured'), findsOneWidget);
      expect(find.text('Recorded: 06/11/2026 09:00 MYT'), findsOneWidget);
      await tester.tap(find.text('Open Check-in in Google Maps'));
      await tester.pumpAndSettle();
      expect(opened!.host, 'www.google.com');
      expect(opened!.queryParameters, {'api': '1', 'query': '3.139,101.6869'});
      source.response = () async =>
          throw const PostgrestException(message: 'denied', code: '42501');
      await tester.tap(find.text('Refresh GPS'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Latitude:'), findsNothing);
      expect(find.textContaining('not authorized'), findsOneWidget);
      source.account(other);
      await tester.pumpAndSettle();
      expect(find.textContaining('Your account changed'), findsOneWidget);
      expect(find.text('Refresh GPS'), findsNothing);
    },
  );

  for (final width in [320.0, 1200.0]) {
    testWidgets('GPS dialog fits ${width}px with large text', (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = GpsSource();
      final repository = WorkAttendanceGpsRepository(source, other, id);
      addTearDown(() async {
        repository.dispose();
        await source.changes.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: WorkAttendanceGpsDialog(repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open Check-in in Google Maps'));
      expect(find.text('Close'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('company page opens GPS only after authorized company access', (
    tester,
  ) async {
    final source = FakeSource();
    final gps = GpsSource();
    final repository = WorkAttendanceRepository(source);
    addTearDown(() async {
      repository.dispose();
      await source.changes.close();
      await gps.changes.close();
    });
    source.companyRead = (_) async => [assignment(company: true)];
    Future<void> page(JobAccess access) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WorkVerificationPage(
            key: UniqueKey(),
            repository: repository,
            companyId: other,
            loadAccess: () async => access,
            gpsSource: gps,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await page(const JobAccess(null, 'Denied'));
    expect(find.text('View attendance GPS'), findsNothing);
    expect(gps.calls, 0);
    await page(const JobAccess({'company_id': other}, null));
    await tester.ensureVisible(find.text('View attendance GPS'));
    await tester.tap(find.text('View attendance GPS'));
    await tester.pumpAndSettle();
    expect(find.text('Attendance GPS'), findsOneWidget);
    expect(gps.calls, 1);
    source.switchAccount(other);
    gps.account(other);
    await tester.pumpAndSettle();
    expect(find.textContaining('Latitude:'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });
}
