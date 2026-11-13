import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../applications/my_applications_repository.dart';
import '../../notifications/notifications_repository.dart';
import '../chat_models.dart';
import '../chat_repository.dart';
import 'chat_runtime_scope.dart';

const chatRuntimeAcceptancePath = '/debug/chat-acceptance';
bool get chatRuntimeAcceptanceEnabled => kDebugMode;

abstract class ChatRuntimeRealtime {
  void start(
    String conversationId,
    void Function(String) status,
    void Function(Map<String, Object?>) event,
  );
  Future<void> stop();
}

class SupabaseChatRuntimeRealtime implements ChatRuntimeRealtime {
  SupabaseChatRuntimeRealtime(this.client);
  final SupabaseClient client;
  RealtimeChannel? _channel;
  int _generation = 0;

  @override
  void start(
    String conversationId,
    void Function(String) status,
    void Function(Map<String, Object?>) event,
  ) {
    final generation = ++_generation;
    void receive(PostgresChangePayload payload) {
      if (generation != _generation) return;
      // Never retain/export raw Realtime records or message text.
      final row = payload.newRecord;
      if (row['conversation_id'] != conversationId) return;
      event({
        'table': payload.table,
        'event': payload.eventType.name,
        'conversation_id': conversationId,
        if (row['message_id'] is String)
          'message_id': chatUuid(row['message_id']),
        if (row['sequence'] is int) 'sequence': row['sequence'],
      });
    }

    _channel = client
        .channel('chat-acceptance-$generation-$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: receive,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: receive,
        )
        .subscribe((value, error) {
          if (generation == _generation) status(value.name);
        });
  }

  @override
  Future<void> stop() async {
    ++_generation;
    final channel = _channel;
    _channel = null;
    if (channel != null) await client.removeChannel(channel);
  }
}

/// Temporary debug tooling. Uses the production repository, never bypasses it.
class ChatRuntimeController extends ChangeNotifier {
  ChatRuntimeController({
    required this.repository,
    required this.readAccount,
    required this.readApplications,
    this.readNotifications,
    this.realtime,
  }) {
    _actor = repository.source.userId;
    _auth = repository.source.accountChanges.listen((actor) {
      if (!_disposed && actor != _actor) _reset(actor);
    });
  }
  final ChatRepository repository;
  final Future<Map<String, dynamic>> Function() readAccount;
  final Future<List<MyJobApplication>> Function() readApplications;
  final Future<List<JobMateNotification>> Function()? readNotifications;
  final ChatRuntimeRealtime? realtime;
  late final StreamSubscription<String?> _auth;
  String? _actor;
  int _generation = 0, _subscriptionGeneration = 0;
  bool _disposed = false;

  bool _trialStopped = false;
  String? _approvedConversation;
  ChatSendReceipt? _lastReceipt;
  bool get trialStopped => _trialStopped;
  bool get writesEnabled =>
      kDebugMode &&
      !_disposed &&
      !_trialStopped &&
      repository.source is ScopedChatRuntimeSource &&
      _actor != null &&
      repository.source.userId == _actor &&
      approvedChatRole(_actor) != null &&
      role == approvedChatRole(_actor) &&
      accountStatus == 'active';
  bool get canCreateApproved =>
      writesEnabled &&
      (selectedApplication == null ||
          selectedApplication == approvedChatApplication);
  bool get canWriteConversation =>
      writesEnabled &&
      _approvedConversation != null &&
      selectedConversation == _approvedConversation;
  String? get agreedBody => approvedChatBody(_actor);
  String? get actorId => _actor;
  String? role, accountStatus, error, selectedConversation, selectedApplication;
  String realtimeStatus = 'stopped';
  bool busy = false;
  int limit = 1;
  ChatConversationPage? conversationPage;
  ChatMessagePage? messagePage;
  List<MyJobApplication> applications = [];
  PendingChatSend? pending;
  String? _conversationFilter;
  final List<Map<String, Object?>> _evidence = [];

  void _record(
    String operation,
    String outcome, [
    Map<String, Object?> data = const {},
  ]) {
    _evidence.add({
      'at': DateTime.now().toUtc().toIso8601String(),
      'actor_id': _actor,
      'operation': operation,
      'outcome': outcome,
      ...data,
    });
    if (_evidence.length > 200) _evidence.removeAt(0);
  }

  String get evidenceJson => const JsonEncoder.withIndent('  ').convert({
    'debug_only': true,
    'writes_enabled': writesEnabled,
    'approved_application_id': approvedChatApplication,
    'trial_stopped': _trialStopped,
    'actor_id': _actor,
    'role': role,
    'account_status': accountStatus,
    'records': _evidence,
    'outstanding': [
      'messaging acceptance',
      'foreign/admin authorization unless observed',
      'Realtime delivery unless an event is observed and reconciled',
      'unencrypted pending storage',
      'device restart',
      'cross-tab acceptance',
      'concurrency',
      'earlier full rollback fingerprint comparison unconfirmed',
    ],
  });

  void _reset(String? actor) {
    _actor = actor;
    ++_generation;
    ++_subscriptionGeneration;
    unawaited(_stopTransport());
    role = accountStatus = error = selectedConversation = selectedApplication =
        null;
    conversationPage = null;
    messagePage = null;
    applications = [];
    pending = null;
    _approvedConversation = null;
    _lastReceipt = null;
    _conversationFilter = null;
    realtimeStatus = 'stopped';
    busy = false;
    _evidence.clear();
    _record('account_changed', 'state_cleared');
    notifyListeners();
  }

  bool _current(int generation) =>
      !_disposed &&
      generation == _generation &&
      _actor != null &&
      repository.source.userId == _actor;

  Future<void> _run(
    String name,
    Future<Map<String, Object?>> Function() action,
  ) async {
    if (!kDebugMode || _disposed || busy) return;
    if (repository.source.userId != _actor) _reset(repository.source.userId);
    final generation = _generation;
    if (!_current(generation)) {
      error = 'Sign in to JobMate first.';
      notifyListeners();
      return;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final data = await action();
      if (_current(generation)) _record(name, 'typed_result', data);
    } catch (failure) {
      if (_current(generation)) {
        final code = failure is PostgrestException ? failure.code : null;
        if (code == '42501' || code == '55000') _trialStopped = true;
        error =
            '${chatError(failure)}'
            '${code == null ? '' : ' SQLSTATE/PostgREST: $code.'}'
            '${failure is FormatException ? ' Typed parsing failed.' : ''}';
        _record(name, 'error', {
          'type': failure.runtimeType.toString(),
          'code': code,
          'typed_parsing_failed': failure is FormatException,
        });
      }
    } finally {
      if (_current(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadIdentity() => _run('identity', () async {
    final generation = _generation;
    final row = await readAccount();
    if (!_current(generation)) throw const ChatSessionChanged();
    if (chatUuid(row['user_id']) != _actor) {
      throw const FormatException('Foreign account.');
    }
    role = chatText(row, 'role');
    accountStatus = chatText(row, 'status');
    return {'role': role, 'status': accountStatus};
  });

  void setLimit(int value) {
    if (busy || ![1, 10, 50].contains(value)) return;
    limit = value;
    conversationPage = null;
    messagePage = null;
    notifyListeners();
  }

  Future<void> loadConversations({bool next = false, String? filter}) => _run(
    'list_my_chat_conversations',
    () async {
      final generation = _generation;
      final before = next ? conversationPage?.nextCursor : null;
      if (next && before == null) {
        throw StateError('No next conversation cursor.');
      }
      if (!next) _conversationFilter = filter == null ? null : chatUuid(filter);
      conversationPage = null;
      final page = await repository.conversations(
        limit: limit,
        before: before,
        conversationId: _conversationFilter,
      );
      if (!_current(generation)) throw const ChatSessionChanged();
      conversationPage = page;
      return {
        'limit': limit,
        'filter': _conversationFilter,
        'before_activity_at': before?.activityAt.toUtc().toIso8601String(),
        'before_conversation_id': before?.conversationId,
        'count': page.items.length,
        'rows': page.items
            .map(
              (row) => {
                'conversation_id': row.id,
                'application_id': row.applicationId,
                'activity_at': row.activityAt.toIso8601String(),
                'last_sequence': row.lastSequence,
                'unread_count': row.unreadCount,
                'can_send': row.canSend,
                'read_only_reason': row.readOnlyReason,
              },
            )
            .toList(),
        'has_next': page.nextCursor != null,
      };
    },
  );

  void selectConversation(String value) {
    if (busy) return;
    final id = chatUuid(value.trim());
    stopRealtime();
    selectedConversation = id;
    messagePage = null;
    error = null;
    pending = null;
    notifyListeners();
  }

  Future<void> loadMessages({bool next = false, bool emptyBoundary = false}) =>
      _run('list_chat_messages', () async {
        final generation = _generation;
        final id = chatUuid(selectedConversation);
        final before = emptyBoundary
            ? 1
            : next
            ? messagePage?.nextBeforeSequence
            : null;
        if (next && before == null) throw StateError('No next message cursor.');
        messagePage = null;
        final page = await repository.messages(
          id,
          limit: limit,
          beforeSequence: before,
        );
        if (!_current(generation)) throw const ChatSessionChanged();
        messagePage = page;
        return {
          'conversation_id': id,
          'limit': limit,
          'before_sequence': before,
          'count': page.items.length,
          'rows': page.items
              .map(
                (row) => {
                  'message_id': row.id,
                  'conversation_id': row.conversationId,
                  'sender_id': row.senderId,
                  'sequence': row.sequence,
                  'sent_at': row.sentAt.toIso8601String(),
                  'body_codepoints': row.body.runes.length,
                },
              )
              .toList(),
          'has_next': page.nextBeforeSequence != null,
        };
      });

  Future<void> loadApplications() => _run('list_my_job_applications', () async {
    final generation = _generation;
    final rows = await readApplications();
    if (!_current(generation)) throw const ChatSessionChanged();
    applications = rows;
    selectedApplication = null;
    return {
      'count': rows.length,
      'application_ids': rows.map((row) => row.id).toList(),
    };
  });

  void _requireWriteApproval() {
    if (!writesEnabled) {
      throw StateError('Separate explicit write approval is required.');
    }
  }

  Future<void> createConversation() async {
    _requireWriteApproval();
    if (!canCreateApproved) {
      throw StateError('Application outside approved trial.');
    }
    await _run('get_or_create_chat_conversation', () async {
      final generation = _generation;
      final id = await repository.getOrCreate(approvedChatApplication);
      if (!_current(generation)) throw const ChatSessionChanged();
      await _verifyApprovedConversation(id, generation);
      selectedConversation = id;
      messagePage = null;
      return {
        'application_id': approvedChatApplication,
        'conversation_id': id,
        'bound_to_approved_application': true,
      };
    });
  }

  Future<ChatConversation> _verifyApprovedConversation(
    String id,
    int generation,
  ) async {
    _requireWriteApproval();
    final page = await repository.conversations(limit: 1, conversationId: id);
    if (!_current(generation)) throw const ChatSessionChanged();
    _requireWriteApproval();
    if (page.items.length != 1 ||
        page.items.single.id != id ||
        page.items.single.applicationId != approvedChatApplication) {
      _trialStopped = true;
      throw StateError('Unable to verify approved application; trial stopped.');
    }
    final row = page.items.single;
    if (!row.canSend) {
      _trialStopped = true;
      _record('capability', 'read_only_stop', {
        'read_only_reason': row.readOnlyReason,
      });
      throw StateError('Backend reports read-only; trial stopped.');
    }
    (repository.source as ScopedChatRuntimeSource).bindConversation(row);
    _approvedConversation = id;
    return row;
  }

  Future<void> send(String body) async {
    _requireWriteApproval();
    if (body != agreedBody) {
      throw StateError('Only the agreed message is approved.');
    }
    await _sendApproved(replay: false);
  }

  Future<void> _sendApproved({required bool replay}) async {
    _requireWriteApproval();
    if (!canWriteConversation) {
      throw StateError('Create/reuse the approved conversation first.');
    }
    await _run(replay ? 'retry_same_uuid_body' : 'send_chat_message', () async {
      final generation = _generation;
      final id = selectedConversation!;
      await _verifyApprovedConversation(id, generation);
      final saved = await repository.prepareSend(id, agreedBody!);
      if (!_current(generation)) throw const ChatSessionChanged();
      _requireWriteApproval();
      if (saved.requestId != approvedChatRequestId(_actor) ||
          saved.body != agreedBody ||
          saved.actorId != _actor ||
          saved.conversationId != id) {
        _trialStopped = true;
        throw StateError('Saved request differs from approved trial; no send.');
      }
      pending = saved;
      final receipt = await repository.sendPending(saved);
      if (!_current(generation)) throw const ChatSessionChanged();
      final previous = _lastReceipt;
      if (previous != null &&
          (previous.message.id != receipt.message.id ||
              previous.message.sequence != receipt.message.sequence)) {
        _trialStopped = true;
        throw const FormatException(
          'Idempotency receipt changed; trial stopped.',
        );
      }
      _lastReceipt = receipt;
      return {
        'request_id': saved.requestId,
        'conversation_id': id,
        'message_id': receipt.message.id,
        'sequence': receipt.message.sequence,
        'same_receipt_as_previous': previous == null ? null : true,
        'retry_record_retained': receipt.retryRecordRetained,
      };
    });
  }

  Future<void> retry() async {
    await _sendApproved(replay: true);
  }

  Future<void> markRead(String messageId) async {
    _requireWriteApproval();
    if (!canWriteConversation ||
        !(messagePage?.items.any(
              (row) =>
                  row.id == messageId &&
                  row.conversationId == _approvedConversation,
            ) ??
            false)) {
      throw StateError(
        'Select a retrieved message in the approved conversation.',
      );
    }
    await _run('mark_chat_conversation_read', () async {
      final generation = _generation;
      final id = selectedConversation!;
      await _verifyApprovedConversation(id, generation);
      return {
        'conversation_id': id,
        'message_id': messageId,
        'read_sequence': await repository.markRead(id, messageId),
      };
    });
  }

  Future<void> loadNotifications() => _run('list_my_notifications', () async {
    if (readNotifications == null) {
      throw StateError('Notification reader unavailable.');
    }
    final rows = await readNotifications!();
    return {
      'limit': 50,
      'offset': 0,
      'count': rows.length,
      'rows': rows
          .map(
            (row) => {
              'notification_id': row.id,
              'notification_type': row.type,
              'created_at': row.createdAt.toIso8601String(),
              'read': row.read,
            },
          )
          .toList(),
      'correlation':
          'quiet-window observation only; no message link; first 50 rows',
    };
  });

  Future<void> startRealtime() => _run('realtime_start', () async {
    final generation = _generation;
    final id = chatUuid(selectedConversation);
    if (realtime == null) throw StateError('Realtime unavailable.');
    stopRealtime();
    final subscription = _subscriptionGeneration;
    await realtime!.stop();
    if (!_current(generation) || subscription != _subscriptionGeneration) {
      throw const ChatSessionChanged();
    }
    realtimeStatus = 'connecting';
    realtime!.start(
      id,
      (status) {
        if (!_current(generation) || subscription != _subscriptionGeneration) {
          return;
        }
        realtimeStatus = status;
        _record('realtime_status', status);
        notifyListeners();
      },
      (event) {
        if (!_current(generation) || subscription != _subscriptionGeneration) {
          return;
        }
        _record('realtime_event', 'observed_not_reconciled', event);
        notifyListeners();
      },
    );
    return {
      'conversation_id': id,
      'delivery': 'unverified; reload typed history to reconcile',
    };
  });
  Future<void> _stopTransport() async {
    try {
      await realtime?.stop();
    } catch (_) {
      /* No raw transport errors/logs. */
    }
  }

  void stopRealtime() {
    ++_subscriptionGeneration;
    realtimeStatus = 'stopped';
    unawaited(_stopTransport());
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    ++_subscriptionGeneration;
    unawaited(_auth.cancel());
    unawaited(_stopTransport());
    repository.dispose();
    super.dispose();
  }
}
