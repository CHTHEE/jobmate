import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/app_workspace.dart';
import '../../shared/navigation/app_routes.dart';
import '../../shared/navigation/workspace_destinations.dart';
import '../../shared/widgets/responsive_layout.dart';
import 'company_rejection_dialog.dart';
import 'company_review_details.dart';
import 'company_review_gateway.dart';
import 'company_logo_review_details.dart';

class CompanyReviewPage extends StatefulWidget {
  const CompanyReviewPage({super.key, this.gateway, this.logoGateway});
  final CompanyReviewGateway? gateway;
  final CompanyReviewGateway? logoGateway;

  @override
  State<CompanyReviewPage> createState() => _CompanyReviewPageState();
}

class _CompanyReviewPageState extends State<CompanyReviewPage> {
  static const _pageSize = 20;
  late final CompanyReviewGateway _documentGateway;
  late final CompanyReviewGateway _logoGateway =
      widget.logoGateway ??
      SupabaseCompanyLogoReviewGateway(Supabase.instance.client);
  bool _isLogo = false;
  CompanyReviewGateway get _gateway =>
      _isLogo ? _logoGateway : _documentGateway;
  List<Map<String, dynamic>> _requests = [];
  bool _loading = false;
  bool _working = false;
  bool _confirming = false;
  bool _hasMore = false;
  int _offset = 0;
  String? _error;
  bool get _busy => _loading || _working || _confirming;

  @override
  void initState() {
    super.initState();
    _documentGateway =
        widget.gateway ??
        SupabaseCompanyReviewGateway(Supabase.instance.client);
    _loadRequests();
  }

  String _message(Object error) {
    if (error is PostgrestException) return error.message;
    if (error is StateError) return error.message.toString();
    if (error is FormatException) return error.message;
    return 'Unable to confirm the result. Refresh the queue and try again.';
  }

  Future<void> _loadRequests() async {
    if (_busy) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _gateway.pending(
        limit: _pageSize + 1,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _requests = rows.take(_pageSize).toList();
        _hasMore = rows.length > _pageSize;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _requests = [];
          _hasMore = false;
          _error = _message(error);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showDetails(Map<String, dynamic> request) async {
    if (_busy) return;
    setState(() => _confirming = true);
    try {
      _gateway.checkSession();
      await showDialog<void>(
        context: context,
        builder: (_) => _isLogo
            ? CompanyLogoReviewDetails(request: request, gateway: _gateway)
            : CompanyReviewDetails(request: request, gateway: _gateway),
      );
    } catch (error) {
      _showMessage(_message(error));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _review(
    Map<String, dynamic> request, {
    required bool approve,
  }) async {
    if (_busy) return;
    setState(() => _confirming = true);
    try {
      _gateway.checkSession();
      final comment = await showDialog<String>(
        context: context,
        builder: (_) => CompanyRejectionDialog(approve: approve, logo: _isLogo),
      );
      if (!mounted || comment == null) return;
      setState(() {
        _confirming = false;
        _working = true;
      });
      await _gateway.review(
        requestId: request['request_id'] as String,
        decision: approve ? 'verified' : 'rejected',
        comment: comment,
      );
      if (!mounted) return;
      _showMessage(
        _isLogo
            ? (approve
                  ? 'Company logo approved.'
                  : 'Company logo rejected. The owner has been notified.')
            : approve
            ? 'Company approved.'
            : 'Company rejected. The reason has been saved for the owner.',
      );
      if (_requests.length == 1 && _offset > 0) _offset -= _pageSize;
      setState(() => _working = false);
      await _loadRequests();
    } catch (error) {
      if (!mounted) return;
      _showMessage(_message(error));
      // Reload on stale/permission/network errors rather than allowing a blind
      // retry against a request that may already have been reviewed.
      setState(() {
        _working = false;
        _confirming = false;
      });
      await _loadRequests();
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _confirming = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _changePage(int amount) {
    if (_busy || _offset + amount < 0 || (amount > 0 && !_hasMore)) return;
    setState(() {
      _offset += amount;
      _requests = [];
    });
    _loadRequests();
  }

  void _selectQueue(bool logo) {
    if (_busy || logo == _isLogo) return;
    setState(() {
      _isLogo = logo;
      _offset = 0;
      _requests = [];
      _hasMore = false;
      _error = null;
    });
    _loadRequests();
  }

  Widget _requestCard(Map<String, dynamic> request) => Card.outlined(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            request['company_name'] as String? ?? 'Company application',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Submitted: ${companySubmissionDate(context, request['submitted_at'])}',
          ),
          Text(
            _isLogo
                ? 'Company photo change'
                : 'Document: ${request['original_name'] ?? 'Not available'}',
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Chip(label: Text('Pending review')),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _showDetails(request),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('View Details'),
              ),
              FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () => _review(request, approve: false),
                child: const Text('Reject'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _review(request, approve: true),
                icon: const Icon(Icons.check),
                label: const Text('Approve'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_working,
    child: AppWorkspace(
      title: 'Company Verification',
      path: AppRoutes.companyReviews,
      role: 'administrator',
      navigationLocked: _busy,
      navigationGroups: {
        ...workspaceDestinations('administrator'),
        'ADMIN TOOLS': [
          (
            AppRoutes.companyReviews,
            'Company Verification',
            Icons.business_outlined,
          ),
        ],
      },
      child: SafeArea(
        child: Stack(
          children: [
            ResponsiveContent(
              maxWidth: 1050,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _loadRequests,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: ResponsiveLayout.pagePadding(context),
                        children: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Company documents'),
                                selected: !_isLogo,
                                onSelected: _busy
                                    ? null
                                    : (_) => _selectQueue(false),
                              ),
                              ChoiceChip(
                                label: const Text('Logo changes'),
                                selected: _isLogo,
                                onSelected: _busy
                                    ? null
                                    : (_) => _selectQueue(true),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy ? null : _loadRequests,
                              child: const Text('Check for updates'),
                            ),
                          ),
                          Text(
                            _isLogo
                                ? 'Pending logo changes'
                                : 'Pending company applications',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isLogo
                                ? 'Compare the current and proposed photo. Only approval replaces the company logo.'
                                : 'Review the submitted details and private supporting PDF before making a decision.',
                          ),
                          const SizedBox(height: 20),
                          if (_error != null) ...[
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: _busy ? null : _loadRequests,
                              child: const Text('Retry'),
                            ),
                          ] else if (_requests.isEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Icon(Icons.task_alt, size: 48),
                            ),
                            Text(
                              _isLogo
                                  ? 'No logo changes are waiting on this page.'
                                  : 'No company applications are waiting on this page.',
                              textAlign: TextAlign.center,
                            ),
                          ] else
                            for (final request in _requests)
                              _requestCard(request),
                          const SizedBox(height: 20),
                          if (_error == null || _offset > 0)
                            ResponsivePagination(
                              page: _offset ~/ _pageSize + 1,
                              onPrevious: _busy || _offset == 0
                                  ? null
                                  : () => _changePage(-_pageSize),
                              onNext: _busy || !_hasMore
                                  ? null
                                  : () => _changePage(_pageSize),
                            ),
                        ],
                      ),
                    ),
            ),
            if (_working)
              const Positioned.fill(
                child: Stack(
                  children: [
                    ModalBarrier(dismissible: false, color: Color(0x55000000)),
                    Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Saving company review...'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
