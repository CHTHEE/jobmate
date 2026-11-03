import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../applications/module2_widgets.dart';

class LocalAttachment {
  const LocalAttachment(this.name, this.bytes, this.kind);
  final String name, kind;
  final Uint8List bytes;
  bool get image => kind == 'image/png' || kind == 'image/jpeg';
}

Future<List<LocalAttachment>> pickDemoFiles() async {
  final files = await openFiles(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Images or PDF',
        extensions: ['png', 'jpg', 'jpeg', 'pdf'],
        mimeTypes: ['image/png', 'image/jpeg', 'application/pdf'],
        uniformTypeIdentifiers: ['public.png', 'public.jpeg', 'com.adobe.pdf'],
      ),
    ],
  );
  if (files.length > 5) throw const FormatException('Choose up to five files.');
  final result = <LocalAttachment>[];
  for (final file in files) {
    final size = await file.length();
    if (size == 0 || size > 5 * 1024 * 1024) {
      throw const FormatException(
        'Each file must be non-empty and at most 5 MiB.',
      );
    }
    final bytes = await file.readAsBytes();
    final pdf =
        bytes.length >= 5 && String.fromCharCodes(bytes.take(5)) == '%PDF-';
    final png =
        bytes.length >= 8 &&
        bytes.take(8).join(',') == '137,80,78,71,13,10,26,10';
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    if (!pdf && !png && !jpeg) {
      throw const FormatException(
        'Choose a PNG, JPEG or PDF with a matching file header.',
      );
    }
    result.add(
      LocalAttachment(
        file.name,
        bytes,
        pdf
            ? 'application/pdf'
            : png
            ? 'image/png'
            : 'image/jpeg',
      ),
    );
  }
  return result;
}

class AttachmentTile extends StatelessWidget {
  const AttachmentTile(this.file, {super.key, this.onRemove});
  final LocalAttachment file;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: file.image && file.bytes.isNotEmpty
        ? Image.memory(
            file.bytes,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
          )
        : const Icon(Icons.insert_drive_file_outlined),
    title: Text(file.name, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      file.bytes.isEmpty
          ? 'Demo placeholder • no file attached'
          : '${(file.bytes.length / 1024).ceil()} KiB • local only',
    ),
    trailing: onRemove == null
        ? null
        : IconButton(
            tooltip: 'Remove attachment',
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
    onTap: () => moduleModal<void>(
      context,
      ModalBody(
        title: file.name,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
        children: [
          if (file.image && file.bytes.isNotEmpty)
            Image.memory(
              file.bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Text('Image preview unavailable.'),
            )
          else
            Text(
              file.bytes.isEmpty
                  ? 'This is a fictional attachment label, not a stored file.'
                  : 'PDF selected locally. Inline PDF rendering is unavailable; the file is not uploaded.',
            ),
        ],
      ),
    ),
  );
}
