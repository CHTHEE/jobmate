import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/admin/company_rejection_dialog.dart';

void main() {
  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'Reject requires a reason and returns trimmed feedback at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showDialog<String>(
                      context: context,
                      builder: (_) => const CompanyRejectionDialog(),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reject'));
        await tester.pump();
        expect(find.text('Enter a reason to continue.'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField), '   ');
        await tester.tap(find.text('Reject'));
        await tester.pump();
        expect(find.byType(CompanyRejectionDialog), findsOneWidget);
        await tester.enterText(
          find.byType(TextFormField),
          '  Please upload a legible registration certificate.  ',
        );
        await tester.tap(find.text('Reject'));
        await tester.pumpAndSettle();
        expect(result, 'Please upload a legible registration certificate.');
        expect(find.byType(CompanyRejectionDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Cancel returns no rejection decision', (tester) async {
    String? result = 'unchanged';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const CompanyRejectionDialog(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Draft reason');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
