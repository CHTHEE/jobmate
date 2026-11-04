/// Payment responses are a NEW integration contract, documented alongside the
/// backend ports. They are not reads from the older Phase4Store demo.
enum SandboxPaymentStatus {
  pending('PENDING', 'Pending'),
  processing('PROCESSING', 'Processing'),
  succeeded('SUCCEEDED', 'Sandbox payment confirmed'),
  failed('FAILED', 'Failed'),
  cancelled('CANCELLED', 'Cancelled');

  const SandboxPaymentStatus(this.value, this.label);
  final String value, label;
  bool get unresolved => this == pending || this == processing;
  static SandboxPaymentStatus parse(Object? value) => values.firstWhere(
    (status) => status.value == value,
    orElse: () => throw const FormatException('Unknown payment status.'),
  );
}

String formatPaymentMinor(int units, [String currency = 'MYR']) =>
    '$currency ${units ~/ 100}.${(units % 100).toString().padLeft(2, '0')}';

class PaymentAmount {
  PaymentAmount(this.minorUnits, this.currency) {
    if (minorUnits <= 0 || minorUnits > 999999999999 || currency != 'MYR') {
      throw const FormatException('Invalid MYR assignment amount.');
    }
  }
  // Integers avoid floating-point rounding; 10000 sen is MYR 100.00.
  final int minorUnits;
  final String currency;
  String get label => formatPaymentMinor(minorUnits, currency);
  static PaymentAmount fromJson(Map<String, dynamic> json) {
    final units = json['amount_minor'];
    if (units is! int) {
      throw const FormatException('Invalid assignment amount.');
    }
    return PaymentAmount(units, paymentString(json, 'currency'));
  }
}

int parsePaymentBonus(String input) {
  final value = input.trim();
  if (value.isEmpty) return 0;
  if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(value)) {
    throw const FormatException(
      'Enter a positive bonus with at most two decimal places, or 0.',
    );
  }
  final parts = value.split('.');
  final units =
      int.parse(parts.first) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  if (units > 999999999999) {
    throw const FormatException('Bonus amount is too large.');
  }
  return units;
}

String paymentString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing payment field: $key.');
  }
  return value;
}

class SandboxPaymentAttempt {
  SandboxPaymentAttempt({
    required this.id,
    required this.assignmentId,
    required this.amount,
    required this.agreedMinor,
    this.bonusMinor = 0,
    required this.status,
    required this.createdAt,
    this.providerReference,
    this.method,
    this.failureReason,
    this.confirmedAt,
    this.checkoutUrl,
  }) {
    if (agreedMinor <= 0 ||
        bonusMinor < 0 ||
        agreedMinor + bonusMinor != amount.minorUnits) {
      throw const FormatException('Invalid agreed amount or bonus.');
    }
    if (status == SandboxPaymentStatus.succeeded &&
        (confirmedAt == null ||
            providerReference == null ||
            providerReference!.isEmpty)) {
      throw const FormatException('Missing trusted payment confirmation.');
    }
  }
  final String id, assignmentId;
  final PaymentAmount amount;
  final int agreedMinor, bonusMinor;
  final SandboxPaymentStatus status;
  final DateTime createdAt;
  final String? providerReference, method, failureReason;
  final DateTime? confirmedAt;
  final Uri? checkoutUrl;
  factory SandboxPaymentAttempt.fromJson(Map<String, dynamic> json) {
    return SandboxPaymentAttempt(
      id: paymentString(json, 'payment_id'),
      assignmentId: paymentString(json, 'assignment_id'),
      amount: PaymentAmount.fromJson(json),
      agreedMinor: json['agreed_amount_minor'] as int,
      bonusMinor: json['bonus_minor'] as int,
      status: SandboxPaymentStatus.parse(json['status']),
      createdAt: DateTime.parse(paymentString(json, 'created_at')),
      providerReference: json['provider_payment_id'] as String?,
      method: json['payment_method'] as String?,
      failureReason: json['failure_reason'] as String?,
      confirmedAt: json['confirmed_at'] == null
          ? null
          : DateTime.parse(json['confirmed_at'] as String),
      checkoutUrl: json['checkout_url'] == null
          ? null
          : SandboxCheckout.fromJson({...json, 'environment': 'sandbox'}).url,
    );
  }
}

class PayableAssignment {
  PayableAssignment({
    required this.id,
    required this.jobTitle,
    required this.companyName,
    required this.workerName,
    required this.amount,
    required this.completed,
    required this.workVerified,
    required this.paymentBlocked,
    required this.canPay,
    required this.employmentType,
    this.canResumeCheckout = false,
    this.blockingReason,
    this.attempts = const [],
  }) {
    if (canResumeCheckout &&
        (!completed ||
            !workVerified ||
            paymentBlocked ||
            !const ['part_time', 'temporary'].contains(employmentType) ||
            !attempts.any((a) => a.status.unresolved) ||
            attempts.any((a) => a.status == SandboxPaymentStatus.succeeded))) {
      throw const FormatException('Inconsistent checkout resume permission.');
    }
    if (canPay &&
        (!const ['part_time', 'temporary'].contains(employmentType) ||
            !completed ||
            !workVerified ||
            paymentBlocked ||
            attempts.any(
              (a) =>
                  a.status.unresolved ||
                  a.status == SandboxPaymentStatus.succeeded,
            ))) {
      throw const FormatException('Inconsistent payment eligibility.');
    }
    if (attempts.any(
      (a) =>
          a.assignmentId != id ||
          a.agreedMinor != amount.minorUnits ||
          a.amount.currency != amount.currency,
    )) {
      throw const FormatException(
        'Payment attempt does not match assignment terms.',
      );
    }
  }
  final String id, jobTitle, companyName, workerName, employmentType;
  final bool canResumeCheckout;
  final PaymentAmount amount;
  final bool completed, workVerified, paymentBlocked, canPay;
  final String? blockingReason;
  final List<SandboxPaymentAttempt> attempts;
  factory PayableAssignment.fromJson(Map<String, dynamic> json) =>
      PayableAssignment(
        id: paymentString(json, 'assignment_id'),
        jobTitle: paymentString(json, 'job_title'),
        companyName: paymentString(json, 'company_name'),
        workerName: paymentString(json, 'worker_name'),
        amount: PaymentAmount.fromJson(json),
        completed: json['completed'] == true,
        workVerified: json['work_verified'] == true,
        paymentBlocked: json['payment_blocked'] != false,
        canPay: json['can_pay'] == true,
        canResumeCheckout:
            json['can_resume_checkout'] == true &&
            json['completed'] == true &&
            json['work_verified'] == true &&
            json['payment_blocked'] == false &&
            const ['part_time', 'temporary'].contains(json['employment_type']),
        employmentType: paymentString(json, 'employment_type'),
        blockingReason: json['blocking_reason'] as String?,
        attempts: (json['attempts'] as List? ?? [])
            .map(
              (row) => SandboxPaymentAttempt.fromJson(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList(growable: false),
      );
  String get availability => canPay
      ? 'Ready for sandbox payment'
      : blockingReason ??
            (attempts.any((a) => a.status == SandboxPaymentStatus.succeeded)
                ? 'Sandbox payment already confirmed'
                : attempts.any((a) => a.status.unresolved)
                ? 'Awaiting provider confirmation'
                : !completed
                ? 'Work is not completed'
                : !workVerified
                ? 'Work verification is required'
                : 'Payment is currently unavailable');
}

class SandboxCheckout {
  const SandboxCheckout({
    required this.paymentId,
    required this.assignmentId,
    required this.url,
  });
  final String paymentId, assignmentId;
  final Uri url;
  factory SandboxCheckout.fromJson(Map<String, dynamic> json) {
    final url = Uri.parse(paymentString(json, 'checkout_url'));
    if (json['environment'] != 'sandbox' ||
        url.scheme != 'https' ||
        url.host != 'www.billplz-sandbox.com' ||
        url.userInfo.isNotEmpty ||
        url.hasPort) {
      throw const FormatException('Invalid sandbox checkout response.');
    }
    return SandboxCheckout(
      paymentId: paymentString(json, 'payment_id'),
      assignmentId: paymentString(json, 'assignment_id'),
      url: url,
    );
  }
}
