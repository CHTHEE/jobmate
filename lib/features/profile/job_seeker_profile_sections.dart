import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

/// A compact, owner-facing editor for the additive Job Seeker profile schema.
/// The repository is injectable so the UI can be exercised without Supabase.
class JobSeekerProfileSections extends StatefulWidget {
  const JobSeekerProfileSections({
    required this.userId,
    this.repository,
    this.canEdit = true,
    super.key,
  });

  final String userId;
  final JobSeekerProfileRepository? repository;
  final bool canEdit;

  @override
  State<JobSeekerProfileSections> createState() =>
      _JobSeekerProfileSectionsState();
}

typedef JobSeekerProfileData = Map<String, List<Map<String, dynamic>>>;

/// Client-side feedback only; the database exclusion constraint remains final.
String? validateWeeklyAvailabilitySlot({
  required int weekday,
  required TimeOfDay start,
  required TimeOfDay end,
  required List<Map<String, dynamic>> existing,
  String? excludedSlotId,
}) {
  final startMinutes = start.hour * 60 + start.minute;
  final endMinutes = end.hour * 60 + end.minute;
  if (weekday < 1 || weekday > 7) return 'Choose a valid weekday.';
  if (endMinutes <= startMinutes) {
    return 'End time must be after start time. Overnight availability is not supported.';
  }
  for (final slot in existing) {
    if (slot['slot_id'] == excludedSlotId || slot['iso_weekday'] != weekday) {
      continue;
    }
    final slotStart = slot['start_time'].toString().split(':');
    final slotEnd = slot['end_time'].toString().split(':');
    final previousStart =
        int.parse(slotStart[0]) * 60 + int.parse(slotStart[1]);
    final previousEnd = int.parse(slotEnd[0]) * 60 + int.parse(slotEnd[1]);
    if (startMinutes < previousEnd && previousStart < endMinutes) {
      return 'This slot overlaps another slot on that day. Adjacent slots are allowed.';
    }
  }
  return null;
}

abstract interface class JobSeekerProfileRepository {
  Future<JobSeekerProfileData> load(String userId);
  Future<void> saveAbout(String userId, String headline, String bio);
  Future<void> saveRecord(
    String userId,
    String section,
    Map<String, dynamic> values,
  );
  Future<void> deleteRecord(String userId, String section, String id);
  Future<String> uploadCertificate(String userId, String recordId, XFile file);
  Future<void> saveCertificate(String userId, Map<String, dynamic> values);
  Future<String> certificateUrl(String userId, String path);
}

class SupabaseJobSeekerProfileRepository implements JobSeekerProfileRepository {
  SupabaseJobSeekerProfileRepository(this.client);

  final SupabaseClient client;
  static const _uuid = Uuid();
  static const _sections = <String, String>{
    'skills': 'skill_id',
    'certifications': 'certification_id',
    'education': 'education_id',
    'experience': 'experience_id',
    'languages': 'language_id',
    'availability': 'slot_id',
  };

  String _checkOwner(String userId) {
    final actual = client.auth.currentUser?.id;
    if (actual == null || actual != userId) {
      throw StateError(
        'Your login changed. Reopen your profile and try again.',
      );
    }
    return actual;
  }

  @override
  Future<JobSeekerProfileData> load(String userId) async {
    _checkOwner(userId);
    final profileFuture = client
        .from('job_seeker_profiles')
        .select('headline,bio')
        .eq('user_id', userId)
        .maybeSingle();
    final skillsFuture = client
        .from('job_seeker_skills')
        .select('skill_id,skill_name,proficiency')
        .eq('user_id', userId)
        .order('skill_name');
    final certificationsFuture = client
        .from('job_seeker_certifications')
        .select(
          'certification_id,certification_name,issuer,issued_on,expires_on,'
          'document_storage_path,document_mime_type,document_size_bytes',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    final educationFuture = client
        .from('job_seeker_education')
        .select(
          'education_id,institution,qualification,field_of_study,started_on,'
          'completed_on,is_current,description',
        )
        .eq('user_id', userId)
        .order('started_on', ascending: false, nullsFirst: false);
    final experienceFuture = client
        .from('job_seeker_work_experiences')
        .select(
          'experience_id,employer_name,job_title,location,started_on,ended_on,'
          'is_current,description',
        )
        .eq('user_id', userId)
        .order('started_on', ascending: false, nullsFirst: false);
    final languagesFuture = client
        .from('job_seeker_languages')
        .select('language_id,language_name,proficiency')
        .eq('user_id', userId)
        .order('language_name');
    final availabilityFuture = client
        .from('job_seeker_availability')
        .select('slot_id,iso_weekday,start_time,end_time,timezone_name')
        .eq('user_id', userId)
        .order('iso_weekday')
        .order('start_time');

    final results = await Future.wait<Object?>([
      profileFuture,
      skillsFuture,
      certificationsFuture,
      educationFuture,
      experienceFuture,
      languagesFuture,
      availabilityFuture,
    ]);
    _checkOwner(userId);
    final profile = results[0] as Map<String, dynamic>?;
    return {
      'about': profile == null ? <Map<String, dynamic>>[] : [profile],
      'skills': _rows(results[1]),
      'certifications': _rows(results[2]),
      'education': _rows(results[3]),
      'experience': _rows(results[4]),
      'languages': _rows(results[5]),
      'availability': _rows(results[6]),
    };
  }

  List<Map<String, dynamic>> _rows(Object? result) =>
      (result as List).cast<Map<String, dynamic>>();

  @override
  Future<void> saveAbout(String userId, String headline, String bio) async {
    _checkOwner(userId);
    await client.rpc(
      'save_my_job_seeker_profile',
      params: {
        'p_headline': headline.trim().isEmpty ? null : headline.trim(),
        'p_bio': bio.trim().isEmpty ? null : bio.trim(),
      },
    );
    _checkOwner(userId);
  }

  @override
  Future<void> saveRecord(
    String userId,
    String section,
    Map<String, dynamic> values,
  ) async {
    _checkOwner(userId);
    final table = _table(section);
    final idColumn = _sections[section]!;
    final id = values[idColumn] as String? ?? _uuid.v4();
    final record = <String, dynamic>{
      ...values,
      idColumn: id,
      'user_id': userId,
    };
    if (section == 'availability') {
      record['timezone_name'] = 'Asia/Kuala_Lumpur';
    }
    if (values.containsKey(idColumn)) {
      final updated = await client
          .from(table)
          .update(record)
          .eq(idColumn, id)
          .eq('user_id', userId)
          .select(idColumn);
      if (updated.isEmpty) {
        throw StateError(
          'This profile entry is unavailable. Refresh and retry.',
        );
      }
    } else {
      await client.from(table).insert(record);
    }
    _checkOwner(userId);
  }

  @override
  Future<void> deleteRecord(String userId, String section, String id) async {
    _checkOwner(userId);
    if (section == 'certifications') {
      await client.rpc(
        'delete_my_job_seeker_certification',
        params: {'p_certification_id': id},
      );
      _checkOwner(userId);
      return;
    }
    final deleted = await client
        .from(_table(section))
        .delete()
        .eq(_sections[section]!, id)
        .eq('user_id', userId)
        .select(_sections[section]!);
    if (deleted.isEmpty) {
      throw StateError('This profile entry is unavailable. Refresh and retry.');
    }
    _checkOwner(userId);
  }

  String _table(String section) => switch (section) {
    'skills' => 'job_seeker_skills',
    'education' => 'job_seeker_education',
    'experience' => 'job_seeker_work_experiences',
    'languages' => 'job_seeker_languages',
    'availability' => 'job_seeker_availability',
    _ => throw ArgumentError.value(section, 'section'),
  };

  @override
  Future<String> uploadCertificate(
    String userId,
    String recordId,
    XFile file,
  ) async {
    _checkOwner(userId);
    if (await file.length() > 5 * 1024 * 1024) {
      throw StateError('Choose a certificate document no larger than 5 MiB.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw StateError('Choose a certificate document no larger than 5 MiB.');
    }
    final mime = lookupMimeType(file.name, headerBytes: bytes);
    const extensions = {
      'application/pdf': 'pdf',
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
    };
    final extension = extensions[mime];
    if (extension == null) {
      throw StateError('Choose a PDF, JPG, PNG or WebP document.');
    }
    final path = '$userId/$recordId/document.$extension';
    await client.storage
        .from('jobmate-profile-certificates')
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
    _checkOwner(userId);
    return path;
  }

  @override
  Future<void> saveCertificate(
    String userId,
    Map<String, dynamic> values,
  ) async {
    _checkOwner(userId);
    await client.rpc(
      'save_job_seeker_certification',
      params: {
        'p_certification_id': values['certification_id'],
        'p_name': values['certification_name'],
        'p_issuer': values['issuer'],
        'p_issued_on': values['issued_on'],
        'p_expires_on': values['expires_on'],
        'p_storage_path': values['document_storage_path'],
      },
    );
    _checkOwner(userId);
  }

  @override
  Future<String> certificateUrl(String userId, String path) async {
    _checkOwner(userId);
    final url = await client.storage
        .from('jobmate-profile-certificates')
        .createSignedUrl(path, 60);
    _checkOwner(userId);
    return url;
  }
}

class _JobSeekerProfileSectionsState extends State<JobSeekerProfileSections> {
  late final JobSeekerProfileRepository _repository;
  JobSeekerProfileData _data = {};
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  int _loadGeneration = 0;

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _skillLevels = [
    'beginner',
    'intermediate',
    'advanced',
    'expert',
  ];
  static const _languageLevels = [
    'beginner',
    'intermediate',
    'advanced',
    'fluent',
    'native',
  ];

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        SupabaseJobSeekerProfileRepository(Supabase.instance.client);
    _load();
  }

  @override
  void didUpdateWidget(covariant JobSeekerProfileSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _data = {};
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final ownerId = widget.userId;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = await _repository.load(ownerId);
      if (!mounted ||
          generation != _loadGeneration ||
          widget.userId != ownerId) {
        return;
      }
      setState(() => _data = data);
    } catch (error) {
      if (!mounted ||
          generation != _loadGeneration ||
          widget.userId != ownerId) {
        return;
      }
      setState(() {
        _loadError = _extensionUnavailable(error)
            ? 'Job Seeker Profile editing is not available in this Supabase environment yet.'
            : 'Unable to load the extended profile. Please retry.';
      });
    } finally {
      if (mounted &&
          generation == _loadGeneration &&
          widget.userId == ownerId) {
        setState(() => _loading = false);
      }
    }
  }

  bool _extensionUnavailable(Object error) {
    if (error is! PostgrestException) return false;
    return const {
      '42P01',
      '42703',
      '42883',
      'PGRST202',
      'PGRST204',
    }.contains(error.code);
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<bool> _perform(
    Future<void> Function() action, {
    required String expectedUserId,
  }) async {
    if (widget.userId != expectedUserId) {
      _message('Your account changed. Reopen your profile before editing.');
      return false;
    }
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      await action();
      if (!mounted || widget.userId != expectedUserId) {
        _message('Your account changed. Reopen your profile before editing.');
        return false;
      }
      try {
        final refreshed = await _repository.load(expectedUserId);
        if (mounted && widget.userId == expectedUserId) {
          setState(() {
            _data = refreshed;
            _loadError = null;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => _loadError = 'Your changes were saved, but the profile could not refresh. Retry to reload.',
          );
        }
      }
      return true;
    } catch (error) {
      _message(_friendlyError(error));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendlyError(Object error) {
    if (error is PostgrestException) {
      final msg = error.message;
      if (msg.contains('duplicate key') || msg.contains('already exists')) {
        return 'That entry already exists. Check the name and try again.';
      }
      if (msg.contains('overlap') || msg.contains('exclusion')) {
        return 'This availability slot overlaps another slot on the same day.';
      }
      return msg;
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  List<Map<String, dynamic>> _rows(String section) => _data[section] ?? [];

  Future<void> _editAbout() async {
    final ownerId = widget.userId;
    final aboutRows = _rows('about');
    final row = aboutRows.isEmpty ? <String, dynamic>{} : aboutRows.first;
    final headline = TextEditingController(
      text: row['headline'] as String? ?? '',
    );
    final bio = TextEditingController(text: row['bio'] as String? ?? '');
    final result = await _showEditor(
      title: 'About me',
      controllers: [headline, bio],
      fields: [
        _textField(headline, 'Headline', max: 160),
        _textField(bio, 'Bio', max: 4000, lines: 5),
      ],
      save: () => _perform(
        () => _repository.saveAbout(ownerId, headline.text, bio.text),
        expectedUserId: ownerId,
      ),
    );
    if (result == true) _message('About me saved.');
  }

  Future<void> _editRecord(String section, [Map<String, dynamic>? row]) async {
    switch (section) {
      case 'skills':
        await _editSkill(row);
        return;
      case 'certifications':
        await _editCertification(row);
        return;
      case 'education':
        await _editEducation(row);
        return;
      case 'experience':
        await _editExperience(row);
        return;
      case 'languages':
        await _editLanguage(row);
        return;
      case 'availability':
        await _editAvailability(row);
        return;
    }
  }

  Future<void> _editSkill(Map<String, dynamic>? row) async {
    final ownerId = widget.userId;
    final name = TextEditingController(
      text: row?['skill_name'] as String? ?? '',
    );
    String? level = row?['proficiency'] as String?;
    final result = await _showEditor(
      title: row == null ? 'Add skill' : 'Edit skill',
      controllers: [name],
      fields: [
        _textField(name, 'Skill name', max: 100),
        DropdownButtonFormField<String?>(
          initialValue: level,
          decoration: const InputDecoration(labelText: 'Proficiency'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Not specified')),
            ..._skillLevels.map(
              (v) => DropdownMenuItem(value: v, child: Text(_title(v))),
            ),
          ],
          onChanged: (v) => level = v,
        ),
      ],
      save: () async {
        if (name.text.trim().isEmpty || name.text.trim().length > 100) {
          _message('Enter a skill name up to 100 characters.');
          return false;
        }
        return _perform(
          () => _repository.saveRecord(ownerId, 'skills', {
            if (row != null) 'skill_id': row['skill_id'],
            'skill_name': name.text.trim(),
            'proficiency': level,
          }),
          expectedUserId: ownerId,
        );
      },
    );
    if (result == true) _message('Skill saved.');
  }

  Future<void> _editLanguage(Map<String, dynamic>? row) async {
    final ownerId = widget.userId;
    final name = TextEditingController(
      text: row?['language_name'] as String? ?? '',
    );
    String level = row?['proficiency'] as String? ?? 'intermediate';
    final result = await _showEditor(
      title: row == null ? 'Add language' : 'Edit language',
      controllers: [name],
      fields: [
        _textField(name, 'Language', max: 100),
        DropdownButtonFormField<String>(
          initialValue: level,
          decoration: const InputDecoration(labelText: 'Proficiency'),
          items: _languageLevels
              .map((v) => DropdownMenuItem(value: v, child: Text(_title(v))))
              .toList(),
          onChanged: (v) {
            if (v != null) level = v;
          },
        ),
      ],
      save: () async {
        if (name.text.trim().isEmpty || name.text.trim().length > 100) {
          _message('Enter a language name up to 100 characters.');
          return false;
        }
        return _perform(
          () => _repository.saveRecord(ownerId, 'languages', {
            if (row != null) 'language_id': row['language_id'],
            'language_name': name.text.trim(),
            'proficiency': level,
          }),
          expectedUserId: ownerId,
        );
      },
    );
    if (result == true) _message('Language saved.');
  }

  Future<void> _editEducation(Map<String, dynamic>? row) async {
    final ownerId = widget.userId;
    final institution = TextEditingController(
      text: row?['institution'] as String? ?? '',
    );
    final qualification = TextEditingController(
      text: row?['qualification'] as String? ?? '',
    );
    final field = TextEditingController(
      text: row?['field_of_study'] as String? ?? '',
    );
    final description = TextEditingController(
      text: row?['description'] as String? ?? '',
    );
    DateTime? started = _date(row?['started_on']);
    DateTime? completed = _date(row?['completed_on']);
    bool studying = row?['is_current'] as bool? ?? false;
    final result = await _showEditor(
      title: row == null ? 'Add education' : 'Edit education',
      controllers: [institution, qualification, field, description],
      fields: [
        _textField(institution, 'Institution', max: 200),
        _textField(qualification, 'Qualification', max: 160),
        _textField(field, 'Field of study', max: 160),
        _dateButton('Start date', started, (v) => started = v),
        _currentDateControl(
          label: 'Currently studying',
          current: studying,
          onChanged: (v) {
            studying = v;
            if (v) completed = null;
          },
          endLabel: 'End date',
          endDate: completed,
          onEndDateChanged: (v) => completed = v,
        ),
        _textField(description, 'Description', max: 2000, lines: 3),
      ],
      save: () async {
        if (institution.text.trim().isEmpty) {
          _message('Institution is required.');
          return false;
        }
        if (!studying &&
            started != null &&
            completed != null &&
            completed!.isBefore(started!)) {
          _message('End date cannot be earlier than start date.');
          return false;
        }
        return _perform(
          () => _repository.saveRecord(ownerId, 'education', {
            if (row != null) 'education_id': row['education_id'],
            'institution': institution.text.trim(),
            'qualification': _nullable(qualification.text),
            'field_of_study': _nullable(field.text),
            'started_on': _dateString(started),
            'completed_on': studying ? null : _dateString(completed),
            'is_current': studying,
            'description': _nullable(description.text),
          }),
          expectedUserId: ownerId,
        );
      },
    );
    if (result == true) _message('Education saved.');
  }

  Future<void> _editExperience(Map<String, dynamic>? row) async {
    final ownerId = widget.userId;
    final company = TextEditingController(
      text: row?['employer_name'] as String? ?? '',
    );
    final title = TextEditingController(
      text: row?['job_title'] as String? ?? '',
    );
    final location = TextEditingController(
      text: row?['location'] as String? ?? '',
    );
    final description = TextEditingController(
      text: row?['description'] as String? ?? '',
    );
    DateTime? started = _date(row?['started_on']);
    DateTime? ended = _date(row?['ended_on']);
    bool current = row?['is_current'] as bool? ?? false;
    final result = await _showEditor(
      title: row == null ? 'Add work experience' : 'Edit work experience',
      controllers: [company, title, location, description],
      fields: [
        _textField(company, 'Company', max: 200),
        _textField(title, 'Job title', max: 160),
        _textField(location, 'Location', max: 255),
        _dateButton('Start date', started, (v) => started = v),
        _currentDateControl(
          label: 'Currently working here',
          current: current,
          onChanged: (v) {
            current = v;
            if (v) ended = null;
          },
          endLabel: 'End date',
          endDate: ended,
          onEndDateChanged: (v) => ended = v,
        ),
        _textField(description, 'Description', max: 4000, lines: 4),
      ],
      save: () async {
        if (company.text.trim().isEmpty || title.text.trim().isEmpty) {
          _message('Company and job title are required.');
          return false;
        }
        if (!current &&
            started != null &&
            ended != null &&
            ended!.isBefore(started!)) {
          _message('End date cannot be earlier than start date.');
          return false;
        }
        return _perform(
          () => _repository.saveRecord(ownerId, 'experience', {
            if (row != null) 'experience_id': row['experience_id'],
            'employer_name': company.text.trim(),
            'job_title': title.text.trim(),
            'location': _nullable(location.text),
            'started_on': _dateString(started),
            'ended_on': current ? null : _dateString(ended),
            'is_current': current,
            'description': _nullable(description.text),
          }),
          expectedUserId: ownerId,
        );
      },
    );
    if (result == true) _message('Work experience saved.');
  }

  Future<void> _editCertification(Map<String, dynamic>? row) async {
    final ownerId = widget.userId;
    final id = row?['certification_id'] as String? ?? const Uuid().v4();
    final name = TextEditingController(
      text: row?['certification_name'] as String? ?? '',
    );
    final issuer = TextEditingController(text: row?['issuer'] as String? ?? '');
    DateTime? issued = _date(row?['issued_on']);
    DateTime? expires = _date(row?['expires_on']);
    String? path = row?['document_storage_path'] as String?;
    XFile? stagedFile;
    String? stagedPath;
    final result = await _showEditor(
      title: row == null ? 'Add certificate' : 'Edit certificate',
      controllers: [name, issuer],
      fields: [
        _textField(name, 'Certificate name', max: 200),
        _textField(issuer, 'Issuing organization', max: 200),
        _dateButton('Issue date', issued, (v) => issued = v),
        _dateButton('Expiry date', expires, (v) => expires = v),
        StatefulBuilder(
          builder: (context, setDialogState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                path == null
                    ? 'No document attached'
                    : 'Private document attached',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving || (path != null && stagedFile == null)
                        ? null
                        : () async {
                            final file = await openFile(
                              acceptedTypeGroups: [
                                XTypeGroup(
                                  label: 'Certificate documents',
                                  extensions: [
                                    'pdf',
                                    'jpg',
                                    'jpeg',
                                    'png',
                                    'webp',
                                  ],
                                ),
                              ],
                            );
                            if (file == null) return;
                            setDialogState(() {
                              stagedFile = file;
                            });
                          },
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      stagedFile?.name ??
                          (path == null
                              ? 'Choose document'
                              : 'Document is immutable'),
                    ),
                  ),
                  if (path != null)
                    TextButton(
                      onPressed: () => setDialogState(() {
                        path = null;
                        stagedFile = null;
                        stagedPath = null;
                      }),
                      child: const Text('Remove attachment'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Self-declared • not independently verified. To replace an attached file, remove this record and add it again.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ],
      save: () async {
        if (name.text.trim().isEmpty) {
          _message('Certificate name is required.');
          return false;
        }
        if (issued != null && expires != null && expires!.isBefore(issued!)) {
          _message('Expiry date cannot be earlier than issue date.');
          return false;
        }
        if (stagedFile != null && stagedPath == null) {
          try {
            if (widget.userId != ownerId) {
              _message(
                'Your account changed. Reopen your profile before editing.',
              );
              return false;
            }
            stagedPath = await _repository.uploadCertificate(
              ownerId,
              id,
              stagedFile!,
            );
            path = stagedPath;
          } catch (error) {
            _message(_friendlyError(error));
            return false;
          }
        }
        return _perform(
          () => _repository.saveCertificate(ownerId, {
            'certification_id': id,
            'certification_name': name.text.trim(),
            'issuer': _nullable(issuer.text),
            'issued_on': _dateString(issued),
            'expires_on': _dateString(expires),
            'document_storage_path': path,
          }),
          expectedUserId: ownerId,
        );
      },
    );
    if (result == true) _message('Certificate saved.');
  }

  Future<void> _editAvailability(Map<String, dynamic>? row) async {
    final ownerId = widget.userId;
    int day = row?['iso_weekday'] as int? ?? 1;
    TimeOfDay start =
        _time(row?['start_time']) ?? const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay end =
        _time(row?['end_time']) ?? const TimeOfDay(hour: 17, minute: 0);
    final result = await _showEditor(
      title: row == null ? 'Add availability' : 'Edit availability',
      fields: [
        DropdownButtonFormField<int>(
          initialValue: day,
          decoration: const InputDecoration(labelText: 'Day'),
          items: List.generate(
            7,
            (i) => DropdownMenuItem(value: i + 1, child: Text(_days[i])),
          ),
          onChanged: (v) {
            if (v != null) day = v;
          },
        ),
        StatefulBuilder(
          builder: (context, setDialogState) => Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final v = await showTimePicker(
                      context: context,
                      initialTime: start,
                    );
                    if (v != null) setDialogState(() => start = v);
                  },
                  icon: const Icon(Icons.schedule),
                  label: Text('From ${start.format(context)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final v = await showTimePicker(
                      context: context,
                      initialTime: end,
                    );
                    if (v != null) setDialogState(() => end = v);
                  },
                  icon: const Icon(Icons.schedule),
                  label: Text('To ${end.format(context)}'),
                ),
              ),
            ],
          ),
        ),
        const Text(
          'Times use Asia/Kuala_Lumpur. Overnight slots are not supported.',
        ),
      ],
      save: () async {
        final validation = validateWeeklyAvailabilitySlot(
          weekday: day,
          start: start,
          end: end,
          existing: _rows('availability'),
          excludedSlotId: row?['slot_id'] as String?,
        );
        if (validation != null) {
          _message(validation);
          return false;
        }
        return _perform(
          () => _repository.saveRecord(ownerId, 'availability', {
            if (row != null) 'slot_id': row['slot_id'],
            'iso_weekday': day,
            'start_time': _timeString(start),
            'end_time': _timeString(end),
            'timezone_name': 'Asia/Kuala_Lumpur',
          }),
          expectedUserId: ownerId,
        );
      },
    );
    if (result == true) _message('Availability saved.');
  }

  Future<bool?> _showEditor({
    required String title,
    required List<Widget> fields,
    required Future<bool> Function() save,
    List<TextEditingController> controllers = const [],
  }) => showDialog<bool>(
    context: context,
    builder: (_) => _ProfileEditorDialog(
      title: title,
      fields: fields,
      save: save,
      controllers: controllers,
    ),
  );

  Widget _textField(
    TextEditingController controller,
    String label, {
    int max = 255,
    int lines = 1,
  }) => TextField(
    controller: controller,
    maxLength: max,
    maxLines: lines,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );

  Widget _currentDateControl({
    required String label,
    required bool current,
    required ValueChanged<bool> onChanged,
    required String endLabel,
    required DateTime? endDate,
    required ValueChanged<DateTime?> onEndDateChanged,
  }) {
    var selectedCurrent = current;
    var selectedEndDate = endDate;
    return StatefulBuilder(
      builder: (context, setDialogState) => Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            value: selectedCurrent,
            onChanged: (value) {
              setDialogState(() {
                selectedCurrent = value;
                if (value) selectedEndDate = null;
              });
              onChanged(value);
            },
          ),
          if (!selectedCurrent)
            _dateButton(endLabel, selectedEndDate, (value) {
              selectedEndDate = value;
              onEndDateChanged(value);
            }),
        ],
      ),
    );
  }

  Widget _dateButton(
    String label,
    DateTime? date,
    ValueChanged<DateTime?> changed,
  ) {
    var selectedDate = date;
    return StatefulBuilder(
      builder: (context, setDialogState) => OutlinedButton.icon(
        onPressed: () async {
          final now = DateTime.now();
          final selected = await showDatePicker(
            context: context,
            initialDate: selectedDate ?? now,
            firstDate: DateTime(1950),
            lastDate: DateTime(now.year + 30),
          );
          if (selected != null) {
            setDialogState(() => selectedDate = selected);
            changed(selected);
          }
        },
        icon: const Icon(Icons.calendar_today_outlined),
        label: Text(
          '$label: ${selectedDate == null ? 'Not set' : _dateString(selectedDate)}',
        ),
      ),
    );
  }

  Future<void> _delete(String section, Map<String, dynamic> row) async {
    final ownerId = widget.userId;
    final idColumn = switch (section) {
      'skills' => 'skill_id',
      'certifications' => 'certification_id',
      'education' => 'education_id',
      'experience' => 'experience_id',
      'languages' => 'language_id',
      _ => 'slot_id',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this entry?'),
        content: Text(
          section == 'certifications'
              ? 'Certificate details will be removed. Its private Storage object is retained and is no longer accessible through this profile.'
              : 'This profile entry will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final removed = await _perform(
      () => _repository.deleteRecord(ownerId, section, row[idColumn] as String),
      expectedUserId: ownerId,
    );
    if (removed) _message('Entry removed.');
  }

  Future<void> _viewCertificate(String? path) async {
    if (path == null) return;
    try {
      final ownerId = widget.userId;
      final url = await _repository.certificateUrl(ownerId, path);
      if (!mounted || widget.userId != ownerId) {
        throw StateError('Your account changed. Reopen your profile.');
      }
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.platformDefault,
      );
      if (!opened) _message('Unable to open the private certificate document.');
    } catch (error) {
      _message(
        'Unable to access this private document: ${_friendlyError(error)}',
      );
    }
  }

  Widget _section(String key, String title, String subtitle) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (key != 'about')
                IconButton(
                  tooltip: 'Add $title',
                  onPressed: _saving || !widget.canEdit
                      ? null
                      : () => _editRecord(key),
                  icon: const Icon(Icons.add_circle_outline),
                ),
            ],
          ),
          const Divider(height: 24),
          if (key == 'about')
            _aboutContent()
          else if (_rows(key).isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('No entries yet. Use + to add one.'),
            )
          else
            ..._rows(key).map((row) => _recordTile(key, row)),
        ],
      ),
    ),
  );

  Widget _aboutContent() {
    final aboutRows = _rows('about');
    final row = aboutRows.isEmpty ? <String, dynamic>{} : aboutRows.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (row['headline'] as String?)?.isNotEmpty == true
              ? row['headline'] as String
              : 'Add a professional headline',
        ),
        const SizedBox(height: 8),
        Text(
          (row['bio'] as String?)?.isNotEmpty == true
              ? row['bio'] as String
              : 'Tell employers about your background and goals.',
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _saving || !widget.canEdit ? null : _editAbout,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
          ),
        ),
      ],
    );
  }

  Widget _recordTile(String section, Map<String, dynamic> row) {
    final (title, subtitle) = switch (section) {
      'skills' => (
        row['skill_name'] as String? ?? '',
        _title(row['proficiency'] as String? ?? 'Not specified'),
      ),
      'certifications' => (
        row['certification_name'] as String? ?? '',
        '${row['issuer'] ?? 'Issuer not provided'} • Self-declared, not verified',
      ),
      'education' => (
        row['institution'] as String? ?? '',
        [
          row['qualification'],
          row['field_of_study'],
          row['is_current'] == true
              ? 'Currently studying'
              : row['completed_on'],
        ].where((v) => v != null && v.toString().isNotEmpty).join(' • '),
      ),
      'experience' => (
        row['job_title'] as String? ?? '',
        '${row['employer_name'] ?? ''}${row['is_current'] == true ? ' • Currently working' : ''}',
      ),
      'languages' => (
        row['language_name'] as String? ?? '',
        _title(row['proficiency'] as String? ?? ''),
      ),
      _ => (
        '${_days[(row['iso_weekday'] as int? ?? 1) - 1]} • ${row['start_time']}–${row['end_time']}',
        'Asia/Kuala_Lumpur',
      ),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      leading: section == 'certifications'
          ? IconButton(
              tooltip: 'View private document',
              onPressed: !widget.canEdit || row['document_storage_path'] == null
                  ? null
                  : () => _viewCertificate(
                      row['document_storage_path'] as String?,
                    ),
              icon: const Icon(Icons.description_outlined),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Edit',
            onPressed: _saving || !widget.canEdit
                ? null
                : () => _editRecord(section, row),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: _saving || !widget.canEdit
                ? null
                : () => _delete(section, row),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_loadError != null && _data.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Extended profile unavailable'),
              const SizedBox(height: 8),
              Text(_loadError!),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loadError != null)
              MaterialBanner(
                content: Text(_loadError!),
                actions: [
                  TextButton(
                    onPressed: _loading ? null : _load,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            _section(
              'about',
              'About me',
              'A short introduction for employers.',
            ),
            const SizedBox(height: 14),
            _section(
              'skills',
              'Skills',
              'Your self-declared skills and proficiency.',
            ),
            const SizedBox(height: 14),
            _section(
              'certifications',
              'Certificates',
              'Documents stay private; self-declared records are not verified.',
            ),
            const SizedBox(height: 14),
            _section(
              'education',
              'Education',
              'Add multiple education records.',
            ),
            const SizedBox(height: 14),
            _section(
              'experience',
              'Work experience',
              'Add multiple work experience records.',
            ),
            const SizedBox(height: 14),
            _section(
              'languages',
              'Languages',
              'Languages and self-reported proficiency.',
            ),
            const SizedBox(height: 14),
            _section(
              'availability',
              'Weekly availability',
              'ISO weekdays and local Asia/Kuala_Lumpur time.',
            ),
          ],
        ),
        if (_saving)
          const Positioned(
            right: 12,
            top: 12,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  String _title(String value) => value.isEmpty
      ? value
      : '${value[0].toUpperCase()}${value.substring(1).replaceAll('_', ' ')}';
  String? _nullable(String value) => value.trim().isEmpty ? null : value.trim();
  DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());
  String? _dateString(DateTime? value) => value == null
      ? null
      : '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  TimeOfDay? _time(Object? value) {
    if (value == null) return null;
    final parts = value.toString().split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  String _timeString(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:00';
}

class _ProfileEditorDialog extends StatefulWidget {
  const _ProfileEditorDialog({
    required this.title,
    required this.fields,
    required this.save,
    required this.controllers,
  });

  final String title;
  final List<Widget> fields;
  final Future<bool> Function() save;
  final List<TextEditingController> controllers;

  @override
  State<_ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<_ProfileEditorDialog> {
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final field in widget.fields)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: field),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving
            ? null
            : () async {
                final dialogNavigator = Navigator.of(context);
                setState(() => _saving = true);
                final saved = await widget.save();
                if (saved && mounted) dialogNavigator.pop(true);
                if (!saved && mounted) setState(() => _saving = false);
              },
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
      ),
    ],
  );
}
