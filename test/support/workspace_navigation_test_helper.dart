import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercise the actual platform menu, rather than assuming width is platform.
Future<void> openWorkspaceMenu(WidgetTester tester) async {
  if (find.byKey(const ValueKey('workspace-sidebar')).evaluate().isNotEmpty) {
    return;
  }
  await tester.tap(
    kIsWeb
        ? find.byTooltip('Open navigation menu')
        : find.byIcon(Icons.more_horiz),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('workspace-navigation')), findsOneWidget);
}

Future<void> scrollWorkspaceMenuTo(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.widgetWithText(ListTile, label),
    180,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('workspace-navigation')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}
