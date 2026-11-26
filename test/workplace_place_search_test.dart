import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_form_page.dart';
import 'package:jobmate/features/jobs/workplace_coordinates.dart';
import 'package:jobmate/features/jobs/workplace_map_picker.dart';
import 'package:jobmate/features/jobs/workplace_place_search.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'job_postings_test.dart'
    show TestJobs, completeJob, field, tapPostingAction;

const first = (
  name: 'First result',
  address: 'Kuala Lumpur, Malaysia',
  coordinates: (latitude: 3.1, longitude: 101.7),
);
const second = (
  name: 'Second result',
  address: 'Selangor, Malaysia',
  coordinates: (latitude: 3.2, longitude: 101.6),
);

class FakeWorkplaceMap extends MapLibrePlatform {
  late CameraPosition camera;
  bool _created = false;

  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    OnPlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  ) {
    if (!_created) {
      _created = true;
      camera = CameraPosition.fromMap(creationParams['initialCameraPosition'])!;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => onPlatformViewCreated(1),
      );
    }
    return const ColoredBox(color: Colors.blueGrey);
  }

  @override
  Future<void> initPlatform(int id) async {}

  @override
  Future<bool?> moveCamera(CameraUpdate cameraUpdate) async {
    camera = CameraPosition.fromMap(cameraUpdate.toJson()[1])!;
    onCameraIdlePlatform(camera);
    return true;
  }

  @override
  Future<CameraPosition?> updateMapOptions(
    Map<String, dynamic> optionsUpdate,
  ) async => camera;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> mount(
  WidgetTester tester,
  WorkplaceSearch search, {
  Future<bool> Function(WorkplacePlace)? select,
  bool autoSearch = false,
  String initialQuery = '',
}) async {
  tester.view.physicalSize = const Size(390, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AlertDialog(
          scrollable: true,
          content: SizedBox(
            width: 560,
            child: WorkplacePlaceSearchField(
              search: search,
              mapReady: true,
              onSelect: select ?? (_) async => true,
              autoSearch: autoSearch,
              initialQuery: initialQuery,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> cancelWorkplacePicker(WidgetTester tester) async {
  final cancel = find.descendant(
    of: find.widgetWithText(AlertDialog, 'Confirm workplace location'),
    matching: find.widgetWithText(TextButton, 'Cancel'),
  );
  await tester.ensureVisible(cancel);
  await tester.tap(cancel);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('narrow Create Job dialog suggests once without confirming', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final originalFactory = MapLibrePlatform.createInstance;
    late FakeWorkplaceMap map;
    MapLibrePlatform.createInstance = () => map = FakeWorkplaceMap();
    addTearDown(() => MapLibrePlatform.createInstance = originalFactory);
    final repo = TestJobs();
    final queries = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: JobFormPage(
          repository: repo,
          pickWorkplace: (context, initial, address, autoSearch) =>
              showWorkplacePicker(
                context,
                initial,
                address,
                autoSearch,
                search: (query) async {
                  queries.add(query);
                  return [first];
                },
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    field(tester, 'Job location').text = '  Mid Valley Megamall  ';
    await tester.pumpAndSettle();
    expect(queries, isEmpty);
    Future<void> openPicker() async {
      final open = find.text('Choose on map');
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      map.onMapStyleLoadedPlatform(null);
      await tester.pumpAndSettle();
    }

    await openPicker();
    final search = find.widgetWithText(TextField, 'Search for a place');
    expect(
      tester.widget<TextField>(search).controller!.text,
      'Mid Valley Megamall',
    );
    expect(queries, ['Mid Valley Megamall']);
    expect(map.camera.target, const LatLng(3.1, 101.7));
    expect(
      find.textContaining('Suggested location (unconfirmed)'),
      findsOneWidget,
    );
    expect(find.text(first.address), findsOneWidget);
    await cancelWorkplacePicker(tester);
    expect(field(tester, 'Job location').text, '  Mid Valley Megamall  ');
    await openPicker();
    expect(queries, ['Mid Valley Megamall']);
    await tapPostingAction(tester, 'Search');
    expect(queries, ['Mid Valley Megamall', 'Mid Valley Megamall']);
    await cancelWorkplacePicker(tester);
    expect(repo.saves, 0);
  });

  testWidgets(
    'automatic search leaves multiple matches for explicit selection',
    (tester) async {
      final queries = <String>[];
      final response = Completer<List<WorkplacePlace>>();
      WorkplaceCoordinates? selected;
      await mount(
        tester,
        (query) async {
          queries.add(query);
          return response.future;
        },
        autoSearch: true,
        initialQuery: '  Example  ',
        select: (place) async {
          selected = place.coordinates;
          return true;
        },
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      response.complete([first, second]);
      await tester.pumpAndSettle();
      expect(queries, ['Example']);
      expect(selected, isNull);
      expect(find.text(first.name), findsOneWidget);
      await tester.tap(find.text(second.name));
      await tester.pumpAndSettle();
      expect(selected, second.coordinates);
    },
  );

  testWidgets(
    'real picker centers, adjusts and confirms separately from search and address',
    (tester) async {
      final originalFactory = MapLibrePlatform.createInstance;
      late FakeWorkplaceMap map;
      MapLibrePlatform.createInstance = () => map = FakeWorkplaceMap();
      addTearDown(() => MapLibrePlatform.createInstance = originalFactory);
      final queries = <String>[];
      WorkplacePickerResult? result;
      final repo = TestJobs()
        ..records = [
          {
            ...completeJob(),
            'job_id': 'draft',
            'status': 'draft',
            'latitude': 3.139,
            'longitude': 101.6869,
          },
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: JobFormPage(
            repository: repo,
            jobId: 'draft',
            pickWorkplace: (context, initial, address, autoSearch) async =>
                result = await showWorkplacePicker(
                  context,
                  initial,
                  address,
                  autoSearch,
                  search: (query) async {
                    queries.add(query);
                    return [first, second];
                  },
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> chooseResult({
        LatLng initial = const LatLng(3.139, 101.6869),
      }) async {
        final previousQueries = queries.length;
        final open = find.text('Change pin');
        await tester.ensureVisible(open);
        await tester.tap(open);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        map.onMapStyleLoadedPlatform(null);
        await tester.pumpAndSettle();
        expect(map.camera.target, initial);
        final search = find.widgetWithText(TextField, 'Search for a place');
        expect(tester.widget<TextField>(search).controller!.text, 'Shah Alam');
        expect(queries, hasLength(previousQueries));
        await tester.enterText(search, 'Example');
        expect(queries, hasLength(previousQueries));
        await tapPostingAction(tester, 'Search');
        expect(queries, hasLength(previousQueries + 1));
        expect(queries.last, 'Example');
        await tapPostingAction(tester, second.name);
        expect(map.camera.target, const LatLng(3.2, 101.6));
        expect(map.camera.zoom, 16);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(repo.saves, 0);
      }

      await chooseResult();
      await cancelWorkplacePicker(tester);
      expect(result, isNull);
      expect(field(tester, 'Job location').text, 'Shah Alam');
      expect(find.text('3.139000, 101.686900'), findsOneWidget);
      expect(find.text('Workplace location confirmed'), findsOneWidget);
      await chooseResult();
      final zoom = find.byTooltip('Zoom in');
      await tester.ensureVisible(zoom);
      await tester.tap(zoom);
      await tester.pumpAndSettle();
      await tapPostingAction(tester, 'Confirm workplace location');
      expect(result?.placeAddress, second.address);
      expect(result?.coordinates, second.coordinates);
      expect(field(tester, 'Job location').text, 'Shah Alam');

      await chooseResult(initial: const LatLng(3.2, 101.6));
      final north = find.byTooltip('Move pin north');
      await tester.ensureVisible(north);
      await tester.tap(north);
      await tester.pumpAndSettle();
      final adjusted = workplaceCoordinates(
        map.camera.target.latitude,
        map.camera.target.longitude,
      )!;
      expect(adjusted, isNot(second.coordinates));
      await tapPostingAction(tester, 'Confirm workplace location');
      expect(result?.placeAddress, isNull);
      expect(result?.coordinates, adjusted);
      expect(field(tester, 'Job location').text, 'Shah Alam');
      expect(
        find.text(
          '${adjusted.latitude.toStringAsFixed(6)}, ${adjusted.longitude.toStringAsFixed(6)}',
        ),
        findsOneWidget,
      );
      expect(repo.saves, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'explicit submission validates and selects only the chosen point',
    (tester) async {
      final queries = <String>[];
      WorkplaceCoordinates? selected;
      await mount(
        tester,
        (query) async {
          queries.add(query);
          return [
            first,
            second,
            (
              name: 'Invalid result',
              address: '',
              coordinates: (latitude: 95.0, longitude: 101.0),
            ),
          ];
        },
        select: (place) async {
          selected = place.coordinates;
          return true;
        },
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2–120'), findsOneWidget);
      expect(queries, isEmpty);
      await tester.enterText(find.byType(TextField), ' Example search ');
      await tester.pumpAndSettle();
      expect(queries, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(queries, ['Example search']);
      expect(find.text(first.name), findsOneWidget);
      expect(find.text(second.name), findsOneWidget);
      expect(find.text('Invalid result'), findsNothing);
      expect(selected, isNull);
      await tester.tap(find.text(second.name));
      await tester.pumpAndSettle();
      expect(selected, second.coordinates);
      expect(
        find.textContaining('pin matches the workplace address'),
        findsOneWidget,
      );
      expect(find.text('Powered by Geoapify'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (code, message) in [
    ('empty', 'No matching places found.'),
    ('rate_limited', 'Search limit reached.'),
    ('timeout', 'Place search timed out.'),
    ('unavailable', 'Place search is unavailable.'),
    ('network', 'Could not reach place search.'),
  ]) {
    testWidgets('search displays $code and allows a subsequent search', (
      tester,
    ) async {
      var attempts = 0;
      await mount(tester, (_) async {
        if (++attempts > 1) return [first];
        if (code == 'empty') return [];
        if (code == 'network') throw Exception('network');
        throw WorkplaceSearchFailure(code);
      });
      await tester.enterText(find.byType(TextField), 'Example');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.textContaining(message), findsOneWidget);
      await tester.tap(find.text(code == 'empty' ? 'Search' : 'Retry search'));
      await tester.pumpAndSettle();
      expect(find.text(first.name), findsOneWidget);
    });
  }
}
