import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/navigation/workspace_destinations.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/responsive_layout.dart';
import 'user_reports_gateway.dart';

class UserReportsPage extends StatefulWidget {
  const UserReportsPage({
    super.key,
    this.admin = false,
    this.reportId,
    this.gateway,
    this.role = 'job_seeker',
  });
  final bool admin;
  final String? reportId;
  final UserReportsGateway? gateway;
  final String role;
  @override
  State<UserReportsPage> createState() => _UserReportsPageState();
}

class _UserReportsPageState extends State<UserReportsPage> {
  static const _pageSize = 30;
  late final UserReportsGateway _gateway =
      widget.gateway ?? SupabaseUserReportsGateway(Supabase.instance.client);
  final _subject = TextEditingController(),
      _description = TextEditingController(),
      _targetQuery = TextEditingController();
  List<Map<String, dynamic>> _rows = [], _history = [];
  List<Map<String, dynamic>> _targetOptions = [];
  Map<String, dynamic>? _report;
  Map<String, dynamic>? _selectedTarget;
  String _category = 'account_safety';
  bool _targetCompanies = false, _targetLoading = false;
  int _targetSearchGeneration = 0;
  int _offset = 0;
  bool _loading = true, _busy = false, _hasMore = false;
  bool _accountCanSubmit = false;
  bool get _canSubmit => _accountCanSubmit || widget.gateway != null;
  String _role = 'job_seeker';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    if (!widget.admin) {
      _loadRole();
    }
  }

  @override
  void didUpdateWidget(covariant UserReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reportId != widget.reportId ||
        oldWidget.admin != widget.admin) {
      _load();
    }
  }

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    _targetQuery.dispose();
    super.dispose();
  }

  Future<void> _loadRole() async {
    try {
      final client = Supabase.instance.client,
          id = Supabase.instance.client.auth.currentUser?.id;
      if (id == null) {
        return;
      }
      final account = await client
          .from('users')
          .select('role,status')
          .eq('user_id', id)
          .single();
      if (!mounted || client.auth.currentUser?.id != id) {
        return;
      }
      setState(() {
        if (account['role'] == 'employer') {
          _role = 'employer';
        }
        _accountCanSubmit =
            account['status'] == 'active' &&
            ['job_seeker', 'employer'].contains(account['role']);
      });
    } catch (_) {
      /* RPCs remain the authority; the form stays unavailable. */
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.reportId == null) {
        final rows = await _gateway.list(
          admin: widget.admin,
          limit: _pageSize + 1,
          offset: _offset,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _rows = rows.take(_pageSize).toList();
          _hasMore = rows.length > _pageSize;
          _report = null;
          _history = [];
        });
      } else {
        final result = await Future.wait([
          _gateway.details(widget.reportId!),
          _gateway.history(widget.reportId!),
        ]);
        if (!mounted) {
          return;
        }
        setState(() {
          _report = result[0] as Map<String, dynamic>;
          _history = result[1] as List<Map<String, dynamic>>;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'We could not load reports. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    if (_selectedTarget == null) {
      setState(
        () => _error =
            'Search for and select a User or Company before submitting.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _gateway.submit(
        _category,
        _subject.text.trim(),
        _description.text.trim(),
        targetUserId: _targetCompanies
            ? null
            : _selectedTarget!['user_id'] as String?,
        targetCompanyId: _targetCompanies
            ? _selectedTarget!['company_id'] as String?
            : null,
      );
      if (!mounted) {
        return;
      }
      _subject.clear();
      _description.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report submitted for review.')),
      );
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Report submission was not confirmed. Check your reports before retrying.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _act(String action) async {
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ReportReasonDialog(action: action),
    );
    if (reason == null || !mounted || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _gateway.act(widget.reportId!, action, reason);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Report updated.')));
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'The report action was not confirmed. Refresh and check its saved status.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _label(Object? value) =>
      (value?.toString() ?? '').replaceAll('_', ' ').trim();

  Future<void> _searchTargets() async {
    final query = _targetQuery.text.trim();
    if (query.length < 2 || _busy) {
      return;
    }
    final generation = ++_targetSearchGeneration;
    final companies = _targetCompanies;
    setState(() {
      _targetLoading = true;
      _error = null;
      _selectedTarget = null;
    });
    try {
      final results = await _gateway.searchTargets(
        companies: companies,
        query: query,
      );
      if (mounted && generation == _targetSearchGeneration) {
        setState(() => _targetOptions = results);
      }
    } catch (_) {
      if (mounted && generation == _targetSearchGeneration) {
        setState(
          () => _error =
              'Unable to search report targets. Try a longer name or retry.',
        );
      }
    } finally {
      if (mounted && generation == _targetSearchGeneration) {
        setState(() => _targetLoading = false);
      }
    }
  }

  Widget _form() => WorkspaceCard(
    title: 'Submit a report',
    subtitle: 'Describe a concern for the JobMate team. Reports are reviewed separately from account, company, job and payment actions.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: const [
            DropdownMenuItem(
              value: 'account_safety',
              child: Text('Account safety'),
            ),
            DropdownMenuItem(value: 'job_content', child: Text('Job content')),
            DropdownMenuItem(
              value: 'company_conduct',
              child: Text('Company conduct'),
            ),
            DropdownMenuItem(value: 'other', child: Text('Other')),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _category = value;
                    if (['account_safety', 'company_conduct'].contains(value)) {
                      _targetSearchGeneration++;
                      _targetLoading = false;
                      _targetCompanies = value == 'company_conduct';
                      _selectedTarget = null;
                      _targetOptions = [];
                      _targetQuery.clear();
                    }
                  });
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<bool>(
          initialValue: _targetCompanies,
          decoration: const InputDecoration(labelText: 'Reported entity'),
          items: const [
            DropdownMenuItem(value: false, child: Text('User')),
            DropdownMenuItem(value: true, child: Text('Company')),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _targetSearchGeneration++;
                    _targetLoading = false;
                    _targetCompanies = value;
                    _selectedTarget = null;
                    _targetOptions = [];
                    _targetQuery.clear();
                  });
                },
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('user-report-target-search'),
          controller: _targetQuery,
          enabled: !_busy,
          onChanged: (_) => setState(() {
            _targetSearchGeneration++;
            _targetLoading = false;
            _selectedTarget = null;
            _targetOptions = [];
          }),
          onSubmitted: (_) => _searchTargets(),
          decoration: InputDecoration(
            labelText: _targetCompanies
                ? 'Search Company name'
                : 'Search User name',
            helperText: 'Enter at least 2 characters. Email and phone details are not shown.',
            suffixIcon: IconButton(
              tooltip: 'Search',
              onPressed: _busy ? null : _searchTargets,
              icon: const Icon(Icons.search),
            ),
          ),
        ),
        if (_targetLoading) const LinearProgressIndicator(),
        if (_targetOptions.isEmpty &&
            _targetQuery.text.trim().length >= 2 &&
            !_targetLoading &&
            _selectedTarget == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No matching targets.'),
          ),
        for (final option in _targetOptions)
          Card.outlined(
            child: ListTile(
              title: Text(
                (option[_targetCompanies ? 'company_name' : 'display_name'] ??
                        'Unnamed')
                    .toString(),
              ),
              subtitle: null,
              trailing: TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _selectedTarget = option;
                        _targetOptions = [];
                      }),
                child: const Text('Select'),
              ),
            ),
          ),
        if (_selectedTarget != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.check_circle_outline),
            title: Text(
              'Selected: ${_selectedTarget![_targetCompanies ? 'company_name' : 'display_name']}',
            ),
            trailing: IconButton(
              tooltip: 'Clear selection',
              onPressed: _busy
                  ? null
                  : () => setState(() => _selectedTarget = null),
              icon: const Icon(Icons.close),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('user-report-subject'),
          controller: _subject,
          enabled: !_busy,
          maxLength: 160,
          decoration: const InputDecoration(labelText: 'Subject'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('user-report-description'),
          controller: _description,
          enabled: !_busy,
          minLines: 4,
          maxLines: 8,
          maxLength: 4000,
          decoration: const InputDecoration(labelText: 'What happened?'),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const ValueKey('user-report-submit'),
            onPressed: _busy ? null : _submit,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Submit report'),
          ),
        ),
      ],
    ),
  );

  Widget _directory() => ResponsiveContent(
    maxWidth: 900,
    child: ListView(
      key: const ValueKey('user-reports-directory-scroll'),
      padding: ResponsiveLayout.pagePadding(context),
      children: [
        PageHeading(
          title: widget.admin ? 'Report queue' : 'My Reports',
          description: widget.admin
              ? 'Review user-submitted concerns. Resolution records do not automatically suspend accounts, restrict companies or moderate jobs.'
              : 'Submit and follow up on reports you have submitted.',
        ),
        if (!widget.admin && _canSubmit) ...[
          _form(),
          const SizedBox(height: 20),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _loading ? null : _load,
            child: const Text('Refresh'),
          ),
        ),
        if (_error != null) _errorPanel(),
        if (_rows.isEmpty && !_loading && _error == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No reports found.')),
          ),
        for (final item in _rows)
          Card.outlined(
            child: ListTile(
              title: Text((item['subject'] ?? 'Report').toString()),
              subtitle: Text(
                '${_label(item['category'])} • ${_label(item['status'])} • ${item['target_user_name'] ?? item['target_company_name'] ?? 'Target unavailable'}${widget.admin && item['reporter_name'] != null ? ' • ${item['reporter_name']}' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: item['report_id'] is String
                  ? () => context.push(
                      '${widget.admin ? AppRoutes.adminReports : AppRoutes.userReports}/${item['report_id']}',
                    )
                  : null,
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!_loading && _error == null)
          ResponsivePagination(
            page: _offset ~/ _pageSize + 1,
            onPrevious: _offset == 0
                ? null
                : () {
                    setState(() => _offset -= _pageSize);
                    _load();
                  },
            onNext: !_hasMore
                ? null
                : () {
                    setState(() => _offset += _pageSize);
                    _load();
                  },
          ),
      ],
    ),
  );

  Widget _details() {
    final report = _report;
    if (report == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              const CircularProgressIndicator()
            else ...[
              Text(_error ?? 'Report details are unavailable.'),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ],
        ),
      );
    }
    final status = report['status']?.toString() ?? '';
    return ResponsiveContent(
      maxWidth: 900,
      child: ListView(
        padding: ResponsiveLayout.pagePadding(context),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.go(
                widget.admin ? AppRoutes.adminReports : AppRoutes.userReports,
              ),
              icon: const Icon(Icons.arrow_back),
              label: Text(widget.admin ? 'Report queue' : 'My reports'),
            ),
          ),
          PageHeading(
            title: (report['subject'] ?? 'Report').toString(),
            description: '${_label(report['category'])} • ${_label(status)}',
          ),
          if (widget.admin && report['reporter_name'] != null)
            WorkspaceInfo('Submitted by', report['reporter_name'].toString()),
          if (widget.admin && report['target_user_name'] != null)
            WorkspaceInfo(
              'Reported User',
              '${report['target_user_name']} (${_label(report['target_user_role'])})',
            ),
          if (widget.admin && report['target_company_name'] != null)
            WorkspaceInfo(
              'Reported Company',
              report['target_company_name'].toString(),
              key: const ValueKey('user-report-company-detail'),
            ),
          WorkspaceInfo(
            'Description',
            (report['description'] ?? '').toString(),
          ),
          if (status == 'information_requested' && !widget.admin)
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _act('respond_information'),
              icon: const Icon(Icons.reply),
              label: const Text('Respond to information request'),
            ),
          if (widget.admin && status == 'open')
            FilledButton(
              onPressed: _busy ? null : () => _act('investigate'),
              child: const Text('Start investigation'),
            ),
          if (widget.admin && status == 'investigating')
            OutlinedButton(
              onPressed: _busy ? null : () => _act('request_information'),
              child: const Text('Request information'),
            ),
          if (widget.admin &&
              [
                'open',
                'investigating',
                'information_requested',
              ].contains(status))
            Wrap(
              spacing: 12,
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => _act('resolve'),
                  child: const Text('Resolve'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _act('dismiss'),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          if (_error != null) _errorPanel(),
          const SizedBox(height: 16),
          const Text(
            'Status history',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          if (_history.isEmpty) const Text('No history available.'),
          for (final event in _history)
            Card.outlined(
              child: ListTile(
                title: Text(
                  '${_label(event['action'])} • ${_label(event['new_status'])}',
                ),
                subtitle: Text(
                  '${event['actor_name'] ?? 'Account'}: ${event['reason'] ?? ''}',
                ),
                isThreeLine: true,
              ),
            ),
        ],
      ),
    );
  }

  Widget _errorPanel() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      _error!,
      textAlign: TextAlign.center,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final path = widget.admin ? AppRoutes.adminReports : AppRoutes.userReports;
    final role = widget.admin ? 'administrator' : _role;
    return AppWorkspace(
      title: widget.admin ? 'User Reports' : 'My Reports',
      path: path,
      role: role,
      navigationGroups: widget.admin
          ? {
              ...workspaceDestinations('administrator'),
              'Admin tools': [
                (
                  AppRoutes.adminPermissions,
                  'Admin permissions',
                  Icons.admin_panel_settings_outlined,
                ),
              ],
            }
          : null,
      child: widget.reportId == null ? _directory() : _details(),
    );
  }
}

class _ReportReasonDialog extends StatefulWidget {
  const _ReportReasonDialog({required this.action});
  final String action;
  @override
  State<_ReportReasonDialog> createState() => _ReportReasonDialogState();
}

class _ReportReasonDialogState extends State<_ReportReasonDialog> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(switch (widget.action) {
      'investigate' => 'Start investigation',
      'request_information' => 'Request information',
      'respond_information' => 'Respond to request',
      'resolve' => 'Resolve report',
      'dismiss' => 'Dismiss report',
      _ => 'Update report',
    }),
    content: TextField(
      controller: _text,
      autofocus: true,
      minLines: 3,
      maxLines: 7,
      maxLength: 4000,
      decoration: InputDecoration(
        labelText: widget.action == 'respond_information'
            ? 'Your response'
            : 'Required reason',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final value = _text.text.trim();
          if (value.isNotEmpty) {
            Navigator.pop(context, value);
          }
        },
        child: const Text('Submit'),
      ),
    ],
  );
}
