import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/my_application_details_page.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';

import 'fixtures/my_applications_source.dart';

void main() {
  for (final status in MyApplicationStatus.values) {
    testWidgets('real $status details show only permitted actions', (
      tester,
    ) async {
      final source = TestMyApplicationsSource()
        ..rows = [applicationRow('test-application', status: status.name)];
      await tester.pumpWidget(
        MaterialApp(
          home: MyApplicationDetailsPage(
            applicationId: 'test-application',
            source: source,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final action in ApplicationResponseAction.values) {
        expect(
          find.text(action.label),
          action.allowed(status) ? findsOneWidget : findsNothing,
        );
      }
      expect(source.responses, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await source.changes.close();
    });
  }
  for (final action in ApplicationResponseAction.values) {
    for (final width in [320.0, 1440.0]) {
      testWidgets(
        '${action.wireName} confirmation/cancel and server result at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final source = TestMyApplicationsSource()
            ..rows = [applicationRow('test-application', status: 'offered')];
          final pending = Completer<String>();
          source.sendResponse = (_, _) => pending.future;
          await tester.pumpWidget(
            MaterialApp(
              home: MyApplicationDetailsPage(
                applicationId: 'test-application',
                source: source,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text(action.label));
          await tester.tap(find.text(action.label));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(source.responses, isEmpty);
          if (action == ApplicationResponseAction.withdraw) {
            expect(
              find.text(
                'Withdrawal is final and cannot be undone through the current workflow.',
              ),
              findsOneWidget,
            );
          }
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(source.responses, isEmpty);
          await tester.tap(find.text(action.label));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Confirm ${action.label}'));
          await tester.pump();
          expect(source.responses, hasLength(1));
          final buttons = tester.widgetList<OutlinedButton>(
            find.byType(OutlinedButton),
          );
          expect(buttons.every((button) => button.onPressed == null), isTrue);
          source.rows = [
            applicationRow('test-application', status: action.result.name),
          ];
          source.historyRows = [
            historyRow('response', status: action.result.name),
          ];
          pending.complete(action.result.name);
          await tester.pumpAndSettle();
          expect(find.text(action.result.label), findsWidgets);
          expect(find.text(action.label), findsNothing);
          expect(source.historyCalls, hasLength(2));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await source.changes.close();
        },
      );
    }
  }
  testWidgets(
    'account switch invalidates confirmation without invoking response',
    (tester) async {
      final source = TestMyApplicationsSource()
        ..rows = [applicationRow('test-application', status: 'offered')];
      await tester.pumpWidget(
        MaterialApp(
          home: MyApplicationDetailsPage(
            applicationId: 'test-application',
            source: source,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Accept Offer'));
      await tester.tap(find.text('Accept Offer'));
      await tester.pumpAndSettle();
      source.rows = [];
      source.switchAccount('seeker-b');
      await tester.pumpAndSettle();
      expect(find.text('Application changed'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm Accept Offer'),
            )
            .onPressed,
        isNull,
      );
      expect(source.responses, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await source.changes.close();
    },
  );
}
