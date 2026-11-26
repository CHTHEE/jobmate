import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/job_discovery_distance.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/features/location/nearby_jobs_map.dart';
import 'package:jobmate/features/location/nearby_map_geometry.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'nearby_jobs_list_test.dart' show origin, posting;

class _MapPlatform extends MapLibrePlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final sources = <String, Map<String, dynamic>>{};
  final layers = <String>[];
  final circles = <String, ({bool interactive, Map<String, dynamic> paint})>{};
  int fits = 0;
  bool disposed = false;
  bool fail = false;
  Future<bool?> Function()? cameraFit;
  bool _created = false;

  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    void Function(int) onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  ) {
    if (!_created) {
      _created = true;
      onPlatformViewCreated(0);
    }
    return const SizedBox.expand();
  }

  @override
  Future<void> initPlatform(int id) async {}

  @override
  Future<List> getSourceIds() async => sources.keys.toList();

  @override
  Future<List> getLayerIds() async => layers;

  @override
  Future<void> addGeoJsonSource(
    String id,
    Map<String, dynamic> geojson, {
    String? promoteId,
  }) async {
    if (fail) throw StateError('Map source unavailable');
    sources[id] = geojson;
  }

  @override
  Future<void> setGeoJsonSource(String id, Map<String, dynamic> geojson) async {
    sources[id] = geojson;
  }

  @override
  Future<void> addFillLayer(
    String sourceId,
    String layerId,
    Map<String, dynamic> properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    required bool enableInteraction,
  }) async => layers.add(layerId);

  @override
  Future<void> addLineLayer(
    String sourceId,
    String layerId,
    Map<String, dynamic> properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    required bool enableInteraction,
  }) async => layers.add(layerId);

  @override
  Future<void> addCircleLayer(
    String sourceId,
    String layerId,
    Map<String, dynamic> properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    required bool enableInteraction,
  }) async {
    circles[layerId] = (interactive: enableInteraction, paint: properties);
    final index = layers.indexOf(belowLayerId ?? '');
    layers.insert(index < 0 ? layers.length : index, layerId);
  }

  @override
  Future<bool?> moveCamera(CameraUpdate update) async {
    fits++;
    return cameraFit == null ? true : cameraFit!();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  final jobs = [
    (job: BrowseJob.published(posting('a', origin.latitude)), distanceKm: 0.0),
    (job: BrowseJob.published(posting('b', origin.latitude)), distanceKm: 0.0),
  ];

  for (final (width, height) in [(320.0, 300.0), (1440.0, 420.0)]) {
    testWidgets('map card clips its viewport and wraps its footer at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previous = MapLibrePlatform.createInstance;
      final platform = _MapPlatform();
      MapLibrePlatform.createInstance = () => platform;
      addTearDown(() => MapLibrePlatform.createInstance = previous);
      await tester.pumpWidget(
        MaterialApp(
          theme: JobMateTheme.light(),
          home: Scaffold(
            body: NearbyJobsMap(
              origin: origin,
              radiusKm: 5,
              results: jobs,
              onJobSelected: (_) {},
              onShowList: () {},
            ),
          ),
        ),
      );
      platform.onMapStyleLoadedPlatform.call(null);
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('nearby-map-card'));
      final viewport = find.byKey(const ValueKey('nearby-map-viewport'));
      final container = tester.widget<Container>(card);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(16));
      expect(decoration.border, Border.all(color: JobMateTheme.divider));
      expect(decoration.color, Colors.white);
      expect(decoration.boxShadow, isNull);
      expect(container.padding, const EdgeInsets.all(8));
      final clip = tester.widget<ClipRRect>(viewport);
      expect(clip.borderRadius, BorderRadius.circular(12));
      expect(clip.clipBehavior, Clip.antiAlias);
      expect(
        find.descendant(of: viewport, matching: find.byType(MapLibreMap)),
        findsOneWidget,
      );
      expect(tester.getSize(viewport).height, height);
      for (final label in [
        '○ Selected location',
        '● Nearby job',
        '5 km radius',
        'OpenFreeMap · © OpenMapTiles · © OpenStreetMap contributors',
        'Reload map',
        'View list',
      ]) {
        final item = find.descendant(of: card, matching: find.text(label));
        expect(item, findsOneWidget);
        expect(
          tester.getTopLeft(item).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(viewport).dy),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('GeoJSON keeps both coincident job IDs and uses longitude first', () {
    final markers = nearbyJobMarkers(jobs)['features'] as List;
    expect(markers.map((feature) => feature['id']), ['a', 'b']);
    for (final feature in markers) {
      expect(feature['geometry']['coordinates'], [
        origin.longitude,
        origin.latitude,
      ]);
    }
    for (final radius in [5, 10, 20]) {
      final ring = nearbyRadiusRing(origin, radius);
      expect(ring.length, greaterThan(4));
      expect(ring.first, ring.last);
      for (final point in ring) {
        expect(
          jobDiscoveryDistanceKm(origin, (
            longitude: point.first,
            latitude: point.last,
          )),
          closeTo(radius, 0.000001),
        );
      }
    }
  });

  testWidgets(
    'delayed and failed camera fits leave the styled map and overlays usable',
    (tester) async {
      final previous = MapLibrePlatform.createInstance;
      final delayed = Completer<bool?>();
      final platform = _MapPlatform()..cameraFit = () => delayed.future;
      MapLibrePlatform.createInstance = () => platform;
      addTearDown(() => MapLibrePlatform.createInstance = previous);
      String? selected;
      Widget page(int radius) => MaterialApp(
        home: Scaffold(
          body: NearbyJobsMap(
            origin: origin,
            radiusKm: radius,
            results: jobs,
            onJobSelected: (id) => selected = id,
            onShowList: () {},
          ),
        ),
      );
      await tester.pumpWidget(page(5));
      await tester.pump();
      platform.onMapStyleLoadedPlatform.call(null);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 16));
      expect(find.textContaining('Map unavailable'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(platform.layers, hasLength(4));
      platform.onFeatureTappedPlatform.call({
        'point': const math.Point<double>(20, 20),
        'latLng': const LatLng(3.15, 101.7),
        'id': 'b',
        'layerId': 'nearby-jobs',
      });
      expect(selected, 'b');
      platform.cameraFit = () async => throw StateError('Bounds rejected');
      await tester.pumpWidget(page(20));
      await tester.pumpAndSettle();
      expect(platform.fits, 2);
      expect(find.textContaining('Map unavailable'), findsNothing);
      delayed.complete(false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a controller without a loaded style times out and offers List', (
    tester,
  ) async {
    final previous = MapLibrePlatform.createInstance;
    final platform = _MapPlatform();
    MapLibrePlatform.createInstance = () => platform;
    addTearDown(() => MapLibrePlatform.createInstance = previous);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyJobsMap(
            origin: origin,
            radiusKm: 5,
            results: jobs,
            onJobSelected: (_) {},
            onShowList: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(platform.layers, isEmpty);
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.textContaining('Map unavailable'), findsOneWidget);
    expect(find.text('View list'), findsOneWidget);
    expect(platform.disposed, isTrue);
  });

  testWidgets(
    'map redraws on style reload, fits only on area changes and disposes',
    (tester) async {
      final factory = MapLibrePlatform.createInstance;
      final platform = _MapPlatform();
      MapLibrePlatform.createInstance = () => platform;
      addTearDown(() => MapLibrePlatform.createInstance = factory);
      String? selected;
      Widget map({
        int radius = 5,
        ({double latitude, double longitude}) point = origin,
        bool filtered = false,
      }) => MaterialApp(
        home: Scaffold(
          body: NearbyJobsMap(
            origin: point,
            radiusKm: radius,
            results: filtered ? [jobs.first] : jobs,
            onJobSelected: (id) => selected = id,
            onShowList: () {},
          ),
        ),
      );
      await tester.pumpWidget(map());
      await tester.pump();
      expect(platform.layers, isEmpty);
      platform.onMapStyleLoadedPlatform.call(null);
      await tester.pumpAndSettle();
      expect(platform.layers, hasLength(4));
      expect(platform.fits, 1);
      expect(find.textContaining('Selected location'), findsOneWidget);
      void expectMarkerPriority() {
        const originLayer = 'nearby-selected-origin';
        const jobLayer = 'nearby-jobs';
        expect(platform.layers.last, jobLayer);
        expect(platform.circles[originLayer]!.interactive, isFalse);
        expect(platform.circles[originLayer]!.paint['circle-opacity'], 0);
        expect(platform.circles[jobLayer]!.interactive, isTrue);
        expect(platform.circles[jobLayer]!.paint['circle-radius'], 11);
      }

      expectMarkerPriority();
      final area = platform.sources['nearby-area-source']!['features'] as List;
      final markers =
          platform.sources['nearby-job-source']!['features'] as List;
      expect(area.last['geometry']['coordinates'], [
        origin.longitude,
        origin.latitude,
      ]);
      expect(markers.map((marker) => marker['geometry']['coordinates']), [
        [origin.longitude, origin.latitude],
        [origin.longitude, origin.latitude],
      ]);
      platform.onFeatureTappedPlatform.call({
        'point': const math.Point<double>(20, 20),
        'latLng': const LatLng(3.15, 101.7),
        'id': 'origin',
        'layerId': 'nearby-selected-origin',
      });
      expect(selected, isNull);
      platform.onFeatureTappedPlatform.call({
        'point': const math.Point<double>(20, 20),
        'latLng': const LatLng(3.15, 101.7),
        'id': 'b',
        'layerId': 'nearby-jobs',
      });
      expect(selected, 'b');
      await tester.pumpWidget(map(filtered: true));
      await tester.pumpAndSettle();
      expect(platform.sources['nearby-job-source']!['features'], hasLength(1));
      expect(platform.fits, 1);
      await tester.pumpWidget(map(radius: 20));
      await tester.pumpAndSettle();
      expect(platform.fits, 2);
      await tester.pumpWidget(
        map(radius: 20, point: (latitude: 3.2, longitude: 101.8)),
      );
      await tester.pumpAndSettle();
      expect(platform.fits, 3);
      final radiusData = platform.sources['nearby-area-source'];
      platform.sources.clear();
      platform.layers.clear();
      platform.onMapStyleLoadedPlatform.call(null);
      await tester.pumpAndSettle();
      expect(platform.layers, hasLength(4));
      expectMarkerPriority();
      expect(platform.sources['nearby-area-source'], radiusData);
      expect(platform.fits, 3);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(platform.disposed, isTrue);
    },
  );

  testWidgets(
    'map failure disposes the view, and Retry or List are available',
    (tester) async {
      final factory = MapLibrePlatform.createInstance;
      final failed = _MapPlatform()..fail = true;
      final retry = _MapPlatform();
      var attempts = 0;
      MapLibrePlatform.createInstance = () => attempts++ == 0 ? failed : retry;
      addTearDown(() => MapLibrePlatform.createInstance = factory);
      var showedList = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NearbyJobsMap(
              origin: origin,
              radiusKm: 5,
              results: jobs,
              onJobSelected: (_) {},
              onShowList: () => showedList = true,
            ),
          ),
        ),
      );
      await tester.pump();
      failed.onMapStyleLoadedPlatform.call(null);
      await tester.pumpAndSettle();
      expect(find.textContaining('Map unavailable'), findsOneWidget);
      expect(failed.disposed, isTrue);
      await tester.tap(find.text('View list'));
      expect(showedList, isTrue);
      await tester.tap(find.text('Retry map'));
      await tester.pump();
      retry.onMapStyleLoadedPlatform.call(null);
      await tester.pumpAndSettle();
      expect(retry.layers, hasLength(4));
      expect(retry.fits, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
