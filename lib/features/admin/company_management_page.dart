import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/responsive_layout.dart';
import 'company_management_gateway.dart';

class CompanyManagementPage extends StatefulWidget {
  const CompanyManagementPage({super.key, this.companyId, this.gateway});
  final String? companyId;
  final CompanyManagementGateway? gateway;

  @override
  State<CompanyManagementPage> createState() => _CompanyManagementPageState();
}

class _CompanyManagementPageState extends State<CompanyManagementPage> {
  static const _pageSize = 5;
  final _searchController = TextEditingController();
  late final CompanyManagementGateway _gateway =
      widget.gateway ??
      SupabaseCompanyManagementGateway(Supabase.instance.client);
  List<Map<String, dynamic>> _companies = [], _history = [];
  Map<String, dynamic>? _company;
  final _listController = ScrollController();
  String? _selectedCompanyId;
  Timer? _searchDebounce;
  int _requestGeneration = 0;
  String _search = '';
  String? _verificationStatus;
  String? _restrictionStatus;
  bool _loading = false, _loadingMore = false, _detailsLoading = false;
  bool _busy = false, _hasMore = false;
  bool _canManageRestrictions = false;
  String? _error;
  String? _detailsError;

  @override
  void initState() {
    super.initState();
    _selectedCompanyId = widget.companyId;
    _detailsLoading = _selectedCompanyId != null;
    _listController.addListener(_onListScroll);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _listController
      ..removeListener(_onListScroll)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CompanyManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) {
      _selectedCompanyId = widget.companyId;
      _load();
    }
  }

  void _onListScroll() {
    if (!_listController.hasClients || _loading || _loadingMore || !_hasMore) {
      return;
    }
    if (_listController.position.extentAfter < 220) _loadMore();
  }

  Future<void> _load() async {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _detailsLoading = _selectedCompanyId != null;
      _companies = [];
      _hasMore = false;
    });
    try {
      // Directory access is read-only for every active Admin. Keep its
      // initial load independent from optional restriction permissions.
      unawaited(_loadRestrictionPermission());
      final rows = await _gateway
          .list(
            limit: _pageSize + 1,
            offset: 0,
            search: _search,
            verificationStatus: _verificationStatus,
            restrictionStatus: _restrictionStatus,
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted || generation != _requestGeneration) return;
      final companies = rows.take(_pageSize).toList();
      final requested = _selectedCompanyId;
      final selected =
          widget.companyId ??
          requested ??
          (companies.isEmpty
              ? null
              : companies.first['company_id']?.toString());
      setState(() {
        _companies = companies;
        _hasMore = rows.length > _pageSize;
        _selectedCompanyId = selected;
        _company = null;
        _history = [];
        _detailsError = null;
        _detailsLoading = selected != null;
      });
      if (selected != null) await _loadCompanyDetails(selected);
    } catch (_) {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _error = 'We could not load company information. Please try again.';
          if (_selectedCompanyId != null && _company == null) {
            _detailsError =
                'We could not load company details. Please try again.';
          }
        });
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _loading = false;
          if (_company == null) _detailsLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final generation = _requestGeneration;
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    try {
      final rows = await _gateway
          .list(
            limit: _pageSize + 1,
            offset: _companies.length,
            search: _search,
            verificationStatus: _verificationStatus,
            restrictionStatus: _restrictionStatus,
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        final seen = _companies.map((item) => item['company_id']).toSet();
        _companies.addAll(
          rows
              .take(_pageSize)
              .where((item) => !seen.contains(item['company_id'])),
        );
        _hasMore = rows.length > _pageSize;
      });
    } catch (_) {
      if (mounted && generation == _requestGeneration) {
        setState(
          () => _error = 'We could not load more companies. Please retry.',
        );
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _requestGeneration++;
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _search = value.trim();
        if (widget.companyId == null) _selectedCompanyId = null;
      });
      _load();
    });
  }

  Future<void> _openFilters() async {
    final filters = await showDialog<(String?, String?)>(
      context: context,
      builder: (context) => _CompanyDirectoryFilterDialog(
        verificationStatus: _verificationStatus,
        restrictionStatus: _restrictionStatus,
      ),
    );
    if (filters == null || !mounted) return;
    setState(() {
      _verificationStatus = filters.$1;
      _restrictionStatus = filters.$2;
      if (widget.companyId == null) _selectedCompanyId = null;
    });
    await _load();
  }

  Future<void> _loadCompanyDetails(String companyId) async {
    setState(() {
      _detailsLoading = true;
      _detailsError = null;
    });
    try {
      final canManage = await _gateway.canManageRestrictions().timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
      final company = canManage
          ? await _gateway
                .managementDetails(companyId)
                .timeout(const Duration(seconds: 20))
          : await _gateway
                .details(companyId)
                .timeout(const Duration(seconds: 20));
      final history = canManage
          ? await _gateway
                .history(companyId)
                .timeout(const Duration(seconds: 20))
          : <Map<String, dynamic>>[];
      if (!mounted || _selectedCompanyId != companyId) return;
      setState(() {
        _company = company;
        _history = history;
        _canManageRestrictions = canManage;
        _detailsError = null;
      });
    } catch (_) {
      if (mounted && _selectedCompanyId == companyId) {
        setState(() {
          _company = null;
          _history = [];
          _detailsError = 'We could not load company details. Please retry.';
        });
      }
    } finally {
      if (mounted && _selectedCompanyId == companyId) {
        setState(() => _detailsLoading = false);
      }
    }
  }

  void _selectCompany(Map<String, dynamic> item) {
    final id = item['company_id']?.toString();
    if (id == null || id.isEmpty || id == _selectedCompanyId) return;
    setState(() {
      _selectedCompanyId = id;
      _company = null;
      _history = [];
      _detailsError = null;
    });
    _loadCompanyDetails(id);
  }

  Future<void> _loadRestrictionPermission() async {
    try {
      final canManage = await _gateway.canManageRestrictions().timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
      if (mounted) setState(() => _canManageRestrictions = canManage);
    } catch (error) {
      debugPrint('Company restriction permission lookup failed: $error');
      if (mounted) setState(() => _canManageRestrictions = false);
    }
  }

  Future<void> _changeRestriction() async {
    final company = _company;
    if (company == null || _busy) return;
    final restricted = company['restriction_status'] == 'restricted';
    final action = restricted ? 'restore' : 'restrict';
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RestrictionReasonDialog(action: action),
    );
    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final companyId = _selectedCompanyId;
      if (companyId == null) return;
      await _gateway.setRestriction(companyId, action, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            restricted ? 'Company restored.' : 'Company restricted.',
          ),
        ),
      );
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _detailsError = 'The Company action was not confirmed. Reload and check its current status.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _value(Object? value) => value?.toString().trim().isNotEmpty == true
      ? value.toString()
      : 'Not provided';

  Widget _companyListRow(Map<String, dynamic> item) {
    final selected = item['company_id']?.toString() == _selectedCompanyId;
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minVerticalPadding: 18,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        selected: selected,
        selectedTileColor: const Color(0xFFE8F8F5),
        leading: const CircleAvatar(
          radius: 25,
          backgroundColor: Color(0xFF9AF3E4),
          foregroundColor: Color(0xFF075E58),
          child: Icon(Icons.business_outlined),
        ),
        title: Text(_value(item['company_name'])),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${_status(item['verification_status'])} / '
            '${_status(item['restriction_status'])} / '
            '${_value(item['member_count'])} members',
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: selected ? const Color(0xFF087F75) : null,
        ),
        onTap: () => _selectCompany(item),
      ),
    );
  }

  Widget _directory() => LayoutBuilder(
    builder: (context, constraints) => ResponsiveContent(
      maxWidth: 1320,
      child: SizedBox(
        height: constraints.maxHeight,
        child: Padding(
          padding: ResponsiveLayout.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeading(
                title: 'Company management',
                description:
                    'Browse company profiles and administrative status.',
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, panes) {
                    final list = Card.outlined(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Companies (${_companies.length})',
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Search and filter companies',
                                  onPressed: _openFilters,
                                  color:
                                      _verificationStatus != null ||
                                          _restrictionStatus != null
                                      ? const Color(0xFF087F75)
                                      : null,
                                  icon: const Icon(Icons.tune),
                                ),
                                IconButton(
                                  tooltip: 'Refresh companies',
                                  onPressed: _loading ? null : _load,
                                  icon: const Icon(Icons.refresh),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: TextField(
                              controller: _searchController,
                              onChanged: _onSearchChanged,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                hintText: 'Search company name',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: _companies.isEmpty && _loading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _companies.isEmpty && _error == null
                                ? const Center(
                                    child: Text('No companies found.'),
                                  )
                                : ListView(
                                    key: const ValueKey('admin-company-list'),
                                    controller: _listController,
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.all(8),
                                    children: [
                                      for (final item in _companies)
                                        _companyListRow(item),
                                      if (_error != null)
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            children: [
                                              Text(
                                                _error!,
                                                textAlign: TextAlign.center,
                                              ),
                                              TextButton(
                                                onPressed: _loadingMore
                                                    ? null
                                                    : _loadMore,
                                                child: const Text('Retry'),
                                              ),
                                            ],
                                          ),
                                        )
                                      else if (_loadingMore)
                                        const Padding(
                                          padding: EdgeInsets.all(16),
                                          child: Center(
                                            child: SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    );
                    final detail = Card.outlined(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                            child: Text('Company details'),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: _detailsLoading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _details(),
                          ),
                        ],
                      ),
                    );
                    if (panes.maxWidth < 760) {
                      return Column(
                        children: [
                          Expanded(flex: 5, child: list),
                          const SizedBox(height: 10),
                          Expanded(flex: 4, child: detail),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: list),
                        const SizedBox(width: 12),
                        Expanded(flex: 6, child: detail),
                      ],
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

  Widget _errorPanel({bool details = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        Text(
          (details ? _detailsError : _error)!,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        TextButton(
          onPressed: details
              ? (_detailsLoading || _selectedCompanyId == null
                    ? null
                    : () => _loadCompanyDetails(_selectedCompanyId!))
              : (_loading ? null : _load),
          child: const Text('Retry'),
        ),
      ],
    ),
  );

  Widget _details() {
    final item = _company;
    if (item == null) {
      if (_selectedCompanyId == null) {
        return const Center(
          child: Text('Select a company to view its details.'),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _detailsError ?? 'Company details are unavailable.',
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: _detailsLoading || _selectedCompanyId == null
                    ? null
                    : () => _loadCompanyDetails(_selectedCompanyId!),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final restricted = item['restriction_status'] == 'restricted';
    final members = (item['members'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    return ListView(
      key: const ValueKey('company-details-scroll'),
      padding: const EdgeInsets.all(20),
      children: [
        PageHeading(
          title: _value(item['company_name']),
          description: 'Company profile and current administrative status.',
        ),
        Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _copyableId(item['company_id']?.toString() ?? ''),
                _info(
                  'Operational status',
                  _status(item['restriction_status']),
                ),
                _info(
                  'Verification status',
                  _status(item['verification_status']),
                ),
                _info('Description', _value(item['company_description'])),
                _info('Industry', _value(item['industry'])),
                _info('Location', _value(item['location'])),
                _info('Created', _date(item['created_at'])),
                if (_canManageRestrictions && restricted)
                  _info(
                    'Restriction reason',
                    _value(item['restriction_reason']),
                  ),
                if (_canManageRestrictions) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _changeRestriction,
                    icon: Icon(restricted ? Icons.lock_open : Icons.block),
                    label: Text(
                      _busy
                          ? 'Saving…'
                          : restricted
                          ? 'Restore company'
                          : 'Restrict company',
                    ),
                  ),
                ],
                if (_detailsError != null) _errorPanel(details: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Memberships (${members.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (members.isEmpty) const Text('No memberships are recorded.'),
        for (final member in members)
          Card.outlined(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(_value(member['name'])),
              subtitle: Text(_status(member['member_role'])),
            ),
          ),
        if (_canManageRestrictions) ...[
          const SizedBox(height: 20),
          Text(
            'Restriction history and Admin audit',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            const Text('No restriction actions have been recorded.'),
          for (final row in _history)
            Card.outlined(
              child: ListTile(
                leading: Icon(
                  row['action'] == 'restricted'
                      ? Icons.block
                      : Icons.lock_open,
                ),
                title: Text(
                  '${_status(row['action'])} · ${_date(row['performed_at'])}',
                ),
                subtitle: Text(
                  'Reason: ${_value(row['reason'])}\nAdmin: ${_value(row['actor_name'])}',
                ),
                isThreeLine: true,
              ),
            ),
        ],
        if (_detailsError != null) _errorPanel(details: true),
      ],
    );
  }

  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 180,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );

  String _status(Object? value) {
    if (value == null || value.toString().isEmpty) return 'Not provided';
    return value
        .toString()
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  String _date(Object? value) {
    final parsed = value is DateTime
        ? value
        : DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return _value(value);
    final local = parsed.toLocal();
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatMediumDate(local)} ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  Widget _copyableId(String id) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        const SizedBox(
          width: 180,
          child: Text(
            'Company ID',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(id, maxLines: 1, overflow: TextOverflow.ellipsis)),
        IconButton(
          tooltip: 'Copy Company ID',
          onPressed: id.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: id));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Company ID copied.')),
                    );
                  }
                },
          icon: const Icon(Icons.copy_outlined),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AppWorkspace(
    title: 'Company Management',
    titleWidget: const SizedBox.shrink(),
    path: widget.companyId == null
        ? AppRoutes.adminCompanies
        : '${AppRoutes.adminCompanies}/${widget.companyId}',
    role: 'administrator',
    focused: widget.companyId != null,
    backFallback: AppRoutes.adminCompanies,
    child: _directory(),
  );
}

class _RestrictionReasonDialog extends StatefulWidget {
  const _RestrictionReasonDialog({required this.action});
  final String action;
  @override
  State<_RestrictionReasonDialog> createState() =>
      _RestrictionReasonDialogState();
}

class _RestrictionReasonDialogState extends State<_RestrictionReasonDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _discardConfirm = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _cancel() {
    if (_controller.text.trim().isNotEmpty && !_discardConfirm) {
      setState(() {
        _discardConfirm = true;
        _error = 'Discard the reason or keep editing.';
      });
    } else if (_discardConfirm) {
      setState(() {
        _discardConfirm = false;
        _error = null;
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.action == 'restrict' ? 'Restrict company' : 'Restore company',
    ),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.action == 'restrict'
                ? 'This records a company restriction. It may not yet block all company activity across JobMate.'
                : 'Restoration returns the Company to operational status. Historical records remain unchanged.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLength: 2000,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Required reason',
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      if (_discardConfirm)
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Discard'),
        ),
      TextButton(
        onPressed: _discardConfirm
            ? () => setState(() {
                _discardConfirm = false;
                _error = null;
              })
            : _cancel,
        child: Text(_discardConfirm ? 'Keep editing' : 'Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final reason = _controller.text.trim();
          if (reason.isEmpty) {
            setState(() => _error = 'Enter a reason.');
            return;
          }
          if (reason.length > 2000) {
            setState(() => _error = 'Reason must be 2000 characters or fewer.');
            return;
          }
          Navigator.pop(context, reason);
        },
        child: Text(widget.action == 'restrict' ? 'Restrict' : 'Restore'),
      ),
    ],
  );
}

class _CompanyDirectoryFilterDialog extends StatefulWidget {
  const _CompanyDirectoryFilterDialog({
    required this.verificationStatus,
    required this.restrictionStatus,
  });

  final String? verificationStatus;
  final String? restrictionStatus;

  @override
  State<_CompanyDirectoryFilterDialog> createState() =>
      _CompanyDirectoryFilterDialogState();
}

class _CompanyDirectoryFilterDialogState
    extends State<_CompanyDirectoryFilterDialog> {
  late String _verification = widget.verificationStatus ?? 'all';
  late String _restriction = widget.restrictionStatus ?? 'all';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Filter companies'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _verification,
          decoration: const InputDecoration(labelText: 'Verification status'),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All statuses')),
            DropdownMenuItem(value: 'pending', child: Text('Pending')),
            DropdownMenuItem(value: 'verified', child: Text('Verified')),
            DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _verification = value);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _restriction,
          decoration: const InputDecoration(labelText: 'Operational status'),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All statuses')),
            DropdownMenuItem(value: 'active', child: Text('Active')),
            DropdownMenuItem(value: 'restricted', child: Text('Restricted')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _restriction = value);
          },
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, (null, null)),
        child: const Text('Clear'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          (
            _verification == 'all' ? null : _verification,
            _restriction == 'all' ? null : _restriction,
          ),
        ),
        child: const Text('Apply'),
      ),
    ],
  );
}
