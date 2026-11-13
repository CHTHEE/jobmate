import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_models.dart';

abstract class ChatSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<Object?> getOrCreate(String applicationId);
  Future<Object?> conversations({
    required int limit,
    ChatConversationCursor? before,
    String? conversationId,
  });
  Future<Object?> messages(
    String conversationId, {
    required int limit,
    int? beforeSequence,
  });
  Future<Object?> send(PendingChatSend pending);
  Future<Object?> markRead(String conversationId, String messageId);
}

class SupabaseChatSource implements ChatSource {
  SupabaseChatSource(this.client, {this.attachmentsEnabled = false});
  final SupabaseClient client;
  final bool attachmentsEnabled;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);

  Future<Object?> _rpc(String name, Map<String, Object?> params) async {
    final actor = userId;
    if (actor == null) throw const AuthException('Sign in to access Chat.');
    final result = await client
        .rpc(name, params: params)
        .retry(enabled: false, requestTimeout: const Duration(seconds: 30));
    if (userId != actor) throw const AuthException('Chat account changed.');
    return result;
  }

  @override
  Future<Object?> getOrCreate(String applicationId) => _rpc(
    'get_or_create_chat_conversation',
    {'p_application_id': chatUuid(applicationId)},
  );
  @override
  Future<Object?> conversations({
    required int limit,
    ChatConversationCursor? before,
    String? conversationId,
  }) => _rpc('list_my_chat_conversations', {
    'p_limit': limit,
    'p_before_activity_at': before?.activityAt.toUtc().toIso8601String(),
    'p_before_conversation_id': before == null
        ? null
        : chatUuid(before.conversationId),
    'p_conversation_id': conversationId == null
        ? null
        : chatUuid(conversationId),
  });
  @override
  Future<Object?> messages(
    String conversationId, {
    required int limit,
    int? beforeSequence,
  }) => _rpc(
    attachmentsEnabled ? 'list_chat_messages_basic_v1' : 'list_chat_messages',
    {
      'p_conversation_id': chatUuid(conversationId),
      'p_limit': limit,
      'p_before_sequence': beforeSequence,
    },
  );
  @override
  Future<Object?> send(PendingChatSend pending) async {
    if (userId != pending.actorId) {
      throw const AuthException('Chat account changed.');
    }
    return _rpc('send_chat_message', {
      'p_conversation_id': pending.conversationId,
      'p_client_request_id': pending.requestId,
      'p_body': pending.body,
    });
  }

  @override
  Future<Object?> markRead(String conversationId, String messageId) =>
      _rpc('mark_chat_conversation_read', {
        'p_conversation_id': chatUuid(conversationId),
        'p_message_id': chatUuid(messageId),
      });
}
