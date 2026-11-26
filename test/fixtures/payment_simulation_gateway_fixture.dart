import 'package:jobmate/features/payments/application_payment_repository.dart';
import 'package:jobmate/features/payments/payment_simulation_gateway.dart';

class PaymentSimulationGatewayFixture implements PaymentSimulationGateway {
  const PaymentSimulationGatewayFixture();

  @override
  String get actor => 'synthetic-job-seeker';

  @override
  Stream<String?> get accountChanges => const Stream.empty();

  @override
  Future<List<SimulationRecipient>> recipients(
    String actor, {
    String? applicationId,
  }) async {
    if (actor != this.actor || applicationId != null) {
      throw StateError('Unexpected recipient lookup in Account Settings');
    }
    return [];
  }

  @override
  Future<void> save(
    String actor,
    SimulationMethod method,
    String name,
    String? bank,
    String identifier,
  ) => throw StateError('Unexpected recipient write in Account Settings');

  @override
  Future<SimulationReceipt> record(SimulationAttempt attempt) =>
      throw StateError('Unexpected payment write in Account Settings');

  @override
  Future<SimulationReceipt?> receipt(
    String actor,
    ApplicationPaymentSummary row,
  ) => throw StateError('Unexpected receipt lookup in Account Settings');
}
