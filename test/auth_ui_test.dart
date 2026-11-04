import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/auth/login_page.dart';
import 'package:jobmate/features/auth/sign_up_page.dart';
import 'package:jobmate/shared/widgets/auth_style.dart';

void main() {
  for (final width in [320.0, 768.0, 1024.0, 1440.0]) {
    testWidgets('Login layout and validation at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));
      expect(find.byType(AuthWordmark), findsOneWidget);
      expect(
        find.text('Your next chapter\nstarts here.'),
        width >= 1024 ? findsOneWidget : findsNothing,
      );
      await tester.ensureVisible(find.text('Sign In'));
      await tester.tap(find.text('Sign In'));
      await tester.pump();
      expect(
        find.text('Please enter both email and password.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'Registration preserves mismatch validation and toggles password',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SignUpPage()));
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Test User');
      await tester.enterText(fields.at(1), 'test@example.com');
      await tester.enterText(fields.at(2), 'Password123!');
      await tester.enterText(fields.at(3), 'Different123!');
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Show password').first);
      await tester.tap(find.byTooltip('Show password').first);
      await tester.pump();
      expect(tester.widget<TextField>(fields.at(2)).obscureText, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
