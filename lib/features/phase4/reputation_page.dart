import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import 'phase4_store.dart';
import 'reputation_gateway.dart';

class ReputationPage extends StatelessWidget {
  const ReputationPage({
    super.key,
    this.employer = false,
    this.store,
    this.gateway,
  });

  final bool employer;
  // Kept for source compatibility with the old preview route; reputation is
  // now loaded only from server-verified aggregate RPCs.
  final Phase4Store? store;
  final ReputationGateway? gateway;

  @override
  Widget build(BuildContext context) => AppWorkspace(
    title: employer ? 'Company Reputation' : 'My Reputation',
    path: employer ? AppRoutes.employerReputation : AppRoutes.reputation,
    role: employer ? 'employer' : 'job_seeker',
    child: WorkspaceContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeading(
            title: employer ? 'Company Reputation' : 'My Reputation',
            description: employer
                ? 'Published evaluations for Companies you currently manage.'
                : 'Published evaluations and verified completed work for your account.',
          ),
          ReputationContent(employer: employer, store: store, gateway: gateway),
        ],
      ),
    ),
  );
}

/// Embedded in the real Job Seeker profile and also used on the role pages.
class ReputationContent extends StatefulWidget {
  const ReputationContent({
    super.key,
    this.employer = false,
    this.store,
    this.interactive = true,
    this.gateway,
  });

  final bool employer;
  final Phase4Store? store;
  final bool interactive;
  final ReputationGateway? gateway;

  @override
  State<ReputationContent> createState() => _ReputationContentState();
}

class _ReputationContentState extends State<ReputationContent> {
  late final ReputationGateway _gateway =
      widget.gateway ?? SupabaseReputationGateway(Supabase.instance.client);
  late Future<Object> _summary = _load();

  Future<Object> _load() async => widget.employer
      ? await _gateway.companySummaries()
      : await _gateway.workerSummary();

  void _retry() => setState(() => _summary = _load());

  int _int(Map<String, dynamic> row, String key) =>
      (row[key] as num?)?.toInt() ?? 0;

  double? _double(Map<String, dynamic> row, String key) =>
      (row[key] as num?)?.toDouble();

  @override
  Widget build(BuildContext context) => FutureBuilder<Object>(
    future: _summary,
    builder: (context, snapshot) {
      Widget body;
      if (snapshot.connectionState != ConnectionState.done) {
        body = const Center(child: CircularProgressIndicator());
      } else if (snapshot.hasError) {
        body = WorkspaceCard(
          title: 'Reputation unavailable',
          child: const Text(
            'We could not load the verified summary. Try again.',
          ),
        );
      } else if (widget.employer) {
        body = _companyContent(
          (snapshot.data! as List).cast<Map<String, dynamic>>(),
        );
      } else {
        body = _workerContent(snapshot.data! as Map<String, dynamic>);
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.interactive)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: snapshot.connectionState == ConnectionState.done
                    ? _retry
                    : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh reputation'),
              ),
            ),
          if (snapshot.hasError)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: widget.interactive ? _retry : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          body,
        ],
      );
    },
  );

  Widget _workerContent(Map<String, dynamic> row) {
    final published = _int(row, 'published_application_count');
    final rated = _int(row, 'rated_application_count');
    final average = _double(row, 'core_average');
    final shifts = _int(row, 'verified_completed_shift_count');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspaceCard(
          title: 'Evaluation',
          subtitle: 'Company evaluations revealed after both sides submit.',
          leading: const Icon(Icons.rate_review_outlined),
          child: _metric(
            average == null
                ? 'No ratings yet'
                : '${average.toStringAsFixed(2)} / 5',
            '$rated Core-rated applications - $published published evaluations',
          ),
        ),
        const SizedBox(height: 12),
        WorkspaceCard(
          title: 'Working Performance',
          subtitle:
              'Verified work records only; each row is one scheduled Shift.',
          leading: const Icon(Icons.verified_outlined),
          child: _metric(
            shifts == 0 ? 'No verified completed Shifts yet' : '$shifts',
            'completed and verified Shifts',
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Applications have equal weight in the evaluation average. Shifts with an unresolved related dispute are excluded. Attendance and punctuality are not scored.',
        ),
      ],
    );
  }

  Widget _companyContent(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const WorkspaceCard(
        title: 'Company Reputation',
        child: Text('No Company is currently available to this account.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows) ...[
          WorkspaceCard(
            title: row['company_name'] as String? ?? 'Company',
            subtitle:
                'Evaluation - Worker feedback revealed after both sides submit',
            leading: const Icon(Icons.business_outlined),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _metric(
                  _averageLabel(_double(row, 'core_average')),
                  '${_int(row, 'rated_application_count')} Core-rated applications - ${_int(row, 'published_application_count')} published evaluations',
                ),
                const SizedBox(height: 16),
                const Text('Criteria breakdown'),
                const SizedBox(height: 8),
                ..._criteria(row['criteria_averages']).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${item['label']}: ${item['average'] == null ? 'No ratings' : '${(item['average'] as num).toStringAsFixed(2)} / 5'} (${item['sample_count']} applications)',
                    ),
                  ),
                ),
                if (_criteria(row['criteria_averages']).isEmpty)
                  const Text('No published criterion ratings yet.'),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const Text(
          'Company feedback belongs to the Company; it is not assigned to individual members.',
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _criteria(Object? value) => value is List
      ? value.map((item) => Map<String, dynamic>.from(item as Map)).toList()
      : const [];

  String _averageLabel(double? value) =>
      value == null ? 'No ratings yet' : '${value.toStringAsFixed(2)} / 5';

  Widget _metric(String value, String detail) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      Text(detail),
    ],
  );
}
