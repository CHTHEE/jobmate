import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'application_payment_repository.dart';

enum SimulationMethod {
  bank('bank_transfer', 'Bank Transfer'),
  tng('tng_ewallet', "Touch 'n Go eWallet");

  const SimulationMethod(this.code, this.label);
  final String code;
  final String label;

  static SimulationMethod parse(Object? code) =>
      values.singleWhere((value) => value.code == code);
}

class SimulationRecipient {
  SimulationRecipient.fromJson(Map row)
    : id = row['method_id'] as String,
      method = SimulationMethod.parse(row['method_type']),
      name = row['recipient_name'] as String,
      bank = row['bank_name'] as String?,
      masked = _mask(row['masked_identifier']);

  final String id;
  final SimulationMethod method;
  final String name;
  final String? bank;
  final String masked;
}

String _mask(Object? value) {
  if (value is! String || !RegExp(r'^\*{4}[0-9]{4}$').hasMatch(value)) {
    throw const FormatException('Invalid masked payment details.');
  }
  return value;
}

class SimulationAttempt {
  SimulationAttempt({
    required this.actor,
    required this.settlement,
    required this.recipient,
    required this.bonus,
  }) : requestId = const Uuid().v4();

  final String actor;
  final ApplicationPaymentSummary settlement;
  final SimulationRecipient recipient;
  final int bonus;
  final String requestId;
  int get total => settlement.confirmedBaseSen! + bonus;
}

class SimulationReceipt {
  const SimulationReceipt({
    required this.reference,
    required this.recordedAt,
    required this.base,
    required this.bonus,
    required this.total,
    this.method,
    this.name,
    this.bank,
    this.masked,
  });

  final String reference;
  final DateTime recordedAt;
  final int base, bonus, total;
  final SimulationMethod? method;
  final String? name, bank, masked;
}

abstract interface class PaymentSimulationGateway {
  String? get actor;
  Stream<String?> get accountChanges;
  Future<List<SimulationRecipient>> recipients(
    String actor, {
    String? applicationId,
  });
  Future<void> save(
    String actor,
    SimulationMethod method,
    String name,
    String? bank,
    String identifier,
  );
  Future<SimulationReceipt> record(SimulationAttempt attempt);
  Future<SimulationReceipt?> receipt(
    String actor,
    ApplicationPaymentSummary row,
  );
}

class SupabasePaymentSimulationGateway implements PaymentSimulationGateway {
  SupabasePaymentSimulationGateway(this.client);
  final SupabaseClient client;

  @override
  String? get actor => client.auth.currentUser?.id;

  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);

  Future<dynamic> _rpc(
    String expected,
    String name, [
    Map<String, dynamic>? params,
  ]) async {
    if (actor != expected) throw StateError('Session changed.');
    final value = await client.rpc(name, params: params);
    if (actor != expected) throw StateError('Session changed.');
    return value;
  }

  @override
  Future<List<SimulationRecipient>> recipients(
    String actor, {
    String? applicationId,
  }) async {
    final rows =
        await (applicationId == null
                ? _rpc(actor, 'list_my_payment_recipient_methods_v1')
                : _rpc(actor, 'list_application_payment_recipient_methods_v1', {
                    'p_application_id': applicationId,
                  }))
            as List;
    final methods = rows
        .map((row) => SimulationRecipient.fromJson(row as Map))
        .toList();
    if (methods.map((row) => row.method).toSet().length != methods.length) {
      throw const FormatException('Duplicate payment methods.');
    }
    return methods;
  }

  @override
  Future<void> save(
    String actor,
    SimulationMethod method,
    String name,
    String? bank,
    String identifier,
  ) async {
    await _rpc(actor, 'save_my_payment_recipient_method_v1', {
      'p_method_type': method.code,
      'p_recipient_name': name,
      'p_bank_name': bank,
      'p_recipient_identifier': identifier,
    });
  }

  @override
  Future<SimulationReceipt> record(SimulationAttempt attempt) async {
    final row = attempt.settlement;
    final result = await _rpc(
      attempt.actor,
      'record_demo_application_payment_with_method_v1',
      {
        'p_application_id': row.applicationId,
        'p_request_id': attempt.requestId,
        'p_bonus_sen': attempt.bonus,
        'p_method_id': attempt.recipient.id,
        'p_proposal_id': row.proposalId,
        'p_confirmed_base_sen': row.confirmedBaseSen,
      },
    ) as Map;
    if (result['application_id'] != row.applicationId ||
        result['payment_status'] != 'demo_recorded' ||
        result['total_sen'] != attempt.total ||
        result['payment_method_type'] != attempt.recipient.method.code) {
      throw const FormatException('Could not verify the recorded payment.');
    }
    return SimulationReceipt(
      reference: result['payment_id'] as String,
      recordedAt: DateTime.parse(result['recorded_at'] as String),
      base: row.confirmedBaseSen!,
      bonus: attempt.bonus,
      total: attempt.total,
      method: attempt.recipient.method,
      name: result['recipient_name'] as String,
      bank: result['bank_name'] as String?,
      masked: _mask(result['recipient_masked']),
    );
  }

  @override
  Future<SimulationReceipt?> receipt(
    String actor,
    ApplicationPaymentSummary row,
  ) async {
    final rows = await _rpc(actor, 'get_application_demo_payment_method_v1', {
      'p_application_id': row.applicationId,
    }) as List;
    if (rows.isEmpty && row.paymentId == null) return null;
    final method = rows.single as Map;
    if (row.paymentId == null ||
        method['payment_id'] != row.paymentId ||
        method['has_method'] is! bool) {
      throw const FormatException(
        'Refresh the settlement before viewing the receipt.',
      );
    }
    final hasMethod = method['has_method'] as bool;
    return SimulationReceipt(
      reference: row.paymentId!,
      recordedAt: DateTime.parse(row.recordedAt!),
      base: row.confirmedBaseSen!,
      bonus: row.bonusSen,
      total: row.totalSen!,
      method: hasMethod ? SimulationMethod.parse(method['method_type']) : null,
      name: hasMethod ? method['recipient_name'] as String : null,
      bank: hasMethod ? method['bank_name'] as String? : null,
      masked: hasMethod ? _mask(method['masked_identifier']) : null,
    );
  }
}
