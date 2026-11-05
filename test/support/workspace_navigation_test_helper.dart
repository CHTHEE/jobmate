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
  final hidden = find.widgetWithText(ListTile, label, skipOffstage: false);
  if (hidden.evaluate().isNotEmpty && find.text(label).evaluate().isEmpty) {
    final groups = find.ancestor(
      of: hidden,
      matching: find.byType(ExpansionTile),
    );
    if (groups.evaluate().isNotEmpty) {
      final group = groups.first;
      final title = (tester.widget<ExpansionTile>(group).title as Text).data!;
      await tester.ensureVisible(group);
      await tester.tap(
        find
            .descendant(
              of: group,
              matching: find.widgetWithText(ListTile, title),
            )
            .first,
      );
      await tester.pumpAndSettle();
    }
  }
  await tester.scrollUntilVisible(
    find.widgetWithText(ListTile, label),
    label == 'Dashboard' ? -180 : 180,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('workspace-navigation')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}
