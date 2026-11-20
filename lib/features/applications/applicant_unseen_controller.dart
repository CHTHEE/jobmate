import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'applicant_notification_repository.dart';

/// Capture before loading a selected job's applicants. Only the page can
/// establish that those results are still current and were actually displayed.
class ApplicantDisplayScope {
  ApplicantDisplayScope._(this._session, this._jobId);

  final Object _session;
  final String _jobId;
}

class ApplicantUnseenController extends ChangeNotifier
    with WidgetsBindingObserver {
  ApplicantUnseenController(
    this._repository, {
    required String? Function() currentUserId,
    required Stream<String?> accountChanges,
  }) : _currentUserId = currentUserId,
       _actor = currentUserId() {
    _accountSubscription = accountChanges.listen(_accountChanged);
  }

  static final _sessions = Expando<ApplicantUnseenController>();

  /// The app's Supabase client owns a single controller across employer routes.
  static ApplicantUnseenController session(SupabaseClient client) {
    return _sessions[client] ??= ApplicantUnseenController(
      ApplicantNotificationRepository(client),
      currentUserId: () => client.auth.currentUser?.id,
      accountChanges: client.auth.onAuthStateChange.map(
        (e) => e.session?.user.id,
      ),
    ).._observeLifecycle();
  }

  final ApplicantNotificationRepository _repository;
  final String? Function() _currentUserId;
  late final StreamSubscription<String?> _accountSubscription;
  String? _actor;
  String? _companyId;
  Object _session = Object();
  int _request = 0;
  Map<String, int> _counts = const {};
  Future<void>? _refreshing;
  bool _failed = false;
  bool _disposed = false;
  bool _observing = false;

  bool get _active =>
      !_disposed &&
      _companyId != null &&
      _actor != null &&
      _actor == _currentUserId();
  Map<String, int> get counts => _active ? _counts : const {};
  bool get hasUnseen => counts.values.any((count) => count > 0);
  int countFor(String jobId) => counts[jobId.toLowerCase()] ?? 0;
  bool get loading => _active && _refreshing != null;
  bool get refreshFailed => _active && _failed;

  void _observeLifecycle() {
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  void _reset() {
    _session = Object();
    ++_request;
    _counts = const {};
    _refreshing = null;
    _failed = false;
    notifyListeners();
  }

  void _accountChanged(String? actor) {
    if (_disposed || actor == _actor) return;
    _actor = actor;
    _companyId = null;
    _reset();
  }

  /// Called with the company from an existing authorized workspace read.
  /// Counts themselves are grouped across all companies authorized by the RPC.
  void enterWorkspace({
    required String? accountId,
    required String? companyId,
  }) {
    if (_disposed || accountId != _currentUserId()) return;
    _accountChanged(accountId);
    if (_companyId != companyId) {
      _companyId = accountId == null ? null : companyId;
      _reset();
    }
    unawaited(refresh());
  }

  Future<void> refresh() => _refresh();

  Future<void> _refresh({bool supersede = false}) {
    if (!_active) return Future.value();
    final pending = _refreshing;
    if (!supersede && pending != null) return pending;
    final request = ++_request;
    final done = Completer<void>();
    _refreshing = done.future;
    _failed = false;
    unawaited(_load(request, done));
    notifyListeners();
    return done.future;
  }

  Future<void> _load(int request, Completer<void> done) async {
    bool current() => _active && _request == request;
    try {
      final counts = await _repository.listUnseenCounts();
      if (current()) _counts = counts;
    } catch (_) {
      if (current()) _failed = true;
    } finally {
      if (current()) {
        _refreshing = null;
        notifyListeners();
      }
      done.complete();
    }
  }

  ApplicantDisplayScope? beginApplicantLoad(
    String? selectedJobId, {
    String? companyId,
  }) {
    if (!_active ||
        selectedJobId == null ||
        (companyId != null && companyId != _companyId)) {
      return null;
    }
    try {
      return ApplicantDisplayScope._(
        _session,
        ApplicantNotificationRepository.jobId(selectedJobId),
      );
    } on FormatException {
      return null;
    }
  }

  /// The caller must pass IDs from the rendered result and verify that the
  /// result is still the current successful load for this selected job.
  Future<int> acknowledgeDisplayed(
    ApplicantDisplayScope scope,
    List<String> displayedIds, {
    required bool Function() isCurrentDisplay,
    void Function(List<String>)? onBatchSent,
  }) async {
    bool current() => _active && identical(scope._session, _session);
    final ids = displayedIds.toSet().toList(growable: false);
    var inserted = 0;
    var succeeded = false;
    try {
      for (var start = 0; start < ids.length; start += 100) {
        if (!current() || !isCurrentDisplay() || !current()) {
          throw StateError(
            'The displayed applicant list is no longer current.',
          );
        }
        final batch = ids.sublist(start, math.min(start + 100, ids.length));
        final result = _repository.acknowledge(scope._jobId, batch);
        onBatchSent?.call(batch);
        inserted += await result;
        succeeded = true;
      }
    } finally {
      if (succeeded && current()) await _refresh(supersede: true);
    }
    if (!current()) {
      throw StateError('The employer workspace changed during acknowledgment.');
    }
    return inserted;
  }

  @override
  void dispose() {
    _disposed = true;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    unawaited(_accountSubscription.cancel());
    super.dispose();
  }
}
