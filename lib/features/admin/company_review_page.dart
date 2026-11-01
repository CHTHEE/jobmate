import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets/mobile_back_action.dart';

class CompanyReviewPage extends StatefulWidget {
  const CompanyReviewPage({super.key});

  @override
  State<CompanyReviewPage> createState() => _CompanyReviewPageState();
}

class _CompanyReviewPageState extends State<CompanyReviewPage> {
  static const _pageSize = 20;
  final _supabase = Supabase.instance.client;
  final _actorId = Supabase.instance.client.auth.currentUser?.id;

  List<Map<String, dynamic>> _requests = [];
  bool _loading = false;
  bool _working = false;
  bool _hasMore = false;
  int _offset = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    if (_loading || _working) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_actorId == null || _supabase.auth.currentUser?.id != _actorId) {
        throw StateError('Your signed-in account has changed.');
      }
      final data = await _supabase.rpc(
        'list_company_review_requests',
        params: {'p_limit': _pageSize + 1, 'p_offset': _offset},
      );
      if (!mounted) return;
      if (_supabase.auth.currentUser?.id != _actorId) {
        throw StateError('Your signed-in account has changed.');
      }
      if (data is! List) {
        throw const FormatException('Unexpected Company review response.');
      }
      final rows = data
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      setState(() {
        _requests = rows.take(_pageSize).toList();
        _hasMore = rows.length > _pageSize;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      debugPrint('Company review queue load failed: $error');
      if (!mounted) return;
      setState(() {
        _error = error is StateError
            ? error.message.toString()
            : 'Unable to load Company review requests. Please retry.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _label(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Future<void> _openDocument(Map<String, dynamic> request) async {
    if (_working) return;
    final path = request['storage_path'] as String?;
    if (path == null || path.isEmpty) {
      _showMessage('This request does not have a document path.');
      return;
    }
    setState(() => _working = true);
    try {
      if (_supabase.auth.currentUser?.id != _actorId) {
        throw StateError('Your signed-in account has changed.');
      }
      final url = await _supabase.storage
          .from('jobmate-company-verification')
          .createSignedUrl(path, 60);
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('Unable to open the document.');
    } catch (error) {
      debugPrint('Company document open failed: $error');
      if (mounted) {
        _showMessage(
          error is StateError
              ? error.message.toString()
              : 'Unable to open the private PDF. Check your review permission and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String?> _askRejectionReason() async {
    final controller = TextEditingController();
    String? validationMessage;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reject Company application'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('The Company owner will see this reason.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: 'Rejection reason',
                  errorText: validationMessage,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final reason = controller.text.trim();
                if (reason.isEmpty) {
                  setDialogState(
                    () => validationMessage = 'Enter a reason to continue.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, reason);
              },
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _review(
    Map<String, dynamic> request, {
    required bool approve,
  }) async {
    if (_working) return;
    final String? comment;
    if (approve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Approve Company?'),
          content: const Text(
            'This marks the Company as verified and allows its owner to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Approve'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      comment = null;
    } else {
      comment = await _askRejectionReason();
      if (!mounted || comment == null) return;
    }

    setState(() => _working = true);
    try {
      if (_actorId == null || _supabase.auth.currentUser?.id != _actorId) {
        throw StateError('Your signed-in account has changed.');
      }
      await _supabase.rpc(
        'review_company_request',
        params: {
          'p_request_id': request['request_id'],
          'p_decision': approve ? 'verified' : 'rejected',
          'p_review_comment': comment,
        },
      );
      if (!mounted) return;
      _showMessage(approve ? 'Company approved.' : 'Company rejected.');
      setState(() => _working = false);
      await _loadRequests();
    } on PostgrestException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      debugPrint('Company review action failed: $error');
      if (mounted) {
        _showMessage('Unable to save the review. Refresh and try again.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showDetails(Map<String, dynamic> request) {
    final snapshot = request['profile_snapshot'];
    final details = snapshot is Map
        ? Map<String, dynamic>.from(snapshot)
        : <String, dynamic>{};
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(request['company_name'] as String? ?? 'Company details'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in details.entries)
                  if (entry.value != null && entry.value.toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _label(entry.key),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 2),
                          SelectableText(entry.value.toString()),
                        ],
                      ),
                    ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _working ? null : () => _openDocument(request),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(
                    request['original_name'] as String? ?? 'Open supporting PDF',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _changePage(int amount) {
    if (_loading || _working) return;
    final next = _offset + amount;
    if (next < 0 || (amount > 0 && !_hasMore)) return;
    setState(() {
      _offset = next;
      _requests = [];
    });
    _loadRequests();
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final companyName =
        request['company_name'] as String? ?? 'Company application';
    final submittedAt = request['submitted_at']?.toString();
    final filename = request['original_name'] as String? ?? 'Supporting PDF';
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(companyName, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('Submitted: ${submittedAt ?? 'Unknown'}'),
            Text('Document: $filename'),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _working ? null : () => _showDetails(request),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Review details'),
                ),
                FilledButton.tonal(
                  onPressed: _working
                      ? null
                      : () => _review(request, approve: false),
                  child: const Text('Reject'),
                ),
                FilledButton.icon(
                  onPressed: _working
                      ? null
                      : () => _review(request, approve: true),
                  icon: const Icon(Icons.check),
                  label: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: mobileBackLeading(context),
        title: const Text('Company reviews'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _working ? null : _loadRequests,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1050),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _loadRequests,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _requests.isEmpty
                  ? const Center(child: Text('No Company applications are waiting for review.'))
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          'Pending Company applications',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 16),
                        for (final request in _requests)
                          _buildRequestCard(request),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: _offset == 0
                                  ? null
                                  : () => _changePage(-_pageSize),
                              child: const Text('Previous'),
                            ),
                            Text('Page ${_offset ~/ _pageSize + 1}'),
                            TextButton(
                              onPressed: _hasMore
                                  ? () => _changePage(_pageSize)
                                  : null,
                              child: const Text('Next'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
          if (_working)
            const ColoredBox(
              color: Color(0x55000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
