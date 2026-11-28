import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme/jobmate_theme.dart';
import '../jobs/job_display.dart';
import '../chat/chat_application_button.dart';
import '../chat/chat_repository.dart';
import 'employer_applicants_repository.dart';
import 'employer_resume_button.dart';
import 'resume_pdf_opener.dart';
import 'module2_widgets.dart';
import '../phase4/cross_party_reputation_content.dart';
import '../phase4/reputation_gateway.dart';

abstract interface class ApplicantProfileRepository {
  Future<Map<String, dynamic>> load(String applicationId);
}

/// Calls the application-scoped RPC. The caller supplies no applicant or
/// Company identity; the database derives both from the Application.
class SupabaseApplicantProfileRepository implements ApplicantProfileRepository {
  SupabaseApplicantProfileRepository(this.client);

  final SupabaseClient client;

  @override
  Future<Map<String, dynamic>> load(String applicationId) async {
    final result = await client.rpc(
      'get_applicant_profile_for_company',
      params: {'p_application_id': applicationId},
    );
    if (result is! Map) {
      throw const FormatException('Invalid applicant profile response.');
    }
    final response = Map<String, dynamic>.from(result);
    if (response['application_id'] != applicationId ||
        response['profile'] is! Map) {
      throw const FormatException('Invalid applicant profile response.');
    }
    return response;
  }
}

class ApplicantProfileButton extends StatelessWidget {
  const ApplicantProfileButton({
    required this.applicationId,
    this.repository,
    this.applicant,
    this.jobTitle,
    this.applicantsRepository,
    this.resumeOpener,
    this.createChatRepository,
    this.reputationGateway,
    super.key,
  });

  final String applicationId;
  final ApplicantProfileRepository? repository;
  final JobApplicant? applicant;
  final String? jobTitle;
  final EmployerApplicantsRepository? applicantsRepository;
  final ResumePdfOpener? resumeOpener;
  final ChatRepository Function()? createChatRepository;
  final CrossPartyReputationGateway? reputationGateway;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: ValueKey('applicant-profile:$applicationId'),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => _ApplicantProfileDialog(
        applicationId: applicationId,
        repository: repository,
        applicant: applicant,
        jobTitle: jobTitle,
        applicantsRepository: applicantsRepository,
        resumeOpener: resumeOpener,
        createChatRepository: createChatRepository,
        reputationGateway: reputationGateway,
      ),
    ),
    icon: const Icon(Icons.account_circle_outlined),
    label: const Text('View applicant profile'),
  );
}

class _ApplicantProfileDialog extends StatefulWidget {
  const _ApplicantProfileDialog({
    required this.applicationId,
    this.repository,
    this.applicant,
    this.jobTitle,
    this.applicantsRepository,
    this.resumeOpener,
    this.createChatRepository,
    this.reputationGateway,
  });

  final String applicationId;
  final ApplicantProfileRepository? repository;
  final JobApplicant? applicant;
  final String? jobTitle;
  final EmployerApplicantsRepository? applicantsRepository;
  final ResumePdfOpener? resumeOpener;
  final ChatRepository Function()? createChatRepository;
  final CrossPartyReputationGateway? reputationGateway;

  @override
  State<_ApplicantProfileDialog> createState() =>
      _ApplicantProfileDialogState();
}

class _ApplicantProfileDialogState extends State<_ApplicantProfileDialog> {
  late final ApplicantProfileRepository _repository =
      widget.repository ??
      SupabaseApplicantProfileRepository(Supabase.instance.client);
  Map<String, dynamic>? _response;
  String? _error;
  bool _loading = true;
  final _scroll = ScrollController();
  late final String? _actor;
  late final Object? _company;
  late final String? _jobId;
  JobApplicant? get _applicant => widget.applicantsRepository?.applicants
      .where((row) => row.id == widget.applicationId)
      .firstOrNull;
  bool get _valid {
    final repo = widget.applicantsRepository;
    if (repo == null) return true;
    return repo.active &&
        repo.source.userId == _actor &&
        repo.jobId == _jobId &&
        repo.job != null &&
        repo.context?.access.company?['company_id'] == _company &&
        widget.applicant?.id == widget.applicationId &&
        _applicant?.applicantId == widget.applicant?.applicantId;
  }

  void _contextChanged() {
    if (!mounted) return;
    setState(() {
      if (!_valid) {
        _response = null;
        _loading = false;
        _error = 'Applicant profile unavailable or your application context changed. Close and reopen this profile.';
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // Bind the authorized overview context before starting any asynchronous read.
    _actor = widget.applicantsRepository?.source.userId;
    _company =
        widget.applicantsRepository?.context?.access.company?['company_id'];
    _jobId = widget.applicantsRepository?.jobId;
    widget.applicantsRepository?.addListener(_contextChanged);
    _load();
  }

  @override
  void dispose() {
    widget.applicantsRepository?.removeListener(_contextChanged);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_valid) {
      _contextChanged();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _repository.load(widget.applicationId);
      if (!mounted || !_valid) return;
      setState(() => _response = response);
    } catch (error) {
      if (!mounted || !_valid) return;
      setState(() {
        _response = null;
        _error = error is PostgrestException && error.code == '42501'
            ? 'Applicant profile unavailable or you no longer have access.'
            : 'Unable to load this applicant profile. Please retry.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> get _profile =>
      Map<String, dynamic>.from(_response?['profile'] as Map? ?? const {});

  List<Map<String, dynamic>> _records(String key) =>
      (_response?[key] as List? ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();

  String _text(Object? value) => value?.toString().trim() ?? '';

  String _dateRange(Map<String, dynamic> row, String start, String end) {
    final from = _text(row[start]);
    final to = _text(row[end]);
    if (from.isEmpty && to.isEmpty) return '';
    return '${from.isEmpty ? 'Date not provided' : from} – ${to.isEmpty ? 'End date not provided' : to}';
  }

  String _studyStatus(Map<String, dynamic> row) {
    if (row['is_current'] == true) return 'Currently studying';
    if (row['is_current'] == false) return 'Not currently studying';
    return 'Study status not provided';
  }

  Widget _section(String title, List<Widget> children, String emptyMessage) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: JobMateTheme.darkTeal,
            ),
          ),
          const SizedBox(height: 5),
          if (children.isEmpty)
            Text(
              emptyMessage,
              style: const TextStyle(color: JobMateTheme.body, fontSize: 13),
            )
          else
            ...children,
          const Divider(height: 16),
        ],
      );

  Widget _entry(String title, Iterable<String> details) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        for (final detail in details.where((value) => value.trim().isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: SelectableText(detail),
          ),
      ],
    ),
  );

  Widget _content() {
    final profile = _profile;
    final skills = _records('skills');
    final education = _records('education');
    final experience = _records('work_experiences');
    final languages = _records('languages');
    final availability = _records('availability');
    final certifications = _records('certifications');
    const weekdays = {
      1: 'Monday',
      2: 'Tuesday',
      3: 'Wednesday',
      4: 'Thursday',
      5: 'Friday',
      6: 'Saturday',
      7: 'Sunday',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section('About', [
          if (_text(profile['headline']).isNotEmpty)
            Text(
              _text(profile['headline']),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          if (_text(profile['bio']).isNotEmpty)
            SelectableText(_text(profile['bio'])),
        ], 'No profile introduction provided.'),
        const SizedBox(height: 12),
        CrossPartyReputationContent.applicant(
          applicationId: widget.applicationId,
          gateway: widget.reputationGateway,
        ),
        const SizedBox(height: 12),
        _section('Skills', [
          if (skills.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final row in skills)
                  Chip(
                    label: Text(
                      [
                        _text(row['skill_name']).ifEmpty('Skill'),
                        _text(row['proficiency']),
                      ].where((value) => value.isNotEmpty).join(' - '),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
        ], 'No skills provided.'),
        const SizedBox(height: 12),
        _section('Education', [
          for (final row in education)
            _entry(_text(row['institution']).ifEmpty('Education'), [
              [
                _text(row['qualification']),
                _text(row['field_of_study']),
              ].where((value) => value.isNotEmpty).join(' · '),
              _studyStatus(row),
              _dateRange(row, 'started_on', 'completed_on'),
              _text(row['description']),
            ]),
        ], 'No education provided.'),
        const SizedBox(height: 12),
        _section('Work experience', [
          for (final row in experience)
            _entry(_text(row['job_title']).ifEmpty('Work experience'), [
              _text(row['employer_name']),
              if (row['is_current'] == true) 'Currently working',
              _text(row['location']),
              _dateRange(row, 'started_on', 'ended_on'),
              _text(row['description']),
            ]),
        ], 'No work experience provided.'),
        const SizedBox(height: 12),
        _section('Languages', [
          for (final row in languages)
            _entry(_text(row['language_name']).ifEmpty('Language'), [
              _text(row['proficiency']),
            ]),
        ], 'No languages provided.'),
        const SizedBox(height: 12),
        _section('Weekly availability', [
          for (final row in availability)
            _entry(
              weekdays[row['iso_weekday']] ??
                  'Day ${_text(row['iso_weekday']).ifEmpty('not provided')}',
              [
                '${_clock(row['start_time'])} – ${_clock(row['end_time'])}',
                _text(row['timezone_name']),
              ],
            ),
        ], 'No weekly availability provided.'),
        const SizedBox(height: 12),
        _section('Certifications', [
          for (final row in certifications)
            _entry(_text(row['certification_name']).ifEmpty('Certification'), [
              _text(row['issuer']),
              _dateRange(row, 'issued_on', 'expires_on'),
              row['document_attached'] == true
                  ? 'Private document attached; contents are not shown here.'
                  : 'No document attached.',
              row['independently_verified'] == true
                  ? 'Independently verified'
                  : 'Self-declared; not independently verified',
            ]),
        ], 'No certifications provided.'),
      ],
    );
  }

  String _clock(Object? value) {
    final text = _text(value);
    if (text.isEmpty) return 'Time not provided';
    final parts = text.split(':');
    return parts.length >= 2 ? '${parts[0]}:${parts[1]}' : text;
  }

  Widget _identity(JobApplicant applicant) {
    final initials = applicant.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first)
        .join()
        .toUpperCase();
    final applied = applicant.appliedAt.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: JobMateTheme.teal50,
                foregroundColor: JobMateTheme.darkTeal,
                child: initials.isEmpty
                    ? const Icon(Icons.person_outline)
                    : Text(initials, style: const TextStyle(fontSize: 15)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      applicant.name,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (widget.jobTitle?.isNotEmpty == true)
                      Text(
                        'Applied for: ${widget.jobTitle}',
                        style: const TextStyle(
                          color: JobMateTheme.body,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MyApplicationStatusBadge(applicant.status),
              Text(
                'Applied: ${jobDate(applied)} - ${TimeOfDay.fromDateTime(applied).format(context)}',
                style: const TextStyle(color: JobMateTheme.body, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _message(String path) async {
    if (!mounted || !_valid || widget.applicantsRepository?.updating == true) {
      return;
    }
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    await router.push<void>(path);
  }

  @override
  Widget build(BuildContext context) {
    final applicant = _valid && _error == null ? _applicant : null;
    final available =
        !_loading && _error == null && _response != null && _valid;
    return AlertDialog(
      constraints: BoxConstraints(
        maxWidth: 640,
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      insetPadding: const EdgeInsets.all(16),
      titlePadding: const EdgeInsets.fromLTRB(20, 10, 10, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Applicant Profile',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Close applicant profile',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (applicant != null) _identity(applicant),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'Loading applicant profile',
                      ),
                    ),
                  )
                else if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _valid ? _load : null,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ),
                ] else if (available) ...[
                  if (_text(_profile['headline']).isEmpty &&
                      _text(_profile['bio']).isEmpty &&
                      [
                        'skills',
                        'education',
                        'work_experiences',
                        'languages',
                        'availability',
                        'certifications',
                      ].every((key) => _records(key).isEmpty))
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'No profile details have been provided yet.',
                        style: TextStyle(color: JobMateTheme.body),
                      ),
                    ),
                  if (applicant?.coverNote?.trim().isNotEmpty == true) ...[
                    _section('Application note', [
                      SelectableText(applicant!.coverNote!),
                    ], ''),
                    const SizedBox(height: 8),
                  ],
                  _content(),
                  if (applicant?.resumeId != null) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Resume',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: JobMateTheme.darkTeal,
                      ),
                    ),
                    EmployerResumeButton(
                      key: ValueKey(
                        'profile-resume:${applicant!.id}:${applicant.resumeId}',
                      ),
                      repository: widget.applicantsRepository!,
                      applicant: applicant,
                      opener: widget.resumeOpener,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (available &&
            applicant != null &&
            widget.applicantsRepository != null)
          ChatApplicationButton(
            applicationId: applicant.id,
            employer: true,
            enabled: !widget.applicantsRepository!.updating,
            createRepository: widget.createChatRepository,
            navigate: _message,
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
