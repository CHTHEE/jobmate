import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/app_workspace.dart';
import 'reputation_gateway.dart';
import 'reputation_summary.dart';

/// Embedded in the existing read-only profile dialogs. Each request remains
/// scoped to the selected Application or visible Company at the server.
class CrossPartyReputationContent extends StatefulWidget {
  const CrossPartyReputationContent.applicant({
    super.key,
    required String applicationId,
    this.gateway,
  }) : _identifier = applicationId,
       _company = false;

  const CrossPartyReputationContent.company({
    super.key,
    required String companyId,
    this.gateway,
  }) : _identifier = companyId,
       _company = true;

  final String _identifier;
  final bool _company;
  final CrossPartyReputationGateway? gateway;

  @override
  State<CrossPartyReputationContent> createState() =>
      _CrossPartyReputationContentState();
}

class _CrossPartyReputationContentState
    extends State<CrossPartyReputationContent> {
  CrossPartyReputationGateway? _gateway;
  StreamSubscription<AuthState>? _sessionSubscription;
  late Future<Map<String, dynamic>> _summary;
  bool _sessionChanged = false;

  bool get _company => widget._company;

  @override
  void initState() {
    super.initState();
    _configureGateway();
    _summary = _load();
  }

  void _configureGateway() {
    unawaited(_sessionSubscription?.cancel());
    _sessionSubscription = null;
    _sessionChanged = false;
    _gateway = widget.gateway;
    if (_gateway != null) return;
    try {
      final client = Supabase.instance.client;
      final actor = client.auth.currentUser?.id;
      _gateway = SupabaseCrossPartyReputationGateway(client);
      _sessionSubscription = client.auth.onAuthStateChange.listen(
        (_) {
          if (mounted && client.auth.currentUser?.id != actor) {
            setState(() => _sessionChanged = true);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (mounted) setState(() => _sessionChanged = true);
        },
      );
    } catch (_) {
      // Missing client configuration is an unavailable summary, not an empty
      // history. The request Future presents the same retryable error state.
    }
  }

  @override
  void didUpdateWidget(CrossPartyReputationContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._identifier != widget._identifier ||
        oldWidget._company != widget._company ||
        oldWidget.gateway != widget.gateway) {
      _configureGateway();
      _summary = _load();
    }
  }

  Future<Map<String, dynamic>> _load() async {
    final gateway = _gateway;
    if (gateway == null || _sessionChanged) {
      throw StateError('Reopen this profile with an active account.');
    }
    final id = widget._identifier;
    final company = _company;
    final row = company
        ? await gateway.visibleCompanySummary(id)
        : await gateway.applicantSummary(id);
    final key = company ? 'company_id' : 'application_id';
    if (row[key] != id) {
      throw const FormatException(
        'Reputation summary identity does not match.',
      );
    }
    validateReputationSummary(row, company: company);
    return row;
  }

  void _retry() {
    setState(() {
      _summary = _load();
    });
  }

  @override
  void dispose() {
    unawaited(_sessionSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _summary,
    builder: (context, snapshot) {
      if (!_sessionChanged &&
          snapshot.connectionState != ConnectionState.done) {
        return const WorkspaceCard(
          title: 'Reputation',
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (_sessionChanged || snapshot.hasError) {
        final denied =
            snapshot.error is PostgrestException &&
            (snapshot.error as PostgrestException).code == '42501';
        return WorkspaceCard(
          title: 'Reputation unavailable',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _sessionChanged
                    ? 'Your account changed. Reopen this profile to continue.'
                    : denied
                    ? 'This reputation summary is unavailable or you no longer have access. Try again.'
                    : 'We could not load the verified summary. Try again.',
              ),
              if (!_sessionChanged)
                TextButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry reputation'),
                ),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _company ? 'Company reputation' : 'Applicant reputation',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (_company)
            CompanyReputationSummary(row: snapshot.data!)
          else
            WorkerReputationSummary(row: snapshot.data!),
        ],
      );
    },
  );
}
