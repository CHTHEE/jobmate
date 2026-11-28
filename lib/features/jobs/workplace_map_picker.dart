import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../shared/theme/jobmate_theme.dart';
import 'workplace_coordinates.dart';
import 'workplace_place_search.dart';

class WorkplacePickerResult {
  const WorkplacePickerResult(this.coordinates, {this.placeAddress});

  final WorkplaceCoordinates coordinates;
  final String? placeAddress;
}

typedef WorkplacePicker = Future<WorkplacePickerResult?> Function(
  BuildContext context,
  WorkplaceCoordinates? initial,
  String address,
  bool autoSearch,
);

Future<WorkplacePickerResult?> showWorkplacePicker(
  BuildContext context,
  WorkplaceCoordinates? initial,
  String address,
  bool autoSearch, {
  WorkplaceSearch search = searchWorkplacePlaces,
}) => showDialog<WorkplacePickerResult>(
  context: context,
  builder: (_) => _WorkplaceMapPicker(
    initial: initial,
    address: address,
    autoSearch: autoSearch,
    search: search,
  ),
);

class _WorkplaceMapPicker extends StatefulWidget {
  const _WorkplaceMapPicker({
    required this.initial,
    required this.address,
    required this.autoSearch,
    required this.search,
  });

  final WorkplaceCoordinates? initial;
  final String address;
  final bool autoSearch;
  final WorkplaceSearch search;

  @override
  State<_WorkplaceMapPicker> createState() => _WorkplaceMapPickerState();
}

class _WorkplaceMapPickerState extends State<_WorkplaceMapPicker> {
  static const _style = 'https://tiles.openfreemap.org/styles/liberty';
  late final _initialPosition = CameraPosition(
    target: LatLng(
      widget.initial?.latitude ?? 3.139,
      widget.initial?.longitude ?? 101.6869,
    ),
    zoom: widget.initial == null ? 11 : 16,
  );
  MapLibreMapController? _controller;
  WorkplacePlace? _selectedPlace;
  Timer? _styleTimeout;
  bool _ready = false, _timedOut = false, _moving = false;
  bool _commandInFlight = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _waitForStyle();
  }

  void _waitForStyle() {
    _styleTimeout?.cancel();
    _styleTimeout = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _timedOut = true);
    });
  }

  @override
  void dispose() {
    _styleTimeout?.cancel();
    super.dispose();
  }

  Future<void> _move({
    double north = 0,
    double east = 0,
    double zoom = 0,
  }) async {
    final controller = _controller;
    final camera = controller?.cameraPosition;
    if (controller == null || camera == null) return;
    final step = 0.001 * (23 - camera.zoom).clamp(1, 23) / 8;
    final target = LatLng(
      (camera.target.latitude + north * step).clamp(-85.0, 85.0),
      (camera.target.longitude + east * step + 180) % 360 - 180,
    );
    await _moveCamera(
      CameraPosition(
        target: target,
        zoom: (camera.zoom + zoom).clamp(1.0, 22.0),
      ),
    );
  }

  WorkplaceCoordinates? _pinAt(CameraPosition? camera) =>
      workplaceCoordinates(camera?.target.latitude, camera?.target.longitude);

  void _checkPlaceAssociation(CameraPosition? camera) {
    if (_selectedPlace?.coordinates != _pinAt(camera)) {
      _selectedPlace = null;
    }
  }

  Future<bool> _centerOnPlace(WorkplacePlace place) async {
    final point = workplaceCoordinates(
      place.coordinates.latitude,
      place.coordinates.longitude,
    );
    if (point == null) return false;
    final moved = await _moveCamera(
      CameraPosition(target: LatLng(point.latitude, point.longitude), zoom: 16),
    );
    if (!mounted || !moved) return false;
    final address = place.address.trim();
    _selectedPlace = address.isEmpty
        ? null
        : (name: place.name, address: address, coordinates: point);
    return true;
  }

  void _confirmPin() {
    final camera = _controller?.cameraPosition;
    final pin = _pinAt(camera);
    if (!_ready || _moving || _commandInFlight || pin == null) return;
    _checkPlaceAssociation(camera);
    Navigator.pop(
      context,
      WorkplacePickerResult(pin, placeAddress: _selectedPlace?.address),
    );
  }

  Future<bool> _moveCamera(CameraPosition position) async {
    final controller = _controller;
    if (controller == null || !_ready || _commandInFlight) return false;
    setState(() => _commandInFlight = true);
    try {
      return await controller.moveCamera(
            CameraUpdate.newCameraPosition(position),
          ) ==
          true;
    } on Exception {
      return false;
    } finally {
      if (mounted) setState(() => _commandInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pin = _pinAt(_controller?.cameraPosition);
    final attempt = _attempt;
    final mapHeight = (MediaQuery.sizeOf(context).height * .43).clamp(
      160.0,
      360.0,
    );
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JobMateTheme.dialogRadius),
        side: const BorderSide(color: JobMateTheme.divider),
      ),
      actionsOverflowButtonSpacing: 8,
      title: const Text(
        'Choose workplace location',
        style: TextStyle(
          color: JobMateTheme.heading,
          fontWeight: FontWeight.w700,
        ),
      ),
      scrollable: true,
      content: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WorkplacePlaceSearchField(
              search: widget.search,
              initialQuery: widget.address,
              autoSearch: widget.autoSearch,
              mapReady: _ready,
              onSelect: _centerOnPlace,
            ),
            const SizedBox(height: 12),
            const Text(
              'Pan or use the controls to place the pin, then confirm.',
              style: TextStyle(color: JobMateTheme.body),
            ),
            const SizedBox(height: 12),
            SizedBox(
              // The positioned map fills the Stack but does not size it.
              // Give it the dialog's available width instead of the pin's.
              width: double.infinity,
              height: mapHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(JobMateTheme.controlRadius),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: MapLibreMap(
                        key: ValueKey(attempt),
                        initialCameraPosition: _initialPosition,
                        styleString: _style,
                        annotationOrder: const [],
                        trackCameraPosition: true,
                        gestureRecognizers: {
                          if (!kIsWeb)
                            Factory<OneSequenceGestureRecognizer>(
                              EagerGestureRecognizer.new,
                            ),
                        },
                        rotateGesturesEnabled: false,
                        tiltGesturesEnabled: false,
                        onMapCreated: (controller) {
                          if (mounted && attempt == _attempt) {
                            _controller = controller;
                          }
                        },
                        onStyleLoadedCallback: () {
                          if (!mounted || attempt != _attempt) return;
                          _styleTimeout?.cancel();
                          setState(() => _ready = true);
                        },
                        onCameraMoveStarted: (_) {
                          if (mounted && attempt == _attempt) {
                            setState(() => _moving = true);
                          }
                        },
                        onCameraMove: (camera) {
                          if (mounted && attempt == _attempt) {
                            _checkPlaceAssociation(camera);
                          }
                        },
                        onCameraIdle: () {
                          if (mounted && attempt == _attempt) {
                            _checkPlaceAssociation(_controller?.cameraPosition);
                            setState(() => _moving = false);
                          }
                        },
                      ),
                    ),
                    if (_ready)
                      IgnorePointer(
                        child: Transform.translate(
                          offset: const Offset(0, -18),
                          child: const Icon(
                            Icons.location_pin,
                            size: 36,
                            color: Colors.red,
                          ),
                        ),
                      )
                    else if (!_timedOut)
                      const CircularProgressIndicator(),
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.fromBorderSide(
                              BorderSide(color: JobMateTheme.divider),
                            ),
                            borderRadius: BorderRadius.all(
                              Radius.circular(JobMateTheme.controlRadius),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!_ready && _timedOut)
              TextButton(
                onPressed: () {
                  setState(() {
                    _controller = null;
                    _selectedPlace = null;
                    _attempt++;
                    _timedOut = false;
                    _moving = false;
                  });
                  _waitForStyle();
                },
                child: const Text('Map did not load. Retry'),
              ),
            if (_ready)
              Wrap(
                children: [
                  IconButton(
                    tooltip: 'Move pin north',
                    onPressed: () => _move(north: 1),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: 'Move pin south',
                    onPressed: () => _move(north: -1),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  IconButton(
                    tooltip: 'Move pin west',
                    onPressed: () => _move(east: -1),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  IconButton(
                    tooltip: 'Move pin east',
                    onPressed: () => _move(east: 1),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                  IconButton(
                    tooltip: 'Zoom in',
                    onPressed: () => _move(zoom: 1),
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    tooltip: 'Zoom out',
                    onPressed: () => _move(zoom: -1),
                    icon: const Icon(Icons.remove),
                  ),
                ],
              ),
            const Text(
              'OpenFreeMap · © OpenMapTiles · © OpenStreetMap contributors',
              style: TextStyle(color: JobMateTheme.body, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: JobMateTheme.darkTeal,
            foregroundColor: Colors.white,
          ),
          onPressed: !_ready || _moving || _commandInFlight || pin == null
              ? null
              : _confirmPin,
          child: const Text('Confirm workplace location'),
        ),
      ],
    );
  }
}
