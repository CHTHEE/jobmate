import 'dart:typed_data';

import 'chat_file_digest.dart';

/// Local selection only. Never serialized into the text pending-send store.
/// Header checks improve picker feedback; they are NOT server validation or AV.
class ChatAttachmentDraft {
  ChatAttachmentDraft._(this.name, this.mimeType, Uint8List bytes)
    : bytes = bytes.asUnmodifiableView();

  static const maximumBytes = 5 * 1024 * 1024;
  static const extensions = ['jpg', 'jpeg', 'png', 'pdf', 'docx', 'xlsx'];
  static const unavailable =
      'Attachment preview only. Uploading and sending files requires the new secure backend.';
  final String name, mimeType;
  final Uint8List bytes;
  late final String digest = chatFileDigest(bytes);
  bool get isImage => mimeType.startsWith('image/');
  String get sizeLabel => bytes.length < 1024
      ? '${bytes.length} B'
      : bytes.length < 1024 * 1024
      ? '${(bytes.length / 1024).toStringAsFixed(1)} KB'
      : '${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB';

  factory ChatAttachmentDraft.select(String name, Uint8List bytes) {
    if (name.trim().isEmpty ||
        name.runes.length > 255 ||
        RegExp(r'[\x00-\x1f\x7f/\\]').hasMatch(name)) {
      throw const FormatException(
        'Use a filename of 1–255 characters without paths or control characters.',
      );
    }
    if (bytes.isEmpty || bytes.length > maximumBytes) {
      throw const FormatException(
        'Choose a non-empty file of at most 5 MB (5,242,880 bytes).',
      );
    }
    final ext = name.split('.').last.toLowerCase();
    final mime = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'pdf' => 'application/pdf',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      _ => throw const FormatException('Choose JPG, PNG, PDF, DOCX or XLSX.'),
    };
    bool starts(List<int> header) =>
        bytes.length >= header.length &&
        Iterable<int>.generate(header.length)
            .every((i) => bytes[i] == header[i]);
    final headerMatches = switch (ext) {
      'jpg' || 'jpeg' => starts([0xff, 0xd8, 0xff]),
      'png' => starts([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      'pdf' => starts([0x25, 0x50, 0x44, 0x46, 0x2d]),
      _ => starts([0x50, 0x4b, 0x03, 0x04]),
    };
    if (!headerMatches) {
      throw const FormatException(
        'The file header does not match its extension.',
      );
    }
    // OOXML ZIP packages require trusted structural validation; this is not AV.
    // Copy once so the caller cannot mutate the accepted selection.
    return ChatAttachmentDraft._(name, mime, Uint8List.fromList(bytes));
  }
}
