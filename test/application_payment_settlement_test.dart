import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/payments/application_payment_page.dart';
import 'package:jobmate/features/payments/application_payment_repository.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';

const _applicationId = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> _recordedSettlement() => {
  'application_id': _applicationId,
  'job_title': 'Fixture shift',
  'company_name': 'Fixture employer',
  'worker_name': 'Fixture worker',
  'employment_type': 'part_time',
  'salary_period': 'hourly',
  'offer_id': '22222222-2222-4222-8222-222222222222',
  'offer_version': 2,
  'salary_min_sen': 1000,
  'salary_max_sen': 2000,
  'payable_hours': 5,
  'calculated_min_sen': 5000,
  'calculated_max_sen': 10000,
  'proposal_id': '33333333-3333-4333-8333-333333333333',
  'proposal_version': 1,
  'proposed_base_sen': 7500,
  'proposal_status': 'confirmed',
  'confirmed_base_sen': 7500,
  'payment_id': '44444444-4444-4444-8444-444444444444',
  'bonus_sen': 500,
  'payment_status': 'demo_recorded',
  'recorded_at': '2026-11-24T10:00:00Z',
  'blocking_reason': null,
};

class _ReadOnlySettlementSource implements ApplicationPaymentSource {
  int reads = 0;

  @override
  String get userId => 'fixture-actor';

  @override
  Stream<String?> get accountChanges => const Stream.empty();

  @override
  Future<List<ApplicationPaymentSummary>> list() async {
    reads++;
    return [ApplicationPaymentSummary.fromJson(_recordedSettlement())];
  }

  @override
  Future<void> propose(ApplicationPaymentSummary summary, int amountSen) =>
      throw StateError('Unexpected settlement write');

  @override
  Future<void> respond(
    ApplicationPaymentSummary summary, {
    required bool accept,
  }) => throw StateError('Unexpected settlement write');

  @override
  Future<void> recordDemoPayment(
    ApplicationPaymentSummary summary,
    int bonusSen,
  ) => throw StateError('Unexpected settlement write');
}

void main() {
  test('recorded settlement uses the confirmed amount and cannot be recorded again', () {
    final fixture = _recordedSettlement();
    final record = ApplicationPaymentSummary.fromJson(fixture);
    expect(record.totalSen, 8000);
    expect(record.canPropose, isFalse);
    expect(record.canConfirm, isFalse);
    expect(record.canRecordDemoPayment, isFalse);
    expect(
      () => ApplicationPaymentSummary.fromJson({
        ...fixture,
        'confirmed_base_sen': null,
      }),
      throwsFormatException,
    );
  });

  for (final (role, root) in [
    ('employer', AppRoutes.employerPayments),
    ('job_seeker', AppRoutes.payments),
  ]) {
    testWidgets(
      '$role opens the recorded settlement for the selected application',
      (tester) async {
        final source = _ReadOnlySettlementSource();
        final repository = ApplicationPaymentRepository(source);
        final detailRepository = ApplicationPaymentRepository(source);
        final router = GoRouter(
          initialLocation: root,
          routes: [
            GoRoute(
              path: root,
              builder: (_, _) =>
                  ApplicationPaymentPage(role: role, repository: repository),
            ),
            GoRoute(
              path: '$root/settlements/:applicationId',
              builder: (_, state) => ApplicationPaymentPage(
                role: role,
                repository: detailRepository,
                applicationId: state.pathParameters['applicationId'],
              ),
            ),
          ],
        );
        addTearDown(repository.dispose);
        addTearDown(detailRepository.dispose);
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        final view = find.text('View Settlement');
        await tester.ensureVisible(view);
        await tester.tap(view);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ApplicationPaymentPage>(
                find.byType(ApplicationPaymentPage),
              )
              .applicationId,
          _applicationId,
        );
        expect(find.text('Fixture shift'), findsWidgets);
        expect(find.text('View Settlement'), findsNothing);
        expect(find.textContaining('Save Demo Payment'), findsNothing);
        expect(source.reads, 2);
        final back = find.text('Back to Payment Overview');
        await tester.ensureVisible(back);
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.text('View Settlement'), findsOneWidget);
      },
    );
  }
}
