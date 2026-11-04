import 'package:supabase_flutter/supabase_flutter.dart';

import 'payment_models.dart';

class PaymentAccess {
  const PaymentAccess(this.userId, this.role);
  final String userId, role;
}

class PaymentIntegrationPending implements Exception {
  const PaymentIntegrationPending();
}

abstract class PaymentRepository {
  void checkSession();
  Future<PaymentAccess> access();
  Future<List<PayableAssignment>> assignments({
    required int offset,
    required int limit,
  });
  Future<PayableAssignment> assignment(String assignmentId);
  Future<SandboxCheckout> createCheckout(
    String assignmentId,
    String requestId, {
    int bonusMinor = 0,
  });
  Future<PayableAssignment> refresh(String assignmentId);
  Future<PayableAssignment> forPayment(String paymentId);
}

/// Calls the new payment-handling Edge Function. Missing integration is surfaced
/// explicitly; this repository never substitutes demo assignments or success.
class SupabasePaymentRepository implements PaymentRepository {
  SupabasePaymentRepository(this.client)
    : _actorId = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _actorId;
  @override
  void checkSession() {
    if (_actorId == null || client.auth.currentUser?.id != _actorId) {
      throw StateError(
        'Your account changed. Reopen Payments after signing in.',
      );
    }
  }

  @override
  Future<PaymentAccess> access() async {
    checkSession();
    final user = await client
        .from('users')
        .select('role, status')
        .eq('user_id', _actorId!)
        .single();
    checkSession();
    final role = user['role'];
    if (user['status'] != 'active' ||
        !const ['employer', 'job_seeker', 'administrator'].contains(role)) {
      throw StateError(
        'An active JobMate account is required to view payments.',
      );
    }
    return PaymentAccess(_actorId, role as String);
  }

  Future<Map<String, dynamic>> _request(
    String action, [
    Map<String, dynamic> fields = const {},
  ]) async {
    checkSession();
    try {
      final response = await client.functions.invoke(
        'payment-handling',
        body: {'action': action, ...fields},
      );
      checkSession();
      return _response(response.status, response.data);
    } on FunctionException catch (error) {
      checkSession();
      if (error.status == 404 || error.status == 501 || error.status == 503) {
        throw const PaymentIntegrationPending();
      }
      if (error.status == 401 || error.status == 403) {
        throw StateError(
          'You do not have access to this payment. Sign in with the assignment account.',
        );
      }
      rethrow;
    }
  }

  Map<String, dynamic> _response(int status, dynamic data) {
    if (status == 404 ||
        status == 501 ||
        status == 503 ||
        (data is Map && data['code'] == 'PAYMENT_INTEGRATION_PENDING')) {
      throw const PaymentIntegrationPending();
    }
    if (status < 200 ||
        status >= 300 ||
        data is! Map ||
        data['environment'] != 'sandbox') {
      throw const FormatException('Unable to confirm sandbox payment data.');
    }
    return Map<String, dynamic>.from(data);
  }

  @override
  Future<List<PayableAssignment>> assignments({
    required int offset,
    required int limit,
  }) async {
    final result = await _request('list_assignments', {
      'offset': offset,
      'limit': limit,
    });
    if (result['assignments'] is! List) {
      throw const FormatException('Invalid payment list.');
    }
    return (result['assignments'] as List)
        .map(
          (row) =>
              PayableAssignment.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<PayableAssignment> assignment(String assignmentId) async =>
      PayableAssignment.fromJson(
        Map<String, dynamic>.from(
          (await _request('get_assignment', {
                'assignment_id': assignmentId,
              }))['assignment']
              as Map,
        ),
      );
  @override
  Future<SandboxCheckout> createCheckout(
    String assignmentId,
    String requestId, {
    int bonusMinor = 0,
  }) async => SandboxCheckout.fromJson(
    await _request('create_checkout', {
      'assignment_id': assignmentId,
      'request_id': requestId,
      'bonus_minor': bonusMinor,
    }),
  );
  @override
  Future<PayableAssignment> refresh(String assignmentId) async =>
      PayableAssignment.fromJson(
        Map<String, dynamic>.from(
          (await _request('refresh_status', {
                'assignment_id': assignmentId,
              }))['assignment']
              as Map,
        ),
      );
  @override
  Future<PayableAssignment> forPayment(String paymentId) async =>
      PayableAssignment.fromJson(
        Map<String, dynamic>.from(
          (await _request('get_payment', {
                'payment_id': paymentId,
              }))['assignment']
              as Map,
        ),
      );
}
