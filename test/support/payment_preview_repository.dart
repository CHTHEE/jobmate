// MANUAL UI PREVIEW ONLY. Never import this file from lib/ or an Edge Function.
// No Supabase initialization, credentials, network calls or persistent storage.
import 'package:jobmate/features/payments/payment_models.dart';
import 'package:jobmate/features/payments/payment_repository.dart';

const previewAssignmentId = '11111111-1111-4111-8111-111111111111';

enum PaymentPreviewScenario {
  ready('Ready · Part-time'),
  temporary('Ready · Temporary'),
  incomplete('Blocked · Work incomplete'),
  unverified('Blocked · Work unverified'),
  disputed('Blocked · Work dispute'),
  fullTime('Blocked · Full-time'),
  pending('Pending · Existing checkout'),
  processing('Processing'),
  confirmed('Confirmed · Simulated only'),
  failed('Failed creation · Retry allowed'),
  cancelled('Cancelled bill · Retry allowed'),
  unavailable('Backend not connected'),
  uncertain('Lose create response · Keep Pending');

  const PaymentPreviewScenario(this.label);
  final String label;
}

class PaymentPreviewData {
  PaymentPreviewScenario scenario = PaymentPreviewScenario.ready;
  final List<SandboxPaymentAttempt> attempts = [];
  int creates = 0;
  void reset(PaymentPreviewScenario value) {
    scenario = value;
    attempts.clear();
    creates = 0;
    final status = switch (value) {
      PaymentPreviewScenario.pending => SandboxPaymentStatus.pending,
      PaymentPreviewScenario.processing => SandboxPaymentStatus.processing,
      PaymentPreviewScenario.confirmed => SandboxPaymentStatus.succeeded,
      PaymentPreviewScenario.failed => SandboxPaymentStatus.failed,
      PaymentPreviewScenario.cancelled => SandboxPaymentStatus.cancelled,
      _ => null,
    };
    if (status != null) {
      attempts.add(
        _attempt('22222222-2222-4222-8222-222222222222', 1000, status),
      );
    }
  }

  SandboxPaymentAttempt _attempt(
    String id,
    int bonus,
    SandboxPaymentStatus status, {
    bool unknown = false,
  }) => SandboxPaymentAttempt(
    id: id,
    assignmentId: previewAssignmentId,
    amount: PaymentAmount(10000 + bonus, 'MYR'),
    agreedMinor: 10000,
    bonusMinor: bonus,
    status: status,
    createdAt: DateTime.now(),
    confirmedAt: status == SandboxPaymentStatus.succeeded
        ? DateTime.now()
        : null,
    providerReference: status == SandboxPaymentStatus.failed || unknown
        ? null
        : 'UI-PREVIEW-NOT-A-REAL-BILL',
    checkoutUrl: status.unresolved && !unknown
        ? Uri.parse('https://www.billplz-sandbox.com/bills/ui-preview-only')
        : null,
    failureReason: status == SandboxPaymentStatus.failed
        ? 'Simulated rejected creation. No gateway was contacted.'
        : null,
  );

  void simulateResult(SandboxPaymentStatus status) {
    if (attempts.isEmpty || !attempts.first.status.unresolved) return;
    final old = attempts.first;
    attempts[0] = SandboxPaymentAttempt(
      id: old.id,
      assignmentId: old.assignmentId,
      amount: old.amount,
      agreedMinor: old.agreedMinor,
      bonusMinor: old.bonusMinor,
      status: status,
      createdAt: old.createdAt,
      providerReference: old.providerReference,
      confirmedAt: status == SandboxPaymentStatus.succeeded
          ? DateTime.now()
          : null,
      checkoutUrl: status.unresolved ? old.checkoutUrl : null,
    );
  }

  PayableAssignment view(String role) {
    if (scenario == PaymentPreviewScenario.unavailable) {
      throw const PaymentIntegrationPending();
    }
    final completed = scenario != PaymentPreviewScenario.incomplete;
    final verified = scenario != PaymentPreviewScenario.unverified;
    final blocked = scenario == PaymentPreviewScenario.disputed;
    final type = scenario == PaymentPreviewScenario.fullTime
        ? 'full_time'
        : scenario == PaymentPreviewScenario.temporary
        ? 'temporary'
        : 'part_time';
    final active = attempts.any((a) => a.status.unresolved);
    final paid = attempts.any(
      (a) => a.status == SandboxPaymentStatus.succeeded,
    );
    final eligible =
        role == 'employer' &&
        completed &&
        verified &&
        !blocked &&
        type != 'full_time';
    final reason = !completed
        ? 'Work is not completed.'
        : !verified
        ? 'Work verification is required.'
        : blocked
        ? 'Resolve the work-completion dispute before paying.'
        : type == 'full_time'
        ? 'Full-time payments are outside this version.'
        : paid
        ? 'Simulated payment confirmed. No gateway payment occurred.'
        : active
        ? 'Pending test attempt. Resume or check its status.'
        : role != 'employer'
        ? 'Read-only preview role.'
        : null;
    return PayableAssignment(
      id: previewAssignmentId,
      jobTitle: 'Preview cafe shift',
      companyName: 'Fictional Preview Company',
      workerName: 'Fictional Preview Worker',
      amount: PaymentAmount(10000, 'MYR'),
      employmentType: type,
      completed: completed,
      workVerified: verified,
      paymentBlocked: blocked,
      canPay: eligible && !active && !paid,
      canResumeCheckout: eligible && active && !paid,
      blockingReason: reason,
      attempts: List.unmodifiable(attempts),
    );
  }
}

class PreviewPaymentRepository implements PaymentRepository {
  PreviewPaymentRepository(this.data, this.role);
  final PaymentPreviewData data;
  final String role;
  @override
  void checkSession() {} // Fictional actors; this is not an authentication test.
  @override
  Future<PaymentAccess> access() async => PaymentAccess('preview-$role', role);
  @override
  Future<List<PayableAssignment>> assignments({
    required int offset,
    required int limit,
  }) async => offset == 0 ? [data.view(role)] : [];
  @override
  Future<PayableAssignment> assignment(String assignmentId) async {
    if (assignmentId != previewAssignmentId) {
      throw StateError('Unknown preview assignment.');
    }
    return data.view(role);
  }

  @override
  Future<PayableAssignment> forPayment(String paymentId) async {
    if (!data.attempts.any((a) => a.id == paymentId)) {
      throw StateError('Unknown preview payment.');
    }
    return data.view(role);
  }

  @override
  Future<PayableAssignment> refresh(String assignmentId) =>
      assignment(assignmentId);
  @override
  Future<SandboxCheckout> createCheckout(
    String assignmentId,
    String requestId, {
    int bonusMinor = 0,
  }) async {
    if (role != 'employer' ||
        assignmentId != previewAssignmentId ||
        !data.view(role).canPay ||
        bonusMinor < 0) {
      throw StateError('Preview assignment is not payable.');
    }
    final unknown = data.scenario == PaymentPreviewScenario.uncertain;
    data.attempts.insert(
      0,
      data._attempt(
        requestId,
        bonusMinor,
        SandboxPaymentStatus.pending,
        unknown: unknown,
      ),
    );
    data.creates++;
    if (unknown) throw StateError('Simulated lost response.');
    return SandboxCheckout(
      paymentId: requestId,
      assignmentId: assignmentId,
      url: data.attempts.first.checkoutUrl!,
    );
  }
}
