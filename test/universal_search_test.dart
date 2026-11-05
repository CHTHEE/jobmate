import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/search/universal_search_page.dart';

class _CompanySearch implements PublicCompanySearch {
  int calls = 0;

  @override
  Future<List<PublicCompanyResult>> find(String query) async {
    calls++;
    return const [
      PublicCompanyResult(
        id: 'company-1',
        name: 'Verified Studio',
        industry: 'Design',
        location: 'Kuala Lumpur',
      ),
    ];
  }
}

void main() {
  for (final width in [320.0, 1440.0]) {
    testWidgets('dashboard search opens a light top-center dialog at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showJobMateSearchPanel(context),
                child: const Text('Open search'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open search'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      final rect = tester.getRect(find.byType(Dialog));
      expect(dialog.alignment, Alignment.topCenter);
      expect(rect.center.dx, closeTo(width / 2, 1));
      expect(rect.top, lessThan(150));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ModalBarrier && widget.color == const Color(0x29000000),
        ),
        findsOneWidget,
      );
      expect(find.text('Search JobMate'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Open search'), findsOneWidget);
    });
  }

  testWidgets('embedded search keeps a session-only recent query', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: UniversalSearchPage(embedded: true)),
      ),
    );
    expect(find.text('No recent searches in this session.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'engineer');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('engineer'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets(
    'Search separates demo jobs, verified companies and private people',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final companySearch = _CompanySearch();

      await tester.pumpWidget(
        MaterialApp(home: UniversalSearchPage(companySearch: companySearch)),
      );
      expect(find.textContaining('Demo jobs only'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Studio');
      await tester.tap(find.text('Companies'));
      await tester.pumpAndSettle();
      expect(companySearch.calls, 1);
      expect(find.text('Verified Studio'), findsOneWidget);
      expect(find.text('Design • Kuala Lumpur'), findsOneWidget);

      await tester.tap(find.text('People'));
      await tester.pumpAndSettle();
      expect(find.text('People search is not available yet'), findsOneWidget);
      expect(find.text('Verified Studio'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
