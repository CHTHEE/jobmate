import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_scoring_gateway.dart';
import 'user_management_gateway.dart';

class UserAccountDetailsDialog extends StatefulWidget {
  const UserAccountDetailsDialog({
    super.key,
    required this.userId,
    required this.gateway,
    this.canManage = true,
    this.scoringGateway,
    this.scoringSessionSource,
    this.scoringEnabledForTesting,
  });

  final String userId;
  final UserManagementGateway gateway;
  final bool canManage;
  final AdminScoringGateway? scoringGateway;
  final AdminScoringSessionSource? scoringSessionSource;

  /// Test-only injection; profile/release builds remain disabled by [kDebugMode].
  final bool? scoringEnabledForTesting;

  @override
  State<UserAccountDetailsDialog> createState() =>
      _UserAccountDetailsDialogState();
}

class _UserAccountDetailsDialogState extends State<UserAccountDetailsDialog> {
  Map<String, dynamic>? _account;
  List<Map<String, dynamic>> _history = [];
  int _offset = 0;
  bool _more = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _message;
  AdminScoringGateway? _scoringGateway;
  AdminScoringSessionSource? _scoringSessionSource;
  StreamSubscription<String?>? _scoringSessionSubscription;
  String? _scoringActorId;
  int _scoringGeneration = 0;
  bool _scoringLoading = false;
  bool _scoringSessionInvalid = false;
  AdminJobSeekerReputation? _reputation;
  AdminJobSeekerTrustScore? _trustScore;
  String? _reputationError;
  String? _trustError;
  bool _trustAccessDenied = false;

  bool get _scoringEnabled =>
      kDebugMode && (widget.scoringEnabledForTesting ?? adminScoringEnabled);

  @override
  void initState() {
    super.initState();
    _configureScoring();
    _load();
  }

  void _configureScoring() {
    unawaited(_scoringSessionSubscription?.cancel());
    _scoringSessionSubscription = null;
    _scoringSessionInvalid = false;
    if (!_scoringEnabled) return;
    final gateway = widget.scoringGateway;
    if (gateway == null) {
      final client = Supabase.instance.client;
      _scoringGateway = SupabaseAdminScoringGateway(client);
      _scoringSessionSource =
          widget.scoringSessionSource ??
          SupabaseAdminScoringSessionSource(client);
    } else {
      _scoringGateway = gateway;
      _scoringSessionSource = widget.scoringSessionSource;
    }
    final session = _scoringSessionSource;
    _scoringActorId = session?.currentUserId;
    if (session == null) return;
    if (_scoringActorId == null) _scoringSessionInvalid = true;
    _scoringSessionSubscription = session.userIdChanges.listen((userId) {
      if (userId != _scoringActorId) _invalidateScoringSession();
    }, onError: (_, _) => _invalidateScoringSession());
  }

  void _invalidateScoringSession() {
    if (!mounted || _scoringSessionInvalid) return;
    setState(() {
      _scoringSessionInvalid = true;
      _scoringGeneration++;
      _scoringLoading = false;
      _reputation = null;
      _trustScore = null;
      _reputationError = null;
      _trustError = null;
      _trustAccessDenied = false;
    });
  }

  void _clearScoring() {
    _scoringGeneration++;
    _scoringLoading = false;
    _reputation = null;
    _trustScore = null;
    _reputationError = null;
    _trustError = null;
    _trustAccessDenied = false;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _account = null;
      _history = [];
      _clearScoring();
    });
    try {
      final account = widget.canManage
          ? await widget.gateway.details(widget.userId)
          : await widget.gateway.directoryDetails(widget.userId);
      final history = widget.canManage
          ? await widget.gateway.history(widget.userId, _offset)
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _account = account;
        _history = history.take(20).toList();
        _more = history.length > 20;
      });
      if (_scoringEnabled && account?['role'] == 'job_seeker') {
        unawaited(_loadScoring(widget.userId));
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() {
          _error = switch (error.code) {
            'PGRST202' => 'Account details are temporarily unavailable. Please try again later.',
            'P0001'
                when error.message ==
                    'User Management permission is required.' =>
              'You do not have access to these account details.',
            _ => error.message,
          };
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to load account details. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadScoring(String targetUserId) async {
    final gateway = _scoringGateway;
    if (gateway == null || _scoringSessionInvalid) return;
    final generation = ++_scoringGeneration;
    final actorId = _scoringActorId;
    setState(() {
      _scoringLoading = true;
      _reputation = null;
      _trustScore = null;
      _reputationError = null;
      _trustError = null;
      _trustAccessDenied = false;
    });
    AdminJobSeekerReputation? reputation;
    AdminJobSeekerTrustScore? trust;
    String? reputationError;
    String? trustError;
    var trustAccessDenied = false;
    try {
      reputation = await gateway.jobSeekerReputation(targetUserId);
    } catch (_) {
      reputationError = 'Job Seeker Reputation is unavailable.';
    }
    try {
      trust = await gateway.jobSeekerTrustScore(targetUserId);
    } on AdminTrustAccessDenied {
      trustAccessDenied = true;
    } catch (_) {
      // The server is authoritative for permission denial; never preserve a
      // prior value after either denial or malformed data.
      trustError = 'Internal Trust Score is temporarily unavailable.';
    }
    if (!mounted ||
        generation != _scoringGeneration ||
        _scoringSessionInvalid ||
        (_scoringSessionSource != null &&
            (_scoringSessionSource!.currentUserId == null ||
                _scoringSessionSource!.currentUserId != actorId))) {
      return;
    }
    setState(() {
      _scoringLoading = false;
      _reputation = reputation;
      _trustScore = trust;
      _reputationError = reputationError;
      _trustError = trustError;
      _trustAccessDenied = trustAccessDenied;
    });
  }

  Future<void> _changeStatus(String action) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AccountRestrictionDialog(action: action),
    );
    if (!mounted || result == null) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.gateway.changeStatus(
        widget.userId,
        action,
        result.isEmpty ? null : result,
      );
      if (mounted) {
        _offset = 0;
        _message = action == 'suspend'
            ? 'Account suspended.'
            : 'Account reactivated.';
      }
    } on PostgrestException catch (error) {
      if (mounted) _message = error.message;
    } catch (_) {
      if (mounted) {
        _message =
            'Unable to confirm the action. Check the saved status and history.';
      }
    } finally {
      if (mounted) {
        await _load();
        if (mounted) setState(() => _saving = false);
      }
    }
  }

  String _value(Object? value) => value == null || value.toString().isEmpty
      ? 'Not provided'
      : value.toString();

  String _displayDate(Object? value) {
    final parsed = value is DateTime
        ? value
        : DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return _value(value);
    final local = parsed.toLocal();
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatMediumDate(local)} ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  Widget _scoringSection() {
    final reputation = _reputation;
    final trust = _trustScore;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Scoring', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_scoringSessionInvalid)
          const Text(
            'Scoring was cleared because the administrator account changed.',
          )
        else if (_scoringLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else ...[
          if (reputation != null)
            Text(
              reputation.coreAverage == null
                  ? 'Job Seeker Reputation: Unavailable (no released ratings)'
                  : 'Job Seeker Reputation: ${reputation.coreAverage!.toStringAsFixed(1)} / 5',
            )
          else
            Text(_reputationError ?? 'Job Seeker Reputation is unavailable.'),
          const SizedBox(height: 6),
          if (_trustAccessDenied)
            const Text(
              'You do not have permission to view Internal Trust Score.',
            )
          else if (trust != null)
            Text(
              trust.isAvailable
                  ? 'Internal Trust Score: ${trust.trustScore!.toStringAsFixed(1)} / 100 — Provisional / Not Certified'
                  : 'Internal Trust Score: Unavailable — ${trust.missingFactors.isEmpty ? 'evidence is incomplete' : 'missing ${trust.missingFactors.join(', ')}'}',
            )
          else
            Text(
              _trustError ?? 'Internal Trust Score is temporarily unavailable.',
            ),
          TextButton.icon(
            onPressed: () => _loadScoring(widget.userId),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry scoring'),
          ),
        ],
      ],
    );
  }

  @override
  void didUpdateWidget(covariant UserAccountDetailsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _offset = 0;
      _load();
      return;
    }
    if (oldWidget.scoringGateway != widget.scoringGateway ||
        oldWidget.scoringSessionSource != widget.scoringSessionSource ||
        oldWidget.scoringEnabledForTesting != widget.scoringEnabledForTesting) {
      _clearScoring();
      _configureScoring();
      if (_scoringEnabled && _account?['role'] == 'job_seeker') {
        unawaited(_loadScoring(widget.userId));
      }
    }
  }

  @override
  void dispose() {
    _scoringGeneration++;
    unawaited(_scoringSessionSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('User account'),
        content: SizedBox(
          width: 600,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: _error != null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Retry'),
                            ),
                          ],
                        )
                      : account == null
                      ? const Text('This account is unavailable.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Account information',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            for (final field in <(String, Object?)>[
                              ('Name', account['name']),
                              ('Role', account['role']),
                              ('Account status', account['account_status']),
                              ('Verification', account['verification_status']),
                              ('Joined', _displayDate(account['created_at'])),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text('${field.$1}: ${_value(field.$2)}'),
                              ),
                            if (_scoringEnabled &&
                                account['role'] == 'job_seeker')
                              _scoringSection(),
                            if (widget.canManage) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Contact and company information',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              for (final field in <(String, Object?)>[
                                ('Email', account['email']),
                                ('Phone', account['phone_num']),
                                if (account['memberships'] is! List) ...[
                                  ('Company', account['company_name']),
                                  ('Company role', account['member_role']),
                                ],
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    '${field.$1}: ${_value(field.$2)}',
                                  ),
                                ),
                            ],
                            if (widget.canManage &&
                                account['memberships'] is List)
                              for (final membership
                                  in account['memberships'] as List)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    'Company: ${_value(membership['company_name'])} — ${_value(membership['member_role'])}',
                                  ),
                                ),
                            if (_message != null) ...[
                              const SizedBox(height: 12),
                              Text(_message!),
                            ],
                            if (widget.canManage) ...[
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (account['account_status'] == 'active')
                                    FilledButton(
                                      onPressed: _saving
                                          ? null
                                          : () => _changeStatus('suspend'),
                                      child: const Text('Suspend account'),
                                    ),
                                  if (account['account_status'] == 'suspended')
                                    FilledButton(
                                      onPressed: _saving
                                          ? null
                                          : () => _changeStatus('reactivate'),
                                      child: const Text('Reactivate account'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Account restriction history',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (_history.isEmpty)
                                const Text('No recorded actions.'),
                              for (final item in _history)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    _value(item['action']).replaceAll('_', ' '),
                                  ),
                                  subtitle: Text(
                                    '${_value(item['performed_at'])} • ${_value(item['actor_name'])}'
                                    '${item['reason'] == null ? '' : '\nReason: ${item['reason']}'}',
                                  ),
                                ),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: _saving || _offset == 0
                                        ? null
                                        : () {
                                            _offset -= 20;
                                            _load();
                                          },
                                    child: const Text('Previous'),
                                  ),
                                  Text('Page ${_offset ~/ 20 + 1}'),
                                  TextButton(
                                    onPressed: _saving || !_more
                                        ? null
                                        : () {
                                            _offset += 20;
                                            _load();
                                          },
                                    child: const Text('Next'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class AccountRestrictionDialog extends StatefulWidget {
  const AccountRestrictionDialog({super.key, required this.action});
  final String action;

  @override
  State<AccountRestrictionDialog> createState() =>
      _AccountRestrictionDialogState();
}

class _AccountRestrictionDialogState extends State<AccountRestrictionDialog> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _allowPop = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    if (_reason.text.trim().isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard the reason?'),
          content: const Text('The reason you entered will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _confirm() {
    if (!_form.currentState!.validate()) return;
    final reason = _reason.text.trim();
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(reason);
    });
  }

  @override
  Widget build(BuildContext context) {
    final suspending = widget.action == 'suspend';
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: AlertDialog(
        title: Text(suspending ? 'Suspend account?' : 'Reactivate account?'),
        content: Form(
          key: _form,
          child: TextFormField(
            controller: _reason,
            maxLength: 2000,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: suspending
                  ? 'Suspension reason (required)'
                  : 'Reactivation reason (required)',
            ),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? 'Enter a reason.' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: _cancel, child: const Text('Cancel')),
          FilledButton(
            onPressed: _confirm,
            child: Text(suspending ? 'Suspend' : 'Reactivate'),
          ),
        ],
      ),
    );
  }
}
