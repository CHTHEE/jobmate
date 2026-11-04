
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flutter widget smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('JobMate'),
          ),
        ),
      ),
    );

    expect(find.text('JobMate'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
