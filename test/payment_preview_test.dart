import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/payments/payment_models.dart';

import 'support/payment_preview.dart';
import 'support/payment_preview_repository.dart';

void main() {
  test('Preview gates cover unavailable/incomplete/unverified/disputed/full-time without real services', () async {
    final data = PaymentPreviewData();
    for (final scenario in [
      PaymentPreviewScenario.incomplete,
      PaymentPreviewScenario.unverified,
      PaymentPreviewScenario.disputed,
      PaymentPreviewScenario.fullTime,
    ]) {
      data.reset(scenario);
      expect(data.view('employer').canPay, isFalse);
      await expectLater(
        PreviewPaymentRepository(
          data,
          'employer',
        ).createCheckout(previewAssignmentId, 'id'),
        throwsStateError,
      );
    }
    data.reset(PaymentPreviewScenario.ready);
    expect(data.view('job_seeker').canPay, isFalse);
    expect(data.view('administrator').canPay, isFalse);
  });

  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'Manual preview can exercise Bonus and simulated result without Supabase at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1050);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        // Supabase is deliberately not initialized. No real gateway opener is used.
        await tester.pumpWidget(const PaymentPreviewApp());
        await tester.pumpAndSettle();
        expect(find.textContaining('UI PREVIEW'), findsOneWidget);
        await tester.ensureVisible(find.text('Open Employer payment'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open Employer payment'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '20.00');
        await tester.ensureVisible(find.text('Pay now · Sandbox'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pay now · Sandbox'));
        await tester.pumpAndSettle();
        expect(find.textContaining('MYR 120.00'), findsOneWidget);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Open sandbox checkout'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open sandbox checkout'));
        // The payment page stays busy while its injected checkout dialog is open.
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.textContaining('No Billplz request is made.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Simulate paid · Confirmed'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Check payment status'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Check payment status'));
        await tester.pumpAndSettle();
        expect(find.text('Sandbox payment confirmed'), findsOneWidget);
        await tester.tap(find.text('Preview cases'));
        await tester.pumpAndSettle();
        expect(find.text('Local preview attempts: 1'), findsOneWidget);
        await tester.ensureVisible(find.text('Open Job Seeker history'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open Job Seeker history'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('View payment details'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('View payment details'));
        await tester.pumpAndSettle();
        expect(find.text('Sandbox payment confirmed'), findsOneWidget);
        expect(find.text('Pay now · Sandbox'), findsNothing);
        expect(find.textContaining('UI PREVIEW'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  test('Preview lost response keeps an attempt Pending and cannot start a duplicate', () async {
    final data = PaymentPreviewData()..reset(PaymentPreviewScenario.uncertain);
    final repo = PreviewPaymentRepository(data, 'employer');
    await expectLater(
      repo.createCheckout(previewAssignmentId, 'first'),
      throwsStateError,
    );
    expect(data.attempts.single.status, SandboxPaymentStatus.pending);
    expect(data.attempts.single.checkoutUrl, isNull);
    await expectLater(
      repo.createCheckout(previewAssignmentId, 'second'),
      throwsStateError,
    );
    expect(data.creates, 1);
  });
}
