import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
}

enum ApplicationResponseAction {
  acceptOffer('accept_offer', 'Accept Offer', MyApplicationStatus.hired),
  declineOffer('decline_offer', 'Decline Offer', MyApplicationStatus.declined),
  withdraw('withdraw', 'Withdraw Application', MyApplicationStatus.withdrawn);

  const ApplicationResponseAction(this.wireName, this.label, this.result);
  final String wireName;
  final String label;
  final MyApplicationStatus result;
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
}

class SupabaseMyApplicationsSource implements MyApplicationsSource {
  SupabaseMyApplicationsSource(this.client);
  final SupabaseClient client;
  @override
  Future<String> respond(String applicationId, String action) async {
    if (!ApplicationResponseAction.values.any(
      (value) => value.wireName == action,
    )) {
      throw StateError('This application action is unavailable.');
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
  MyApplicationDetailsRepository(this.source, this.applicationId)
    : _actor = source.userId {
    _subscription = source.accountChanges.listen((id) {
      if (id == _actor) return;
      _clear();
      if (id != null) load();
    });
  }
  final MyApplicationsSource source;
  final String applicationId;
  late final StreamSubscription<String?> _subscription;
  String? _actor;
  int _generation = 0, _historyRequest = 0;
  bool _disposed = false;
  bool loading = true, historyLoading = false;
  bool responding = false;
  String? responseError;
  int _sessionVersion = 0;
  int get sessionVersion => _sessionVersion;
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
      notifyListeners();
      if (_application != null) await loadHistory();
    } catch (_) {
      if (!_current(generation, actor)) return;
      loading = false;
      error = 'Unable to load this application. Please retry.';
      notifyListeners();
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
      await source.respond(applicationId, action);
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
  MyApplicationsRepository(this.source) : _actorId = source.userId {
    _subscription = source.accountChanges.listen((id) {
      if (id == _actorId) return;
      reset();
      if (id != null) load();
    });
  }
  final MyApplicationsSource source;
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
    loading = true;
    loaded = false;
    error = null;
    notifyListeners();
    try {
      if (actor == null) throw StateError('Sign in to view your applications.');
      final rows = await source.list();
      if (_disposed || generation != _generation || source.userId != actor) {
        return;
      }
      final applications = rows.map(MyJobApplication.new).toList();
      _applications.addAll(applications);
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
