import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/theme/jobmate_theme.dart';
import 'workplace_coordinates.dart';

typedef WorkplacePlace = ({
  String name,
  String address,
  WorkplaceCoordinates coordinates,
});
typedef WorkplaceSearch = Future<List<WorkplacePlace>> Function(String query);

Future<List<WorkplacePlace>> searchWorkplacePlaces(String query) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) throw const WorkplaceSearchFailure('unauthenticated');
  try {
    final response = await client.functions
        .invoke('search-workplace-places', body: {'query': query})
        .timeout(const Duration(seconds: 24));
    if (client.auth.currentUser?.id != userId) {
      throw const WorkplaceSearchFailure('unauthenticated');
    }
    final data = response.data;
    if (data is! Map || data['places'] is! List) {
      throw const WorkplaceSearchFailure('unavailable');
    }
    final places = <WorkplacePlace>[];
    final rows = data['places'] as List;
    for (final row in rows.take(5)) {
      if (row is! Map || row['name'] is! String || row['address'] is! String) {
        continue;
      }
      final coordinates = workplaceCoordinates(
        row['latitude'],
        row['longitude'],
      );
      if (coordinates == null || (row['name'] as String).trim().isEmpty) {
        continue;
      }
      places.add((
        name: row['name'] as String,
        address: row['address'] as String,
        coordinates: coordinates,
      ));
    }
    if (rows.isNotEmpty && places.isEmpty) {
      throw const WorkplaceSearchFailure('unavailable');
    }
    return places;
  } on FunctionException catch (error) {
    throw WorkplaceSearchFailure(switch (error.status) {
      400 => 'invalid_query',
      401 || 403 => 'unauthenticated',
      429 => 'rate_limited',
      504 => 'timeout',
      _ => 'unavailable',
    });
  } on TimeoutException {
    throw const WorkplaceSearchFailure('timeout');
  }
}

class WorkplaceSearchFailure implements Exception {
  const WorkplaceSearchFailure(this.code);
  final String code;
}

class WorkplacePlaceSearchField extends StatefulWidget {
  const WorkplacePlaceSearchField({
    super.key,
    required this.search,
    required this.mapReady,
    required this.onSelect,
    this.initialQuery = '',
    this.autoSearch = false,
  });

  final WorkplaceSearch search;
  final bool mapReady;
  final Future<bool> Function(WorkplacePlace) onSelect;
  final String initialQuery;
  final bool autoSearch;

  @override
  State<WorkplacePlaceSearchField> createState() =>
      _WorkplacePlaceSearchFieldState();
}

class _WorkplacePlaceSearchFieldState extends State<WorkplacePlaceSearchField> {
  late final _query = TextEditingController(text: widget.initialQuery.trim());
  List<WorkplacePlace> _places = const [];
  String? _message;
  bool _loading = false, _centering = false, _selected = false, _retry = false;
  int _generation = 0;
  WorkplacePlace? _pendingSuggestion;
  WorkplacePlace? _shownSuggestion;

  @override
  void initState() {
    super.initState();
    if (widget.autoSearch && _query.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _generation == 0) unawaited(_submit(suggest: true));
      });
    }
  }

  @override
  void didUpdateWidget(WorkplacePlaceSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.mapReady && widget.mapReady && _pendingSuggestion != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applySuggestion();
      });
    }
  }

  void _applySuggestion() {
    final place = _pendingSuggestion;
    if (place == null || !widget.mapReady || _centering) return;
    _pendingSuggestion = null;
    unawaited(_select(place, suggested: true));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _submit({bool suggest = false}) async {
    if (_loading || _centering) return;
    final query = _query.text.trim();
    final generation = ++_generation;
    _pendingSuggestion = null;
    final valid =
        query.length >= 2 &&
        query.length <= 120 &&
        !query.runes.any((rune) => rune < 32 || rune == 127);
    setState(() {
      _places = const [];
      _shownSuggestion = null;
      _message = valid ? null : 'Enter a place name of 2–120 characters.';
      _retry = false;
      _loading = valid;
    });
    if (!valid) return;
    try {
      final response = await widget.search(query);
      if (!mounted || generation != _generation) return;
      setState(() {
        _places = response
            .where(
              (place) =>
                  workplaceCoordinates(
                    place.coordinates.latitude,
                    place.coordinates.longitude,
                  ) !=
                  null,
            )
            .take(5)
            .toList();
        if (_places.isEmpty) {
          _message = 'No matching places found. Try another search or position the pin manually.';
        }
      });
      if (suggest && _places.length == 1) {
        _pendingSuggestion = _places.single;
        _applySuggestion();
      }
    } on WorkplaceSearchFailure catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _retry =
            error.code != 'invalid_query' && error.code != 'unauthenticated';
        _message = switch (error.code) {
          'invalid_query' => 'Enter a place name of 2–120 characters.',
          'unauthenticated' =>
            'An active Employer session is required for search.',
          'rate_limited' => 'Search limit reached. Try again later.',
          'timeout' =>
            'Place search timed out. Try again or position the pin manually.',
          _ =>
            'Place search is unavailable. You can position the pin manually.',
        };
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _retry = true;
        _message = 'Could not reach place search. Check your connection or position the pin manually.';
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _select(WorkplacePlace place, {bool suggested = false}) async {
    if (_centering || !widget.mapReady) return;
    setState(() => _centering = true);
    _pendingSuggestion = null;
    final moved = await widget.onSelect(place);
    if (!mounted) return;
    setState(() {
      _centering = false;
      if (moved) {
        _places = const [];
        _selected = true;
        _shownSuggestion = suggested ? place : null;
        _message = suggested ? null : 'Check that the pin matches the workplace address before confirming.';
      } else {
        _message = 'Could not center the map. Select the result again or move the pin manually.';
      }
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Builder(
        builder: (context) {
          final input = TextField(
            controller: _query,
            enabled: !_centering,
            maxLength: 120,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              _generation++;
              _pendingSuggestion = null;
              setState(() {
                _places = const [];
                _shownSuggestion = null;
                _message = null;
                _retry = false;
                _loading = false;
              });
            },
            decoration: const InputDecoration(
              labelText: 'Search for a place',
              hintText: 'Search buildings, streets or areas',
              counterText: '',
              prefixIcon: Icon(Icons.search),
            ),
          );
          final button = FilledButton(
            onPressed: _loading || _centering ? null : _submit,
            child: Text(_retry ? 'Retry search' : 'Search'),
          );
          // AlertDialog measures its content intrinsically before layout.
          if (MediaQuery.sizeOf(context).width < 500 ||
              MediaQuery.textScalerOf(context).scale(14) > 18) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [input, const SizedBox(height: 8), button],
            );
          }
          return Row(
            children: [
              Expanded(child: input),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
      if (_loading)
        const LinearProgressIndicator(semanticsLabel: 'Searching for places'),
      if (_message case final message?)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Semantics(liveRegion: true, child: Text(message)),
        ),
      if (_shownSuggestion case final place?)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Semantics(
            liveRegion: true,
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(JobMateTheme.controlRadius),
                side: const BorderSide(color: JobMateTheme.teal100),
              ),
              tileColor: JobMateTheme.teal50,
              leading: const Icon(
                Icons.place_outlined,
                color: JobMateTheme.darkTeal,
              ),
              title: Text(place.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (place.address.isNotEmpty && place.address != place.name)
                    Text(place.address),
                  const Text(
                    'Suggested location (unconfirmed)',
                    style: TextStyle(
                      color: JobMateTheme.teal800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (_places.isNotEmpty)
        SizedBox(
          height: _places.length == 1 ? 92 : 172,
          child: ListView.separated(
            padding: const EdgeInsets.only(top: 8),
            primary: false,
            itemCount: _places.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (_, index) {
              final place = _places[index];
              return Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    JobMateTheme.controlRadius,
                  ),
                  side: const BorderSide(color: JobMateTheme.divider),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  hoverColor: JobMateTheme.teal50,
                  focusColor: JobMateTheme.teal100,
                  leading: const Icon(
                    Icons.place_outlined,
                    color: JobMateTheme.darkTeal,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  title: Text(
                    place.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: place.address.isEmpty
                      ? null
                      : Text(
                          place.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  enabled: widget.mapReady && !_centering,
                  onTap: () => _select(place),
                ),
              );
            },
          ),
        ),
      if (_places.isNotEmpty || _selected)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: () => launchUrl(Uri.https('www.geoapify.com')),
              child: const Text('Powered by Geoapify'),
            ),
            const Text('© OpenStreetMap contributors'),
          ],
        ),
    ],
  );
}
