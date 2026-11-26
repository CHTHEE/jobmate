import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/job_discovery_place_search.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const result = (
    name: 'Mid Valley Megamall',
    address: 'Kuala Lumpur, Malaysia',
    coordinates: (latitude: 3.118, longitude: 101.677),
  );
  const invalid = (
    name: 'Invalid suggestion',
    address: '',
    coordinates: (latitude: 100.0, longitude: 101.677),
  );
  for (final width in [320.0, 1440.0]) {
    testWidgets('one search and suggestion tap select exactly once at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      var selections = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final place = await showDialog<DiscoveryPlace>(
                    context: context,
                    builder: (_) => DiscoveryPlaceDialog(
                      search: (query) async {
                        calls++;
                        expect(query, 'Mid Valley');
                        return [invalid, result];
                      },
                    ),
                  );
                  expect(place, result);
                  selections++;
                },
                child: const Text('Open Nearby location'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Nearby location'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Mid Valley  ');
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text(result.name), findsNothing);
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(selections, 0);
      expect(find.text(invalid.name), findsNothing);
      expect(find.text('Powered by Geoapify'), findsOneWidget);
      expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
      final suggestion = find.widgetWithText(ListTile, result.name);
      // Capture the callback to simulate a repeat before dismissal finishes.
      final repeatTap = tester.widget<ListTile>(suggestion).onTap!;
      await tester.ensureVisible(suggestion);
      await tester.tap(suggestion);
      repeatTap();
      await tester.pumpAndSettle();
      expect(find.byType(DiscoveryPlaceDialog), findsNothing);
      expect(find.text('Open Nearby location'), findsOneWidget);
      expect(calls, 1);
      expect(selections, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'search recovers from errors and empty results, and ignores late cancellation',
    (tester) async {
      final pending = Completer<List<DiscoveryPlace>>();
      var calls = 0;
      var selected = result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final place = await showDialog<DiscoveryPlace>(
                    context: context,
                    builder: (_) => DiscoveryPlaceDialog(
                      search: (_) async {
                        switch (++calls) {
                          case 1:
                            throw const FunctionException(status: 429);
                          case 2:
                            return [];
                          default:
                            return pending.future;
                        }
                      },
                    ),
                  );
                  if (place != null) selected = place;
                },
                child: const Text('Change place'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Change place'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Penang');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(selected, result);
      await tester.tap(find.text('Change place'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Penang');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Too many location searches'), findsOneWidget);
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.text('No Malaysian locations found.'), findsOneWidget);
      await tester.tap(find.text('Search'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      pending.complete([
        (name: 'Penang', address: '', coordinates: result.coordinates),
      ]);
      await tester.pumpAndSettle();
      expect(selected, result);
      expect(find.byType(DiscoveryPlaceDialog), findsNothing);
      expect(calls, 3);
      expect(tester.takeException(), isNull);
    },
  );
}
