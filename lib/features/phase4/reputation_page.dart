import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import 'phase4_store.dart';
import 'reputation_gateway.dart';
import 'reputation_summary.dart';

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
      maxWidth: 1280,
      child: ReputationContent(
        employer: employer,
        store: store,
        gateway: gateway,
        showPageHeading: true,
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
    this.showPageHeading = false,
    this.gateway,
    this.sessionSource,
  });

  final bool employer;
  final Phase4Store? store;
  final bool interactive;
  final bool showPageHeading;
  final ReputationGateway? gateway;
  final ReputationSessionSource? sessionSource;

  @override
  State<ReputationContent> createState() => _ReputationContentState();
}

class _ReputationContentState extends State<ReputationContent> {
  late ReputationGateway _gateway;
  ReputationSessionSource? _sessionSource;
  StreamSubscription<String?>? _sessionSubscription;
  String? _actorId;
  bool _sessionInvalid = false;
  int _requestGeneration = 0;
  late Future<Object> _summary;

  @override
  void initState() {
    super.initState();
    _configure();
  }

  void _configure() {
    unawaited(_sessionSubscription?.cancel());
    _sessionSubscription = null;
    _sessionInvalid = false;
    final injectedGateway = widget.gateway;
    final injectedSession = widget.sessionSource;
    if (injectedGateway == null) {
      final client = Supabase.instance.client;
      _gateway = SupabaseReputationGateway(client);
      _sessionSource =
          injectedSession ?? SupabaseReputationSessionSource(client);
    } else {
      _gateway = injectedGateway;
      _sessionSource = injectedSession;
    }
    final source = _sessionSource;
    _actorId = source?.currentUserId;
    if (source != null) {
      if (_actorId == null) _sessionInvalid = true;
      _sessionSubscription = source.userIdChanges.listen((userId) {
        if (userId != _actorId) _invalidateSession();
      }, onError: (Object error, StackTrace stack) => _invalidateSession());
    }
    _summary = _load();
  }

  void _invalidateSession() {
    if (!mounted || _sessionInvalid) return;
    setState(() {
      _sessionInvalid = true;
      _requestGeneration++;
    });
  }

  Future<Object> _load() async {
    if (_sessionInvalid) {
      throw StateError('Your account changed. Reopen Reputation to continue.');
    }
    final generation = ++_requestGeneration;
    final actorId = _actorId;
    final result = widget.employer
        ? await _gateway.companySummaries()
        : await _gateway.workerSummary();
    if (generation != _requestGeneration ||
        _sessionInvalid ||
        (_sessionSource != null &&
            (_sessionSource!.currentUserId == null ||
                _sessionSource!.currentUserId != actorId))) {
      throw StateError('Your account changed. Reopen Reputation to continue.');
    }
    return result;
  }

  @override
  void didUpdateWidget(covariant ReputationContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employer != widget.employer ||
        oldWidget.gateway != widget.gateway ||
        oldWidget.sessionSource != widget.sessionSource) {
      _requestGeneration++;
      _configure();
    }
  }

  void _retry() {
    if (_sessionInvalid) return;
    setState(() {
      _summary = _load();
    });
  }

  @override
  void dispose() {
    _requestGeneration++;
    unawaited(_sessionSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Object>(
    future: _summary,
    builder: (context, snapshot) {
      Widget body;
      if (_sessionInvalid) {
        body = WorkspaceCard(
          title: 'Reputation unavailable',
          child: const Text(
            'Your account changed or signed out. Reopen Reputation after signing in.',
          ),
        );
      } else if (snapshot.connectionState != ConnectionState.done) {
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
        body = WorkerReputationSummary(
          row: snapshot.data! as Map<String, dynamic>,
        );
      }
      final refresh = TextButton.icon(
        onPressed:
            !_sessionInvalid && snapshot.connectionState == ConnectionState.done
            ? _retry
            : null,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh reputation'),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showPageHeading)
            PageHeading(
              title: widget.employer ? 'Company Reputation' : 'My Reputation',
              description: widget.employer
                  ? 'Published worker feedback for the companies you manage.'
                  : 'Published company feedback and your verified work.',
              actions: [if (widget.interactive) refresh],
            )
          else if (widget.interactive)
            Align(alignment: Alignment.centerRight, child: refresh),
          if (!_sessionInvalid && snapshot.hasError)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: widget.interactive ? _retry : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          body,
          if (widget.interactive &&
              !_sessionInvalid &&
              snapshot.connectionState == ConnectionState.done &&
              !snapshot.hasError)
            Wrap(
              spacing: 12,
              children: [
                if (widget.showPageHeading)
                  TextButton.icon(
                    onPressed: () {
                      final route = widget.employer
                          ? AppRoutes.employerSoftSkillEvaluations
                          : AppRoutes.softSkillEvaluations;
                      context.go('$route?view=received');
                    },
                    icon: const Icon(Icons.rate_review_outlined),
                    label: const Text('View received evaluations'),
                  ),
                TextButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('How ratings are calculated'),
                      content: const SingleChildScrollView(
                        child: Text(
                          'Reputation uses eligible received evaluations published after both sides submit. Each rated application has equal weight. '
                          'Only observed core skills count. Additional criteria and Not Observed responses are excluded from the core rating. '
                          'Unresolved disputes can exclude evaluations and verified shifts. Attendance and punctuality are not scored. '
                          'Company feedback belongs to the company and is not assigned to individual members.',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.info_outline),
                  label: const Text('How ratings work'),
                ),
              ],
            ),
        ],
      );
    },
  );

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
          CompanyReputationSummary(row: row),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
