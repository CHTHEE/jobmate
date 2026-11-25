import '../applications/job_marketplace_format.dart';
import '../applications/module2_repository.dart';
import '../profile/job_seeker_profile_sections.dart';

enum RecommendationSort { bestMatch, newest, salary }

enum LimitedEvidenceReason { jobRequirements, profile }

class JobMatch {
  const JobMatch(
    this.job,
    this.score,
    this.matchedSkills,
    this.skillsToDevelop,
    this.explanation, {
    required this.sharedKeywords,
    required this.employmentPreferenceMatch,
    required this.locationPreferenceMatch,
    required this.limitedEvidenceReasons,
  });

  final BrowseJob job;
  final int? score;
  final List<String> matchedSkills, skillsToDevelop;
  final String explanation;
  final Set<String> sharedKeywords;
  final bool employmentPreferenceMatch, locationPreferenceMatch;
  final Set<LimitedEvidenceReason> limitedEvidenceReasons;

  bool get keywordOverlap => sharedKeywords.isNotEmpty;

  num? get disclosedMinimum => marketplaceSalary(job) == salaryNotDisclosed
      ? null
      : num.tryParse(job.text('salary_min'));
}

// Preserve punctuation used in technical skills such as C++, C# and .NET.
final _token = RegExp(r'\.?[a-z0-9][a-z0-9+#]*');
String normalizeMatchText(String text) =>
    _token.allMatches(text.toLowerCase()).map((m) => m[0]).join(' ');

bool _containsPhrase(String text, String phrase) =>
    phrase.isNotEmpty && ' $text '.contains(' $phrase ');

Set<String> _keywords(String text) =>
    normalizeMatchText(text)
        .split(' ')
        .where((token) => token.length >= 3 && !_genericWords.contains(token))
        .toSet();

const _genericWords = {
  'and',
  'the',
  'for',
  'with',
  'you',
  'our',
  'from',
  'will',
  'have',
  'are',
  'job',
  'role',
  'work',
  'team',
  'skills',
  'skill',
  'experience',
  'required',
  'preferred',
  'requirements',
  'years',
  'year',
  'must',
  'able',
  'looking',
};

// Only explicitly labeled skill lists support gap claims. Other requirement
// bullets can corroborate a known profile skill without being parsed as skills.
final _skillLabel = RegExp(
  r'^\s*(?:required skills|skills required|skills)\s*:\s*',
  caseSensitive: false,
);
final _listSeparator = RegExp(r'[,;](?![^()]*\))');
final _conjunction = RegExp(r'\s+(?:and|&)\s+', caseSensitive: false);
final _uncertainRequirement = RegExp(
  r'\b(?:or|either|optional|preferred|no|not|without|bonus)\b|\?',
  caseSensitive: false,
);
final _ambiguousSkill = RegExp(
  r'[/()\[\]]|\b(?:knowledge|experience|proficiency|proficient|familiarity|familiar|'
  r'required|recommended|plus|equivalent|related|such as)\b',
  caseSensitive: false,
);
final _skillName = RegExp(
  r'^[a-z0-9.+#-]+(?:\s+[a-z0-9.+#-]+){0,3}$',
  caseSensitive: false,
);

Map<String, String> _listedSkills(
  Iterable<String> requirements,
  Map<String, String> profileSkills,
) {
  final listed = <String, String>{};
  for (final line in requirements.where(_skillLabel.hasMatch)) {
    for (final item
        in line.replaceFirst(_skillLabel, '').split(_listSeparator)) {
      final name = item.trim().replaceFirst(RegExp(r'[.!]+$'), '');
      final parts = name.split(_conjunction);
      if (_uncertainRequirement.hasMatch(name) ||
          _ambiguousSkill.hasMatch(name) ||
          !parts.every(_skillName.hasMatch)) {
        continue;
      }
      final key = normalizeMatchText(name);
      if (key.isEmpty) continue;
      if (parts.length == 1 || profileSkills.containsKey(key)) {
        listed[key] = name;
      } else {
        // A conjunction can also be part of a skill name. Resolve it only
        // when each component independently appears as a profile skill.
        final keys = parts.map(normalizeMatchText).toList();
        if (keys.every(profileSkills.containsKey)) {
          listed.addEntries(
            keys.map((key) => MapEntry(key, profileSkills[key]!)),
          );
        }
      }
    }
  }
  return listed;
}

List<JobMatch> matchJobs(
  Iterable<BrowseJob> jobs,
  JobSeekerProfileData profile, {
  required Set<String> appliedJobIds,
  required DateTime now,
  String location = '',
  String employmentType = '',
}) {
  final profileSkills = <String, String>{};
  for (final row in profile['skills'] ?? const []) {
    final name = (row['skill_name'] as String? ?? '').trim();
    final normalized = normalizeMatchText(name);
    if (normalized.isNotEmpty) profileSkills[normalized] = name;
  }
  final background = _keywords(
    [
      for (final row in profile['about'] ?? const []) ...[
        row['headline'],
        row['bio'],
      ],
      for (final row in profile['experience'] ?? const []) ...[
        row['job_title'],
        row['description'],
      ],
    ].whereType<String>().join(' '),
  );

  return [
    for (final job in jobs)
      if (job.unavailable(now) == null && !appliedJobIds.contains(job.id))
        _match(job, profileSkills, background, location, employmentType),
  ];
}

JobMatch _match(
  BrowseJob job,
  Map<String, String> skills,
  Set<String> background,
  String location,
  String employmentType,
) {
  final requirements = job.bullets('requirements');
  final listed = _listedSkills(requirements, skills);
  final prose = requirements
      .where(
        (line) =>
            !_skillLabel.hasMatch(line) &&
            !_uncertainRequirement.hasMatch(line),
      )
      .map(normalizeMatchText)
      .toList();
  final proseMatches = skills.keys
      .where((key) => prose.any((line) => _containsPhrase(line, key)))
      .toSet();
  final matched = {...listed.keys.where(skills.containsKey), ...proseMatches};
  final gaps = listed.keys.where((key) => !skills.containsKey(key)).toList();
  final overview = job.text('role_overview');
  final hasOverview = _keywords(overview).length >= 2;
  final jobKeywords = _keywords('${job.title} $overview');
  final keywordOverlap = jobKeywords.intersection(background);
  final jobLocation = normalizeMatchText(job.text('location'));
  final preferredLocation = normalizeMatchText(location);
  final jobType = job.text('employment_type');
  final compareSkills = skills.isNotEmpty && listed.isNotEmpty;
  final compareBackground = background.isNotEmpty && jobKeywords.length >= 2;
  // Prose can corroborate known skills but provides no denominator for gaps.
  final corroboratedSkills = proseMatches.length;
  final compareType = employmentType.isNotEmpty && jobType.isNotEmpty;
  final compareLocation =
      preferredLocation.isNotEmpty && jobLocation.isNotEmpty;
  final typeMatches = compareType && employmentType == jobType;
  final locationMatches =
      compareLocation && _containsPhrase(jobLocation, preferredLocation);
  final evidence = <(int, double)>[
    if (compareSkills) (50, (listed.length - gaps.length) / listed.length),
    if (compareBackground) (30, keywordOverlap.length / jobKeywords.length),
    if (compareType) (10, typeMatches ? 1 : 0),
    if (compareLocation) (10, locationMatches ? 1 : 0),
  ];
  // Two explicit skills can stand on their own. With a shorter skill list,
  // require a substantive overview and an independent comparison. The
  // threshold counts comparable evidence, including actual mismatches.
  final enoughEvidence =
      (compareSkills && listed.length >= 2) ||
      (compareBackground &&
          hasOverview &&
          (compareSkills ||
              corroboratedSkills >= 2 ||
              compareType ||
              compareLocation));
  final score = enoughEvidence
      ? (100 *
                evidence.fold<double>(0, (sum, e) => sum + e.$1 * e.$2) /
                evidence.fold<int>(0, (sum, e) => sum + e.$1))
            .round()
      : null;
  final basis = [
    if (compareSkills) 'skills',
    if (compareBackground) 'profile or experience keywords',
    if (compareType || compareLocation) 'selected preferences',
  ];
  final limitedReasons = {
    if (score == null && listed.length < 2 && (listed.isEmpty || !hasOverview))
      LimitedEvidenceReason.jobRequirements,
    if (score == null &&
        ((skills.isEmpty && (listed.isNotEmpty || background.isEmpty)) ||
            (background.isEmpty && hasOverview)))
      LimitedEvidenceReason.profile,
  };
  return JobMatch(
    job,
    score,
    matched.map((key) => skills[key]!).toList()..sort(),
    (skills.isEmpty ? <String>[] : gaps.map((key) => listed[key]!).toList())
      ..sort(),
    [
      if (score != null) 'Based on ${basis.join(', ')}.',
      if (score != null && !compareSkills && corroboratedSkills >= 2)
        'Requirements also mention skills from your profile.',
      if (compareSkills && gaps.length == listed.length)
        'No listed skills overlap with your profile.',
      if (limitedReasons.contains(LimitedEvidenceReason.jobRequirements))
        'Limited job requirements available for comparison.',
      if (limitedReasons.contains(LimitedEvidenceReason.profile))
        'Profile skills or experience are missing.',
      if (locationMatches) 'Matches your selected location.',
      if (typeMatches) 'Matches your selected employment type.',
    ].join(' '),
    sharedKeywords: Set.unmodifiable(keywordOverlap),
    employmentPreferenceMatch: typeMatches,
    locationPreferenceMatch: locationMatches,
    limitedEvidenceReasons: Set.unmodifiable(limitedReasons),
  );
}

List<JobMatch> filterMatches(
  Iterable<JobMatch> matches, {
  String location = '',
  String employmentType = '',
  String salaryPeriod = '',
  num? minimumSalary,
  int minimumScore = 0,
  RecommendationSort sort = RecommendationSort.bestMatch,
}) {
  final rows = matches.where((match) {
    final job = match.job;
    return (location.isEmpty || job.text('location') == location) &&
        (employmentType.isEmpty ||
            job.text('employment_type') == employmentType) &&
        (minimumScore == 0 || (match.score ?? -1) >= minimumScore) &&
        (salaryPeriod.isEmpty ||
            (job.text('salary_period') == salaryPeriod &&
                match.disclosedMinimum != null)) &&
        (minimumSalary == null ||
            (salaryPeriod.isNotEmpty &&
                job.text('salary_period') == salaryPeriod &&
                (match.disclosedMinimum ?? -1) >= minimumSalary));
  }).toList();

  num? comparableSalary(JobMatch item) =>
      item.job.text('salary_period') == salaryPeriod && salaryPeriod.isNotEmpty
      ? item.disclosedMinimum
      : null;

  DateTime? date(JobMatch item) =>
      DateTime.tryParse(item.job.text('published_at'));
  rows.sort((a, b) {
    // Limited evidence always uses the date and ID tie-breakers.
    final primary = switch (sort) {
      _ when a.score == null && b.score == null => 0,
      RecommendationSort.bestMatch => (b.score ?? -1).compareTo(a.score ?? -1),
      RecommendationSort.newest => 0,
      RecommendationSort.salary => (comparableSalary(b) ?? -1).compareTo(
        comparableSalary(a) ?? -1,
      ),
    };
    if (primary != 0) return primary;
    final aDate = date(a);
    final bDate = date(b);
    final byDate = aDate == null
        ? (bDate == null ? 0 : 1)
        : (bDate == null ? -1 : bDate.compareTo(aDate));
    return byDate != 0 ? byDate : a.job.id.compareTo(b.job.id);
  });
  return rows;
}
