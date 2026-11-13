import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'chat_attachment_draft.dart';
import 'chat_attachment_models.dart';
import 'chat_models.dart';

abstract class ChatAttachmentGateway {
  String? get actorId;
  Stream<String?> get accounts;
  Future<ChatAttachment> reserve(
    String conversation,
    String request,
    String id,
    ChatAttachmentDraft file,
    String? caption,
  );
  Future<ChatAttachment> status(String id);
  Future<List<ChatAttachment>> pending(String conversation);
  Future<void> chunk(String id, int index, Uint8List bytes);
  Future<ChatAttachment> validate(String id);
  Future<ChatMessage> send(String id);
  Future<Uri> download(ChatAttachment attachment);
  void cancelTransfers();
}

class SupabaseChatAttachmentGateway implements ChatAttachmentGateway {
  SupabaseChatAttachmentGateway(this.client, {required this.enabled});
  final SupabaseClient client;
  final bool enabled;
  Completer<void>? _abort;
  @override
  void cancelTransfers() {
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  @override
  String? get actorId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accounts =>
      client.auth.onAuthStateChange.map((e) => e.session?.user.id);
  Future<Object?> _rpc(String name, Map<String, Object?> params) async {
    final actor = actorId;
    if (!enabled || actor == null) throw StateError('Attachments unavailable.');
    final result = await client
        .rpc(name, params: params)
        .retry(enabled: false, requestTimeout: const Duration(seconds: 30));
    if (actorId != actor) throw StateError('Account changed.');
    return result;
  }

  Future<Object?> _edge(
    String op,
    String id, {
    int? index,
    Uint8List? bytes,
  }) async {
    final actor = actorId;
    if (!enabled || actor == null) throw StateError('Attachments unavailable.');
    final abort = Completer<void>();
    _abort = abort;
    final result = await client.functions.invoke(
      'chat-basic-attachments',
      queryParameters: {'op': op},
      abortSignal: abort.future,
      body: bytes ?? <String, Object?>{},
      headers: {
        'x-attachment-id': chatUuid(id),
        if (index != null) 'x-chunk-index': '$index',
        if (bytes != null) 'Content-Type': 'application/octet-stream',
      },
    );
    if (actorId != actor || result.status != 200) {
      throw StateError('Not confirmed.');
    }
    return result.data;
  }

  @override
  Future<ChatAttachment> reserve(
    String conversation,
    String request,
    String id,
    ChatAttachmentDraft file,
    String? caption,
  ) async => ChatAttachment.fromRow(
    chatRow(
      await _rpc('reserve_chat_attachment_basic_v1', {
        'p_conversation_id': chatUuid(conversation),
        'p_client_request_id': chatUuid(request),
        'p_attachment_id': chatUuid(id),
        'p_original_name': file.name,
        'p_mime_type': file.mimeType,
        'p_size_bytes': file.bytes.length,
        'p_sha256': file.digest,
        'p_caption': caption,
      }),
    ),
  );
  @override
  Future<ChatAttachment> status(String id) async => ChatAttachment.fromRow(
    chatRow(
      await _rpc('get_chat_attachment_basic_v1', {
        'p_attachment_id': chatUuid(id),
      }),
    ),
  );
  @override
  Future<List<ChatAttachment>> pending(String conversation) async => chatRows(
    await _rpc('list_pending_chat_attachments_basic_v1', {
      'p_conversation_id': chatUuid(conversation),
    }),
    8,
  ).map(ChatAttachment.fromRow).toList();
  @override
  Future<void> chunk(String id, int index, Uint8List bytes) async {
    await _edge('upload', id, index: index, bytes: bytes);
  }

  @override
  Future<ChatAttachment> validate(String id) async =>
      ChatAttachment.fromRow(chatRow(await _edge('validate', id)));
  @override
  Future<ChatMessage> send(String id) async => ChatMessage.fromRow(
    chatRow(
      await _rpc('send_chat_attachment_basic_v1', {
        'p_attachment_id': chatUuid(id),
      }),
    ),
    sentResult: true,
  );
  @override
  Future<Uri> download(ChatAttachment attachment) async {
    final actor = actorId;
    if (!enabled ||
        actor == null ||
        attachment.state != 'committed' ||
        attachment.path == null) {
      throw StateError('Unavailable.');
    }
    // RLS reauthorizes current participation; never accepts a caller-selected path.
    final url = await client.storage
        .from('jobmate-chat-basic-files')
        .createSignedUrl(
          attachment.path!,
          60,
          download: DownloadBehavior.named(attachment.name),
        );
    if (actor != actorId) throw StateError('Account changed.');
    return Uri.parse(url);
  }
}

/// Server reservations recover identities; bytes/URLs/captions are never added
/// to plaintext local pending storage. Cancellation stops between acknowledged
/// chunks; an in-flight request may finish and must be reconciled on retry.
class ChatAttachmentsController extends ChangeNotifier {
  ChatAttachmentsController(this.gateway) : _actor = gateway.actorId {
    _auth = gateway.accounts.listen((actor) {
      if (actor != _actor) {
        _actor = actor;
        clear();
      }
    });
  }
  final ChatAttachmentGateway gateway;
  late final StreamSubscription<String?> _auth;
  String? _actor;
  int _generation = 0;
  bool _disposed = false, _cancel = false;
  bool busy = false;
  double progress = 0;
  String phase = 'Selected', error = '';
  ChatAttachmentDraft? file;
  ChatAttachment? reservation;
  ChatMessage? receipt;
  String? _id, _request, _caption, _conversation;
  bool get hasIdentity => _id != null;
  bool get needsExit => file != null || hasIdentity || busy;
  bool _current(int g) =>
      !_disposed &&
      g == _generation &&
      _actor != null &&
      gateway.actorId == _actor;
  void select(ChatAttachmentDraft value) {
    if (busy) return;
    if (reservation case final prior?) {
      if (value.name != prior.name ||
          value.mimeType != prior.mime ||
          value.bytes.length != prior.size ||
          value.digest != prior.expectedHash) {
        error = 'Reselect the same original file for this saved request.';
        notifyListeners();
        return;
      }
    } else if (hasIdentity) {
      return;
    }
    file = value;
    error = '';
    notifyListeners();
  }

  void clear() {
    gateway.cancelTransfers();
    ++_generation;
    file = null;
    reservation = null;
    receipt = null;
    _id = _request = _caption = _conversation = null;
    busy = false;
    _cancel = false;
    progress = 0;
    phase = 'Selected';
    error = '';
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    gateway.cancelTransfers();
    _cancel = true;
    phase = 'Cancelling; keep this request for retry';
    notifyListeners();
  }

  void recover(ChatAttachment value) {
    if (busy || value.senderId != _actor || value.state == 'committed') return;
    clear();
    reservation = value;
    _id = value.id;
    _request = value.requestId;
    _caption = value.caption;
    _conversation = value.conversationId;
    phase = value.state == 'pending'
        ? 'Reselect the same file to resume upload'
        : value.state;
    notifyListeners();
  }

  Future<void> run(String conversation, String caption) async {
    if (busy ||
        _actor == null ||
        gateway.actorId != _actor ||
        !hasIdentity && file == null) {
      return;
    }
    if (!hasIdentity) {
      if (caption.isNotEmpty) validateChatBody(caption);
      _id = const Uuid().v4();
      _request = const Uuid().v4();
      _caption = caption.isEmpty ? null : caption;
      _conversation = chatUuid(conversation);
    }
    if (_conversation != conversation) return;
    final g = _generation;
    busy = true;
    _cancel = false;
    error = '';
    notifyListeners();
    try {
      var row =
          reservation ??
          await gateway.reserve(conversation, _request!, _id!, file!, _caption);
      if (!_current(g)) return;
      if (row.id != _id ||
          row.requestId != _request ||
          row.senderId != _actor ||
          row.conversationId != conversation ||
          row.caption != _caption) {
        throw const FormatException('Binding');
      }
      reservation = row;
      if (_cancel) return;
      row = await gateway.status(row.id);
      if (!_current(g) || _cancel) return;
      reservation = row;
      if (row.state == 'pending') {
        if (file == null) {
          phase = 'Reselect the same file to resume upload';
          return;
        }
        phase = 'Uploading';
        notifyListeners();
        const size = 262144;
        for (
          var offset = 0, index = 0;
          offset < file!.bytes.length;
          offset += size, index++
        ) {
          final end = (offset + size).clamp(0, file!.bytes.length);
          await gateway.chunk(
            row.id,
            index,
            Uint8List.sublistView(file!.bytes, offset, end),
          );
          if (!_current(g) || _cancel) return;
          progress = end / file!.bytes.length;
          notifyListeners();
        }
      }
      if (row.state == 'pending' || row.state == 'validating') {
        phase = 'Checking file type and content';
        notifyListeners();
        row = await gateway.validate(row.id);
        if (!_current(g) || _cancel) return;
        reservation = row;
      }
      if (row.state == 'rejected' || row.state == 'expired') {
        phase = row.state;
        return;
      }
      if (row.state != 'validated' && row.state != 'committed') {
        phase = 'Checking file type and content';
        return;
      }
      phase = 'Confirming message';
      notifyListeners();
      final sent = await gateway.send(row.id);
      if (!_current(g)) return;
      if (sent.attachment?.id != _id ||
          sent.attachment?.requestId != _request ||
          sent.senderId != _actor ||
          sent.conversationId != conversation) {
        throw const FormatException('Receipt');
      }
      receipt = sent;
      file = null;
      phase = 'Sent';
    } catch (_) {
      if (_current(g)) {
        error = 'Attachment not confirmed. Retry keeps the same file and request identity. A busy validation may need two minutes before retry.';
        phase = 'Not confirmed';
      }
    } finally {
      if (_current(g)) {
        busy = false;
        if (_cancel) {
          phase = 'Cancelled locally; retry reconciles the same request';
        }
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    clear();
    unawaited(_auth.cancel());
    super.dispose();
  }
}
