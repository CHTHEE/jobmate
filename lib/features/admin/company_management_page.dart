import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
  static const _pageSize = 30;
  late final CompanyManagementGateway _gateway =
      widget.gateway ??
      SupabaseCompanyManagementGateway(Supabase.instance.client);
  List<Map<String, dynamic>> _companies = [], _history = [];
  Map<String, dynamic>? _company;
  int _offset = 0;
  bool _loading = true, _busy = false, _hasMore = false;
  bool _canManageRestrictions = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CompanyManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final canManage = await _gateway.canManageRestrictions();
      if (widget.companyId == null) {
        final rows = await _gateway.list(limit: _pageSize + 1, offset: _offset);
        if (!mounted) return;
        setState(() {
          _companies = rows.take(_pageSize).toList();
          _hasMore = rows.length > _pageSize;
          _company = null;
          _history = [];
          _canManageRestrictions = canManage;
        });
      } else {
        final company = canManage
            ? await _gateway.managementDetails(widget.companyId!)
            : await _gateway.details(widget.companyId!);
        final history = canManage
            ? await _gateway.history(widget.companyId!)
            : <Map<String, dynamic>>[];
        if (!mounted) return;
        setState(() {
          _company = company;
          _history = history;
          _canManageRestrictions = canManage;
        });
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'We could not load company information. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _page(int amount) {
    if (_loading || (amount > 0 && !_hasMore)) return;
    final next = _offset + amount;
    if (next < 0) return;
    setState(() {
      _offset = next;
      _companies = [];
    });
    _load();
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
      await _gateway.setRestriction(widget.companyId!, action, reason);
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
      if (mounted)
        setState(
          () => _error = 'The Company action was not confirmed. Reload and check its current status.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _value(Object? value) => value?.toString().trim().isNotEmpty == true
      ? value.toString()
      : 'Not provided';

  Widget _directory() => ResponsiveContent(
    maxWidth: 1050,
    child: ListView(
      padding: ResponsiveLayout.pagePadding(context),
      children: [
        const PageHeading(
          title: 'Companies',
          description:
              'Browse company profiles, membership and current status.',
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _loading ? null : _load,
            child: const Text('Refresh'),
          ),
        ),
        if (_companies.isEmpty && !_loading && _error == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No companies found.')),
          ),
        for (final item in _companies)
          Card.outlined(
            child: ListTile(
              title: Text(_value(item['company_name'])),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Chip(
                      label: Text(
                        'Operations: ${_status(item['restriction_status'])}',
                      ),
                    ),
                    Chip(
                      label: Text(
                        'Verification: ${_status(item['verification_status'])}',
                      ),
                    ),
                    Chip(
                      label: Text('Members: ${_value(item['member_count'])}'),
                    ),
                    if (item['industry'] != null)
                      Chip(label: Text(_value(item['industry']))),
                    if (item['location'] != null)
                      Chip(label: Text(_value(item['location']))),
                  ],
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: item['company_id'] is String
                  ? () => context.push(
                      '${AppRoutes.adminCompanies}/${item['company_id']}',
                    )
                  : null,
            ),
          ),
        if (_error != null) _errorPanel(),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!_loading && _error == null)
          ResponsivePagination(
            page: _offset ~/ _pageSize + 1,
            onPrevious: _offset == 0 ? null : () => _page(-_pageSize),
            onNext: !_hasMore ? null : () => _page(_pageSize),
          ),
      ],
    ),
  );

  Widget _errorPanel() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        TextButton(
          onPressed: _loading ? null : _load,
          child: const Text('Retry'),
        ),
      ],
    ),
  );

  Widget _details() {
    final item = _company;
    if (item == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? 'Company details are unavailable.',
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: _loading ? null : _load,
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
    return ResponsiveContent(
      maxWidth: 980,
      child: ListView(
        key: const ValueKey('company-details-scroll'),
        padding: ResponsiveLayout.pagePadding(context),
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
                  if (_error != null) _errorPanel(),
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
          if (_error != null) _errorPanel(),
        ],
      ),
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
    path: widget.companyId == null
        ? AppRoutes.adminCompanies
        : '${AppRoutes.adminCompanies}/${widget.companyId}',
    role: 'administrator',
    focused: widget.companyId != null,
    backFallback: AppRoutes.adminCompanies,
    child:
        _loading &&
            (widget.companyId == null ? _companies.isEmpty : _company == null)
        ? const Center(child: CircularProgressIndicator())
        : widget.companyId == null
        ? _directory()
        : _details(),
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
