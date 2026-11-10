import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'job_application_repository.dart';
import 'my_applications_repository.dart';
import 'employer_applicants_repository.dart';
import 'hiring_membership_source.dart';

// Temporary diagnostics: never log raw exceptions, object paths or signed URLs.
void debugPublishedLogo(String message) {
  if (kDebugMode) debugPrint('[JobMate logo] $message');
}

String sanitizedLogoStorageMessage(String message) => message
    .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '[URL omitted]')
    .replaceAll(
      RegExp(
        r'(?:bearer\s+|(?:token|apikey|authorization|signature|secret|key)\s*[:=]\s*)\S+',
        caseSensitive: false,
      ),
      '[credential omitted]',
    )
    .replaceAll(RegExp(r'[A-Za-z0-9_=.\-]{20,}'), '[value omitted]');

enum ApplicationStage {
  applied('Applied'),
  shortlisted('Shortlisted / Reviewing'),
  interview('Interview'),
  offered('Offered'),
  hired('Hired'),
  rejected('Rejected'),
  withdrawn('Withdrawn');

  const ApplicationStage(this.label);
  final String label;
  bool get completed => [hired, rejected, withdrawn].contains(this);
  bool get canWithdraw => [applied, shortlisted, interview].contains(this);
  List<ApplicationStage> get employerNext => switch (this) {
    applied => [shortlisted, rejected],
    shortlisted => [interview, rejected],
    interview => [offered, rejected],
    offered => [hired, rejected],
    _ => [],
  };

  static ApplicationStage? fromLabel(String label) => switch (label
      .toLowerCase()) {
    'applied' => applied,
    'reviewing' || 'shortlisted' || 'shortlisted / reviewing' => shortlisted,
    'interview' => interview,
    'offered' => offered,
    'hired' => hired,
    'rejected' => rejected,
    'withdrawn' => withdrawn,
    _ => null,
  };
}

/// Public presentation projection: hidden salary never enters this model.
/// This is NOT a replacement for backend column-level protection.
class BrowseJob {
  BrowseJob(Map<String, dynamic> fields, {required this.company})
    : fields = Map.unmodifiable({
        for (final key in const [
          'job_id',
          'logo_storage_path',
          'title',
          'department',
          'location',
          'employment_type',
          'work_arrangement',
          'vacancies',
          'application_deadline',
          'status',
          'role_overview',
          'original_description',
          'responsibilities',
          'requirements',
          'benefits',
          'salary_visible',
          'published_at',
        ])
          key: fields[key],
        if (fields['salary_visible'] == true)
          for (final key in ['salary_min', 'salary_max', 'salary_period'])
            key: fields[key],
      });
  final Map<String, dynamic> fields;
  final String company;
  String? get logoStoragePath => fields['logo_storage_path'] as String?;
  factory BrowseJob.published(Map<String, dynamic> row) => BrowseJob({
    ...row,
    'status': 'published',
  }, company: row['company_name'] as String? ?? '');
  String text(String key) => '${fields[key] ?? ''}';
  String get id => text('job_id');
  String get title => text('title');
  List<String> bullets(String key) =>
      (fields[key] as List? ?? []).whereType<String>().toList();
  String? unavailable([DateTime? now]) {
    if (text('status') != 'published') {
      return 'This job is ${text('status')}. Applications are unavailable.';
    }
    final deadline = DateTime.tryParse(text('application_deadline'));
    if (deadline == null) return 'Application deadline is unavailable.';
    final today = now ?? DateTime.now();
    if (deadline.isBefore(DateTime(today.year, today.month, today.day))) {
      return 'Application deadline has passed.';
    }
    return null;
  }
}

abstract class PublishedJobsSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<List<Map<String, dynamic>>> list();
  Future<String> signLogo(String path);
}

class SupabasePublishedJobsSource implements PublishedJobsSource {
  SupabasePublishedJobsSource(this.client);
  final SupabaseClient client;
  @override
  Future<String> signLogo(String path) =>
      client.storage.from('jobmate-company-logos').createSignedUrl(path, 300);
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);
  @override
  Future<List<Map<String, dynamic>>> list() async {
    debugPublishedLogo(
      'RPC list_published_jobs project=${Uri.parse(client.rest.url).host}',
    );
    final rows = await client.rpc('list_published_jobs');
    if (kDebugMode && rows is List) {
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index] as Map;
        final path = row['logo_storage_path'];
        debugPublishedLogo(
          'RPC row=$index logo_field=${row.containsKey('logo_storage_path')} '
          'logo_path=${path == null
              ? 'null'
              : path is String && path.trim().isNotEmpty
              ? 'nonempty'
              : 'empty/invalid'}',
        );
      }
    }
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}

/// Real browsing stays separate from the application demo's fictional jobs.
class PublishedJobsRepository extends ChangeNotifier {
  PublishedJobsRepository(this.source, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      _actorId = source.userId {
    _subscription = source.accountChanges.listen((id) {
      if (id == _actorId) return;
      reset();
      if (id != null) load();
    });
  }
  final PublishedJobsSource source;
  final DateTime Function() _now;
  final _logoUrls = <String, (DateTime, Future<String?>)>{};
  final _failedLogos = <String>{};
  int _logoGeneration = 0;

  Future<String?> logoUrl(String? path) {
    if (_disposed ||
        source.userId == null ||
        source.userId != _actorId ||
        path == null ||
        path.trim().isEmpty ||
        !jobs.any((job) => job.logoStoragePath == path)) {
      debugPublishedLogo(
        'Signing skipped: missing path, unavailable job or changed session.',
      );
      return Future.value(null);
    }
    final cached = _logoUrls[path];
    if (cached != null && _now().isBefore(cached.$1)) {
      debugPublishedLogo(
        'Signing cache hit; failed=${_failedLogos.contains(path)}',
      );
      return cached.$2;
    }
    final actor = _actorId;
    final generation = _logoGeneration;
    final future = () async {
      try {
        debugPublishedLogo(
          'createSignedUrl start bucket=jobmate-company-logos ttl=300',
        );
        final url = await source.signLogo(path);
        if (_disposed ||
            generation != _logoGeneration ||
            source.userId != actor) {
          return null;
        }
        _failedLogos.remove(path);
        debugPublishedLogo('createSignedUrl succeeded');
        return url;
      } catch (failure) {
        if (!_disposed &&
            generation == _logoGeneration &&
            source.userId == actor) {
          _failedLogos.add(path);
        }
        if (failure is StorageException) {
          debugPublishedLogo(
            'createSignedUrl failed Storage status=${sanitizedLogoStorageMessage(failure.statusCode ?? 'unknown')} '
            'message=${sanitizedLogoStorageMessage(failure.message)}',
          );
        } else {
          debugPublishedLogo(
            'createSignedUrl failed type=${failure.runtimeType}',
          );
        }
        // Logo failures never prevent viewing jobs or show a broken image.
        return null;
      }
    }();
    // Reuse pending requests too, and renew before the five-minute URL expires.
    _logoUrls[path] = (_now().add(const Duration(seconds: 285)), future);
    return future;
  }

  late final StreamSubscription<String?> _subscription;
  String? _actorId;
  int _generation = 0;
  bool _disposed = false;
  bool loading = false, loaded = false;
  String? error;
  final List<BrowseJob> _jobs = [];
  final Set<String> _saved = {};
  List<BrowseJob> get jobs =>
      source.userId == _actorId ? List.unmodifiable(_jobs) : const [];
  BrowseJob? job(String id) => jobs.where((j) => j.id == id).firstOrNull;
  bool saved(String id) => source.userId == _actorId && _saved.contains(id);
  void toggleSave(String id) {
    if (job(id) == null) return;
    if (!_saved.remove(id)) _saved.add(id);
    notifyListeners();
  }

  Future<void> load() async {
    if (_disposed) return;
    if (source.userId != _actorId) reset();
    if (loading) return;
    // Explicit refresh should recover after a transient Storage/policy failure.
    for (final path in _failedLogos) {
      _logoUrls.remove(path);
    }
    _failedLogos.clear();
    final actor = source.userId;
    final generation = ++_generation;
    _jobs.clear();
    error = null;
    loaded = false;
    loading = true;
    notifyListeners();
    try {
      if (actor == null) throw StateError('Sign in to browse jobs.');
      final rows = await source.list();
      if (_disposed || generation != _generation || source.userId != actor) {
        return;
      }
      final jobs = rows.map(BrowseJob.published).toList();
      _jobs.addAll(jobs);
      loaded = true;
    } catch (failure) {
      if (_disposed || generation != _generation || source.userId != actor) {
        return;
      }
      error = failure is StateError
          ? failure.message.toString()
          : failure is PostgrestException && failure.code == '42501'
          ? 'An active Job Seeker account is required to browse jobs.'
          : 'Unable to load jobs. Please retry.';
    } finally {
      if (!_disposed && generation == _generation) {
        if (source.userId != actor) {
          reset();
        } else {
          loading = false;
          notifyListeners();
        }
      }
    }
  }

  List<BrowseJob> searchJobs({
    String query = '',
    String type = '',
    String arrangement = '',
    String location = '',
    String sort = 'Newest',
    bool savedOnly = false,
  }) {
    final result = jobs
        .where(
          (j) =>
              '${j.title} ${j.company} ${j.text('role_overview')} ${j.text('original_description')} ${j.text('department')} ${j.bullets('requirements').join(' ')}'
                  .toLowerCase()
                  .contains(query.trim().toLowerCase()) &&
              (type.isEmpty || j.text('employment_type') == type) &&
              (arrangement.isEmpty ||
                  j.text('work_arrangement') == arrangement) &&
              j
                  .text('location')
                  .toLowerCase()
                  .contains(location.toLowerCase()) &&
              (!savedOnly || saved(j.id)),
        )
        .toList();
    result.sort(
      (a, b) => switch (sort) {
        'Title' => a.title.compareTo(b.title),
        'Deadline' =>
          a
              .text('application_deadline')
              .compareTo(b.text('application_deadline')),
        _ => b.text('published_at').compareTo(a.text('published_at')),
      },
    );
    return result;
  }

  void reset() {
    ++_logoGeneration;
    _logoUrls.clear();
    _failedLogos.clear();
    ++_generation;
    _actorId = source.userId;
    _jobs.clear();
    _saved.clear();
    loading = false;
    loaded = false;
    error = 'Your session changed. Refresh to load jobs.';
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_logoGeneration;
    _logoUrls.clear();
    _failedLogos.clear();
    ++_generation;
    _subscription.cancel();
    super.dispose();
  }
}

class DemoApplication {
  DemoApplication({
    required this.id,
    required this.jobId,
    required this.candidate,
    required this.stage,
    required this.note,
    required DateTime date,
    this.skills = const [],
    this.resume = false,
    this.mine = false,
  }) : timeline = [(ApplicationStage.applied, date)] {
    if (stage != ApplicationStage.applied) timeline.add((stage, date));
  }
  final String id, jobId, candidate, note;
  final List<String> skills;
  final bool resume, mine;
  ApplicationStage stage;
  final List<(ApplicationStage, DateTime)> timeline;
  String internalNote = '';
  DateTime get date => timeline.first.$2;
}

/// Isolated fictional environment. No job, user, application or resume writes.
class Module2Repository extends ChangeNotifier {
  Module2Repository({
    this.publishedSource,
    this.applicationGatewayFactory,
    this.myApplicationsSource,
    this.employerApplicantsSource,
  }) {
    reset();
  }
  static final session = Module2Repository();
  final PublishedJobsSource? publishedSource;
  final MyApplicationsSource? myApplicationsSource;
  final EmployerApplicantsSource? employerApplicantsSource;
  EmployerApplicantsSource createEmployerApplicantsSource() =>
      employerApplicantsSource ??
      SupabaseEmployerApplicantsSource(Supabase.instance.client);
  MyApplicationsRepository? _myApplications;
  MyApplicationsRepository get myApplications =>
      _myApplications ??= MyApplicationsRepository(
        myApplicationsSource ??
            createMyApplicationsSource(Supabase.instance.client),
      );
  final JobApplicationGateway Function()? applicationGatewayFactory;
  JobApplicationGateway createApplicationGateway() =>
      applicationGatewayFactory?.call() ??
      SupabaseJobApplicationGateway(Supabase.instance.client);
  PublishedJobsRepository? _browse;
  PublishedJobsRepository get browse => _browse ??= PublishedJobsRepository(
    publishedSource ?? SupabasePublishedJobsSource(Supabase.instance.client),
  );

  @override
  void dispose() {
    _browse?.dispose();
    _myApplications?.dispose();
    super.dispose();
  }

  final List<BrowseJob> _jobs = [];
  final List<DemoApplication> _applications = [];
  final Set<String> _saved = {};
  final Map<String, String> _noteDrafts = {};
  String noteDraft(String key) => _noteDrafts[key] ?? '';
  void keepNoteDraft(String key, String value) => _noteDrafts[key] = value;
  void clearNoteDraft(String key) => _noteDrafts.remove(key);
  List<BrowseJob> get jobs => List.unmodifiable(_jobs);
  List<DemoApplication> get applications => List.unmodifiable(_applications);
  BrowseJob? job(String id) => _jobs.where((j) => j.id == id).firstOrNull;
  DemoApplication? application(String id) =>
      _applications.where((a) => a.id == id).firstOrNull;
  bool saved(String id) => _saved.contains(id);
  bool applied(String id) => _applications.any((a) => a.jobId == id && a.mine);
  void toggleSave(String id) {
    if (job(id) == null) return;
    if (!_saved.remove(id)) _saved.add(id);
    notifyListeners();
  }

  List<BrowseJob> searchJobs({
    String query = '',
    String type = '',
    String arrangement = '',
    String location = '',
    String sort = 'Newest',
    bool savedOnly = false,
  }) {
    final words = query.toLowerCase().trim();
    final result = _jobs
        .where(
          (j) =>
              j.text('status') == 'published' &&
              '${j.title} ${j.company} ${j.text('role_overview')} ${j.text('department')} ${j.bullets('requirements').join(' ')}'
                  .toLowerCase()
                  .contains(words) &&
              (type.isEmpty || j.text('employment_type') == type) &&
              (arrangement.isEmpty ||
                  j.text('work_arrangement') == arrangement) &&
              j
                  .text('location')
                  .toLowerCase()
                  .contains(location.toLowerCase()) &&
              (!savedOnly || saved(j.id)),
        )
        .toList();
    result.sort(
      (a, b) => switch (sort) {
        'Title' => a.title.compareTo(b.title),
        'Deadline' =>
          a
              .text('application_deadline')
              .compareTo(b.text('application_deadline')),
        _ => b.text('published_at').compareTo(a.text('published_at')),
      },
    );
    return result;
  }

  List<DemoApplication> searchApplications({
    bool mineOnly = false,
    String query = '',
    String jobId = '',
    ApplicationStage? stage,
    String tab = 'All',
    String sort = 'Newest',
  }) {
    final result = _applications.where((a) {
      final j = job(a.jobId)!;
      return (!mineOnly || a.mine) &&
          (jobId.isEmpty || a.jobId == jobId) &&
          (stage == null || a.stage == stage) &&
          (tab == 'All' ||
              (tab == 'Completed' ? a.stage.completed : !a.stage.completed)) &&
          '${a.candidate} ${j.title} ${j.company} ${a.skills.join(' ')}'
              .toLowerCase()
              .contains(query.trim().toLowerCase());
    }).toList();
    result.sort(
      (a, b) => sort == 'Name'
          ? a.candidate.compareTo(b.candidate)
          : sort == 'Oldest'
          ? a.date.compareTo(b.date)
          : b.date.compareTo(a.date),
    );
    return result;
  }

  Future<void> submit(String jobId, String note) async {
    final j = job(jobId);
    if (j == null || j.unavailable() != null) {
      throw StateError('This demo job is unavailable.');
    }
    if (applied(jobId)) {
      throw StateError('You already have a demo application for this job.');
    }
    if (note.length > 1000) {
      throw StateError('Keep the note within 1,000 characters.');
    }
    _applications.add(
      DemoApplication(
        id: 'demo-application-${_applications.length + 1}',
        jobId: jobId,
        candidate: 'Demo candidate (you)',
        stage: ApplicationStage.applied,
        note: note.trim(),
        date: DateTime.now(),
        mine: true,
      ),
    );
    notifyListeners();
  }

  void transition(
    String id,
    ApplicationStage next, {
    required bool employer,
    String note = '',
  }) {
    final a = application(id);
    if (a == null) throw StateError('Demo application is unavailable.');
    final allowed = employer
        ? a.stage.employerNext.contains(next)
        : a.mine &&
              ((a.stage.canWithdraw && next == ApplicationStage.withdrawn) ||
                  (a.stage == ApplicationStage.offered &&
                      [
                        ApplicationStage.hired,
                        ApplicationStage.withdrawn,
                      ].contains(next)));
    if (!allowed) throw StateError('This status change is unavailable.');
    if (note.length > 1000) {
      throw StateError('Keep the internal note within 1,000 characters.');
    }
    a.stage = next;
    if (employer && next == ApplicationStage.rejected) {
      a.internalNote = note.trim();
    }
    a.timeline.add((next, DateTime.now()));
    notifyListeners();
  }

  void reset() {
    _browse?.reset();
    _myApplications?.reset();
    _saved.clear();
    _noteDrafts.clear();
    _applications.clear();
    _jobs.clear();
    final now = DateTime.now();
    for (var i = 0; i < 5; i++) {
      _jobs.add(
        BrowseJob(
          {
            'job_id': 'demo-job-${i + 1}',
            'title': [
              'Retail Assistant',
              'Flutter Intern',
              'Customer Support Associate',
              'Event Crew',
              'Office Assistant',
            ][i],
            'department': [
              'Retail',
              'Engineering',
              'Operations',
              'Events',
              'Administration',
            ][i],
            'location': [
              'Shah Alam',
              'Kuala Lumpur',
              'Petaling Jaya',
              'Kuala Lumpur',
              'Shah Alam',
            ][i],
            'employment_type': [
              'part_time',
              'internship',
              'full_time',
              'temporary',
              'contract',
            ][i],
            'work_arrangement': [
              'on_site',
              'hybrid',
              'remote',
              'on_site',
              'on_site',
            ][i],
            'vacancies': i + 1,
            'status': i == 4 ? 'closed' : 'published',
            'salary_visible': i.isEven,
            'salary_min': 12,
            'salary_max': 18,
            'salary_period': 'hourly',
            'application_deadline': now
                .add(Duration(days: i == 3 ? -1 : 30 + i))
                .toIso8601String()
                .substring(0, 10),
            'published_at': now.subtract(Duration(days: i)).toIso8601String(),
            'role_overview': 'A fictional opportunity to explore the JobMate application workflow. No real vacancy is advertised.',
            'responsibilities': [
              'Support the team with daily tasks.',
              'Communicate clearly with colleagues.',
            ],
            'requirements': ['Communication skills', 'Willingness to learn'],
            'benefits': i == 1 ? <String>[] : ['Demo training programme'],
          },
          company: [
            'Demo Cedar Store',
            'Demo Pixel Studio',
            'Demo Horizon Services',
            'Demo Gather Events',
            'Demo Cedar Store',
          ][i],
        ),
      );
    }
    for (var i = 0; i < ApplicationStage.values.length; i++) {
      _applications.add(
        DemoApplication(
          id: 'demo-seed-$i',
          jobId: i == 3 ? 'demo-job-4' : 'demo-job-${i % 3 + 1}',
          candidate: i == 0 || i == 3
              ? 'Demo candidate (you)'
              : 'Sample candidate ${i + 1}',
          stage: ApplicationStage.values[i],
          note: 'Fictional application for UI preview.',
          date: now.subtract(Duration(days: i + 1)),
          skills: ['Communication', 'Teamwork'],
          resume: i.isEven,
          mine: i == 0 || i == 3,
        ),
      );
    }
    notifyListeners();
  }
}
