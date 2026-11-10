import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/work_attendance/engagement_closure_controls.dart';

import 'work_assignment_creation_dialog_test.dart'
    show FakeEngagementClosureGateway;

class _CountingGateway extends FakeEngagementClosureGateway {
  int closes = 0;
  @override
  Future<DateTime> close(String applicationId, String reason) async {
    closes++;
    return DateTime.utc(2026, 11, 10);
  }
}

Widget controls(
  EngagementClosureGateway gateway, {
  int refresh = 0,
  String application = 'fixture-application',
}) => MaterialApp(
  home: Scaffold(
    body: EngagementClosureControls(
      applicationId: application,
      worker: false,
      gateway: gateway,
      refreshToken: refresh,
    ),
  ),
);

void main() {
  testWidgets('context change while reason dialog is open prevents closure', (
    tester,
  ) async {
    final gateway = _CountingGateway();
    await tester.pumpWidget(controls(gateway, application: 'old'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close Engagement'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Fixture reason');
    await tester.pumpWidget(controls(gateway, application: 'new'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(gateway.closes, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'failed refresh removes stale closure action and offers read retry',
    (tester) async {
      final gateway = FakeEngagementClosureGateway();
      await tester.pumpWidget(controls(gateway));
      await tester.pumpAndSettle();
      expect(find.text('Close Engagement'), findsOneWidget);
      gateway.statusHandler = (_) async => throw StateError('offline');
      await tester.pumpWidget(controls(gateway, refresh: 1));
      await tester.pumpAndSettle();
      expect(find.text('Close Engagement'), findsNothing);
      expect(find.text('Refresh engagement status'), findsOneWidget);
      gateway.statusHandler = null;
      await tester.tap(find.text('Refresh engagement status'));
      await tester.pumpAndSettle();
      expect(find.text('Close Engagement'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late old-application status cannot overwrite current closure state',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final gateway = FakeEngagementClosureGateway();
      gateway.statusHandler = (id) => id == 'old'
          ? pending.future
          : Future.value({'closure_status': 'closed', 'eligible': true});
      await tester.pumpWidget(controls(gateway, application: 'old'));
      await tester.pump();
      await tester.pumpWidget(controls(gateway, application: 'new'));
      await tester.pumpAndSettle();
      pending.complete({'closure_status': 'open', 'eligible': true});
      await tester.pumpAndSettle();
      expect(find.text('Engagement status: Closed'), findsOneWidget);
      expect(find.text('Close Engagement'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('updated gateway supplies the new authoritative status', (
    tester,
  ) async {
    final first = FakeEngagementClosureGateway();
    final second = FakeEngagementClosureGateway()
      ..statusHandler = (_) async => {
        'closure_status': 'closed',
        'eligible': true,
      };
    await tester.pumpWidget(controls(first));
    await tester.pumpAndSettle();
    await tester.pumpWidget(controls(second));
    await tester.pumpAndSettle();
    expect(find.text('Engagement status: Closed'), findsOneWidget);
    expect(find.text('Close Engagement'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
