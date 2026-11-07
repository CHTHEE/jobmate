import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/navigation/workspace_destinations.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/responsive_layout.dart';
import 'job_moderation_gateway.dart';

class JobModerationPage extends StatefulWidget {
  const JobModerationPage({super.key, this.jobId, this.gateway});
  final String? jobId;
  final JobModerationGateway? gateway;

  @override
  State<JobModerationPage> createState() => _JobModerationPageState();
}

class _JobModerationPageState extends State<JobModerationPage> {
  static const _pageSize = 30;
  late final JobModerationGateway _gateway =
      widget.gateway ?? SupabaseJobModerationGateway(Supabase.instance.client);
  List<Map<String, dynamic>> _jobs = [], _history = [];
  Map<String, dynamic>? _job;
  String? _filter, _error;
  int _offset = 0;
  bool _loading = true, _busy = false, _hasMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant JobModerationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobId != widget.jobId) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.jobId == null) {
        final rows = await _gateway.list(
          status: _filter,
          limit: _pageSize + 1,
          offset: _offset,
        );
        if (!mounted) return;
        setState(() {
          _jobs = rows.take(_pageSize).toList();
          _hasMore = rows.length > _pageSize;
          _job = null;
          _history = [];
        });
      } else {
        final result = await Future.wait([
          _gateway.details(widget.jobId!),
          _gateway.history(widget.jobId!),
        ]);
        if (!mounted) return;
        setState(() {
          _job = result[0] as Map<String, dynamic>;
          _history = result[1] as List<Map<String, dynamic>>;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'We could not load job reviews. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changePage(int direction) {
    if (_loading || (direction > 0 && !_hasMore)) return;
    final next = _offset + direction * _pageSize;
    if (next < 0) return;
    setState(() {
      _offset = next;
      _jobs = [];
    });
    _load();
  }

  void _changeFilter(String? value) {
    setState(() {
      _filter = value;
      _offset = 0;
      _jobs = [];
    });
    _load();
  }

  Future<void> _act(String action) async {
    if (_busy || widget.jobId == null) return;
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ModerationReasonDialog(action: action),
    );
    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _gateway.act(widget.jobId!, action, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_success(action))));
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'The moderation action was not confirmed. Refresh and check the saved status before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _success(String action) => switch (action) {
    'flag' => 'Job flagged for investigation.',
    'start_review' => 'Moderation review started.',
    'note' => 'Investigation note recorded.',
    'clear' => 'Job cleared.',
    'restrict' => 'Job restriction recorded.',
    'restore' => 'Job restriction restored.',
    _ => 'Moderation status updated.',
  };

  String _label(Object? value) =>
      (value?.toString() ?? '').replaceAll('_', ' ').trim();

  Widget _integrationNotice() => Card.outlined(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'A restriction does not yet hide this posting everywhere in JobMate.',
      ),
    ),
  );

  Widget _directory() => ResponsiveContent(
    maxWidth: 1050,
    child: ListView(
      key: const ValueKey('job-moderation-directory-scroll'),
      padding: ResponsiveLayout.pagePadding(context),
      children: [
        const PageHeading(
          title: 'Review Job Postings',
          description: 'Review existing Job Postings without changing draft, published or closed status.',
        ),
        _integrationNotice(),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            ResponsiveFilter(
              width: 240,
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _filter,
                decoration: const InputDecoration(
                  labelText: 'Moderation status',
                ),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('All')),
                  DropdownMenuItem(
                    value: 'unflagged',
                    child: Text('Unflagged'),
                  ),
                  DropdownMenuItem(value: 'flagged', child: Text('Flagged')),
                  DropdownMenuItem(
                    value: 'under_review',
                    child: Text('Under review'),
                  ),
                  DropdownMenuItem(value: 'cleared', child: Text('Cleared')),
                  DropdownMenuItem(
                    value: 'restricted',
                    child: Text('Restricted'),
                  ),
                ],
                onChanged: _loading ? null : _changeFilter,
              ),
            ),
            TextButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
        if (_error != null) _errorPanel(),
        if (_jobs.isEmpty && !_loading && _error == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No jobs match this moderation filter.')),
          ),
        for (final row in _jobs)
          Card.outlined(
            child: ListTile(
              title: Text((row['title'] ?? 'Job posting').toString()),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Chip(
                      label: Text(
                        (row['company_name'] ?? 'Company').toString(),
                      ),
                    ),
                    Chip(label: Text('Posting: ${_label(row['job_status'])}')),
                    Chip(
                      label: Text(
                        'Review: ${_label(row['moderation_status'])}',
                      ),
                    ),
                    if (row['employment_type'] != null)
                      Chip(label: Text(_label(row['employment_type']))),
                  ],
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: row['job_id'] is String
                  ? () => context.push(
                      '${AppRoutes.adminJobModeration}/${row['job_id']}',
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
            onPrevious: _offset == 0 ? null : () => _changePage(-1),
            onNext: !_hasMore ? null : () => _changePage(1),
          ),
      ],
    ),
  );

  Widget _details() {
    final item = _job;
    if (item == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              const CircularProgressIndicator()
            else ...[
              Text(_error ?? 'Job details are unavailable.'),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ],
        ),
      );
    }
    final status = item['moderation_status']?.toString() ?? 'unflagged';
    return ResponsiveContent(
      maxWidth: 1050,
      child: ListView(
        key: const ValueKey('job-moderation-details-scroll'),
        padding: ResponsiveLayout.pagePadding(context),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.go(AppRoutes.adminJobModeration),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Job Moderation directory'),
            ),
          ),
          _integrationNotice(),
          PageHeading(
            title: (item['title'] ?? 'Job posting').toString(),
            description:
                '${item['company_name'] ?? 'Company'} · Posting: ${_label(item['job_status'])} · Moderation: ${_label(status)}',
          ),
          if (_error != null) _errorPanel(),
          WorkspaceCard(
            title: 'Job details',
            subtitle: 'Job ID ${item['job_id'] ?? ''}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _info('Department', item['department']),
                _info('Employment type', item['employment_type']),
                _info('Work arrangement', item['work_arrangement']),
                _info('Location', item['location']),
                _info('Original description', item['original_description']),
                _info('Role overview', item['role_overview']),
                _info('Responsibilities', item['responsibilities']),
                _info('Requirements', item['requirements']),
                _info('Benefits', item['benefits']),
                _info('Created', item['created_at']),
              ],
            ),
          ),
          const SizedBox(height: 16),
          WorkspaceCard(
            title: 'Company information',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _info('Company', item['company_name']),
                _info('Industry', item['company_industry']),
                _info('Location', item['company_location']),
                _info('Verification', item['company_verification_status']),
              ],
            ),
          ),
          const SizedBox(height: 16),
          WorkspaceCard(
            title: 'Moderation actions',
            subtitle: 'Every action requires a reason and is recorded in Admin history.',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _actions(status),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Moderation history',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (_history.isEmpty) const Text('No moderation actions recorded.'),
          for (final event in _history)
            Card.outlined(
              child: ListTile(
                title: Text(
                  '${_label(event['action'])} · ${_label(event['created_at'])}',
                ),
                subtitle: Text(
                  'Status: ${_label(event['previous_status'])} → ${_label(event['new_status'])}\n'
                  'Reason: ${event['reason'] ?? ''}\nAdmin: ${event['actor_name'] ?? 'Admin'}',
                ),
                isThreeLine: true,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _actions(String status) {
    final actions = <(String, String, IconData)>[];
    if (status == 'unflagged' || status == 'cleared') {
      actions.add(('flag', 'Flag for investigation', Icons.flag_outlined));
    }
    if (status == 'flagged') {
      actions.add(('start_review', 'Start review', Icons.manage_search));
    }
    if (status == 'flagged' || status == 'under_review') {
      actions.add((
        'note',
        'Record investigation note',
        Icons.note_add_outlined,
      ));
      actions.add(('clear', 'Record no violation', Icons.check_circle_outline));
      actions.add(('restrict', 'Restrict job', Icons.block));
    }
    if (status == 'restricted') {
      actions.add(('restore', 'Restore job', Icons.lock_open));
    }
    return [
      for (final action in actions)
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _act(action.$1),
          icon: Icon(action.$3),
          label: Text(action.$2),
        ),
    ];
  }

  Widget _info(String label, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        SelectableText(
          value?.toString().trim().isNotEmpty == true
              ? value.toString()
              : 'Not provided',
        ),
      ],
    ),
  );

  Widget _errorPanel() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
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

  @override
  Widget build(BuildContext context) => AppWorkspace(
    title: 'Job Moderation',
    path: AppRoutes.adminJobModeration,
    role: 'administrator',
    navigationGroups: {
      ...workspaceDestinations('administrator'),
      'Admin tools': [
        (
          AppRoutes.adminPermissions,
          'Admin permissions',
          Icons.admin_panel_settings_outlined,
        ),
      ],
    },
    child: widget.jobId == null ? _directory() : _details(),
  );
}

class _ModerationReasonDialog extends StatefulWidget {
  const _ModerationReasonDialog({required this.action});
  final String action;
  @override
  State<_ModerationReasonDialog> createState() =>
      _ModerationReasonDialogState();
}

class _ModerationReasonDialogState extends State<_ModerationReasonDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _title => switch (widget.action) {
    'flag' => 'Flag job for investigation',
    'start_review' => 'Start moderation review',
    'note' => 'Record investigation note',
    'clear' => 'Record no violation',
    'restrict' => 'Restrict job',
    'restore' => 'Restore job restriction',
    _ => 'Moderation action',
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_title),
    content: TextField(
      key: const ValueKey('job-moderation-reason'),
      controller: _controller,
      autofocus: true,
      minLines: 3,
      maxLines: 7,
      maxLength: 4000,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        labelText: 'Reason (required)',
        helperText: 'This will be recorded in moderation history.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Save action'),
      ),
    ],
  );
}
