import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/applications/applications_page.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/features/applications/my_applications_page.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';
import 'package:jobmate/shared/widgets/responsive_layout.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fixtures/my_applications_source.dart';

void main() {
  late TestMyApplicationsSource source;
  late Module2Repository module;
  setUp(() {
    source = TestMyApplicationsSource();
    module = Module2Repository(myApplicationsSource: source);
  });
  tearDown(() async {
    module.dispose();
    await source.changes.close();
  });
  Future<void> showPage(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: JobMateTheme.light(),
      home: ApplicationsPage(repository: module),
    ),
  );

  for (final width in [
    320.0,
    360.0,
    390.0,
    430.0,
    568.0,
    600.0,
    768.0,
    840.0,
    1024.0,
    1280.0,
    1440.0,
    1920.0,
  ]) {
    testWidgets('Real cards preserve responsive UI at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = width == 320
          ? 2
          : 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      source.rows = [applicationRow('bc697799-463f-4251-b6be-8888551c3712')];
      await showPage(tester);
      await tester.pumpAndSettle();
      expect(find.byType(MyApplicationsPage), findsOneWidget);
      expect(find.text('Part-Time Cafe Crew'), findsOneWidget);
      expect(find.text('ABC Company'), findsOneWidget);
      expect(find.text('Applied'), findsOneWidget);
      expect(find.text('Applied 4 Nov 2026'), findsOneWidget);
      expect(find.text('Application submitted.'), findsOneWidget);
      expect(find.byIcon(LucideIcons.calendar), findsOneWidget);
      expect(find.text('Your applications'), findsOneWidget);
      expect(find.text('DEMO / PREVIEW'), findsNothing);
      expect(find.textContaining('Demo candidate'), findsNothing);
      expect(
        find.byKey(const ValueKey('bc697799-463f-4251-b6be-8888551c3712')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'View Application'),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('Withdraw'), findsNothing);
      expect(find.text('Resume not provided'), findsNothing);
      expect(find.text('Message Employer'), findsOneWidget);
      expect(find.text('View Job'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, columns) in [(320.0, 1), (768.0, 2), (1440.0, 3)]) {
    testWidgets('Application grid fits $columns columns at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const title = 'Senior Customer Service and Front of House Coordinator';
      const company = 'Northern Regional Hospitality and Events Group';
      source.rows = [
        applicationRow('3'),
        {
          ...applicationRow('2', status: 'shortlisted'),
          'job_title': title,
          'company_name': company,
        },
        applicationRow('1'),
      ];
      await showPage(tester);
      await tester.pumpAndSettle();
      Rect bounds(String id) => tester.getRect(find.byKey(ValueKey(id)));
      final first = bounds('3');
      final second = bounds('2');
      final third = bounds('1');
      expect(second.top == first.top, columns >= 2);
      expect(third.top == first.top, columns == 3);
      if (columns >= 2) {
        expect(second.height, first.height);
        Rect buttonBounds(String id, String label) => tester.getRect(
          find.descendant(
            of: find.byKey(ValueKey(id)),
            matching: label == 'View Application'
                ? find.widgetWithText(FilledButton, label)
                : find.widgetWithText(OutlinedButton, label),
          ),
        );
        expect(
          buttonBounds('3', 'View Application').top,
          buttonBounds('2', 'View Application').top,
        );
        expect(
          buttonBounds('2', 'View Job').top,
          buttonBounds('2', 'Message Employer').top,
        );
      }
      expect(find.text(title), findsOneWidget);
      expect(find.text(company), findsOneWidget);
      for (final card in [first, second, third]) {
        expect(card.left, greaterThanOrEqualTo(0));
        expect(card.right, lessThanOrEqualTo(width));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Desktop filters preserve normal widths in partial rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    source.rows = [
      applicationRow('4'),
      applicationRow('3', status: 'withdrawn'),
      {...applicationRow('2'), 'job_title': 'Warehouse assistant'},
      applicationRow('1', status: 'declined'),
    ];
    await showPage(tester);
    await tester.pumpAndSettle();

    Rect card(String id) => tester.getRect(find.byKey(ValueKey(id)));
    final first = card('4');
    final second = card('3');
    final third = card('2');
    final last = card('1');
    expect(third.top, first.top);
    expect(last.top, greaterThan(first.top));
    expect(last.left, first.left);
    expect(last.width, first.width);

    await tester.tap(find.byKey(const ValueKey('workspace-filters-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Active'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, 'View Application'),
      findsNWidgets(2),
    );
    expect(card('4').width, first.width);
    expect(card('2').width, first.width);
    expect(card('2').left, second.left);
    expect(card('2').top, card('4').top);

    await tester.enterText(find.byType(TextField), 'Warehouse assistant');
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, 'View Application'),
      findsOneWidget,
    );
    expect(card('2').left, first.left);
    expect(card('2').width, first.width);

    await tester.tap(find.widgetWithText(TextButton, 'Clear filters'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, 'View Application'),
      findsNWidgets(4),
    );
    expect(card('2').left, third.left);
    expect(card('1').width, first.width);
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale, columns) in [
    (768.0, 1.0, 2),
    (768.0, 1.6, 1),
    (320.0, 2.0, 1),
  ]) {
    testWidgets(
      'Single result uses one of $columns columns at $width and ${scale}x',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        source.rows = [applicationRow('single')];
        await showPage(tester);
        await tester.pumpAndSettle();
        final card = find.byKey(const ValueKey('single'));
        final grid = find.ancestor(
          of: card,
          matching: find.byType(ResponsiveGrid),
        );
        final gridBounds = tester.getRect(grid);
        final cardBounds = tester.getRect(card);
        expect(cardBounds.left, gridBounds.left);
        expect(
          cardBounds.width,
          closeTo(
            (gridBounds.width - ResponsiveLayout.cardGap * (columns - 1)) /
                columns,
            .01,
          ),
        );
        expect(cardBounds.right, lessThanOrEqualTo(width));
        expect(
          find.descendant(of: grid, matching: find.byType(Card)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Loading, failure, retry and empty states never show demo rows', (
    tester,
  ) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    source.fetch = () => pending.future;
    await showPage(tester);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('Unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load applications'), findsOneWidget);
    expect(find.text('Retail Assistant'), findsNothing);
    source.fetch = () async => [];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No applications yet'), findsOneWidget);
    source.fetch = () async => [applicationRow('real')];
    await tester.tap(find.byTooltip('Refresh applications'));
    await tester.pumpAndSettle();
    expect(find.text('ABC Company'), findsOneWidget);
  });

  testWidgets(
    'Search, status and completed filters distinguish declined/withdrawn',
    (tester) async {
      source.rows = [
        applicationRow('applied'),
        {
          ...applicationRow('declined', status: 'declined'),
          'job_title': 'Declined job',
        },
        {
          ...applicationRow('withdrawn', status: 'withdrawn'),
          'job_title': 'Withdrawn job',
        },
      ];
      await showPage(tester);
      await tester.pumpAndSettle();
      for (final (label, value) in [
        ('All', '3'),
        ('Active', '1'),
        ('Completed', '2'),
      ]) {
        expect(
          tester
              .widget<Text>(find.byKey(ValueKey('application-count-$label')))
              .data,
          value,
        );
      }
      await tester.tap(find.byKey(const ValueKey('workspace-filters-toggle')));
      await tester.pumpAndSettle();
      final completed = find.widgetWithText(ChoiceChip, 'Completed');
      await tester.ensureVisible(completed);
      await tester.tap(completed);
      await tester.pumpAndSettle();
      expect(find.text('Part-Time Cafe Crew'), findsNothing);
      expect(find.text('Declined'), findsOneWidget);
      expect(find.text('Withdrawn'), findsOneWidget);
      expect(find.text('You declined the offer.'), findsOneWidget);
      expect(find.text('You withdrew this application.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Declined job');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('declined')), findsOneWidget);
      expect(find.text('Withdrawn job'), findsNothing);
      await tester.enterText(find.byType(TextField), 'no match');
      await tester.pumpAndSettle();
      expect(find.text('No applications found'), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(TextButton, 'Clear filters').first,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Clear filters').first);
      await tester.pumpAndSettle();
      final statusField = find.byType(DropdownButtonFormField<String>).first;
      await tester.ensureVisible(statusField);
      await tester.tap(statusField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Declined').last);
      await tester.pumpAndSettle();
      expect(find.text('Declined job'), findsOneWidget);
      expect(find.text('Withdrawn job'), findsNothing);
      final clear = find.widgetWithText(TextButton, 'Clear filters');
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      Rect card(String id) => tester.getRect(find.byKey(ValueKey(id)));
      expect(card('withdrawn').top, lessThan(card('applied').top));
      final sortField = find.byType(DropdownButtonFormField<String>).last;
      await tester.ensureVisible(sortField);
      await tester.tap(sortField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oldest').last);
      await tester.pumpAndSettle();
      expect(card('applied').top, lessThan(card('withdrawn').top));
      expect(source.calls, 1);
    },
  );

  testWidgets(
    'Account switch removes previous cards and logout cannot keep cache',
    (tester) async {
      source.rows = [applicationRow('old')];
      await showPage(tester);
      await tester.pumpAndSettle();
      source.rows = [
        {...applicationRow('new'), 'company_name': 'New account company'},
      ];
      source.switchAccount('seeker-b');
      await tester.pumpAndSettle();
      expect(find.text('ABC Company'), findsNothing);
      expect(find.text('New account company'), findsOneWidget);
      source.switchAccount(null);
      await tester.pumpAndSettle();
      expect(find.text('New account company'), findsNothing);
      expect(module.myApplications.applications, isEmpty);
    },
  );

  testWidgets('Returning from a job refreshes and preserves the real job ID', (
    tester,
  ) async {
    source.rows = [applicationRow('old')];
    String? openedJob;
    final router = GoRouter(
      initialLocation: '/applications',
      routes: [
        GoRoute(
          path: '/applications',
          builder: (_, _) => ApplicationsPage(repository: module),
        ),
        GoRoute(
          path: '/jobs/:id',
          builder: (context, state) {
            openedJob = state.pathParameters['id'];
            return Scaffold(
              body: TextButton(
                onPressed: () => context.pop(),
                child: const Text('Return'),
              ),
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View Job'));
    await tester.tap(find.text('View Job'));
    await tester.pumpAndSettle();
    expect(openedJob, 'real-job-id');
    source.rows = [
      applicationRow('old'),
      {...applicationRow('new'), 'job_title': 'New application'},
    ];
    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();
    expect(source.calls, 2);
    expect(find.text('New application'), findsOneWidget);
  });
}
