import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../applications/module2_repository.dart';
import '../jobs/job_display.dart';
import 'job_matching.dart';

/// Transport for explicitly requested AI insights.
abstract interface class RecommendationExplanationSource {
  Future<Object?> fetch(List<ExplanationJob> jobs, {Future<void>? abortSignal});
}

/// The Flutter adapter sends only shortlisted job IDs. The Edge handler
/// verifies those jobs against the caller's authorized feed.
/// The matcher and its evidence stay separate from this transport model.
class ExplanationJob {
  ExplanationJob.fromJob(BrowseJob job)
    : jobId = job.id,
      employmentType = _approvedValue(
        job.text('employment_type'),
        jobEmploymentTypes,
      ),
      workArrangement = _approvedValue(
        job.text('work_arrangement'),
        _arrangements,
      );

  final String jobId;
  final String? employmentType, workArrangement;

  bool get supportsInsights =>
      employmentType != null || workArrangement != null;
}

const _arrangements = {'on_site', 'hybrid', 'remote'};

String? _approvedValue(String value, Iterable<String> catalog) =>
    catalog.contains(value) ? value : null;

enum InsightScenario {
  strong,
  partial,
  limited;

  // Use the existing 70% filter threshold for presentation only. A real
  // numeric score, including zero, belongs to a scored scenario.
  static InsightScenario forMatch(JobMatch match) => switch (match.score) {
    null => limited,
    >= 70 => strong,
    _ => partial,
  };
}

typedef _Choices = ({String why, String consider, String next});
typedef InsightRun = ({String text, bool emphasis});

enum InsightSectionKind {
  why('Why this job may suit you'),
  consider('What to consider'),
  next('Suggested next step');

  const InsightSectionKind(this.title);
  final String title;
}

class InsightSection {
  const InsightSection(this.kind, this.runs, {this.fromAi = true});

  final InsightSectionKind kind;
  final List<InsightRun> runs;
  final bool fromAi;

  String get title => kind.title;
  String get text => runs.map((run) => run.text).join();
}

InsightRun _plain(String text) => (text: text, emphasis: false);
InsightRun _bold(String text) => (text: text, emphasis: true);

List<InsightRun> _emphasizedList(List<String> items) => [
  for (var i = 0; i < items.length; i++) ...[
    if (i > 0)
      _plain(
        i != items.length - 1
            ? ', '
            : items.length == 2
            ? ' and '
            : ', and ',
      ),
    _bold(items[i]),
  ],
];

String _readableList(Iterable<String> values) {
  final items = values.take(3).toList();
  return switch (items.length) {
    0 => '',
    1 => items.first,
    2 => '${items.first} and ${items.last}',
    _ => '${items.take(2).join(', ')}, and ${items.last}',
  };
}

class RecommendationInsightPlan {
  RecommendationInsightPlan._(this._scenarios);

  final Map<InsightScenario, _Choices> _scenarios;

  static RecommendationInsightPlan? _parse(Map row) {
    if (row.length != InsightScenario.values.length + 1) return null;
    final scenarios = <InsightScenario, _Choices>{};
    for (final scenario in InsightScenario.values) {
      final raw = row[scenario.name];
      if (raw is! Map || raw.length != 3) return null;
      final why = raw['why'];
      final consider = raw['consider'];
      final next = raw['next'];
      if (why is! String ||
          !const {'0', 's', 'b', 'p'}.contains(why) ||
          consider is! String ||
          !(scenario == InsightScenario.limited
                  ? const {'0', 'g', 'l'}
                  : const {'0', 'g', 'r'})
              .contains(consider) ||
          next is! String ||
          !const {'0', 'p', 'u', 'r'}.contains(next)) {
        return null;
      }
      scenarios[scenario] = (why: why, consider: consider, next: next);
    }
    return RecommendationInsightPlan._(scenarios);
  }

  List<InsightSection> sectionsFor(JobMatch match) {
    final scenario = InsightScenario.forMatch(match);
    final choice = _scenarios[scenario]!;
    final skills = _readableList(match.matchedSkills);
    final skillRuns = _emphasizedList(match.matchedSkills.take(3).toList());
    final keywords = _readableList(
      match.sharedKeywords.map((word) => '“$word”'),
    );
    final gaps = _readableList(match.skillsToDevelop);
    final title = match.job.title.trim();
    final role = title.isEmpty ? 'this role' : 'the $title position';
    final skillEvidence = skills.isEmpty
        ? null
        : [
            _plain('Your profile lists '),
            ...skillRuns,
            _plain(', which the posting mentions for $role.'),
          ];
    final location = match.job.text('location');
    final employmentType = jobLabel(match.job.text('employment_type'));
    final preferences = [
      if (match.employmentPreferenceMatch && employmentType.isNotEmpty)
        '$employmentType employment',
      if (match.locationPreferenceMatch && location.isNotEmpty)
        'the job location ($location)',
    ];
    final preferenceEvidence = preferences.isEmpty
        ? null
        : [
            ..._emphasizedList([
              if (preferences.length == 1)
                '${preferences.first[0].toUpperCase()}${preferences.first.substring(1)}'
              else
                ...preferences,
            ]),
            _plain(
              preferences.length == 1
                  ? ' matches your selected preference.'
                  : ' match your selected preferences.',
            ),
          ];
    final why = switch (choice.why) {
      's' => skillEvidence,
      'b' when keywords.isNotEmpty =>
        skills.isEmpty
            ? [
                _plain(
                  'The posting for $role shares $keywords with your profile or work experience.',
                ),
              ]
            : [
                _plain('Your profile and the posting for $role overlap on '),
                ...skillRuns,
                _plain('.'),
              ],
      'p' => preferenceEvidence,
      _ => null,
    };
    final score = match.score;
    final scoreLead = score == null
        ? [
            _plain(
              'There is limited information available to estimate your fit for this role.',
            ),
          ]
        : [_plain('Your estimated match is '), _bold('$score%')];
    final scoreFollowup = switch (score) {
      null => '',
      0 => ' based on the available comparisons.',
      >= 70 => '. Check for requirements the comparison may not cover.',
      _ => '. Compare the remaining requirements with your experience.',
    };
    final consider = switch (choice.consider) {
      'g' when gaps.isNotEmpty => [
        ...scoreLead,
        _plain(
          '${score == null ? '' : '.'} The posting lists $gaps, which your profile does not currently show.',
        ),
      ],
      'r' || 'l' => [
        ...scoreLead,
        if (scoreFollowup.isNotEmpty) _plain(scoreFollowup),
      ],
      _ => null,
    };
    final project = skills.isEmpty
        ? null
        : 'Highlight a project or work example involving $skills in your application.';
    final needsProfile = match.limitedEvidenceReasons.contains(
      LimitedEvidenceReason.profile,
    );
    final next = switch (choice.next) {
      'p' when project != null => project,
      'p' when keywords.isNotEmpty =>
        'Pick a project or work example that demonstrates your experience with $keywords.',
      'u' when gaps.isNotEmpty =>
        'If you have experience with $gaps, add a relevant example to your profile.',
      'u' when needsProfile => 'Add a relevant skill or work example to your profile so future comparisons have more to work with.',
      'r' => 'Pick one requirement from the posting and prepare an example of how you meet it.',
      _ => null,
    };
    final localNext = next == null && (why != null || consider != null)
        ? project
        : null;
    final whyExtra = choice.why == 'p' ? skillEvidence : preferenceEvidence;
    return [
      if (why != null)
        InsightSection(InsightSectionKind.why, [
          ...why,
          if (whyExtra != null) ...[_plain(' '), ...whyExtra],
        ]),
      if (consider != null)
        InsightSection(InsightSectionKind.consider, consider),
      if (next != null || localNext != null)
        InsightSection(InsightSectionKind.next, [
          _plain(next ?? localNext!),
        ], fromAi: next != null),
    ];
  }
}

class RecommendationExplanations {
  const RecommendationExplanations(
    this.source, {
    this.timeout = const Duration(seconds: 20),
  });

  final RecommendationExplanationSource source;
  final Duration timeout;
  static const shortlistLimit = 5;
  static const insightsVersion = 1;

  Future<Map<String, RecommendationInsightPlan>> load(
    Iterable<BrowseJob> shortlist,
  ) async => (await loadResult(shortlist)).plans;

  Future<InsightLoadResult> loadResult(
    Iterable<BrowseJob> shortlist, {
    Future<void>? abortSignal,
  }) async {
    final candidates = <String, ExplanationJob>{};
    for (final job in shortlist) {
      final candidate = ExplanationJob.fromJob(job);
      if (candidate.jobId.isEmpty || !candidate.supportsInsights) {
        continue;
      }
      candidates[candidate.jobId] = candidate;
      if (candidates.length == shortlistLimit) break;
    }
    const empty = <String, RecommendationInsightPlan>{};
    if (candidates.isEmpty) return (plans: empty, failure: null);
    final request = candidates.values.toList()
      ..sort((a, b) => a.jobId.compareTo(b.jobId));
    final abort = Completer<void>();
    unawaited(
      abortSignal?.then((_) {
        if (!abort.isCompleted) abort.complete();
      }),
    );
    try {
      final response = await source
          .fetch(List.unmodifiable(request), abortSignal: abort.future)
          .timeout(timeout);
      final plans = _validate(response, candidates);
      return (
        plans: plans,
        failure: plans.isEmpty ? InsightFailure.temporary : null,
      );
    } on FunctionException catch (error) {
      final failure = switch (error.status) {
        401 || 403 || 404 || 405 || 503 => InsightFailure.unavailable,
        400 || 422 => InsightFailure.shortlist,
        _ => InsightFailure.temporary,
      };
      return (plans: empty, failure: failure);
    } catch (_) {
      return (plans: empty, failure: InsightFailure.temporary);
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }

  /// A legacy response or any malformed batch leaves deterministic text visible.
  Map<String, RecommendationInsightPlan> _validate(
    Object? response,
    Map<String, ExplanationJob> candidates,
  ) {
    if (response is! Map ||
        response.length != 2 ||
        response['insights_version'] != insightsVersion ||
        response['insights'] is! List) {
      return const {};
    }
    final rows = response['insights'] as List;
    if (rows.length != candidates.length) return const {};
    final validated = <String, RecommendationInsightPlan>{};
    for (final row in rows) {
      if (row is! Map) return const {};
      final id = row['job_id'];
      if (id is! String ||
          validated.containsKey(id) ||
          !candidates.containsKey(id)) {
        return const {};
      }
      final plan = RecommendationInsightPlan._parse(row);
      if (plan == null) return const {};
      validated[id] = plan;
    }
    return Map.unmodifiable(validated);
  }
}

enum InsightFailure { temporary, shortlist, unavailable }

typedef InsightLoadResult = ({
  Map<String, RecommendationInsightPlan> plans,
  InsightFailure? failure,
});

typedef _PostingKey = (String, String?, String?);

_PostingKey _postingKey(BrowseJob job) {
  final posting = ExplanationJob.fromJob(job);
  return (posting.jobId, posting.employmentType, posting.workArrangement);
}

/// In-memory request state shared across visits to For You in this app session.
class RecommendationInsightRequests extends ChangeNotifier {
  RecommendationInsightRequests({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const cooldown = Duration(seconds: 30);
  final DateTime Function() _now;
  final _retryAfter = <String, DateTime>{};
  final _plans = <_PostingKey, RecommendationInsightPlan>{};
  final _failures = <String, InsightFailure>{};
  String? _actor;
  Object? _owner;
  RecommendationExplanationSource? _source;
  InsightFailure? _unavailable;
  Completer<void>? _pending;

  bool get loading => _pending != null;
  bool get hasLoaded => _plans.isNotEmpty;
  Duration get remaining {
    final delay = _retryAfter[_actor]?.difference(_now());
    return delay == null || delay.isNegative ? Duration.zero : delay;
  }

  // The page re-renders on account changes. Cached plans belong only to the
  // current account and transport, while recent cooldowns survive navigation.
  void activate(
    Object owner,
    String? actor,
    RecommendationExplanationSource? source,
  ) {
    if (_owner == owner && _actor == actor && identical(_source, source)) {
      return;
    }
    _cancelPending();
    _owner = owner;
    _actor = actor;
    _source = source;
    _plans.clear();
    _failures.clear();
    _unavailable = null;
  }

  RecommendationInsightPlan? planFor(BrowseJob job) => _plans[_postingKey(job)];

  List<JobMatch> shortlist(Iterable<JobMatch> matches) => matches
      .where(
        (match) =>
            match.score != null &&
            match.job.id.isNotEmpty &&
            ExplanationJob.fromJob(match.job).supportsInsights,
      )
      .take(RecommendationExplanations.shortlistLimit)
      .toList();

  String _batchKey(Iterable<JobMatch> matches) =>
      (matches.map((match) => _postingKey(match.job).toString()).toList()
            ..sort())
          .join('|');

  InsightFailure? failureFor(List<JobMatch> matches) =>
      _unavailable ?? _failures[_batchKey(matches)];

  Future<void> load(Object owner, List<JobMatch> matches) async {
    final actor = _actor;
    final source = _source;
    final batch = shortlist(matches);
    final failure = failureFor(batch);
    if (_owner != owner ||
        actor == null ||
        source == null ||
        loading ||
        hasLoaded ||
        remaining > Duration.zero ||
        batch.isEmpty ||
        failure == InsightFailure.shortlist ||
        failure == InsightFailure.unavailable) {
      return;
    }
    final key = _batchKey(batch);
    final pending = Completer<void>();
    _pending = pending;
    _retryAfter.removeWhere((_, until) => !until.isAfter(_now()));
    _retryAfter[actor] = _now().add(cooldown);
    notifyListeners();
    final result = await RecommendationExplanations(
      source,
    ).loadResult(batch.map((match) => match.job), abortSignal: pending.future);
    if (!identical(_pending, pending)) return;
    _pending = null;
    _retryAfter[actor] = _now().add(cooldown);
    if (result.failure == InsightFailure.unavailable) {
      _unavailable = result.failure;
    } else if (result.failure case final failure?) {
      _failures[key] = failure;
    } else {
      _failures.remove(key);
      for (final match in batch) {
        if (result.plans[match.job.id] case final plan?) {
          _plans[_postingKey(match.job)] = plan;
        }
      }
    }
    notifyListeners();
  }

  void cancel(Object owner) {
    if (_owner == owner) {
      activate(Object(), null, null);
    }
  }

  void _cancelPending() {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    if (_actor case final actor?) _retryAfter[actor] = _now().add(cooldown);
    pending.complete();
  }
}
