import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/notifications/notifications_page.dart';

import 'fixtures/notifications_source.dart';

void main() {
  testWidgets('embedded notifications filter unread without a page AppBar', (
    tester,
  ) async {
    final source = FakeNotificationsSource();
    source.rows = [
      notificationRow(),
      notificationRow(id: 'read', readAt: '2026-11-05T00:00:00Z'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 440,
            height: 600,
            child: NotificationsPage(source: source, embedded: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Application received'), findsNWidgets(2));
    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();
    expect(find.text('Application received'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await source.changes.close();
  });

  for (final width in [320.0, 1440.0]) {
    testWidgets('notification layout at width $width with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = FakeNotificationsSource();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: NotificationsPage(source: source),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Application received'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await source.changes.close();
    });
  }
  testWidgets('stale mark failure shows no message after account change', (
    tester,
  ) async {
    final source = FakeNotificationsSource();
    final pending = Completer<bool>();
    source.onMark = () => pending.future;
    await tester.pumpWidget(
      MaterialApp(home: NotificationsPage(source: source)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Application received'));
    source.rows = [];
    source.switchAccount('employer');
    pending.completeError(Exception('old account'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Application received'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await source.changes.close();
  });
  for (final actor in ['seeker', 'employer']) {
    testWidgets('$actor sees server content, local time and read indicators', (
      tester,
    ) async {
      final source = FakeNotificationsSource()..actor = actor;
      source.rows = [
        notificationRow(),
        notificationRow(id: 'read', readAt: '2026-11-05T00:00:00Z'),
      ];
      await tester.pumpWidget(
        MaterialApp(home: NotificationsPage(source: source)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Application received'), findsNWidgets(2));
      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      final context = tester.element(find.byType(NotificationsPage));
      final local = DateTime.parse(source.rows.first['created_at'] as String)
          .toLocal();
      final format = MaterialLocalizations.of(context);
      final expected =
          '${format.formatMediumDate(local)}, ${format.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
      expect(find.text(expected), findsNWidgets(2));
      expect(find.byTooltip('Refresh'), findsNothing);
      expect(source.lists, 1);
      await tester.pumpWidget(const SizedBox());
      await source.changes.close();
    });
  }
  testWidgets('loading, failure, retry, empty and direct account switch', (
    tester,
  ) async {
    final source = FakeNotificationsSource();
    final pending = Completer<List<Map<String, dynamic>>>();
    source.onList = () => pending.future;
    await tester.pumpWidget(
      MaterialApp(home: NotificationsPage(source: source)),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    source.onList = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Application received'), findsOneWidget);
    source.rows = [];
    source.switchAccount('employer');
    await tester.pumpAndSettle();
    expect(find.text('Application received'), findsNothing);
    expect(find.text('You do not have any notifications yet.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(source.changes.hasListener, isFalse);
    await source.changes.close();
  });
  testWidgets('duplicate taps blocked; false and errors show safe feedback', (
    tester,
  ) async {
    final source = FakeNotificationsSource();
    final pending = Completer<bool>();
    source.onMark = () => pending.future;
    await tester.pumpWidget(
      MaterialApp(home: NotificationsPage(source: source)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Application received'));
    await tester.pump();
    await tester.tap(find.text('Application received'));
    expect(source.marks, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('This notification is unavailable.'), findsOneWidget);
    expect(source.lists, 2);
    source.onMark = () async => throw Exception('failure');
    await tester.tap(find.text('Application received'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.circle), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to mark this notification as read. Please retry.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await source.changes.close();
  });
  testWidgets('returning through GoRouter refreshes retained page', (
    tester,
  ) async {
    final source = FakeNotificationsSource();
    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        GoRoute(
          path: '/notifications',
          builder: (_, _) => NotificationsPage(source: source),
        ),
        GoRoute(
          path: '/other',
          builder: (_, _) => const Scaffold(body: Text('Other')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    router.push('/other');
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(source.lists, 2);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    await source.changes.close();
  });
}
