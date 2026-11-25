import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ApplicationPaymentSummary {
  ApplicationPaymentSummary.fromJson(Map<String, dynamic> row)
    : applicationId = _uuid(row, 'application_id'),
      jobTitle = _text(row, 'job_title'),
      companyName = _text(row, 'company_name'),
      workerName = _text(row, 'worker_name'),
      employmentType = _oneOf(row, 'employment_type', const {'part_time'}),
      salaryPeriod = _oneOf(row, 'salary_period', const {'hourly'}),
      offerId = _uuid(row, 'offer_id'),
      offerVersion = _positiveInt(row, 'offer_version'),
      salaryMinSen = _optionalInt(row, 'salary_min_sen'),
      salaryMaxSen = _optionalInt(row, 'salary_max_sen'),
      payableHours = _optionalNumber(row, 'payable_hours'),
      calculatedMinSen = _optionalInt(row, 'calculated_min_sen'),
      calculatedMaxSen = _optionalInt(row, 'calculated_max_sen'),
      proposalId = _optionalUuid(row, 'proposal_id'),
      proposalVersion = _optionalInt(row, 'proposal_version'),
      proposedBaseSen = _optionalInt(row, 'proposed_base_sen'),
      proposalStatus = _optionalOneOf(row, 'proposal_status', const {
        'pending',
        'declined',
        'confirmed',
      }),
      confirmedBaseSen = _optionalInt(row, 'confirmed_base_sen'),
      paymentId = _optionalUuid(row, 'payment_id'),
      bonusSen = _int(row, 'bonus_sen'),
      paymentStatus = _optionalOneOf(row, 'payment_status', const {
        'demo_recorded',
      }),
      recordedAt = _optionalText(row, 'recorded_at'),
      blockingReason = _optionalText(row, 'blocking_reason') {
    if (row.keys.toSet().difference(_keys).isNotEmpty ||
        row.keys.toSet().length != _keys.length ||
        !row.keys.toSet().containsAll(_keys) ||
        salaryMinSen != null &&
            salaryMaxSen != null &&
            salaryMinSen! > salaryMaxSen! ||
        calculatedMinSen != null &&
            calculatedMaxSen != null &&
            calculatedMinSen! > calculatedMaxSen! ||
        (proposalId == null) != (proposalVersion == null) ||
        (proposalId == null) != (proposedBaseSen == null) ||
        (proposalId == null) != (proposalStatus == null) ||
        confirmedBaseSen != null &&
            (proposalStatus != 'confirmed' ||
                confirmedBaseSen != proposedBaseSen) ||
        proposalStatus == 'confirmed' && confirmedBaseSen == null ||
        (paymentId == null) != (paymentStatus == null) ||
        (paymentId == null) != (recordedAt == null) ||
        paymentId != null && confirmedBaseSen == null) {
      throw const FormatException('Invalid payment settlement response.');
    }
    if (recordedAt != null && DateTime.tryParse(recordedAt!) == null) {
      throw const FormatException('Invalid payment field: recorded_at.');
    }
  }

  static const _keys = {
    'application_id',
    'job_title',
    'company_name',
    'worker_name',
    'employment_type',
    'salary_period',
    'offer_id',
    'offer_version',
    'salary_min_sen',
    'salary_max_sen',
    'payable_hours',
    'calculated_min_sen',
    'calculated_max_sen',
    'proposal_id',
    'proposal_version',
    'proposed_base_sen',
    'proposal_status',
    'confirmed_base_sen',
    'payment_id',
    'bonus_sen',
    'payment_status',
    'recorded_at',
    'blocking_reason',
  };

  final String applicationId, jobTitle, companyName, workerName;
  final String employmentType, salaryPeriod, offerId;
  final int offerVersion, bonusSen;
  final int? salaryMinSen, salaryMaxSen;
  final double? payableHours;
  final int? calculatedMinSen, calculatedMaxSen, proposalVersion;
  final String? proposalId, proposalStatus, paymentId, paymentStatus;
  final String? recordedAt, blockingReason;
  final int? proposedBaseSen, confirmedBaseSen;

  bool get canPropose =>
      blockingReason == null &&
      salaryMinSen != null &&
      salaryMaxSen != null &&
      calculatedMinSen != null &&
      calculatedMaxSen != null &&
      proposalStatus != 'pending' &&
      proposalStatus != 'confirmed' &&
      paymentId == null;

  bool get canReject =>
      proposalId != null && proposalStatus == 'pending' && paymentId == null;

  bool get canConfirm =>
      canReject &&
      blockingReason == null &&
      payableHours != null &&
      salaryMinSen != null &&
      salaryMaxSen != null &&
      calculatedMinSen != null &&
      calculatedMaxSen != null &&
      proposedBaseSen != null &&
      proposedBaseSen! >= calculatedMinSen! &&
      proposedBaseSen! <= calculatedMaxSen!;

  bool get canRecordDemoPayment =>
      confirmedBaseSen != null && paymentId == null && blockingReason == null;

  int? get totalSen =>
      confirmedBaseSen == null ? null : confirmedBaseSen! + bonusSen;

  static String _uuid(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        ).hasMatch(value)) {
      throw FormatException('Invalid payment field: $key.');
    }
    return value;
  }

  static String? _optionalUuid(Map<String, dynamic> row, String key) =>
      row[key] == null ? null : _uuid(row, key);

  static String _text(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid payment field: $key.');
    }
    return value;
  }

  static String? _optionalText(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid payment field: $key.');
    }
    return value;
  }

  static String _oneOf(
    Map<String, dynamic> row,
    String key,
    Set<String> allowed,
  ) {
    final value = _text(row, key);
    if (!allowed.contains(value)) {
      throw FormatException('Invalid payment field: $key.');
    }
    return value;
  }

  static String? _optionalOneOf(
    Map<String, dynamic> row,
    String key,
    Set<String> allowed,
  ) {
    if (row[key] == null) return null;
    return _oneOf(row, key, allowed);
  }

  static int _int(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! int || value < 0 || value > 999999999999) {
      throw FormatException('Invalid payment field: $key.');
    }
    return value;
  }

  static int _positiveInt(Map<String, dynamic> row, String key) {
    final value = _int(row, key);
    if (value < 1) throw FormatException('Invalid payment field: $key.');
    return value;
  }

  static int? _optionalInt(Map<String, dynamic> row, String key) =>
      row[key] == null ? null : _int(row, key);

  static double? _optionalNumber(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return null;
    if (value is! num || !value.isFinite || value < 0) {
      throw FormatException('Invalid payment field: $key.');
    }
    return value.toDouble();
  }
}

abstract interface class ApplicationPaymentSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<List<ApplicationPaymentSummary>> list();
  Future<void> propose(ApplicationPaymentSummary summary, int amountSen);
  Future<void> respond(
    ApplicationPaymentSummary summary, {
    required bool accept,
  });
  Future<void> recordDemoPayment(
    ApplicationPaymentSummary summary,
    int bonusSen,
  );
}

class SupabaseApplicationPaymentSource implements ApplicationPaymentSource {
  SupabaseApplicationPaymentSource(this.client);
  final SupabaseClient client;

  // Reuse a request ID after a transport failure: the server may already have
  // committed the operation. IDs are scoped to the actor and exact payload.
  // An acknowledged RPC result retires the ID; a failed/unknown result keeps it.
  final Map<String, String> _pendingRequestIds = {};

  String _requestId(String key) =>
      _pendingRequestIds.putIfAbsent(key, () => const Uuid().v4());

  @override
  String? get userId => client.auth.currentUser?.id;

  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);

  void _assertSameActor(String? actor) {
    if (actor == null || userId != actor) {
      throw StateError('Your session changed. Refresh Payment Handling.');
    }
  }

  @override
  Future<List<ApplicationPaymentSummary>> list() async {
    final actor = userId;
    _assertSameActor(actor);
    final response = await client.rpc('list_my_payment_settlements_v1');
    _assertSameActor(actor);
    if (response is! List) {
      throw const FormatException('Invalid payment settlement list.');
    }
    return response
        .map(
          (row) => ApplicationPaymentSummary.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> propose(ApplicationPaymentSummary summary, int amountSen) async {
    final actor = userId;
    _assertSameActor(actor);
    final requestKey =
        'propose:$actor:${summary.applicationId}:${summary.offerId}:${summary.offerVersion}:$amountSen';
    await client.rpc(
      'propose_application_final_salary_v1',
      params: {
        'p_application_id': summary.applicationId,
        'p_offer_id': summary.offerId,
        'p_offer_version': summary.offerVersion,
        'p_request_id': _requestId(requestKey),
        'p_amount_sen': amountSen,
      },
    );
    _assertSameActor(actor);
    _pendingRequestIds.remove(requestKey);
  }

  @override
  Future<void> respond(
    ApplicationPaymentSummary summary, {
    required bool accept,
  }) async {
    final actor = userId;
    _assertSameActor(actor);
    final proposalId = summary.proposalId;
    final amountSen = summary.proposedBaseSen;
    if (proposalId == null || amountSen == null) {
      throw StateError(
        'Refresh the current salary proposal before responding.',
      );
    }
    final requestKey =
        'respond:$actor:${summary.applicationId}:$proposalId:$accept:$amountSen';
    await client.rpc(
      'respond_application_final_salary_v1',
      params: {
        'p_application_id': summary.applicationId,
        'p_proposal_id': proposalId,
        'p_request_id': _requestId(requestKey),
        'p_accept': accept,
        'p_amount_sen': amountSen,
      },
    );
    _assertSameActor(actor);
    _pendingRequestIds.remove(requestKey);
  }

  @override
  Future<void> recordDemoPayment(
    ApplicationPaymentSummary summary,
    int bonusSen,
  ) async {
    final actor = userId;
    _assertSameActor(actor);
    final requestKey = 'record:$actor:${summary.applicationId}:$bonusSen';
    await client.rpc(
      'record_demo_application_payment_v1',
      params: {
        'p_application_id': summary.applicationId,
        'p_request_id': _requestId(requestKey),
        'p_bonus_sen': bonusSen,
      },
    );
    _assertSameActor(actor);
    _pendingRequestIds.remove(requestKey);
  }
}

class ApplicationPaymentRepository extends ChangeNotifier {
  ApplicationPaymentRepository(this.source) : _actor = source.userId {
    _subscription = source.accountChanges.listen(_onAccountChange);
  }

  final ApplicationPaymentSource source;
  late final StreamSubscription<String?> _subscription;
  String? _actor;
  int _generation = 0;
  bool _disposed = false;
  bool loading = false;
  String? error;
  List<ApplicationPaymentSummary> summaries = const [];

  void _onAccountChange(String? actor) {
    if (actor == _actor) return;
    _actor = actor;
    _generation++;
    summaries = const [];
    loading = false;
    error = actor == null ? 'Sign in to view Payment Handling.' : null;
    notifyListeners();
    if (actor != null) load();
  }

  Future<void> load() async {
    if (_disposed) return;
    final actor = source.userId;
    final generation = ++_generation;
    summaries = const [];
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (actor == null) throw StateError('Sign in to view Payment Handling.');
      final result = await source.list();
      if (generation != _generation || source.userId != actor) return;
      summaries = result;
    } catch (failure) {
      if (generation != _generation || source.userId != actor) return;
      error = failure is StateError
          ? failure.message.toString()
          : failure is PostgrestException && failure.code == '42501'
          ? 'Payment access is not available for this account.'
          : 'Unable to load Payment Handling. Please retry.';
    } finally {
      if (generation == _generation && source.userId == actor) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> mutate(
    Future<void> Function() action, {
    String? expectedActor,
  }) async {
    final actor = source.userId;
    final generation = _generation;
    if (_disposed || actor == null) {
      throw StateError('Sign in before changing this payment.');
    }
    if (expectedActor != null && expectedActor != actor) {
      throw StateError('Your account changed. Refresh Payment Handling.');
    }
    try {
      await action();
    } catch (_) {
      if (!_disposed && generation == _generation && actor == source.userId) {
        summaries = const [];
        error = 'The update could not be confirmed. Refresh payments before trying again.';
        notifyListeners();
      }
      rethrow;
    }
    if (_disposed || generation != _generation || actor != source.userId) {
      throw StateError('Your account changed. Refresh Payment Handling.');
    }
    await load();
    if (_disposed || actor != source.userId) {
      throw StateError('Your account changed. Refresh Payment Handling.');
    }
    if (error != null) {
      throw StateError(
        'The change was saved, but the latest payment status could not be loaded. '
        'Refresh payments before taking another action.',
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _subscription.cancel();
    super.dispose();
  }
}
