import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../jobs/workplace_coordinates.dart';

typedef DiscoveryPlace = ({
  String name,
  String address,
  WorkplaceCoordinates coordinates,
});
typedef DiscoveryPlaceSearch = Future<List<DiscoveryPlace>> Function(String);

Future<List<DiscoveryPlace>> searchJobDiscoveryPlaces(
  String query, {
  SupabaseClient? client,
}) async {
  final supabase = client ?? Supabase.instance.client;
  final userId = supabase.auth.currentSession?.user.id;
  if (userId == null) throw const _DiscoverySessionExpired();
  final response = await supabase.functions
      .invoke('search-job-discovery-places', body: {'query': query.trim()})
      .timeout(const Duration(seconds: 24));
  if (supabase.auth.currentSession?.user.id != userId) {
    throw const _DiscoverySessionExpired();
  }
  final data = response.data;
  if (data is! Map || data['places'] is! List) {
    throw const FormatException('Invalid place search response');
  }
  final rows = data['places'] as List;
  final places = <DiscoveryPlace>[];
  for (final row in rows.take(5)) {
    if (row is! Map || row['name'] is! String || row['address'] is! String) {
      continue;
    }
    final name = (row['name'] as String).trim();
    final coordinates = workplaceCoordinates(row['latitude'], row['longitude']);
    if (name.isNotEmpty && coordinates != null) {
      places.add((
        name: name,
        address: row['address'],
        coordinates: coordinates,
      ));
    }
  }
  if (rows.isNotEmpty && places.isEmpty) {
    throw const FormatException('No valid places in response');
  }
  return places;
}

class _DiscoverySessionExpired implements Exception {
  const _DiscoverySessionExpired();
}

class DiscoveryPlaceDialog extends StatefulWidget {
  const DiscoveryPlaceDialog({super.key, required this.search});

  final DiscoveryPlaceSearch search;

  @override
  State<DiscoveryPlaceDialog> createState() => _DiscoveryPlaceDialogState();
}

class _DiscoveryPlaceDialogState extends State<DiscoveryPlaceDialog> {
  final _query = TextEditingController();
  List<DiscoveryPlace> _places = const [];
  String? _message;
  bool _loading = false;
  bool _finished = false;

  bool _isOpen(ModalRoute<dynamic>? route) =>
      mounted && !_finished && route?.isCurrent == true;

  void _close([DiscoveryPlace? place]) {
    if (!_isOpen(ModalRoute.of(context))) return;
    // The closing animation can leave a tile hit-testable for another tap.
    _finished = true;
    Navigator.of(context).pop(place);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final route = ModalRoute.of(context);
    if (_loading || !_isOpen(route)) return;
    final query = _query.text.trim();
    if (query.length < 2) {
      setState(() => _message = 'Enter at least two characters.');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
      _places = const [];
    });
    try {
      final places = await widget.search(query);
      if (!_isOpen(route) || _query.text.trim() != query) return;
      setState(() {
        _places = places.where((place) {
          final point = place.coordinates;
          return place.name.trim().isNotEmpty &&
              workplaceCoordinates(point.latitude, point.longitude) != null;
        }).toList();
        if (_places.isEmpty) _message = 'No Malaysian locations found.';
      });
    } catch (error) {
      if (!_isOpen(route) || _query.text.trim() != query) return;
      setState(() {
        _message = switch (error) {
          FunctionException(status: 401) || _DiscoverySessionExpired() =>
            'Sign in again to search for a location.',
          FunctionException(status: 403) =>
            'Location search requires an active Job Seeker account.',
          FunctionException(status: 429) =>
            'Too many location searches. Try again later.',
          FunctionException(status: 504) || TimeoutException() =>
            'Location search timed out. Try again or continue browsing jobs.',
          _ => 'Location search is unavailable. You can still browse jobs.',
        };
      });
    } finally {
      if (_isOpen(route)) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Search location'),
    scrollable: true,
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _query,
            autofocus: true,
            readOnly: _loading,
            maxLength: 120,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submit(),
            onChanged: (_) => setState(() {
              _message = null;
              _places = const [];
            }),
            decoration: const InputDecoration(
              labelText: 'Place in Malaysia',
              prefixIcon: Icon(Icons.place_outlined),
              counterText: '',
            ),
          ),
          if (_loading)
            const LinearProgressIndicator(
              semanticsLabel: 'Searching locations',
            ),
          if (_message case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(message)),
            ),
          if (_places.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: const Text('Select a location to apply it'),
              ),
            ),
          for (final place in _places)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(place.name),
              subtitle: place.address.isEmpty || place.address == place.name
                  ? null
                  : Text(place.address),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _close(place),
            ),
          if (_places.isNotEmpty)
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
      ),
    ),
    actions: [
      TextButton(onPressed: () => _close(), child: const Text('Cancel')),
      FilledButton(
        onPressed: _loading ? null : _submit,
        child: const Text('Search'),
      ),
    ],
  );
}
