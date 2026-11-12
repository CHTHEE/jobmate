import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/app_workspace.dart';

@immutable
class EmployerProfileData {
  const EmployerProfileData({
    this.bio = '',
    this.jobTitle = '',
    this.department = '',
    this.professionalExperience = '',
  });

  final String bio;
  final String jobTitle;
  final String department;
  final String professionalExperience;

  factory EmployerProfileData.fromRow(Map<String, dynamic>? row) {
    if (row == null) return const EmployerProfileData();
    return EmployerProfileData(
      bio: row['bio'] as String? ?? '',
      jobTitle: row['job_title'] as String? ?? '',
      department: row['department'] as String? ?? '',
      professionalExperience: row['professional_experience'] as String? ?? '',
    );
  }

  EmployerProfileData copyWith({
    String? bio,
    String? jobTitle,
    String? department,
    String? professionalExperience,
  }) => EmployerProfileData(
    bio: bio ?? this.bio,
    jobTitle: jobTitle ?? this.jobTitle,
    department: department ?? this.department,
    professionalExperience:
        professionalExperience ?? this.professionalExperience,
  );

  Map<String, Object?> toSaveRpcParameters() => {
    'p_bio': _optional(bio),
    'p_job_title': _optional(jobTitle),
    'p_department': _optional(department),
    'p_professional_experience': _optional(professionalExperience),
  };

  static String? _optional(String value) =>
      value.trim().isEmpty ? null : value.trim();
}

abstract interface class EmployerProfileRepository {
  Future<EmployerProfileData> load(String userId);
  Future<void> save(String userId, EmployerProfileData profile);
}

/// Reads the caller's RLS-protected row and writes only through the
/// server-authorized RPC, which derives the profile owner from auth.uid().
class SupabaseEmployerProfileRepository implements EmployerProfileRepository {
  SupabaseEmployerProfileRepository(this.client);

  final SupabaseClient client;

  void _requireCurrentUser(String userId) {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('Your login changed. Reopen your profile and retry.');
    }
  }

  @override
  Future<EmployerProfileData> load(String userId) async {
    _requireCurrentUser(userId);
    final row = await client
        .from('employer_profiles')
        .select('bio,job_title,department,professional_experience')
        .eq('user_id', userId)
        .maybeSingle();
    return EmployerProfileData.fromRow(row);
  }

  @override
  Future<void> save(String userId, EmployerProfileData profile) async {
    _requireCurrentUser(userId);
    await client.rpc(
      'save_my_employer_profile',
      params: profile.toSaveRpcParameters(),
    );
  }
}

class EmployerProfileSections extends StatefulWidget {
  const EmployerProfileSections({
    required this.userId,
    required this.canEdit,
    this.repository,
    super.key,
  });

  final String userId;
  final bool canEdit;
  final EmployerProfileRepository? repository;

  @override
  State<EmployerProfileSections> createState() =>
      _EmployerProfileSectionsState();
}

class _EmployerProfileSectionsState extends State<EmployerProfileSections> {
  late final EmployerProfileRepository _repository;
  EmployerProfileData _profile = const EmployerProfileData();
  bool _hasLoaded = false;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        SupabaseEmployerProfileRepository(Supabase.instance.client);
    _load();
  }

  bool _isMissingExtension(Object error) =>
      error is PostgrestException &&
      const {
        '42P01',
        '42703',
        '42883',
        'PGRST202',
        'PGRST204',
      }.contains(error.code);

  Future<void> _load() async {
    if (_loading && _hasLoaded) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final result = await _repository.load(widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = result;
        _hasLoaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = _isMissingExtension(error)
            ? 'Employer Profile editing is not available in this Supabase environment yet.'
            : 'Unable to load your professional profile. Please retry.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _save(EmployerProfileData submitted) async {
    if (_saving || !widget.canEdit) return false;
    setState(() => _saving = true);
    try {
      await _repository.save(widget.userId, submitted);
      if (!mounted) return true;
      setState(() {
        _profile = submitted;
        _hasLoaded = true;
        _loadError = null;
      });
      try {
        final refreshed = await _repository.load(widget.userId);
        if (mounted) setState(() => _profile = refreshed);
      } catch (_) {
        if (mounted) {
          setState(
            () => _loadError = 'Your changes were saved, but the profile could not refresh. Retry to reload.',
          );
        }
      }
      if (mounted) _message('Professional profile saved.');
      return true;
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendlyError(Object error) {
    if (error is PostgrestException) {
      if (error.code == '42501') {
        return 'Your active Employer account could not be authorized to save this profile.';
      }
      if (_isMissingExtension(error)) {
        return 'Employer Profile editing is not available in this Supabase environment yet.';
      }
      return error.message;
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _EmployerProfileEditorDialog(initial: _profile, onSave: _save),
    );
  }

  Widget _valueRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 190,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: SelectableText(value.trim().isEmpty ? 'Not provided' : value),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading && !_hasLoaded) {
      return const WorkspaceCard(
        title: 'Professional profile',
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null && !_hasLoaded) {
      return WorkspaceCard(
        title: 'Professional profile',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
      );
    }
    return WorkspaceCard(
      title: 'Professional profile',
      subtitle: 'Personal career details. Company information stays on the Company Profile.',
      child: Column(
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
          _valueRow('Bio', _profile.bio),
          _valueRow('Job title', _profile.jobTitle),
          _valueRow('Department', _profile.department),
          _valueRow('Professional experience', _profile.professionalExperience),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: widget.canEdit && !_saving ? _edit : null,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_outlined),
              label: const Text('Edit profile'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployerProfileEditorDialog extends StatefulWidget {
  const _EmployerProfileEditorDialog({
    required this.initial,
    required this.onSave,
  });

  final EmployerProfileData initial;
  final Future<bool> Function(EmployerProfileData) onSave;

  @override
  State<_EmployerProfileEditorDialog> createState() =>
      _EmployerProfileEditorDialogState();
}

class _EmployerProfileEditorDialogState
    extends State<_EmployerProfileEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _bio;
  late final TextEditingController _title;
  late final TextEditingController _department;
  late final TextEditingController _experience;
  bool _saving = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _bio = TextEditingController(text: widget.initial.bio);
    _title = TextEditingController(text: widget.initial.jobTitle);
    _department = TextEditingController(text: widget.initial.department);
    _experience = TextEditingController(
      text: widget.initial.professionalExperience,
    );
  }

  @override
  void dispose() {
    _bio.dispose();
    _title.dispose();
    _department.dispose();
    _experience.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final saved = await widget.onSave(
      EmployerProfileData(
        bio: _bio.text,
        jobTitle: _title.text,
        department: _department.text,
        professionalExperience: _experience.text,
      ),
    );
    if (!mounted) return;
    if (saved) {
      _popAfterGuard();
    } else {
      setState(() => _saving = false);
    }
  }

  bool get _hasUnsavedChanges =>
      _bio.text != widget.initial.bio ||
      _title.text != widget.initial.jobTitle ||
      _department.text != widget.initial.department ||
      _experience.text != widget.initial.professionalExperience;

  Future<void> _requestClose() async {
    if (_saving) return;
    if (!_hasUnsavedChanges) {
      _popAfterGuard();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard profile changes?'),
        content: const Text(
          'Your unsaved professional profile edits will be lost.',
        ),
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
    if (discard == true && mounted) _popAfterGuard();
  }

  void _popAfterGuard() {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Widget _input(
    TextEditingController controller,
    String label, {
    required int maxLength,
    int maxLines = 1,
  }) => TextFormField(
    controller: controller,
    maxLength: maxLength,
    maxLines: maxLines,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: (value) => (value?.runes.length ?? 0) > maxLength
        ? '$label must be $maxLength characters or fewer.'
        : null,
  );

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_saving) _requestClose();
    },
    child: AlertDialog(
      title: const Text('Edit professional profile'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _input(_bio, 'Bio', maxLength: 4000, maxLines: 5),
                const SizedBox(height: 14),
                _input(_title, 'Job title', maxLength: 120),
                const SizedBox(height: 14),
                _input(_department, 'Department', maxLength: 120),
                const SizedBox(height: 14),
                _input(
                  _experience,
                  'Professional experience',
                  maxLength: 4000,
                  maxLines: 5,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _requestClose,
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ],
    ),
  );
}
