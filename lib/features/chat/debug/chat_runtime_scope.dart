import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../chat_models.dart';
import '../chat_source.dart';

// CH/KZ explicit approval, 13 November 2026. No other trial is authorized.
const approvedChatApplication = 'fb352472-8a41-45cf-a9a6-5e70e25e66e8';
const approvedChatSeeker = 'fb66cc74-1a4f-44e0-ae4f-6831c7a39b8f';
const approvedChatEmployer = '50c0d35f-c1cd-4fa1-b864-6f6e1e833fd0';
String? approvedChatRole(String? actor) => switch (actor) {
  approvedChatSeeker => 'job_seeker',
  approvedChatEmployer => 'employer',
  _ => null,
};
String? approvedChatBody(String? actor) => switch (actor) {
  approvedChatSeeker => 'Hi, this is a JobMate Chat QA test.',
  approvedChatEmployer => 'Hello, employer reply received. Chat QA test.',
  _ => null,
};
String approvedChatRequestId(String? actor) {
  if (approvedChatRole(actor) == null) {
    throw StateError('Participant outside approved trial.');
  }
  // Same identity across reloads, tabs, devices and cleared local retry storage.
  // Backend uniqueness + exact body permits only one logical message per sender.
  return const Uuid().v5(
    Namespace.url.value,
    'jobmate/approved-chat-qa/2026-11-13/$approvedChatApplication/$actor',
  );
}

/// Defense at the RPC boundary as well as the controller/buttons. Reads delegate
/// normally. This wraps the existing source; it adds no authentication or RPCs.
class ScopedChatRuntimeSource implements ChatSource {
  ScopedChatRuntimeSource(this.delegate, {required this.writePermit});
  final ChatSource delegate;
  final bool Function() writePermit;
  String? _conversation;
  void bindConversation(ChatConversation row) {
    if (row.applicationId != approvedChatApplication ||
        _conversation != null && _conversation != row.id) {
      throw StateError('Conversation outside approved trial.');
    }
    _conversation = row.id;
  }

  void _guard([String? conversation]) {
    if (!kDebugMode ||
        !writePermit() ||
        approvedChatRole(userId) == null ||
        conversation != null && conversation != _conversation) {
      throw StateError('Write outside approved Chat scope.');
    }
  }

  @override
  String? get userId => delegate.userId;
  @override
  Stream<String?> get accountChanges => delegate.accountChanges;
  @override
  Future<Object?> getOrCreate(String applicationId) async {
    _guard();
    if (applicationId != approvedChatApplication) {
      throw StateError('Application outside approved trial.');
    }
    return delegate.getOrCreate(applicationId);
  }

  @override
  Future<Object?> send(PendingChatSend pending) async {
    _guard(pending.conversationId);
    if (pending.actorId != userId ||
        pending.requestId != approvedChatRequestId(userId) ||
        pending.body != approvedChatBody(userId)) {
      throw StateError('Only the fixed approved message/request is permitted.');
    }
    return delegate.send(pending);
  }

  @override
  Future<Object?> markRead(String conversationId, String messageId) async {
    _guard(conversationId);
    return delegate.markRead(conversationId, messageId);
  }

  @override
  Future<Object?> conversations({
    required int limit,
    ChatConversationCursor? before,
    String? conversationId,
  }) => delegate.conversations(
    limit: limit,
    before: before,
    conversationId: conversationId,
  );
  @override
  Future<Object?> messages(
    String conversationId, {
    required int limit,
    int? beforeSequence,
  }) => delegate.messages(
    conversationId,
    limit: limit,
    beforeSequence: beforeSequence,
  );
}
