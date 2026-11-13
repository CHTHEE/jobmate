import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/app_workspace.dart';

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
    super.key,
  });

  final String applicationId;
  final ApplicantProfileRepository? repository;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: ValueKey('applicant-profile:$applicationId'),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => _ApplicantProfileDialog(
        applicationId: applicationId,
        repository: repository,
      ),
    ),
    icon: const Icon(Icons.account_circle_outlined),
    label: const Text('View applicant profile'),
  );
}

class _ApplicantProfileDialog extends StatefulWidget {
  const _ApplicantProfileDialog({required this.applicationId, this.repository});

  final String applicationId;
  final ApplicantProfileRepository? repository;

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _repository.load(widget.applicationId);
      if (!mounted) return;
      setState(() => _response = response);
    } catch (error) {
      if (!mounted) return;
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

  Widget _section(String title, List<Widget> children, String emptyMessage) =>
      WorkspaceCard(
        title: title,
        child: children.isEmpty
            ? Text(emptyMessage)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
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
        _section('Skills', [
          for (final row in skills)
            _entry(_text(row['skill_name']).ifEmpty('Skill'), [
              _text(row['proficiency']),
            ]),
        ], 'No skills provided.'),
        const SizedBox(height: 12),
        _section('Education', [
          for (final row in education)
            _entry(_text(row['institution']).ifEmpty('Education'), [
              [
                _text(row['qualification']),
                _text(row['field_of_study']),
              ].where((value) => value.isNotEmpty).join(' · '),
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

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Applicant profile'),
    content: SizedBox(
      width: 620,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 600),
        child: _loading && _response == null
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_error!),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              )
            : Stack(
                children: [
                  SingleChildScrollView(child: _content()),
                  if (_loading)
                    const Positioned(
                      right: 4,
                      top: 4,
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
