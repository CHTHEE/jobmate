import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'compensation_offer.dart';

enum MyApplicationStatus {
  submitted('Applied'),
  shortlisted('Shortlisted'),
  interview('Interview'),
  offered('Offered'),
  hired('Hired'),
  rejected('Rejected'),
  declined('Declined'),
  withdrawn('Withdrawn');

  const MyApplicationStatus(this.label);
  final String label;
  bool get completed =>
      const [hired, rejected, declined, withdrawn].contains(this);

  /// Recruitment state only: Hired does not mean the worker's shifts are done.
  String? get lifecycleExplanation => switch (this) {
    offered => 'The worker can accept or decline this offer before hiring. Withdrawal remains a separate pre-hire action.',
    hired => 'This application is Hired. Withdrawal and offer decline are unavailable after hiring. Work shifts and their records are managed separately. Ending a hired arrangement is not supported by the current workflow.',
    declined => 'The worker declined the offer before hiring. This is separate from withdrawing an application.',
    withdrawn => 'The worker withdrew the application before hiring. This is separate from declining an offer.',
    _ => null,
  };
}

enum ApplicationResponseAction {
  acceptOffer('accept_offer', 'Accept Offer', MyApplicationStatus.hired),
  declineOffer('decline_offer', 'Decline Offer', MyApplicationStatus.declined),
  withdraw('withdraw', 'Withdraw Application', MyApplicationStatus.withdrawn);

  const ApplicationResponseAction(this.wireName, this.label, this.result);
  final String wireName;
  final String label;
  final MyApplicationStatus result;
  String get confirmationMessage => switch (this) {
    acceptOffer => 'Accept this offer and change the application status to Hired? After hiring, you cannot withdraw the application or decline this offer. Work shifts are managed separately.',
    declineOffer => 'Decline this offer before hiring and change the application status to Declined? This does not withdraw the application or cancel a hired arrangement. The current workflow cannot undo this decision.',
    withdraw => 'Withdraw this application before hiring and change its status to Withdrawn? This is separate from declining an offer or ending a hired arrangement. Withdrawal is final and cannot be undone through the current workflow.',
  };
  bool allowed(MyApplicationStatus status) => this == withdraw
      ? const [
          MyApplicationStatus.submitted,
          MyApplicationStatus.shortlisted,
          MyApplicationStatus.interview,
          MyApplicationStatus.offered,
        ].contains(status)
      : status == MyApplicationStatus.offered;
}

/// The ten-column projection returned by list_my_job_applications.
class MyJobApplication {
  MyJobApplication(Map<String, dynamic> row)
    : fields = Map.unmodifiable(row),
      id = _requiredText(row, 'application_id'),
      jobId = _requiredText(row, 'job_id'),
      jobTitle = _requiredText(row, 'job_title'),
      companyName = _requiredText(row, 'company_name'),
      resumeId = row['resume_id'] as String?,
      coverNote = row['cover_note'] as String?,
      appliedAt = DateTime.parse(_requiredText(row, 'applied_at')),
      updatedAt = DateTime.parse(_requiredText(row, 'updated_at')),
      withdrawnAt = row['withdrawn_at'] == null
          ? null
          : DateTime.parse(row['withdrawn_at'] as String),
      status = MyApplicationStatus.values.firstWhere(
        (status) => status.name == row['status'],
        orElse: () =>
            throw const FormatException('Unrecognized application status.'),
      );
  final Map<String, dynamic> fields;
  final String id, jobId;
  final String jobTitle, companyName;
  final String? resumeId, coverNote;
  final DateTime appliedAt, updatedAt;
  final DateTime? withdrawnAt;
  final MyApplicationStatus status;

  static String _requiredText(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('Missing application field: $key.');
    }
    return value;
  }
}

abstract class MyApplicationsSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<List<Map<String, dynamic>>> list();
  Future<List<Map<String, dynamic>>> history(String applicationId);
  Future<String> respond(String applicationId, String action);
  Future<Map<String, dynamic>?> currentCompensationOffer(String applicationId);
  Future<void> acceptCompensationOffer(
    String applicationId,
    String offerId,
    int offerVersion,
  );
}

typedef MyApplicationSnapshot = ({
  List<Map<String, dynamic>> rows,
  bool complete,
});

abstract interface class CompleteMyApplicationsSource {
  Future<MyApplicationSnapshot> listSnapshot();
}

/// Marker for transports that send the exact versioned Offer identity.
/// Wrappers with additional acceptance side effects must opt in explicitly.
abstract interface class ExactVersionCompensationOfferSource {
  Future<void> acceptCompensationOffer(
    String applicationId,
    String offerId,
    int offerVersion,
  );
}

class SupabaseMyApplicationsSource
    implements
        MyApplicationsSource,
        ExactVersionCompensationOfferSource,
        CompleteMyApplicationsSource {
  SupabaseMyApplicationsSource(this.client);
  final SupabaseClient client;
  @override
  Future<String> respond(String applicationId, String action) async {
    if (!ApplicationResponseAction.values.any(
      (value) => value.wireName == action,
    )) {
      throw StateError('This application action is unavailable.');
    }
    if (action == ApplicationResponseAction.acceptOffer.wireName) {
      final actor = userId;
      final versionedOffer = await currentCompensationOffer(applicationId);
      if (userId != actor) {
        throw StateError('Your session changed. Refresh the application.');
      }
      if (versionedOffer != null) {
        throw StateError(
          'Accept this Offer using its exact displayed version.',
        );
      }
    }
    final result = await client.rpc(
      'respond_to_job_application',
      params: {'p_application_id': applicationId, 'p_action': action},
    );
    if (result is! String) {
      throw const FormatException('Invalid application response.');
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>?> currentCompensationOffer(
    String applicationId,
  ) async {
    final result = await client.rpc(
      'get_my_current_application_compensation_offer_v1',
      params: {'p_application_id': applicationId},
    );
    if (result == null) return null;
    if (result is! Map) {
      throw const FormatException('Invalid compensation offer response.');
    }
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<void> acceptCompensationOffer(
    String applicationId,
    String offerId,
    int offerVersion,
  ) async {
    final result = await client.rpc(
      'accept_application_compensation_offer_v1',
      params: {
        'p_application_id': applicationId,
        'p_offer_id': offerId,
        'p_offer_version': offerVersion,
      },
    );
    if (result is! Map ||
        result['application_id'] != applicationId ||
        result['offer_id'] != offerId ||
        result['offer_version'] != offerVersion ||
        result['status'] != 'hired' ||
        result['accepted'] != true) {
      throw const FormatException('Invalid compensation acceptance response.');
    }
  }

  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);
  @override
  Future<List<Map<String, dynamic>>> list() async {
    final rows = await client.rpc('list_my_job_applications');
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  @override
  Future<MyApplicationSnapshot> listSnapshot() async {
    final actor = userId;
    final rows = <Map<String, dynamic>>[];
    final ids = <String>{};
    int? total;
    while (total == null || rows.length < total) {
      if (actor == null || actor != userId) {
        throw StateError('Your session changed. Refresh your applications.');
      }
      try {
        final page = await client
            .rpc<List<dynamic>>('list_my_job_applications')
            .order('application_id', ascending: true)
            .range(rows.length, rows.length + 199)
            .count(CountOption.exact);
        if (total != null && total != page.count) break;
        total = page.count;
        if (page.data.isEmpty) break;
        final batch = page.data
            .cast<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        if (batch.any((row) {
              final id = row['application_id'];
              return id is! String || id.isEmpty || !ids.add(id);
            }) ||
            rows.length + batch.length > total) {
          return (rows: rows, complete: false);
        }
        rows.addAll(batch);
      } on TypeError {
        // A missing or unreadable Content-Range cannot prove completeness.
        if (total == null && actor == userId) {
          return (rows: await list(), complete: false);
        }
        break;
      }
    }
    return (rows: rows, complete: total == rows.length);
  }

  @override
  Future<List<Map<String, dynamic>>> history(String applicationId) async {
    final rows = await client.rpc(
      'list_application_history',
      params: {'p_application_id': applicationId},
    );
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}

class ApplicationHistoryEvent {
  ApplicationHistoryEvent(Map<String, dynamic> row)
    : id = row['history_id'] as String,
      previousStatus = row['previous_status'] == null
          ? null
          : _status(row['previous_status']),
      newStatus = _status(row['new_status']),
      changedBy = row['changed_by'] as String?,
      changedByName = row['changed_by_name'] as String?,
      note = row['note'] as String?,
      changedAt = DateTime.parse(row['changed_at'] as String);
  final String id;
  final MyApplicationStatus? previousStatus;
  final MyApplicationStatus newStatus;
  final String? changedBy, changedByName, note;
  final DateTime changedAt;
  static MyApplicationStatus _status(dynamic value) =>
      MyApplicationStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () =>
            throw const FormatException('Unrecognized history status.'),
      );
}

/// Per-route details: ownership is established from the seeker's RPC list before
/// requesting history, including on direct URLs and after an account switch.
class MyApplicationDetailsRepository extends ChangeNotifier {
  MyApplicationDetailsRepository(
    this.source,
    this.applicationId, {
    this.compensationOffersEnabled = p03CompensationOffersEnabled,
  }) : _actor = source.userId {
    _subscription = source.accountChanges.listen((id) {
      if (id == _actor) return;
      _clear();
      if (id != null) load();
    });
  }
  final MyApplicationsSource source;
  final bool compensationOffersEnabled;
  final String applicationId;
  late final StreamSubscription<String?> _subscription;
  String? _actor;
  int _generation = 0, _historyRequest = 0;
  bool _disposed = false;
  bool loading = true, historyLoading = false;
  bool responding = false;
  String? responseError;
  bool offerLoading = false;
  String? offerError;
  CompensationOffer? _compensationOffer;
  CompensationOffer? get compensationOffer =>
      source.userId == _actor ? _compensationOffer : null;
  bool get canAcceptOffer =>
      !offerLoading &&
      offerError == null &&
      (compensationOffer == null ||
          compensationOffersEnabled &&
              source is ExactVersionCompensationOfferSource);
  int _sessionVersion = 0;
  int get sessionVersion => _sessionVersion;

  /// Identifies each authoritative application read, including fast refreshes.
  int get applicationReadVersion => _generation;
  bool currentSession(int version) =>
      !_disposed &&
      version == _sessionVersion &&
      _actor != null &&
      source.userId == _actor;
  String? error, historyError;
  MyJobApplication? _application;
  List<ApplicationHistoryEvent> _history = [];
  MyJobApplication? get application =>
      source.userId == _actor ? _application : null;
  List<ApplicationHistoryEvent> get events =>
      source.userId == _actor ? List.unmodifiable(_history) : const [];
  bool _current(int generation, String? actor) =>
      !_disposed && generation == _generation && source.userId == actor;

  void _clear() {
    ++_sessionVersion;
    responding = false;
    responseError = null;
    ++_generation;
    ++_historyRequest;
    _actor = source.userId;
    _application = null;
    _history = [];
    _compensationOffer = null;
    offerLoading = false;
    offerError = null;
    loading = false;
    historyLoading = false;
    historyError = null;
    error = 'Your session changed. Refresh to view this application.';
    notifyListeners();
  }

  Future<void> load() async {
    if (responding) return;
    await _load();
  }

  Future<void> _load() async {
    if (_disposed) return;
    if (source.userId != _actor) _clear();
    final generation = ++_generation;
    final actor = _actor;
    _application = null;
    _history = [];
    _compensationOffer = null;
    offerLoading = false;
    offerError = null;
    loading = true;
    historyLoading = false;
    error = null;
    historyError = null;
    notifyListeners();
    try {
      if (actor == null) throw StateError('Sign in to view this application.');
      final rows = await source.list();
      if (!_current(generation, actor)) return;
      final row = rows
          .where((row) => row['application_id'] == applicationId)
          .firstOrNull;
      _application = row == null ? null : MyJobApplication(row);
      loading = false;
      await loadCompensationOffer();
      if (_application != null) await loadHistory();
    } catch (_) {
      if (!_current(generation, actor)) return;
      loading = false;
      error = 'Unable to load this application. Please retry.';
      notifyListeners();
    }
  }

  Future<void> loadCompensationOffer() async {
    if (_disposed) return;
    final selected = application;
    _compensationOffer = null;
    offerError = null;
    // Pending offers still need classification when versioned actions are off.
    if (selected?.status != MyApplicationStatus.offered &&
        !(compensationOffersEnabled &&
            selected?.status == MyApplicationStatus.hired)) {
      offerLoading = false;
      notifyListeners();
      return;
    }
    final status = selected!.status;
    final generation = _generation, actor = _actor;
    offerLoading = true;
    notifyListeners();
    try {
      final row = await source.currentCompensationOffer(applicationId);
      if (!_current(generation, actor)) return;
      if (row != null) {
        final offer = CompensationOffer.fromJson(row);
        if (offer.applicationId != applicationId ||
            status == MyApplicationStatus.offered &&
                (!offer.isCurrent || offer.isAccepted) ||
            status == MyApplicationStatus.hired && !offer.isAccepted) {
          throw const FormatException(
            'Offer does not match this application state.',
          );
        }
        _compensationOffer = offer;
      }
    } catch (_) {
      if (!_current(generation, actor)) return;
      offerError =
          'Unable to verify the current Offer. Refresh before responding.';
    } finally {
      if (_current(generation, actor)) {
        offerLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> respond(MyJobApplication selected, String action) async {
    final version = _sessionVersion;
    final choice = ApplicationResponseAction.values
        .where((a) => a.wireName == action)
        .firstOrNull;
    if (!currentSession(version) ||
        responding ||
        loading ||
        choice == ApplicationResponseAction.acceptOffer && !canAcceptOffer ||
        application?.id != selected.id ||
        application?.status != selected.status ||
        choice == null ||
        !choice.allowed(selected.status)) {
      throw StateError('This action is unavailable. Refresh the application.');
    }
    responding = true;
    responseError = null;
    notifyListeners();
    Object? failure;
    try {
      // Display status from the subsequent owned application read; the RPC
      // contract does not prescribe the contents of its text acknowledgement.
      if (choice == ApplicationResponseAction.acceptOffer &&
          compensationOffersEnabled &&
          _compensationOffer != null) {
        if (source is! ExactVersionCompensationOfferSource) {
          throw StateError(
            'Exact-version acceptance is unavailable with this hiring workflow.',
          );
        }
        final offer = _compensationOffer!;
        await (source as ExactVersionCompensationOfferSource)
            .acceptCompensationOffer(
              applicationId,
              offer.offerId,
              offer.version,
            );
      } else {
        await source.respond(applicationId, action);
      }
    } catch (error) {
      failure = error;
    }
    if (!currentSession(version)) return;
    // Reconcile success and conflicts with authoritative status and history.
    // Keep the mutation locked throughout this refresh.
    await _load();
    if (!currentSession(version)) return;
    responding = false;
    if (failure != null) {
      responseError = failure is PostgrestException && failure.code == '42501'
          ? 'Application access denied. Check your signed-in account.'
          : 'Unable to confirm this action. Review the refreshed status before retrying.';
    }
    notifyListeners();
  }

  Future<void> loadHistory() async {
    if (_disposed || application == null || loading) return;
    final generation = _generation, request = ++_historyRequest;
    final actor = _actor;
    historyLoading = true;
    historyError = null;
    _history = [];
    notifyListeners();
    try {
      final rows = await source.history(applicationId);
      if (!_current(generation, actor) || request != _historyRequest) return;
      final events = rows.map(ApplicationHistoryEvent.new).toList();
      // The RPC supplies oldest-first ordering; retain it without inferred events.
      _history = events;
    } catch (_) {
      if (!_current(generation, actor) || request != _historyRequest) return;
      historyError = 'Unable to load status history. Please retry.';
    } finally {
      if (_current(generation, actor) && request == _historyRequest) {
        historyLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_sessionVersion;
    ++_generation;
    ++_historyRequest;
    _subscription.cancel();
    super.dispose();
  }
}

class MyApplicationsRepository extends ChangeNotifier {
  MyApplicationsRepository(this.source, {this.verifyCompleteness = false})
    : _actorId = source.userId {
    _subscription = source.accountChanges.listen((id) {
      if (id == _actorId) return;
      reset();
      if (id != null) load();
    });
  }
  final MyApplicationsSource source;
  final bool verifyCompleteness;
  bool _complete = false;
  bool get complete => loaded && source.userId == _actorId && _complete;
  late final StreamSubscription<String?> _subscription;
  String? _actorId;
  int _generation = 0;
  bool _disposed = false;
  bool loading = false, loaded = false;
  String? error;
  final List<MyJobApplication> _applications = [];
  List<MyJobApplication> get applications =>
      source.userId == _actorId ? List.unmodifiable(_applications) : const [];

  List<MyJobApplication> search({
    String query = '',
    String tab = 'All',
    String status = '',
    String sort = 'Newest',
  }) {
    final rows = applications
        .where(
          (a) =>
              '${a.jobTitle} ${a.companyName}'.toLowerCase().contains(
                query.trim().toLowerCase(),
              ) &&
              (status.isEmpty || a.status.name == status) &&
              (tab == 'All' ||
                  (tab == 'Completed'
                      ? a.status.completed
                      : !a.status.completed)),
        )
        .toList();
    rows.sort((a, b) {
      final byDate = a.appliedAt.compareTo(b.appliedAt);
      final order = byDate == 0 ? a.id.compareTo(b.id) : byDate;
      return sort == 'Oldest' ? order : -order;
    });
    return rows;
  }

  Future<void> load() async {
    if (_disposed) return;
    if (source.userId != _actorId) reset();
    if (loading) return;
    final actor = source.userId;
    final generation = ++_generation;
    _applications.clear();
    _complete = false;
    loading = true;
    loaded = false;
    error = null;
    notifyListeners();
    try {
      if (actor == null) throw StateError('Sign in to view your applications.');
      final reader = source;
      final snapshot =
          verifyCompleteness && reader is CompleteMyApplicationsSource
          ? await (reader as CompleteMyApplicationsSource).listSnapshot()
          : (rows: await reader.list(), complete: false);
      if (_disposed || generation != _generation || source.userId != actor) {
        return;
      }
      final applications = snapshot.rows.map(MyJobApplication.new).toList();
      _applications.addAll(applications);
      _complete = snapshot.complete;
      loaded = true;
    } catch (failure) {
      if (_disposed || generation != _generation || source.userId != actor) {
        return;
      }
      error = failure is StateError
          ? failure.message.toString()
          : failure is PostgrestException && failure.code == '42501'
          ? 'An active Job Seeker account is required to view applications.'
          : 'Unable to load applications. Please retry.';
    } finally {
      if (!_disposed && generation == _generation) {
        if (source.userId != actor) {
          reset();
        } else {
          loading = false;
          notifyListeners();
        }
      }
    }
  }

  void reset() {
    ++_generation;
    _actorId = source.userId;
    _applications.clear();
    _complete = false;
    loading = false;
    loaded = false;
    error = 'Your session changed. Refresh your applications.';
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _subscription.cancel();
    super.dispose();
  }
}
