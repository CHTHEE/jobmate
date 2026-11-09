import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Phase A RPCs are the authorization and eligibility boundary.
abstract interface class EngagementClosureGateway {
  Future<Map<String, dynamic>> status(String applicationId);
  Future<DateTime> close(String applicationId, String reason);
  Future<String> request(String applicationId, String reason);
  Future<List<Map<String, dynamic>>> companyRequests();
  Future<DateTime?> respond(String requestId, String decision, String reason);
}

@immutable
class EngagementClosureStatusSnapshot {
  const EngagementClosureStatusSnapshot({
    this.loading = false,
    this.status,
    this.error,
  });

  final bool loading;
  final Map<String, dynamic>? status;
  final String? error;

  bool get isClosed => status?['closure_status'] == 'closed';
}

class SupabaseEngagementClosureGateway implements EngagementClosureGateway {
  SupabaseEngagementClosureGateway(this.client);
  final SupabaseClient client;
  late final String? _actorId = client.auth.currentUser?.id;

  Future<dynamic> _call(String name, [Map<String, dynamic>? params]) async {
    if (_actorId == null || client.auth.currentUser?.id != _actorId) {
      throw const AuthException('Authentication required.');
    }
    final result = await client.rpc(name, params: params);
    if (client.auth.currentUser?.id != _actorId) {
      throw const AuthException('Account changed. Refresh engagement status.');
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> status(String applicationId) async {
    final result = await _call('get_my_job_engagement_closure_status', {
      'p_application_id': applicationId,
    });
    if (result is! List || result.length != 1 || result.single is! Map) {
      throw const FormatException('Invalid engagement status response.');
    }
    final row = Map<String, dynamic>.from(result.single as Map);
    if (!const {
          'open',
          'closure_requested',
          'closed',
          'ineligible',
        }.contains(row['closure_status']) ||
        row['eligible'] is! bool) {
      throw const FormatException('Invalid engagement status fields.');
    }
    return row;
  }

  DateTime _timestamp(Object? value) {
    if (value is! String) {
      throw const FormatException('Invalid closure timestamp.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw const FormatException('Invalid closure timestamp.');
    }
    return parsed.toUtc();
  }

  @override
  Future<DateTime> close(String applicationId, String reason) async =>
      _timestamp(
        await _call('close_job_engagement', {
          'p_application_id': applicationId,
          'p_reason': reason,
        }),
      );

  @override
  Future<String> request(String applicationId, String reason) async {
    final result = await _call('request_job_engagement_closure', {
      'p_application_id': applicationId,
      'p_reason': reason,
    });
    if (result is! String || result.isEmpty) {
      throw const FormatException('Invalid closure request response.');
    }
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> companyRequests() async {
    final result = await _call('list_company_engagement_closure_requests');
    if (result is! List || result.any((row) => row is! Map)) {
      throw const FormatException('Invalid closure request list.');
    }
    return result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<DateTime?> respond(
    String requestId,
    String decision,
    String reason,
  ) async {
    final result = await _call('respond_job_engagement_closure_request', {
      'p_request_id': requestId,
      'p_decision': decision,
      'p_reason': reason,
    });
    return result == null ? null : _timestamp(result);
  }
}

/// Adds close/request actions to the existing application-group surfaces.
class EngagementClosureControls extends StatefulWidget {
  const EngagementClosureControls({
    super.key,
    required this.applicationId,
    required this.worker,
    this.gateway,
    this.onClosed,
    this.onStatusChanged,
    this.refreshToken = 0,
  });
  final String applicationId;
  final bool worker;
  final EngagementClosureGateway? gateway;
  final VoidCallback? onClosed;
  final ValueChanged<EngagementClosureStatusSnapshot>? onStatusChanged;
  final int refreshToken;

  @override
  State<EngagementClosureControls> createState() =>
      _EngagementClosureControlsState();
}

class _EngagementClosureControlsState extends State<EngagementClosureControls> {
  late final EngagementClosureGateway _gateway =
      widget.gateway ??
      SupabaseEngagementClosureGateway(Supabase.instance.client);
  bool _busy = false;
  bool _statusLoading = true;
  Map<String, dynamic>? _status;
  String? _message;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void didUpdateWidget(covariant EngagementClosureControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.applicationId != widget.applicationId ||
        oldWidget.gateway != widget.gateway ||
        oldWidget.refreshToken != widget.refreshToken) {
      _loadStatus();
    }
  }

  void _publishStatus() {
    final callback = widget.onStatusChanged;
    if (callback == null) return;
    callback(
      EngagementClosureStatusSnapshot(
        loading: _statusLoading,
        status: _status,
        error: _failed ? _message : null,
      ),
    );
  }

  Future<void> _loadStatus() async {
    setState(() {
      _statusLoading = true;
      _failed = false;
      _message = null;
    });
    // Avoid asking the parent to rebuild while this child is mounting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishStatus();
    });
    try {
      final value = await _gateway.status(widget.applicationId);
      if (mounted) {
        setState(() {
          _status = value;
          _statusLoading = false;
        });
        _publishStatus();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _statusLoading = false;
          _failed = true;
          _message = _serverMessage(error);
        });
        _publishStatus();
      }
    }
  }

  Future<String?> _reason(String title, String prompt) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _ClosureReasonDialog(title: title, prompt: prompt),
    );
  }

  Future<void> _act() async {
    if (_busy ||
        _statusLoading ||
        _status?['closure_status'] == 'closed' ||
        (!widget.worker && _status?['eligible'] != true)) {
      return;
    }
    final reason = await _reason(
      widget.worker ? 'Request engagement closure' : 'Close engagement',
      widget.worker ? 'Reason for your request' : 'Closure reason',
    );
    if (!mounted || reason == null) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (widget.worker) {
        await _gateway.request(widget.applicationId, reason);
        if (mounted) {
          setState(() => _message = 'Closure request submitted.');
        }
      } else {
        await _gateway.close(widget.applicationId, reason);
        if (mounted) {
          setState(
            () => _message = 'Engagement closed. Evaluation is now available.',
          );
          widget.onClosed?.call();
        }
      }
      await _loadStatus();
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = _serverMessage(error);
        });
        // Reconcile after failed or uncertain network responses before
        // allowing another action; the server remains authoritative.
        await _loadStatus();
        if (mounted && _status?['closure_status'] != 'ineligible') {
          setState(() {
            _failed = true;
            _message ??= _serverMessage(error);
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_message != null)
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _message!,
              style: TextStyle(
                color: _failed ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ),
        ),
      if (_statusLoading)
        const LinearProgressIndicator()
      else if (_status == null)
        TextButton.icon(
          onPressed: _loadStatus,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh engagement status'),
        )
      else ...[
        Text(switch (_status!['closure_status']) {
          'closed' => 'Engagement status: Closed',
          'closure_requested' => 'Engagement status: Closure requested',
          'ineligible' => 'Engagement status: Ineligible to close',
          _ => 'Engagement status: Open',
        }),
        if (_status!['eligibility_reason'] is String &&
            (_status!['eligibility_reason'] as String).isNotEmpty)
          Text('${_status!['eligibility_reason']}'),
        if (_status!['response_reason'] is String &&
            (_status!['response_reason'] as String).isNotEmpty)
          Text('Company response: ${_status!['response_reason']}'),
      ],
      if (!_statusLoading &&
          _status != null &&
          _status!['closure_status'] != 'closed' &&
          _status!['closure_status'] != 'closure_requested' &&
          (widget.worker || _status!['eligible'] == true))
        OutlinedButton.icon(
          onPressed: _busy ? null : _act,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  widget.worker
                      ? Icons.request_page_outlined
                      : Icons.task_alt_outlined,
                ),
          label: Text(widget.worker ? 'Request closure' : 'Close Engagement'),
        ),
      if (_busy) const LinearProgressIndicator(),
    ],
  );
}

/// Company request inbox backed by the Phase A company-authorized listing RPC.
class CompanyEngagementClosureRequests extends StatefulWidget {
  const CompanyEngagementClosureRequests({
    super.key,
    this.gateway,
    this.onClosed,
  });
  final EngagementClosureGateway? gateway;
  final ValueChanged<String>? onClosed;
  @override
  State<CompanyEngagementClosureRequests> createState() =>
      _CompanyEngagementClosureRequestsState();
}

class _CompanyEngagementClosureRequestsState
    extends State<CompanyEngagementClosureRequests> {
  late final EngagementClosureGateway _gateway =
      widget.gateway ??
      SupabaseEngagementClosureGateway(Supabase.instance.client);
  late Future<List<Map<String, dynamic>>> _future = _gateway.companyRequests();

  Future<String?> _reason(String title) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _ClosureReasonDialog(
        title: title,
        prompt: 'Response reason',
        confirmLabel: 'Submit',
      ),
    );
  }

  Future<void> _respond(Map<String, dynamic> row, String decision) async {
    final reason = await _reason(
      decision == 'close' ? 'Close Engagement' : 'Decline closure request',
    );
    if (!mounted || reason == null) {
      return;
    }
    try {
      await _gateway.respond('${row['request_id']}', decision, reason);
      if (!mounted) {
        return;
      }
      if (decision == 'close') {
        widget.onClosed?.call('${row['application_id']}');
      }
      if (mounted) {
        setState(() => _future = _gateway.companyRequests());
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_serverMessage(error))));
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const LinearProgressIndicator();
      }
      if (snapshot.hasError) {
        return Card.outlined(
          child: ListTile(
            title: const Text('Closure requests unavailable'),
            subtitle: const Text('Retry to load Company requests.'),
            trailing: IconButton(
              onPressed: () =>
                  setState(() => _future = _gateway.companyRequests()),
              icon: const Icon(Icons.refresh),
            ),
          ),
        );
      }
      final rows = snapshot.data ?? const [];
      if (rows.isEmpty) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Engagement closure requests',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final row in rows)
            Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['job_title'] ?? 'Job'} · ${row['worker_name'] ?? 'Worker'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('Status: ${row['status'] ?? 'unknown'}'),
                    if ('${row['request_reason'] ?? ''}'.isNotEmpty)
                      Text('Worker reason: ${row['request_reason']}'),
                    if ('${row['response_reason'] ?? ''}'.isNotEmpty)
                      Text('Response: ${row['response_reason']}'),
                    if (row['status'] == 'pending')
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => _respond(row, 'decline'),
                            child: const Text('Decline'),
                          ),
                          FilledButton(
                            onPressed: () => _respond(row, 'close'),
                            child: const Text('Review and close'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

String _serverMessage(Object error) {
  if (error is PostgrestException && error.message.trim().isNotEmpty) {
    return error.message;
  }
  if (error is AuthException) {
    return 'Sign in again to continue.';
  }
  return 'The request could not be confirmed. Refresh and check the server state before retrying.';
}

class _ClosureReasonDialog extends StatefulWidget {
  const _ClosureReasonDialog({
    required this.title,
    required this.prompt,
    this.confirmLabel = 'Continue',
  });

  final String title;
  final String prompt;
  final String confirmLabel;

  @override
  State<_ClosureReasonDialog> createState() => _ClosureReasonDialogState();
}

class _ClosureReasonDialogState extends State<_ClosureReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      inputFormatters: [LengthLimitingTextInputFormatter(2000)],
      minLines: 2,
      maxLines: 5,
      decoration: InputDecoration(labelText: widget.prompt),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final value = _controller.text.trim();
          if (value.isNotEmpty) {
            Navigator.pop(context, value);
          }
        },
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
