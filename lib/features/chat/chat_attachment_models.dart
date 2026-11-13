import 'chat_models.dart';

const chatAttachmentsEnabled = bool.fromEnvironment(
  'JOBMATE_CHAT_BASIC_ATTACHMENTS',
  defaultValue: true,
);

class ChatAttachment {
  ChatAttachment.fromRow(Map<String, dynamic> row)
    : id = chatUuid(row['attachment_id']),
      conversationId = chatUuid(row['conversation_id']),
      senderId = chatUuid(row['sender_id']),
      requestId = chatUuid(row['client_request_id']),
      messageId = row['message_id'] == null
          ? null
          : chatUuid(row['message_id']),
      name = chatText(row, 'original_name'),
      mime = chatText(row, 'mime_type'),
      size = chatInteger(row['size_bytes'], minimum: 1),
      state = chatText(row, 'state'),
      expectedHash = chatText(row, 'expected_sha256'),
      caption = chatNullableText(row, 'caption'),
      path = chatNullableText(row, 'storage_path') {
    const types = {
      'image/jpeg',
      'image/png',
      'application/pdf',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    };
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedHash) ||
        !types.contains(mime) ||
        row['validation_scope'] != 'basic-type-validation-no-antivirus-v1' ||
        size > 5242880 ||
        name.runes.length > 255 ||
        RegExp(r'[\x00-\x1f\x7f/\\]').hasMatch(name) ||
        !{
          'pending',
          'validating',
          'validated',
          'rejected',
          'committed',
          'expired',
        }.contains(state) ||
        (state == 'committed') != (messageId != null) ||
        (state == 'committed'
            ? path != '$conversationId/$senderId/$id/file'
            : path != null)) {
      throw const FormatException('Invalid attachment metadata.');
    }
    if (caption != null) validateChatBody(caption!);
  }
  final String id, conversationId, senderId, requestId, name, mime, state;
  final String expectedHash;
  final String? messageId, caption, path;
  final int size;
  bool get isImage => mime.startsWith('image/');
}
