import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

abstract class ChatRealtime {
  Future<void> listen(String? conversationId, void Function() reconcile);
  Future<void> stop();
}

/// Events are invalidations only. All visible data is reloaded through Chat RPCs.
class SupabaseChatRealtime implements ChatRealtime {
  SupabaseChatRealtime(this.client);
  static int _instances = 0;
  final int _instance = ++_instances;
  final SupabaseClient client;
  RealtimeChannel? _channel;
  int _generation = 0;
  Timer? _debounce;

  @override
  Future<void> listen(String? conversationId, void Function() reconcile) async {
    final expected = _generation + 1;
    await stop();
    if (expected != _generation) return;
    final generation = expected;
    void invalidate() {
      if (generation != _generation) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 150), () {
        if (generation == _generation) reconcile();
      });
    }

    final channel = client.channel(
      'chat-ui-$_instance-$generation-${conversationId ?? 'list'}',
    );
    for (final event in [
      PostgresChangeEvent.insert,
      PostgresChangeEvent.update,
    ]) {
      channel.onPostgresChanges(
        event: event,
        schema: 'public',
        table: 'chat_conversations',
        callback: (_) => invalidate(),
      );
    }
    if (conversationId != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'chat_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id',
          value: conversationId,
        ),
        callback: (_) => invalidate(),
      );
    }
    _channel = channel;
    channel.subscribe((status, _) {
      // Initial subscribe and reconnect both repair gaps with authoritative reads.
      if (status == RealtimeSubscribeStatus.subscribed) invalidate();
    });
  }

  @override
  Future<void> stop() async {
    ++_generation;
    _debounce?.cancel();
    _debounce = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await client.removeChannel(channel);
      } catch (_) {
        /* No raw logs. */
      }
    }
  }
}
