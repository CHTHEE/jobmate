import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'company_review_gateway.dart';

String companySubmissionDate(BuildContext context, dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return 'Not available';
  final format = MaterialLocalizations.of(context);
  return '${format.formatMediumDate(date)}, ${format.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true)}';
}

class CompanyReviewDetails extends StatefulWidget {
  const CompanyReviewDetails({
    super.key,
    required this.request,
    required this.gateway,
    this.openUrl,
  });
  final Map<String, dynamic> request;
  final CompanyReviewGateway gateway;
  final Future<bool> Function(Uri)? openUrl;

  @override
  State<CompanyReviewDetails> createState() => _CompanyReviewDetailsState();
}

class _CompanyReviewDetailsState extends State<CompanyReviewDetails> {
  bool _preparing = false;
  bool _opening = false;
  String? _error;
  List<Uri>? _links;
  DateTime? _expires;
  Timer? _expiryTimer;

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_preparing || _opening) return;
    setState(() {
      _preparing = true;
      _error = null;
      _links = null;
    });
    final expires = DateTime.now().add(const Duration(seconds: 50));
    try {
      final path = widget.request['storage_path'] as String? ?? '';
      final links = await Future.wait([
        widget.gateway.documentUrl(path, download: false),
        widget.gateway.documentUrl(path, download: true),
      ]);
      widget.gateway.checkSession();
      if (!mounted) return;
      if (!DateTime.now().isBefore(expires)) {
        throw StateError('Document access expired while preparing.');
      }
      setState(() {
        _links = links;
        _expires = expires;
      });
      _expiryTimer?.cancel();
      _expiryTimer = Timer(expires.difference(DateTime.now()), () {
        if (mounted) setState(() => _links = null);
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'We could not open the verification document. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _open(bool download) async {
    if (_opening || _links == null) return;
    try {
      widget.gateway.checkSession();
      if (_expires == null || !DateTime.now().isBefore(_expires!)) {
        setState(() {
          _links = null;
          _error = 'Document access expired. Please prepare a new link.';
        });
        return;
      }
      setState(() {
        _opening = true;
        _error = null;
      });
      final uri = _links![download ? 1 : 0];
      // Separate preparation keeps this launch directly tied to the user's click
      // on web; awaiting Storage before launch can trigger popup blockers.
      final opened =
          await (widget.openUrl?.call(uri) ??
              launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
                webOnlyWindowName: '_blank',
              ));
      if (!opened) throw StateError('Unable to open document.');
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to open the PDF. Allow the document window or prepare a new secure link and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        SelectableText(value),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final snapshot = request['profile_snapshot'];
    final details = snapshot is Map ? snapshot : <String, dynamic>{};
    final bytes = request['size_bytes'];
    return AlertDialog(
      title: Text(request['company_name'] as String? ?? 'Company details'),
      scrollable: true,
      content: SizedBox(
        width: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Chip(label: Text('Pending review')),
            ),
            _field(
              'Company ID',
              request['company_id']?.toString() ?? 'Not available',
            ),
            _field(
              'Submitted',
              companySubmissionDate(context, request['submitted_at']),
            ),
            const Divider(),
            if (details.isEmpty)
              const Text('No company snapshot details were provided.'),
            for (final entry in details.entries)
              if (entry.value != null &&
                  entry.value.toString().trim().isNotEmpty)
                _field(
                  entry.key.toString().replaceAll('_', ' '),
                  entry.value.toString(),
                ),
            const Divider(),
            _field(
              'Supporting PDF',
              request['original_name'] as String? ?? 'Not available',
            ),
            _field(
              'File size',
              bytes is num
                  ? '${(bytes / 1024).toStringAsFixed(1)} KiB (${bytes.toInt()} bytes)'
                  : 'Not available',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_preparing)
              const Center(child: CircularProgressIndicator())
            else if (_links == null)
              OutlinedButton.icon(
                onPressed: _opening ? null : _prepare,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Prepare secure PDF access'),
              )
            else ...[
              const Text(
                'Secure access is temporary. The PDF opens in your browser or PDF application.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _opening ? null : () => _open(false),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('View PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _opening ? null : () => _open(true),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Download PDF'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
