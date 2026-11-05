import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../applications/module2_repository.dart';

enum SearchCategory { jobs, companies, people }

class PublicCompanyResult {
  const PublicCompanyResult({
    required this.id,
    required this.name,
    required this.industry,
    required this.location,
  });

  final String id, name, industry, location;
}

abstract class PublicCompanySearch {
  Future<List<PublicCompanyResult>> find(String query);
}

/// Calls a narrow RPC that returns only approved company summary fields.
class SupabasePublicCompanySearch implements PublicCompanySearch {
  const SupabasePublicCompanySearch();

  @override
  Future<List<PublicCompanyResult>> find(String query) async {
    final data = await Supabase.instance.client.rpc(
      'search_public_companies',
      params: {'p_query': query, 'p_limit': 20},
    );
    if (data is! List) throw const FormatException('Invalid company results.');
    return data.map((value) {
      final row = Map<String, dynamic>.from(value as Map);
      return PublicCompanyResult(
        id: row['company_id'] as String,
        name: row['company_name'] as String,
        industry: row['industry'] as String? ?? '',
        location: row['location'] as String? ?? '',
      );
    }).toList();
  }
}

/// The dashboard search uses the same overlay on Web and mobile.
Future<void> showJobMateSearchPanel(
  BuildContext context, {
  PublicCompanySearch? companySearch,
}) => showDialog<void>(
  context: context,
  barrierColor: const Color(0x29000000),
  builder: (dialogContext) => Dialog(
    alignment: Alignment.topCenter,
    insetPadding: const EdgeInsets.fromLTRB(12, 72, 12, 12),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 640,
        maxHeight: MediaQuery.sizeOf(dialogContext).height - 84,
      ),
      child: SizedBox(
        width: 640,
        child: UniversalSearchPage(
          embedded: true,
          companySearch: companySearch,
        ),
      ),
    ),
  ),
);

class UniversalSearchPage extends StatefulWidget {
  const UniversalSearchPage({
    super.key,
    this.companySearch,
    this.embedded = false,
  });
  final PublicCompanySearch? companySearch;
  final bool embedded;

  @override
  State<UniversalSearchPage> createState() => _UniversalSearchPageState();
}

class _UniversalSearchPageState extends State<UniversalSearchPage> {
  final _query = TextEditingController();
  SearchCategory _category = SearchCategory.jobs;
  List<PublicCompanyResult> _companies = const [];
  bool _loading = false;
  String? _error;
  int _request = 0;
  final List<String> _recent = [];

  void _rememberQuery() {
    final value = _query.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _recent.removeWhere((item) => item.toLowerCase() == value.toLowerCase());
      _recent.insert(0, value);
      if (_recent.length > 5) _recent.removeLast();
    });
  }

  @override
  void dispose() {
    _request++;
    _query.dispose();
    super.dispose();
  }

  void _select(SearchCategory category) {
    setState(() => _category = category);
    if (category == SearchCategory.companies) _searchCompanies();
  }

  Future<void> _searchCompanies() async {
    final query = _query.text.trim();
    final request = ++_request;
    if (query.length < 2) {
      setState(() {
        _companies = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    _rememberQuery();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results =
          await (widget.companySearch ?? const SupabasePublicCompanySearch())
              .find(query);
      if (!mounted || request != _request) return;
      setState(() => _companies = results);
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _companies = const [];
        _error = 'Company search is unavailable. The public company search function may not be installed yet.';
      });
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded)
          const PageHeading(
            title: 'Search JobMate',
            description: 'Explore jobs and verified companies.',
            fontSize: 24,
          ),
        if (widget.embedded) ...[
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Search JobMate',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Close search',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        _searchBody(context),
      ],
    );
    if (widget.embedded) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: content,
      );
    }
    return AppWorkspace(
      title: 'Search',
      path: AppRoutes.search,
      role: 'job_seeker',
      child: WorkspaceContent(maxWidth: 960, child: content),
    );
  }

  Widget _searchBody(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _query,
        maxLength: 100,
        buildCounter: (
          _, {
          required currentLength,
          required isFocused,
          maxLength,
        }) => null,
        textInputAction: TextInputAction.search,
        onChanged: (_) {
          _request++;
          setState(() {
            _companies = const [];
            _error = null;
            _loading = false;
          });
        },
        onSubmitted: (_) {
          if (_category == SearchCategory.companies) {
            _searchCompanies();
          } else {
            _rememberQuery();
          }
        },
        decoration: InputDecoration(
          labelText: 'Search jobs or companies',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _query.clear();
                    _searchCompanies();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close),
                ),
        ),
      ),
      if (widget.embedded && _query.text.isEmpty) ...[
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Recent',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (_recent.isNotEmpty)
              TextButton(
                onPressed: () => setState(_recent.clear),
                child: const Text('Clear'),
              ),
          ],
        ),
        if (_recent.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No recent searches in this session.'),
          )
        else
          for (final item in _recent)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(item),
              onTap: () {
                _query.text = item;
                setState(() {});
                if (_category == SearchCategory.companies) _searchCompanies();
              },
            ),
      ],
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in SearchCategory.values)
            ChoiceChip(
              label: Text(switch (item) {
                SearchCategory.jobs => 'Jobs',
                SearchCategory.companies => 'Companies',
                SearchCategory.people => 'People',
              }),
              selected: _category == item,
              onSelected: (_) => _select(item),
            ),
        ],
      ),
      const SizedBox(height: 20),
      if (!widget.embedded || _query.text.trim().isNotEmpty) ...[
        if (_category == SearchCategory.jobs) _jobs(context),
        if (_category == SearchCategory.companies) _companyResults(context),
      ],
      if (_category == SearchCategory.people)
        const WorkspaceCard(
          title: 'People search is not available yet',
          child: Text(
            'Personal profiles need public/private visibility controls before other people can be searched.',
          ),
        ),
    ],
  );

  Widget _jobs(BuildContext context) {
    final jobs = Module2Repository.session.searchJobs(query: _query.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Demo jobs only. Real public job search is awaiting a backend read contract.',
          style: TextStyle(color: JobMateTheme.body),
        ),
        const SizedBox(height: 12),
        if (jobs.isEmpty)
          const WorkspaceCard(
            title: 'No matches',
            child: Text('Try another job or company name.'),
          )
        else
          for (final job in jobs) ...[
            WorkspaceCard(
              title: job.title,
              subtitle: job.company,
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () {
                    final router = GoRouter.of(context);
                    if (widget.embedded) Navigator.of(context).pop();
                    router.push('${AppRoutes.browseJobs}/${job.id}');
                  },
                  child: const Text('View demo job'),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _companyResults(BuildContext context) {
    if (_query.text.trim().length < 2) {
      return const WorkspaceCard(
        title: 'Verified companies',
        child: Text('Enter at least two letters of a company name.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _loading ? null : _searchCompanies,
            icon: const Icon(Icons.search),
            label: const Text('Search companies'),
          ),
        ),
        const SizedBox(height: 16),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_error != null)
          WorkspaceCard(title: 'Unable to search', child: Text(_error!))
        else if (!_loading && _companies.isEmpty)
          const WorkspaceCard(
            title: 'No verified companies found',
            child: Text('Try another company name.'),
          )
        else
          for (final company in _companies) ...[
            WorkspaceCard(
              title: company.name,
              subtitle: 'Verified company',
              child: Text(
                [
                  company.industry,
                  company.location,
                ].where((value) => value.isNotEmpty).join(' • '),
              ),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}
