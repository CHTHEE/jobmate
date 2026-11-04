import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JobMateNotification {
  JobMateNotification(Map<String, dynamic> row)
    : id = row['notification_id'] as String,
      type = row['notification_type'] as String,
      title = row['title'] as String,
      message = row['message'] as String,
      createdAt = DateTime.parse(row['created_at'] as String),
      readAt = row['read_at'] == null
          ? null
          : DateTime.parse(row['read_at'] as String);
  final String id, type, title, message;
  final DateTime createdAt;
  final DateTime? readAt;
  bool get read => readAt != null;
}

abstract class NotificationsSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<List<Map<String, dynamic>>> list();
  Future<bool> markRead(String notificationId);
}

class SupabaseNotificationsSource implements NotificationsSource {
  SupabaseNotificationsSource(this.client);
  final SupabaseClient client;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);
  @override
  Future<List<Map<String, dynamic>>> list() async {
    // Both keys are required to disambiguate the deployed defaulted overloads.
    final rows = await client.rpc(
      'list_my_notifications',
      params: {'p_limit': 50, 'p_offset': 0},
    );
    return (rows as List)
        .take(50)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  @override
  Future<bool> markRead(String notificationId) async {
    final result = await client.rpc(
      'mark_notification_read',
      params: {'p_notification_id': notificationId},
    );
    if (result is! bool) {
      throw const FormatException('Invalid mark-read response');
    }
    return result;
  }
}

class NotificationsRepository extends ChangeNotifier {
  NotificationsRepository(this.source) : _actor = source.userId {
    _subscription = source.accountChanges.listen((id) {
      if (id == _actor) return;
      _reset();
      if (id != null) load();
    });
  }
  final NotificationsSource source;
  late final StreamSubscription<String?> _subscription;
  String? _actor;
  int _generation = 0, _request = 0;
  bool _disposed = false;
  bool loading = true;
  String? error;
  final List<JobMateNotification> _rows = [];
  final Set<String> _marking = {};
  int get sessionGeneration => _generation;
  bool currentSession(int generation) =>
      !_disposed &&
      generation == _generation &&
      _actor != null &&
      source.userId == _actor;
  List<JobMateNotification> get notifications =>
      source.userId == _actor ? List.unmodifiable(_rows) : const [];
  bool marking(String id) => source.userId == _actor && _marking.contains(id);
  void _reset() {
    ++_generation;
    ++_request;
    _actor = source.userId;
    _rows.clear();
    _marking.clear();
    loading = false;
    error = _actor == null ? 'Sign in to view notifications.' : null;
    notifyListeners();
  }

  Future<void> load() async {
    if (_disposed) return;
    if (source.userId != _actor) _reset();
    final generation = _generation, request = ++_request;
    _rows.clear();
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (_actor == null) throw StateError('Sign in to view notifications.');
      final rows = await source.list();
      if (!currentSession(generation) || request != _request) return;
      final notifications = rows.take(50).map(JobMateNotification.new).toList();
      _rows.addAll(notifications);
    } catch (failure) {
      if (_disposed ||
          generation != _generation ||
          source.userId != _actor ||
          request != _request) {
        return;
      }
      error = failure is StateError
          ? failure.message.toString()
          : notificationError(failure, marking: false);
    } finally {
      if (!_disposed &&
          generation == _generation &&
          request == _request &&
          source.userId == _actor) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// List request sequencing is independent of mutation/session sequencing.
  /// A completed mutation always starts a new authoritative read, even when an
  /// older list request is pending; that older response cannot undo the refresh.
  Future<String?> markRead(String id) async {
    if (!currentSession(_generation) || _marking.contains(id)) return null;
    final item = notifications.where((item) => item.id == id).firstOrNull;
    if (item == null || item.read) return null;
    final generation = _generation;
    _marking.add(id);
    notifyListeners();
    try {
      final found = await source.markRead(id);
      if (!currentSession(generation)) return null;
      await load();
      if (!currentSession(generation)) return null;
      return found ? null : 'This notification is unavailable.';
    } catch (failure) {
      if (!currentSession(generation)) return null;
      return notificationError(failure, marking: true);
    } finally {
      if (currentSession(generation)) {
        _marking.remove(id);
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    ++_request;
    _subscription.cancel();
    _rows.clear();
    _marking.clear();
    super.dispose();
  }
}

String notificationError(Object failure, {required bool marking}) {
  if (failure is AuthException ||
      failure is PostgrestException && failure.code == 'PGRST301') {
    return 'Your session has expired. Sign in again.';
  }
  if (failure is PostgrestException && failure.code == '42501') {
    return 'Notification access is denied. Check that your account is active.';
  }
  return marking
      ? 'Unable to mark this notification as read. Please retry.'
      : 'Unable to load notifications. Please retry.';
}
