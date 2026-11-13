import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_models.dart';

abstract class ChatPendingStore {
  Future<List<PendingChatSend>> load(String actorId);
  Future<PendingChatSend> prepare(PendingChatSend candidate);
  Future<void> remove(PendingChatSend confirmed);
}

/// Uses Supabase Flutter's already installed generic getItem/setItem storage.
/// Dedicated project/account keys never read or overwrite Auth/PKCE keys.
/// Local draft text is not encrypted; never log it or automatically replay it.
class LocalChatPendingStore implements ChatPendingStore {
  LocalChatPendingStore({required this.storage, required String projectUrl})
    : _project = Uri.parse(projectUrl).origin {
    final uri = Uri.parse(projectUrl);
    if (!['https', 'http'].contains(uri.scheme) || uri.host.isEmpty) {
      throw ArgumentError('Use the existing public Supabase project URL.');
    }
  }
  final GotrueAsyncStorage storage;
  final String _project;
  Future<void> _tail = Future.value();
  String _key(String actor) =>
      'jobmate.chat.pending.v1.${Uri.encodeComponent(_project)}.${chatUuid(actor)}';

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<List<PendingChatSend>> _load(String actor) async {
    final raw = await storage.getItem(key: _key(actor));
    if (raw == null) return [];
    final decoded = chatRow(jsonDecode(raw));
    if (decoded['version'] != 1 || decoded['pending'] is! List) {
      throw const FormatException('Invalid saved Chat requests.');
    }
    final records = (decoded['pending'] as List)
        .map((row) => PendingChatSend.fromJson(chatRow(row)))
        .toList();
    final requests = <String>{}, conversations = <String>{};
    if (records.any(
      (row) =>
          row.actorId != chatUuid(actor) ||
          !requests.add(row.requestId) ||
          !conversations.add(row.conversationId),
    )) {
      throw const FormatException('Inconsistent saved Chat requests.');
    }
    return records;
  }

  Future<void> _save(String actor, List<PendingChatSend> records) async {
    final value = jsonEncode({
      'version': 1,
      'pending': records.map((row) => row.toJson()).toList(),
    });
    await storage.setItem(key: _key(actor), value: value);
    // The installed native storage wrapper does not expose setString's boolean.
    // Fail before dispatch if persistence cannot be read back exactly.
    if (await storage.getItem(key: _key(actor)) != value) {
      throw StateError('Chat request could not be saved. No message was sent.');
    }
  }

  @override
  Future<List<PendingChatSend>> load(String actorId) =>
      _serial(() => _load(actorId));

  @override
  Future<PendingChatSend> prepare(PendingChatSend candidate) =>
      _serial(() async {
        final rows = await _load(candidate.actorId);
        final existing = rows
            .where((row) => row.conversationId == candidate.conversationId)
            .firstOrNull;
        if (existing != null) {
          if (existing.body != candidate.body) {
            throw StateError(
              'Resolve the saved message before sending different content.',
            );
          }
          return existing;
        }
        if (rows.any((row) => row.requestId == candidate.requestId)) {
          throw StateError('Chat request identity is already in use.');
        }
        await _save(candidate.actorId, [...rows, candidate]);
        return candidate;
      });

  @override
  Future<void> remove(PendingChatSend confirmed) => _serial(() async {
    final rows = await _load(confirmed.actorId);
    final existing = rows
        .where((row) => row.requestId == confirmed.requestId)
        .firstOrNull;
    if (existing != null &&
        (existing.body != confirmed.body ||
            existing.conversationId != confirmed.conversationId)) {
      throw StateError('Chat request identity changed.');
    }
    await _save(
      confirmed.actorId,
      rows.where((row) => row.requestId != confirmed.requestId).toList(),
    );
  });
}
