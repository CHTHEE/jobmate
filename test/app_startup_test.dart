import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/shared/widgets/app_startup.dart';

void main() {
  testWidgets('Startup draws a loading page until initialization completes', (
    tester,
  ) async {
    final ready = Completer<void>();
    await tester.pumpWidget(
      AppStartup(
        initialize: () => ready.future,
        builder: (_) => const MaterialApp(home: Text('Ready')),
      ),
    );
    expect(find.text('Starting JobMate…'), findsOneWidget);
    expect(find.text('Ready'), findsNothing);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('Configuration failure is visible and retry can recover', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      AppStartup(
        initialize: () async {
          if (attempts++ == 0) {
            throw const AppStartupException('Configuration is missing.');
          }
        },
        builder: (_) => const MaterialApp(home: Text('Ready')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Configuration is missing.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets(
    'Unexpected startup failures do not expose configuration values',
    (tester) async {
      await tester.pumpWidget(
        AppStartup(
          initialize: () => throw StateError('private diagnostic value'),
          builder: (_) => const SizedBox(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('JobMate could not start'), findsOneWidget);
      expect(find.textContaining('private diagnostic value'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
