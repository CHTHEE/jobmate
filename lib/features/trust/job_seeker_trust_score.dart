import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/app_workspace.dart';

/// This is deliberately debug-only. A compile-time define alone cannot enable
/// the private score in profile or release builds.
const jobSeekerTrustScoreEnabled =
    kDebugMode &&
    bool.fromEnvironment('ENABLE_JOB_SEEKER_TRUST_SCORE', defaultValue: false);

const _allowedStates = <String>{
  'available',
  'insufficient_history',
  'temporarily_blocked_evidence',
  'missing_authoritative_contract',
  'dispute_evidence_unavailable',
};

const _requiredFields = <String>{
  'contract_version',
  'calculation_version',
  'state',
  'availability',
  'trust_score',
  'missing_factors',
  'provisional',
  'certification_state',
};

class JobSeekerTrustScore {
  const JobSeekerTrustScore._({
    required this.state,
    required this.available,
    required this.score,
    required this.missingFactors,
  });

  factory JobSeekerTrustScore.fromRpc(dynamic result) {
    if (result is! Map) {
      throw const FormatException('Trust Score response is unavailable.');
    }
    final row = Map<String, dynamic>.from(result);
    if (row.keys.toSet().length != _requiredFields.length ||
        !row.keys.toSet().containsAll(_requiredFields)) {
      throw const FormatException(
        'Trust Score response contains unsupported fields.',
      );
    }

    final state = row['state'];
    final availability = row['availability'];
    final missing = row['missing_factors'];
    if (row['contract_version'] != 'job-seeker-trust-self-read-v1' ||
        row['calculation_version'] != 'js-trust-v2-dispute-provisional' ||
        row['provisional'] != true ||
        row['certification_state'] != 'provisional_not_certified' ||
        state is! String ||
        !_allowedStates.contains(state) ||
        availability is! String ||
        !const {'available', 'unavailable'}.contains(availability) ||
        missing is! List ||
        missing.any((value) => value is! String || value.trim().isEmpty) ||
        missing.toSet().length != missing.length) {
      throw const FormatException('Trust Score response has invalid fields.');
    }

    final available = availability == 'available';
    final rawScore = row['trust_score'];
    if (available) {
      if (state != 'available' ||
          rawScore is! num ||
          !rawScore.isFinite ||
          rawScore < 0 ||
          rawScore > 100 ||
          missing.isNotEmpty) {
        throw const FormatException('Available Trust Score is invalid.');
      }
      return JobSeekerTrustScore._(
        state: state,
        available: true,
        score: rawScore.toDouble(),
        missingFactors: const [],
      );
    }
    if (state == 'available' || rawScore != null) {
      throw const FormatException(
        'Unavailable Trust Score must not contain a score.',
      );
    }
    return JobSeekerTrustScore._(
      state: state,
      available: false,
      score: null,
      missingFactors: List<String>.unmodifiable(missing.cast<String>()),
    );
  }

  final String state;
  final bool available;
  final double? score;
  final List<String> missingFactors;

  String get displayScore {
    final value = score;
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }
}

abstract interface class JobSeekerTrustScoreGateway {
  Future<JobSeekerTrustScore> load();
}

abstract interface class TrustScoreSessionSource {
  String? get currentUserId;
  Stream<String?> get userIdChanges;
}

class SupabaseTrustScoreSessionSource implements TrustScoreSessionSource {
  SupabaseTrustScoreSessionSource(this.client);

  final SupabaseClient client;

  @override
  String? get currentUserId => client.auth.currentSession?.user.id;

  @override
  Stream<String?> get userIdChanges =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);
}

class SupabaseJobSeekerTrustScoreGateway implements JobSeekerTrustScoreGateway {
  SupabaseJobSeekerTrustScoreGateway(this.client)
    : _actorId = client.auth.currentUser?.id;

  final SupabaseClient client;
  final String? _actorId;

  void _checkSession() {
    if (_actorId == null || client.auth.currentUser?.id != _actorId) {
      throw StateError('Your account changed. Reopen Trust Score to continue.');
    }
  }

  @override
  Future<JobSeekerTrustScore> load() async {
    _checkSession();
    final result = await client.rpc('get_my_job_seeker_trust_score_v2');
    _checkSession();
    return JobSeekerTrustScore.fromRpc(result);
  }
}

/// Keeps the Trust Score card out of every non-Job-Seeker profile, even if a
/// caller accidentally includes the section in another profile layout.
class JobSeekerTrustScoreSection extends StatelessWidget {
  const JobSeekerTrustScoreSection({
    super.key,
    required this.isActiveJobSeeker,
    this.enabled = jobSeekerTrustScoreEnabled,
    this.gateway,
    this.sessionSource,
  });

  final bool isActiveJobSeeker;
  final bool enabled;
  final JobSeekerTrustScoreGateway? gateway;
  final TrustScoreSessionSource? sessionSource;

  @override
  Widget build(BuildContext context) {
    if (!enabled || !isActiveJobSeeker) return const SizedBox.shrink();
    return JobSeekerTrustScoreContent(
      gateway: gateway,
      sessionSource: sessionSource,
    );
  }
}

class JobSeekerTrustScoreContent extends StatefulWidget {
  const JobSeekerTrustScoreContent({
    super.key,
    this.gateway,
    this.sessionSource,
  });

  final JobSeekerTrustScoreGateway? gateway;
  final TrustScoreSessionSource? sessionSource;

  @override
  State<JobSeekerTrustScoreContent> createState() =>
      _JobSeekerTrustScoreContentState();
}

class _JobSeekerTrustScoreContentState
    extends State<JobSeekerTrustScoreContent> {
  late JobSeekerTrustScoreGateway _gateway;
  TrustScoreSessionSource? _sessionSource;
  StreamSubscription<String?>? _sessionSubscription;
  String? _actorId;
  bool _sessionInvalid = false;
  int _requestGeneration = 0;
  late Future<JobSeekerTrustScore> _summary;

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
      _gateway = SupabaseJobSeekerTrustScoreGateway(client);
      _sessionSource =
          injectedSession ?? SupabaseTrustScoreSessionSource(client);
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
      }, onError: (_, _) => _invalidateSession());
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

  Future<JobSeekerTrustScore> _load() async {
    if (_sessionInvalid) {
      throw StateError('Your account changed. Reopen Trust Score to continue.');
    }
    final generation = ++_requestGeneration;
    final actorId = _actorId;
    final summary = await _gateway.load();
    if (generation != _requestGeneration ||
        _sessionInvalid ||
        (_sessionSource != null &&
            (_sessionSource!.currentUserId == null ||
                _sessionSource!.currentUserId != actorId))) {
      throw StateError('Your account changed. Reopen Trust Score to continue.');
    }
    return summary;
  }

  @override
  void didUpdateWidget(covariant JobSeekerTrustScoreContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway ||
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
  Widget build(BuildContext context) => FutureBuilder<JobSeekerTrustScore>(
    future: _summary,
    builder: (context, snapshot) {
      final Widget body;
      if (_sessionInvalid) {
        body = _sessionUnavailable();
      } else if (snapshot.connectionState != ConnectionState.done) {
        body = const WorkspaceCard(
          title: 'Trust Score',
          subtitle: 'Private to your Job Seeker account.',
          child: Center(child: CircularProgressIndicator()),
        );
      } else if (snapshot.hasError) {
        body = _error();
      } else if (snapshot.data != null) {
        final summary = snapshot.data!;
        body = _summaryCard(summary);
      } else {
        body = _error();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          if (!_sessionInvalid && snapshot.hasError)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Trust Score'),
              ),
            ),
        ],
      );
    },
  );

  Widget _summaryCard(JobSeekerTrustScore summary) {
    if (!summary.available) {
      return WorkspaceCard(
        title: 'Trust Score unavailable',
        subtitle: 'Private to your Job Seeker account.',
        leading: const Icon(Icons.lock_outline),
        child: const Text(
          'There is not enough reviewed activity to show a provisional Trust Score yet.',
        ),
      );
    }
    return WorkspaceCard(
      title: 'Trust Score',
      subtitle: 'Private to your Job Seeker account.',
      leading: const Icon(Icons.shield_outlined),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${summary.displayScore} / 100',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Chip(label: Text('Provisional')),
          const SizedBox(height: 8),
          const Text(
            'This is a private reference only. It is not a certification and does not replace hiring decisions.',
          ),
        ],
      ),
    );
  }

  Widget _error() => const WorkspaceCard(
    title: 'Trust Score unavailable',
    subtitle: 'Private to your Job Seeker account.',
    leading: Icon(Icons.error_outline),
    child: Text('We could not load your Trust Score. Try again.'),
  );

  Widget _sessionUnavailable() => const WorkspaceCard(
    title: 'Trust Score unavailable',
    subtitle: 'Private to your Job Seeker account.',
    leading: Icon(Icons.lock_outline),
    child: Text(
      'Your account changed or signed out. Reopen your profile after signing in.',
    ),
  );
}
