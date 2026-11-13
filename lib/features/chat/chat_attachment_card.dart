import 'package:flutter/material.dart';

import 'chat_attachment_models.dart';
import 'chat_attachments.dart';
import 'chat_download.dart';
import '../../shared/theme/jobmate_theme.dart';

class ChatAttachmentCard extends StatefulWidget {
  const ChatAttachmentCard({
    super.key,
    required this.attachment,
    required this.gateway,
    this.downloadFile = downloadChatFile,
    this.onImageDisplayed,
    this.foregroundColor,
  });
  final ChatAttachment attachment;
  final ChatAttachmentGateway gateway;
  final Future<void> Function(Future<Uri> Function()) downloadFile;
  final VoidCallback? onImageDisplayed;
  final Color? foregroundColor;
  @override
  State<ChatAttachmentCard> createState() => _ChatAttachmentCardState();
}

class _ChatAttachmentCardState extends State<ChatAttachmentCard> {
  late final String? _actor = widget.gateway.actorId;
  Future<Uri>? _thumbnail;
  String? _error;
  bool _opening = false;
  bool _imageReported = false;
  @override
  void initState() {
    super.initState();
    if (widget.attachment.isImage) {
      _thumbnail = widget.gateway.download(widget.attachment);
    }
  }

  Future<void> _preview() async {
    if (_actor != widget.gateway.actorId) return;
    // Reauthorize on every opening instead of reusing the thumbnail's URL.
    final image = widget.gateway.download(widget.attachment);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StreamBuilder<String?>(
        stream: widget.gateway.accounts,
        builder: (context, _) => Dialog(
          child: SizedBox(
            width: 960,
            height: MediaQuery.sizeOf(context).height * .85,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.attachment.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close image preview',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _actor != widget.gateway.actorId
                      ? const Center(child: Text('Image unavailable.'))
                      : FutureBuilder<Uri>(
                          future: image,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return const Center(
                                child: Text(
                                  'Image unavailable. Close and retry.',
                                ),
                              );
                            }
                            if (!snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            return Center(
                              child: InteractiveViewer(
                                minScale: 1,
                                maxScale: 4,
                                child: Image.network(
                                  snapshot.data!.toString(),
                                  fit: BoxFit.contain,
                                  semanticLabel: widget.attachment.name,
                                  errorBuilder: (_, _, _) => const Text(
                                    'Image unavailable. Close and retry.',
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open() async {
    if (_opening || _actor != widget.gateway.actorId) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await widget.downloadFile(() async {
        final uri = await widget.gateway.download(widget.attachment);
        if (!mounted || _actor != widget.gateway.actorId) {
          throw StateError('Account changed');
        }
        return uri;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'File unavailable. Refresh and retry.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 300),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_thumbnail != null)
          Tooltip(
            message: 'Open image preview',
            child: InkWell(
              onTap: _preview,
              child: FutureBuilder<Uri>(
                future: _thumbnail,
                builder: (context, snapshot) {
                  if (snapshot.hasData && _actor == widget.gateway.actorId) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 300,
                          maxHeight: 320,
                        ),
                        child: Image.network(
                          snapshot.data!.toString(),
                          cacheWidth: 600,
                          fit: BoxFit.contain,
                          frameBuilder: (context, child, frame, _) {
                            if (frame != null && !_imageReported) {
                              _imageReported = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted &&
                                    _actor == widget.gateway.actorId) {
                                  widget.onImageDisplayed?.call();
                                }
                              });
                            }
                            return child;
                          },
                          errorBuilder: (_, _, _) => const Text(
                            'Image preview unavailable. Use Download file.',
                          ),
                        ),
                      ),
                    );
                  }
                  return Text(
                    snapshot.hasError
                        ? 'Image preview unavailable.'
                        : 'Loading image…',
                  );
                },
              ),
            ),
          ),
        if (!widget.attachment.isImage)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  switch (widget.attachment.name
                      .split('.')
                      .last
                      .toLowerCase()) {
                    'pdf' => Icons.picture_as_pdf_outlined,
                    'xlsx' => Icons.table_chart_outlined,
                    _ => Icons.description_outlined,
                  },
                  size: 32,
                  color: JobMateTheme.darkTeal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.attachment.name,
                        style: const TextStyle(color: JobMateTheme.heading),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${(widget.attachment.size / 1024).toStringAsFixed(1)} KB',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: JobMateTheme.body),
                      ),
                    ],
                  ),
                ),
                _downloadButton(),
              ],
            ),
          ),
        if (widget.attachment.isImage)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(widget.attachment.size / 1024).toStringAsFixed(1)} KB',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: widget.foregroundColor ?? JobMateTheme.body,
                ),
              ),
              _downloadButton(),
            ],
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(
              color: widget.foregroundColor ?? JobMateTheme.error,
            ),
          ),
      ],
    ),
  );

  Widget _downloadButton() => IconButton(
    tooltip: 'Download file',
    onPressed: _opening ? null : _open,
    icon: _opening
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            Icons.download_outlined,
            size: 20,
            color: widget.attachment.isImage
                ? widget.foregroundColor
                : JobMateTheme.darkTeal,
          ),
  );
}
