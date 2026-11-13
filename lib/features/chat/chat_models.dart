import '../applications/my_applications_repository.dart';
import 'chat_attachment_models.dart';

String chatUuid(Object? value) {
  if (value is! String ||
      !RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
          .hasMatch(value)) {
    throw const FormatException('Invalid Chat UUID.');
  }
  return value.toLowerCase();
}

String chatText(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (!row.containsKey(key) || value is! String || value.isEmpty) {
    throw FormatException('Invalid Chat field: $key.');
  }
  return value;
}

String? chatNullableText(Map<String, dynamic> row, String key) {
  if (!row.containsKey(key)) throw FormatException('Missing Chat field: $key.');
  if (row[key] == null) return null;
  if (row[key] is! String) throw FormatException('Invalid Chat field: $key.');
  return row[key] as String;
}

int chatInteger(Object? value, {int minimum = 0}) {
  // Fail closed rather than silently round PostgreSQL bigint cursors on Web.
  if (value is! int || value < minimum || value > 9007199254740991) {
    throw const FormatException('Invalid Chat integer.');
  }
  return value;
}

DateTime chatTime(Object? value) {
  final match = value is String
      ? RegExp(
          r'^(\d{4})-(\d{2})-(\d{2})T([01]\d|2[0-3]):([0-5]\d):([0-5]\d)(?:\.\d{1,6})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$',
        ).firstMatch(value)
      : null;
  if (match == null) {
    throw const FormatException('Invalid Chat timestamp.');
  }
  final year = int.parse(match[1]!),
      month = int.parse(match[2]!),
      day = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    throw const FormatException('Invalid Chat calendar date.');
  }
  final result = DateTime.tryParse(value as String);
  if (result == null) throw const FormatException('Invalid Chat timestamp.');
  return result.toUtc();
}

Map<String, dynamic> chatRow(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid Chat row.');
  }
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> chatRows(Object? value, int limit) {
  if (value is! List || value.length > limit) {
    throw const FormatException('Invalid Chat page.');
  }
  return value.map(chatRow).toList(growable: false);
}

void validateChatBody(String body) {
  // Exact Unicode White_Space code points used by the deployed SQL btrim.
  const whitespace = {
    0x09,
    0x0a,
    0x0b,
    0x0c,
    0x0d,
    0x20,
    0x85,
    0xa0,
    0x1680,
    0x2000,
    0x2001,
    0x2002,
    0x2003,
    0x2004,
    0x2005,
    0x2006,
    0x2007,
    0x2008,
    0x2009,
    0x200a,
    0x2028,
    0x2029,
    0x202f,
    0x205f,
    0x3000,
  };
  final runes = body.runes.toList(growable: false);
  if (runes.isEmpty ||
      runes.length > 4000 ||
      runes.every(whitespace.contains)) {
    throw const FormatException(
      'Enter a nonblank message of at most 4000 characters.',
    );
  }
  // PostgreSQL text cannot contain NUL; reject malformed UTF-16 before encoding.
  for (var i = 0; i < body.length; i++) {
    final unit = body.codeUnitAt(i);
    if (unit == 0 || unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('Invalid message character.');
    }
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= body.length ||
          body.codeUnitAt(i) < 0xdc00 ||
          body.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('Invalid message character.');
      }
    }
  }
}

class ChatConversationCursor {
  const ChatConversationCursor(this.activityAt, this.conversationId);
  final DateTime activityAt;
  final String conversationId;
}

class ChatConversation {
  ChatConversation.fromRow(Map<String, dynamic> row)
    : id = chatUuid(row['conversation_id']),
      applicationId = chatUuid(row['application_id']),
      jobId = chatUuid(row['job_id']),
      jobTitle = chatText(row, 'job_title'),
      companyName = chatText(row, 'company_name'),
      workerName = chatText(row, 'worker_name'),
      status = MyApplicationStatus.values.firstWhere(
        (s) => s.name == row['application_status'],
        orElse: () =>
            throw const FormatException('Invalid Chat application status.'),
      ),
      createdAt = chatTime(row['created_at']),
      activityAt = chatTime(row['activity_at']),
      lastMessagePreview = chatNullableText(row, 'last_message_preview'),
      lastMessageAt = row['last_message_at'] == null
          ? null
          : chatTime(row['last_message_at']),
      lastSequence = chatInteger(row['last_sequence']),
      unreadCount = chatInteger(row['unread_count']),
      readOnlyReason = chatNullableText(row, 'read_only_reason'),
      canSend = row['can_send'] is bool
          ? row['can_send'] as bool
          : throw const FormatException('Invalid Chat capability.') {
    if (!row.containsKey('last_message_at') ||
        canSend != (readOnlyReason == null) ||
        (lastSequence == 0) != (lastMessageAt == null) ||
        (lastSequence == 0) != (lastMessagePreview == null) ||
        unreadCount > lastSequence ||
        activityAt.isBefore(createdAt)) {
      throw const FormatException('Inconsistent Chat conversation.');
    }
  }
  final String id, applicationId, jobId, jobTitle, companyName, workerName;
  final MyApplicationStatus status;
  final DateTime createdAt, activityAt;
  final String? lastMessagePreview, readOnlyReason;
  final DateTime? lastMessageAt;
  final int lastSequence, unreadCount;
  final bool canSend;
  ChatConversationCursor get cursor => ChatConversationCursor(activityAt, id);
}

class ChatMessage {
  ChatMessage.fromRow(Map<String, dynamic> row, {bool sentResult = false})
    : id = chatUuid(row['message_id']),
      conversationId = chatUuid(row['conversation_id']),
      senderId = chatUuid(row['sender_id']),
      senderName = sentResult ? null : chatText(row, 'sender_name'),
      body = chatText(row, 'body'),
      attachment = row['attachment'] == null
          ? null
          : ChatAttachment.fromRow(chatRow(row['attachment'])),
      sentAt = chatTime(row['sent_at']),
      sequence = chatInteger(row['sequence'], minimum: 1) {
    validateChatBody(body);
    if (attachment case final file?) {
      if (file.state != 'committed' ||
          !row.containsKey('caption') ||
          file.messageId != id ||
          file.senderId != senderId ||
          file.conversationId != conversationId ||
          row['caption'] != file.caption ||
          body != (file.caption ?? 'Attachment: ${file.name}')) {
        throw const FormatException('Invalid attachment message binding.');
      }
    }
  }
  final String id, conversationId, senderId, body;
  final String? senderName; // Send RPC has no sender_name column.
  final ChatAttachment? attachment;
  final DateTime sentAt;
  final int sequence;
}

class ChatConversationPage {
  ChatConversationPage(List<ChatConversation> rows, this.nextCursor)
    : items = List.unmodifiable(rows);
  final List<ChatConversation> items;
  final ChatConversationCursor? nextCursor;
}

class ChatMessagePage {
  ChatMessagePage(List<ChatMessage> rows, this.nextBeforeSequence)
    : items = List.unmodifiable(rows);
  final List<ChatMessage>
  items; // Descending sequence, matching RPC wire order.
  final int? nextBeforeSequence;
}

class PendingChatSend {
  PendingChatSend({
    required String actorId,
    required String conversationId,
    required String requestId,
    required this.body,
  }) : actorId = chatUuid(actorId),
       conversationId = chatUuid(conversationId),
       requestId = chatUuid(requestId) {
    validateChatBody(body);
  }
  factory PendingChatSend.fromJson(Map<String, dynamic> row) => PendingChatSend(
    actorId: chatText(row, 'actor_id'),
    conversationId: chatText(row, 'conversation_id'),
    requestId: chatText(row, 'request_id'),
    body: chatText(row, 'body'),
  );
  final String actorId, conversationId, requestId, body;
  Map<String, dynamic> toJson() => {
    'actor_id': actorId,
    'conversation_id': conversationId,
    'request_id': requestId,
    'body': body,
  };
}
