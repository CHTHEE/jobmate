import 'package:flutter/foundation.dart';

import '../payments/payment_feature_gate.dart';

/// P03 stays opt-in until the Offer candidate and its prerequisite privilege
/// hardening have been reviewed and installed together.
const p03CompensationOffersEnabled =
    kDebugMode &&
    bool.fromEnvironment(
      'JOBMATE_P03_COMPENSATION_OFFERS',
      defaultValue: false,
    ) ||
    paymentHandlingEnabled;

/// Sanitized versioned MYR terms returned by the P03 Offer RPCs.
/// Sen values are transported as decimal strings so Web does not lose integer
/// precision above JavaScript's safe integer range.
class CompensationOffer {
  CompensationOffer.fromJson(Map<String, dynamic> json)
    : offerId = _requiredUuid(json, 'offer_id'),
      applicationId = _requiredUuid(json, 'application_id'),
      version = _positiveInt(json, 'offer_version'),
      employmentType = _oneOf(json, 'employment_type', const {
        'part_time',
        'temporary',
      }),
      salaryPeriod = _oneOf(json, 'salary_period', const {'hourly', 'daily'}),
      minimumSen = _optionalSen(json, 'salary_min_sen'),
      maximumSen = _optionalSen(json, 'salary_max_sen'),
      currency = _requiredText(json, 'currency'),
      issuerId = _requiredUuid(json, 'issued_by'),
      issuedAt = DateTime.parse(_requiredText(json, 'issued_at')),
      paymentBasisSupported = _requiredBool(json, 'payment_basis_supported'),
      isCurrent = _requiredBool(json, 'is_current'),
      isAccepted = _requiredBool(json, 'is_accepted') {
    if (json.keys.toSet().difference(_keys).isNotEmpty ||
        json.keys.toSet().length != _keys.length ||
        !json.keys.toSet().containsAll(_keys) ||
        currency != 'MYR' ||
        !paymentBasisSupported ||
        minimumSen == null && maximumSen == null ||
        minimumSen != null && maximumSen != null && maximumSen! < minimumSen!) {
      throw const FormatException('Invalid compensation offer response.');
    }
  }

  static const _keys = {
    'offer_id',
    'application_id',
    'offer_version',
    'employment_type',
    'salary_period',
    'salary_min_sen',
    'salary_max_sen',
    'currency',
    'issued_by',
    'issued_at',
    'payment_basis_supported',
    'is_current',
    'is_accepted',
  };

  final String offerId, applicationId, employmentType, salaryPeriod;
  final String currency, issuerId;
  final int version;
  final BigInt? minimumSen, maximumSen;
  final DateTime issuedAt;
  final bool paymentBasisSupported, isCurrent, isAccepted;

  String get salaryRange {
    final min = minimumSen == null ? '—' : _formatSen(minimumSen!);
    final max = maximumSen == null ? '—' : _formatSen(maximumSen!);
    return 'MYR $min – $max / $salaryPeriod';
  }

  static String _formatSen(BigInt value) =>
      '${value ~/ BigInt.from(100)}.${(value % BigInt.from(100)).toString().padLeft(2, '0')}';

  static String _requiredText(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid compensation offer field: $key.');
    }
    return value;
  }

  static int _positiveInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int || value < 1) {
      throw FormatException('Invalid compensation offer field: $key.');
    }
    return value;
  }

  static String _requiredUuid(Map<String, dynamic> json, String key) {
    final value = _requiredText(json, key);
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value)) {
      throw FormatException('Invalid compensation offer field: $key.');
    }
    return value;
  }

  static String _oneOf(
    Map<String, dynamic> json,
    String key,
    Set<String> allowed,
  ) {
    final value = _requiredText(json, key);
    if (!allowed.contains(value)) {
      throw FormatException('Invalid compensation offer field: $key.');
    }
    return value;
  }

  static BigInt? _optionalSen(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String || !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) {
      throw FormatException('Invalid compensation offer field: $key.');
    }
    final amount = BigInt.parse(value);
    if (amount > BigInt.parse('9223372036854775807')) {
      throw FormatException('Invalid compensation offer field: $key.');
    }
    return amount;
  }

  static bool _requiredBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! bool) {
      throw FormatException('Invalid compensation offer field: $key.');
    }
    return value;
  }
}
