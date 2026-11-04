import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/payments/payment_models.dart';
import 'package:jobmate/features/payments/payment_pages.dart';
import 'package:jobmate/features/payments/payment_repository.dart';
import 'package:jobmate/features/payments/payment_routes.dart';

const assignmentId = '11111111-1111-4111-8111-111111111111';
SandboxPaymentAttempt attempt(SandboxPaymentStatus status, {int bonus = 0}) =>
    SandboxPaymentAttempt(
      id: '22222222-2222-4222-8222-222222222222',
      assignmentId: assignmentId,
      amount: PaymentAmount(10000 + bonus, 'MYR'),
      agreedMinor: 10000,
      bonusMinor: bonus,
      status: status,
      createdAt: DateTime.utc(2026, 11, 4),
      providerReference: status == SandboxPaymentStatus.succeeded
          ? 'bill_test'
          : null,
      confirmedAt: status == SandboxPaymentStatus.succeeded
          ? DateTime.utc(2026, 11, 4, 1)
          : null,
    );
PayableAssignment sampleAssignment({
  bool canPay = true,
  bool completed = true,
  bool verified = true,
  bool blocked = false,
  String type = 'part_time',
  bool canResumeCheckout = false,
  List<SandboxPaymentAttempt> attempts = const [],
}) => PayableAssignment(
  id: assignmentId,
  jobTitle: 'Cafe shift',
  companyName: 'Fixture Cafe',
  workerName: 'Fixture Worker',
  amount: PaymentAmount(10000, 'MYR'),
  employmentType: type,
  completed: completed,
  workVerified: verified,
  paymentBlocked: blocked,
  canPay: canPay,
  canResumeCheckout: canResumeCheckout,
  attempts: attempts,
);

class FixturePayments implements PaymentRepository {
  String role = 'employer';
  bool validSession = true, unavailable = false, loseResponse = false;
  PayableAssignment detail = sampleAssignment();
  int creates = 0, refreshes = 0, reads = 0;
  final bonuses = <int>[];
  final requestIds = <String>[];
  Completer<void>? waiting;
  @override
  void checkSession() {
    if (!validSession) throw StateError('Account changed.');
  }

  @override
  Future<PaymentAccess> access() async {
    checkSession();
    return PaymentAccess('fixture-user', role);
  }

  @override
  Future<List<PayableAssignment>> assignments({
    required int offset,
    required int limit,
  }) async {
    checkSession();
    if (unavailable) throw const PaymentIntegrationPending();
    return offset == 0 ? [detail] : [];
  }

  @override
  Future<PayableAssignment> assignment(String id) async {
    reads++;
    checkSession();
    if (unavailable) throw const PaymentIntegrationPending();
    return detail;
  }

  @override
  Future<PayableAssignment> forPayment(String id) => assignment(assignmentId);
  @override
  Future<PayableAssignment> refresh(String id) async {
    refreshes++;
    return assignment(id);
  }

  @override
  Future<SandboxCheckout> createCheckout(
    String id,
    String key, {
    int bonusMinor = 0,
  }) async {
    creates++;
    bonuses.add(bonusMinor);
    requestIds.add(key);
    await waiting?.future;
    checkSession();
    if (loseResponse) throw Exception('Lost response');
    return SandboxCheckout(
      paymentId: '22222222-2222-4222-8222-222222222222',
      assignmentId: id,
      url: Uri.parse('https://www.billplz-sandbox.com/bills/test'),
    );
  }
}

Future<void> mount(
  WidgetTester tester,
  FixturePayments data, {
  bool details = true,
  bool returning = false,
  Future<bool> Function(Uri)? open,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SandboxPaymentsPage(
        repository: data,
        role: data.role,
        assignmentId: details && !returning ? assignmentId : null,
        paymentId: returning ? '22222222-2222-4222-8222-222222222222' : null,
        returnFromCheckout: returning,
        openCheckout: open,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pay(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Pay now · Sandbox'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Pay now · Sandbox'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
  await tester.pump();
}

void main() {
  test('MYR amounts and bonus inputs use exact integer sen and reject reductions/invalid input', () {
    expect(PaymentAmount(10001, 'MYR').label, 'MYR 100.01');
    expect(parsePaymentBonus('25.50'), 2550);
    expect(parsePaymentBonus('0'), 0);
    expect(parsePaymentBonus(''), 0);
    for (final value in ['-1', '1.001', '1e3', '1,000', 'NaN']) {
      expect(() => parsePaymentBonus(value), throwsFormatException);
    }
    expect(() => PaymentAmount(0, 'MYR'), throwsFormatException);
    expect(() => sampleAssignment(type: 'full_time'), throwsFormatException);
    expect(() => sampleAssignment(blocked: true), throwsFormatException);
    expect(() => sampleAssignment(verified: false), throwsFormatException);
    expect(
      () => sampleAssignment(attempts: [attempt(SandboxPaymentStatus.pending)]),
      throwsFormatException,
    );
  });
  test('Unconfirmed success and non-sandbox checkout URLs fail closed', () {
    expect(
      () => SandboxPaymentAttempt(
        id: 'id',
        assignmentId: assignmentId,
        amount: PaymentAmount(10000, 'MYR'),
        agreedMinor: 10000,
        status: SandboxPaymentStatus.succeeded,
        createdAt: DateTime.now(),
      ),
      throwsFormatException,
    );
    for (final url in [
      'javascript:alert(1)',
      'https://www.billplz.com/bills/x',
      'https://evil.test',
    ]) {
      expect(
        () => SandboxCheckout.fromJson({
          'payment_id': 'id',
          'assignment_id': assignmentId,
          'environment': 'sandbox',
          'checkout_url': url,
        }),
        throwsFormatException,
      );
    }
  });

  for (final width in [320.0, 768.0, 1440.0]) {
    testWidgets(
      'Payment UI fits $width with large text and all attempt statuses',
      (tester) async {
        tester.view.physicalSize = Size(width, 1050);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = FixturePayments()
          ..detail = sampleAssignment(
            canPay: false,
            attempts: [
              for (final status in SandboxPaymentStatus.values)
                attempt(status, bonus: 500),
            ],
          );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: SandboxPaymentsPage(
              role: 'employer',
              assignmentId: assignmentId,
              repository: data,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -900),
        );
        await tester.pumpAndSettle();
        expect(find.text('Sandbox payment confirmed'), findsOneWidget);
        expect(find.textContaining('No worker payout'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Unavailable backend shows integration status without mock payments',
    (tester) async {
      final data = FixturePayments()..unavailable = true;
      await mount(tester, data, details: false);
      expect(find.text('Payments are being connected'), findsOneWidget);
      expect(find.text('Cafe shift'), findsNothing);
      expect(find.text('Pay now · Sandbox'), findsNothing);
      expect(data.creates, 0);
    },
  );
  testWidgets(
    'Employer bonus is additive, confirmed and locked into one checkout',
    (tester) async {
      final data = FixturePayments()..waiting = Completer<void>();
      await mount(tester, data);
      await tester.enterText(find.byType(TextField), '25.50');
      await pay(tester);
      expect(data.creates, 1);
      expect(data.bonuses, [2550]);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      data.waiting!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Open sandbox checkout'), findsOneWidget);
      await tester.tap(find.text('Pay now · Sandbox'));
      await tester.pumpAndSettle();
      expect(data.creates, 1);
      expect(find.text('Sandbox payment confirmed'), findsNothing);
    },
  );
  testWidgets('Negative bonus never reaches checkout creation', (tester) async {
    final data = FixturePayments();
    await mount(tester, data);
    await tester.enterText(find.byType(TextField), '-20');
    await tester.ensureVisible(find.text('Pay now · Sandbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay now · Sandbox'));
    await tester.pumpAndSettle();
    expect(data.creates, 0);
    expect(find.textContaining('at most two decimal'), findsOneWidget);
  });

  testWidgets(
    'Reopened Pending bill resumes its existing checkout without creating a replacement',
    (tester) async {
      final data = FixturePayments()
        ..detail = sampleAssignment(
          canPay: false,
          canResumeCheckout: true,
          attempts: [
            SandboxPaymentAttempt.fromJson({
              'payment_id': '22222222-2222-4222-8222-222222222222',
              'assignment_id': assignmentId,
              'amount_minor': 11000,
              'agreed_amount_minor': 10000,
              'bonus_minor': 1000,
              'currency': 'MYR',
              'status': 'PENDING',
              'created_at': '2026-11-04T00:00:00Z',
              'checkout_url': 'https://www.billplz-sandbox.com/bills/existing',
            }),
          ],
        );
      var opened = 0;
      await mount(
        tester,
        data,
        open: (uri) async {
          opened++;
          expect(uri.path, '/bills/existing');
          return true;
        },
      );
      await tester.ensureVisible(find.text('Open sandbox checkout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open sandbox checkout'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(data.creates, 0);
      final pendingAttempts = data.detail.attempts;
      data.detail = sampleAssignment(
        canPay: false,
        blocked: true,
        attempts: pendingAttempts,
      );
      await tester.tap(find.text('Check payment status'));
      await tester.pumpAndSettle();
      expect(find.text('Open sandbox checkout'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final role in ['job_seeker', 'administrator']) {
    testWidgets('$role payment history is read-only', (tester) async {
      final data = FixturePayments()
        ..role = role
        ..detail = sampleAssignment(canPay: false);
      await mount(tester, data);
      expect(find.text('Pay now · Sandbox'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(data.creates, 0);
    });
  }
  testWidgets(
    'Unknown create result blocks new checkout until status is checked',
    (tester) async {
      final data = FixturePayments()..loseResponse = true;
      await mount(tester, data);
      await pay(tester);
      await tester.pumpAndSettle();
      expect(data.creates, 1);
      expect(find.textContaining('could not be confirmed'), findsOneWidget);
      await tester.tap(find.text('Pay now · Sandbox'));
      await tester.pumpAndSettle();
      expect(data.creates, 1);
      data.detail = sampleAssignment(
        canPay: false,
        attempts: [attempt(SandboxPaymentStatus.pending)],
      );
      await tester.tap(find.text('Check payment status'));
      await tester.pumpAndSettle();
      expect(data.refreshes, 1);
      expect(find.text('Pending'), findsOneWidget);
      expect(data.creates, 1);
    },
  );
  testWidgets(
    'Return page rechecks backend and does not turn Pending into Success',
    (tester) async {
      final data = FixturePayments()
        ..detail = sampleAssignment(
          canPay: false,
          attempts: [attempt(SandboxPaymentStatus.pending)],
        );
      await mount(tester, data, returning: true);
      expect(data.refreshes, 1);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Sandbox payment confirmed'), findsNothing);
      expect(data.creates, 0);
    },
  );
  testWidgets(
    'Blocked checkout window is retryable without creating another bill',
    (tester) async {
      final data = FixturePayments();
      var opened = 0;
      await mount(
        tester,
        data,
        open: (_) async {
          opened++;
          return false;
        },
      );
      await pay(tester);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open sandbox checkout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open sandbox checkout'));
      await tester.pumpAndSettle();
      expect(find.textContaining('window was blocked'), findsOneWidget);
      expect(data.creates, 1);
      await tester.tap(find.text('Open sandbox checkout'));
      await tester.pumpAndSettle();
      expect(opened, 2);
      expect(data.creates, 1);
    },
  );
  testWidgets('Dirty Bonus route exit can cancel without losing input', (
    tester,
  ) async {
    final data = FixturePayments();
    final router = GoRouter(
      initialLocation: '/employer-payments/assignments/$assignmentId',
      routes: [
        sandboxPaymentRoute(
          '/employer-payments/assignments/:assignmentId',
          role: 'employer',
          repository: data,
        ),
        GoRoute(
          path: '/other',
          builder: (_, _) => const Scaffold(body: Text('Other page')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '10.00');
    router.go('/other');
    await tester.pumpAndSettle();
    expect(find.text('Leave this page?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '10.00',
    );
    router.go('/other');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave page'));
    await tester.pumpAndSettle();
    expect(find.text('Other page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
