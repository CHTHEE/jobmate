import 'package:flutter/material.dart';

import '../../shared/widgets/responsive_layout.dart';
import 'company_review_gateway.dart';

/// Shows only the current/proposed pair for this request, not logo history.
class CompanyLogoReviewDetails extends StatefulWidget {
  const CompanyLogoReviewDetails({
    super.key,
    required this.request,
    required this.gateway,
  });
  final Map<String, dynamic> request;
  final CompanyReviewGateway gateway;
  @override
  State<CompanyLogoReviewDetails> createState() =>
      _CompanyLogoReviewDetailsState();
}

class _CompanyLogoReviewDetailsState extends State<CompanyLogoReviewDetails> {
  List<Uri?>? _links;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _links = null;
    });
    try {
      final paths = [
        widget.request['previous_storage_path'],
        widget.request['storage_path'],
      ];
      final links = await Future.wait(
        paths.map(
          (path) async => path == null
              ? null
              : await widget.gateway.documentUrl(
                  path as String,
                  download: false,
                ),
        ),
      );
      widget.gateway.checkSession();
      if (mounted) setState(() => _links = links);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'We could not load the company photos. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _image(String title, Uri? link) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SizedBox(
        height: 180,
        child: link == null
            ? const Center(child: Text('No previous photo'))
            : Image.network(
                link.toString(),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Center(
                  child: Text('Image unavailable. Refresh images.'),
                ),
              ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: SizedBox(
      width: 700,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.request['company_name'] as String? ??
                          'Company logo',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Review the proposed logo before approving. This decision does not verify company documents.',
                    ),
                    const SizedBox(height: 16),
                    if (_loading)
                      const Center(child: CircularProgressIndicator()),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_links != null)
                      ResponsiveGrid(
                        minItemWidth: 220,
                        maxColumns: 2,
                        children: [
                          _image('Current photo at submission', _links![0]),
                          _image('Proposed photo', _links![1]),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: _loading ? null : _load,
                  child: const Text('Refresh images'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
