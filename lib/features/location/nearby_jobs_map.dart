import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../shared/theme/jobmate_theme.dart';
import '../jobs/workplace_coordinates.dart';
import 'nearby_job_results.dart';
import 'nearby_map_geometry.dart';

typedef NearbyMapBuilder = Widget Function(
  BuildContext context,
  WorkplaceCoordinates origin,
  int radiusKm,
  List<NearbyJobResult> results,
  ValueChanged<String> onJobSelected,
  VoidCallback onShowList,
);

class NearbyJobsMap extends StatefulWidget {
  const NearbyJobsMap({
    super.key,
    required this.origin,
    required this.radiusKm,
    required this.results,
    required this.onJobSelected,
    required this.onShowList,
  });

  final WorkplaceCoordinates origin;
  final int radiusKm;
  final List<NearbyJobResult> results;
  final ValueChanged<String> onJobSelected;
  final VoidCallback onShowList;

  @override
  State<NearbyJobsMap> createState() => _NearbyJobsMapState();
}

class _NearbyJobsMapState extends State<NearbyJobsMap> {
  static const _style = 'https://tiles.openfreemap.org/styles/liberty';
  static const _areaSource = 'nearby-area-source';
  static const _jobSource = 'nearby-job-source';
  static const _areaLayer = 'nearby-radius-fill';
  static const _outlineLayer = 'nearby-radius-outline';
  static const _originLayer = 'nearby-selected-origin';
  static const _jobLayer = 'nearby-jobs';

  MapLibreMapController? _controller;
  Timer? _deadline;
  int _attempt = 0;
  int _styleRevision = 0;
  int _installedStyle = 0;
  Object? _syncRun;
  bool _dirty = false;
  bool _fit = true;
  bool _ready = false;
  bool _styleLoaded = false;
  bool _failed = false;
  String _phase = 'waiting for controller';

  bool get _supported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (_supported) _startDeadline();
  }

  void _startDeadline() {
    _deadline?.cancel();
    _phase = 'waiting for controller';
    _log('Creating map view');
    _deadline = Timer(const Duration(seconds: 15), () {
      _log('Startup timeout while $_phase');
      _showFailure();
    });
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[Nearby map #$_attempt] $message');
  }

  void _logError(String operation, Object error, StackTrace stack) {
    if (!kDebugMode) return;
    final description = error is PlatformException
        ? '${error.code}: ${error.message}'
        : error.toString();
    final safeDescription = description
        .replaceAll(RegExp(r'https?://[^\s)\]]+'), '[URL]')
        .replaceAll(
          RegExp(r'\b[\da-fA-F]{8}(?:-[\da-fA-F]{4}){3}-[\da-fA-F]{12}\b'),
          '[ID]',
        )
        .replaceAll(RegExp(r'-?\d+\.\d{2,}'), '[number]');
    _log('$operation: $safeDescription\n$stack');
  }

  Future<T> _step<T>(String operation, Future<T> Function() run) {
    _phase = operation;
    _log(operation);
    return run();
  }

  void _showFailure() {
    if (!mounted) return;
    _deadline?.cancel();
    _detachController();
    setState(() {
      _failed = true;
      _ready = false;
    });
  }

  void _retry() {
    _log('Retry requested');
    _detachController();
    setState(() {
      _attempt++;
      _fit = true;
      _ready = false;
      _failed = false;
    });
    _startDeadline();
  }

  void _detachController() {
    _controller?.onFeatureTapped.remove(_tapFeature);
    // MapLibreMap owns and disposes its controller.
    _controller = null;
    _styleLoaded = false;
    _syncRun = null;
  }

  @override
  void dispose() {
    _log('Disposing map view');
    _deadline?.cancel();
    _detachController();
    super.dispose();
  }

  @override
  void didUpdateWidget(NearbyJobsMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final areaChanged =
        oldWidget.origin != widget.origin ||
        oldWidget.radiusKm != widget.radiusKm;
    if (areaChanged) _fit = true;
    if (areaChanged ||
        !mapEquals(
          _jobLocations(oldWidget.results),
          _jobLocations(widget.results),
        )) {
      _queueSync();
    }
  }

  Map<String, WorkplaceCoordinates?> _jobLocations(
    List<NearbyJobResult> results,
  ) => {for (final result in results) result.job.id: result.job.workplace};

  void _tapFeature(
    math.Point<double> point,
    LatLng coordinates,
    String id,
    String layerId,
    Annotation? annotation,
  ) {
    if (_ready && layerId == _jobLayer) widget.onJobSelected(id);
  }

  void _queueSync() {
    _dirty = true;
    if (_syncRun == null && _controller != null && _styleLoaded && !_failed) {
      unawaited(_sync());
    }
  }

  Future<void> _sync() async {
    final run = _syncRun = Object();
    try {
      while (identical(_syncRun, run) &&
          mounted &&
          _dirty &&
          !_failed &&
          _styleLoaded &&
          _controller != null) {
        _dirty = false;
        final controller = _controller!;
        final revision = _styleRevision;
        final ring = nearbyRadiusRing(widget.origin, widget.radiusKm);
        final area = _areaData(ring, widget.origin);
        final jobs = nearbyJobMarkers(widget.results);
        bool current() =>
            mounted &&
            identical(controller, _controller) &&
            revision == _styleRevision;
        try {
          if (_installedStyle != revision) {
            await _installLayers(controller, area, jobs, current);
            if (!current()) continue;
            _installedStyle = revision;
          } else {
            await _step(
              'Updating radius and origin source',
              () => controller.setGeoJsonSource(_areaSource, area),
            );
            if (!current()) continue;
            await _step(
              'Updating job marker source',
              () => controller.setGeoJsonSource(_jobSource, jobs),
            );
          }
          if (!current()) continue;
          _deadline?.cancel();
          if (!_ready) {
            _log('Style and overlays ready');
            setState(() => _ready = true);
          }
          if (_fit && !_dirty) {
            _fit = false;
            unawaited(_fitCamera(controller, ring, current));
          }
        } catch (error, stack) {
          if (current()) {
            _logError('Overlay setup failed while $_phase', error, stack);
            _showFailure();
          }
        }
      }
    } finally {
      if (identical(_syncRun, run)) _syncRun = null;
    }
  }

  Future<void> _fitCamera(
    MapLibreMapController controller,
    List<List<double>> ring,
    bool Function() current,
  ) async {
    _log('Fitting camera to radius');
    try {
      final moved = await controller.moveCamera(_boundsCamera(ring));
      if (current()) {
        _log(moved == false ? 'Camera fit cancelled' : 'Camera fit returned');
      }
    } catch (error, stack) {
      // A camera command can fail independently of the style and overlays.
      if (current()) _logError('Camera fit failed', error, stack);
    }
  }

  Future<void> _installLayers(
    MapLibreMapController controller,
    Map<String, dynamic> area,
    Map<String, dynamic> jobs,
    bool Function() current,
  ) async {
    final sources = await _step(
      'Reading style source IDs',
      controller.getSourceIds,
    );
    if (!current()) return;
    for (final (id, data) in [(_areaSource, area), (_jobSource, jobs)]) {
      if (sources.contains(id)) {
        await _step(
          'Updating $id',
          () => controller.setGeoJsonSource(id, data),
        );
      } else {
        await _step(
          'Creating $id',
          () => controller.addGeoJsonSource(id, data),
        );
      }
      if (!current()) return;
    }
    final layers = await _step(
      'Reading style layer IDs',
      controller.getLayerIds,
    );
    if (!current()) return;
    const areaFilter = [
      '==',
      ['get', 'kind'],
      'radius',
    ];
    if (!layers.contains(_areaLayer)) {
      await _step(
        'Creating $_areaLayer',
        () => controller.addFillLayer(
          _areaSource,
          _areaLayer,
          const FillLayerProperties(fillColor: '#0F766E', fillOpacity: 0.16),
          filter: areaFilter,
          enableInteraction: false,
        ),
      );
      if (!current()) return;
    }
    if (!layers.contains(_outlineLayer)) {
      await _step(
        'Creating $_outlineLayer',
        () => controller.addLineLayer(
          _areaSource,
          _outlineLayer,
          const LineLayerProperties(lineColor: '#0F766E', lineWidth: 2),
          filter: areaFilter,
          enableInteraction: false,
        ),
      );
      if (!current()) return;
    }
    if (!layers.contains(_originLayer)) {
      await _step(
        'Creating $_originLayer',
        () => controller.addCircleLayer(
          _areaSource,
          _originLayer,
          const CircleLayerProperties(
            circleRadius: 17,
            circleOpacity: 0,
            circleStrokeColor: '#0F766E',
            circleStrokeWidth: 3,
          ),
          belowLayerId: layers.contains(_jobLayer) ? _jobLayer : null,
          filter: const [
            '==',
            ['get', 'kind'],
            'origin',
          ],
          enableInteraction: false,
        ),
      );
      if (!current()) return;
    }
    if (!layers.contains(_jobLayer)) {
      await _step(
        'Creating $_jobLayer',
        () => controller.addCircleLayer(
          _jobSource,
          _jobLayer,
          const CircleLayerProperties(
            circleRadius: 11,
            circleColor: '#0F172A',
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 2,
          ),
          enableInteraction: true,
        ),
      );
    }
  }

  Map<String, dynamic> _areaData(
    List<List<double>> ring,
    WorkplaceCoordinates origin,
  ) => {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': {'kind': 'radius'},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [ring],
        },
      },
      {
        'type': 'Feature',
        'properties': {'kind': 'origin', 'label': 'Selected location'},
        'geometry': {
          'type': 'Point',
          'coordinates': [origin.longitude, origin.latitude],
        },
      },
    ],
  };

  CameraUpdate _boundsCamera(List<List<double>> ring) {
    final latitudes = ring.map((point) => point[1]);
    final longitudes = ring.map((point) => point[0]);
    return CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(
          latitudes.reduce(math.min),
          longitudes.reduce(math.min),
        ),
        northeast: LatLng(
          latitudes.reduce(math.max),
          longitudes.reduce(math.max),
        ),
      ),
      left: 28,
      right: 28,
      top: 28,
      bottom: 28,
    );
  }

  @override
  Widget build(BuildContext context) {
    final attempt = _attempt;
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        key: const ValueKey('nearby-map-card'),
        width: double.infinity,
        padding: const EdgeInsets.all(JobMateTheme.space8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: JobMateTheme.divider),
          borderRadius: BorderRadius.circular(JobMateTheme.dialogRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_supported && !_failed)
              SizedBox(
                width: double.infinity,
                height: constraints.maxWidth < 500 ? 300 : 420,
                child: ClipRRect(
                  key: const ValueKey('nearby-map-viewport'),
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MapLibreMap(
                        key: ValueKey(attempt),
                        initialCameraPosition: CameraPosition(
                          target: LatLng(
                            widget.origin.latitude,
                            widget.origin.longitude,
                          ),
                          zoom: 11,
                        ),
                        styleString: _style,
                        annotationOrder: const [],
                        gestureRecognizers: {
                          if (!kIsWeb)
                            Factory<OneSequenceGestureRecognizer>(
                              EagerGestureRecognizer.new,
                            ),
                        },
                        rotateGesturesEnabled: false,
                        tiltGesturesEnabled: false,
                        onMapCreated: (controller) {
                          if (!mounted || attempt != _attempt || _failed) {
                            return;
                          }
                          _controller = controller;
                          _phase = 'waiting for style load';
                          _log('Controller created');
                          controller.onFeatureTapped.add(_tapFeature);
                        },
                        onStyleLoadedCallback: () {
                          if (!mounted || attempt != _attempt || _failed) {
                            return;
                          }
                          _styleRevision++;
                          _styleLoaded = true;
                          _log('Style loaded (revision $_styleRevision)');
                          _queueSync();
                        },
                      ),
                      if (!_ready)
                        const Align(
                          alignment: Alignment.topCenter,
                          child: LinearProgressIndicator(
                            semanticsLabel: 'Loading map',
                          ),
                        ),
                    ],
                  ),
                ),
              )
            else
              const Text(
                'Map unavailable. You can view the same jobs in List view.',
              ),
            if (_supported && !_failed) ...[
              const SizedBox(height: JobMateTheme.space8),
              Wrap(
                spacing: JobMateTheme.space12,
                runSpacing: JobMateTheme.space4,
                children: [
                  const Text(
                    '○ Selected location',
                    style: TextStyle(color: JobMateTheme.darkTeal),
                  ),
                  const Text(
                    '● Nearby job',
                    style: TextStyle(color: JobMateTheme.heading),
                  ),
                  Text('${widget.radiusKm} km radius'),
                ],
              ),
              const SizedBox(height: JobMateTheme.space4),
              Text(
                'OpenFreeMap · © OpenMapTiles · © OpenStreetMap contributors',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            Wrap(
              spacing: JobMateTheme.space8,
              children: [
                if (_supported)
                  TextButton(
                    onPressed: _retry,
                    child: Text(_failed ? 'Retry map' : 'Reload map'),
                  ),
                TextButton(
                  onPressed: widget.onShowList,
                  child: const Text('View list'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
