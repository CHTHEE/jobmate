import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../shared/widgets/app_workspace.dart';

typedef CompanyProfileData = Map<String, List<Map<String, dynamic>>>;

abstract interface class CompanyProfileRepository {
  Future<CompanyProfileData> load(String companyId);
  Future<void> saveSpecialty(
    String companyId,
    String? specialtyId,
    String name,
  );
  Future<void> deleteSpecialty(String companyId, String specialtyId);
  Future<void> saveCertification(String companyId, Map<String, dynamic> values);
  Future<void> deleteCertification(String companyId, String certificationId);
  Future<String> uploadCertificate(
    String companyId,
    String certificationId,
    XFile file,
  );
  Future<String> certificateUrl(String path);
}

class SupabaseCompanyProfileRepository implements CompanyProfileRepository {
  SupabaseCompanyProfileRepository(this.client);
  final SupabaseClient client;

  String _requireMember(String companyId) {
    final userId = client.auth.currentUser?.id;
    if (userId == null || companyId.isEmpty) {
      throw StateError('Sign in again and select a Company.');
    }
    return userId;
  }

  @override
  Future<CompanyProfileData> load(String companyId) async {
    _requireMember(companyId);
    final specialtyRows = await client
        .from('company_specialties')
        .select('specialty_id,specialty')
        .eq('company_id', companyId)
        .order('specialty');
    final certificationRows = await client
        .from('company_certifications')
        .select(
          'certification_id,certification_name,issuer,issued_on,expires_on,document_storage_path,document_mime_type,document_size_bytes',
        )
        .eq('company_id', companyId)
        .order('created_at', ascending: false);
    return {
      'specialties': List<Map<String, dynamic>>.from(specialtyRows),
      'certifications': List<Map<String, dynamic>>.from(certificationRows),
    };
  }

  @override
  Future<void> saveSpecialty(
    String companyId,
    String? specialtyId,
    String name,
  ) async {
    _requireMember(companyId);
    final normalized = name.trim();
    if (normalized.isEmpty || normalized.length > 150) {
      throw const FormatException(
        'Enter a specialty between 1 and 150 characters.',
      );
    }
    if (specialtyId == null) {
      await client.from('company_specialties').insert({
        'company_id': companyId,
        'specialty': normalized,
      });
    } else {
      await client
          .from('company_specialties')
          .update({'specialty': normalized})
          .eq('company_id', companyId)
          .eq('specialty_id', specialtyId);
    }
  }

  @override
  Future<void> deleteSpecialty(String companyId, String specialtyId) async {
    _requireMember(companyId);
    await client
        .from('company_specialties')
        .delete()
        .eq('company_id', companyId)
        .eq('specialty_id', specialtyId);
  }

  @override
  Future<void> saveCertification(
    String companyId,
    Map<String, dynamic> values,
  ) async {
    _requireMember(companyId);
    await client.rpc(
      'save_company_certification',
      params: {
        'p_company_id': companyId,
        'p_certification_id': values['certification_id'],
        'p_name': values['certification_name'],
        'p_issuer': values['issuer'],
        'p_issued_on': values['issued_on'],
        'p_expires_on': values['expires_on'],
        'p_storage_path': values['document_storage_path'],
      },
    );
  }

  @override
  Future<void> deleteCertification(
    String companyId,
    String certificationId,
  ) async {
    _requireMember(companyId);
    await client.rpc(
      'delete_company_certification_v1',
      params: {
        'p_company_id': companyId,
        'p_certification_id': certificationId,
      },
    );
  }

  @override
  Future<String> uploadCertificate(
    String companyId,
    String certificationId,
    XFile file,
  ) async {
    _requireMember(companyId);
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Choose a non-empty document up to 5 MiB.');
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
      throw const FormatException('Choose a PDF, JPG, PNG or WebP document.');
    }
    final path = '$companyId/$certificationId/document.$extension';
    await client.storage
        .from('jobmate-profile-certificates')
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
    return path;
  }

  @override
  Future<String> certificateUrl(String path) => client.storage
      .from('jobmate-profile-certificates')
      .createSignedUrl(path, 60);
}

class CompanyProfileSections extends StatefulWidget {
  const CompanyProfileSections({
    required this.companyId,
    required this.canEdit,
    this.repository,
    super.key,
  });
  final String companyId;
  final bool canEdit;
  final CompanyProfileRepository? repository;

  @override
  State<CompanyProfileSections> createState() => _CompanyProfileSectionsState();
}

class _CompanyProfileSectionsState extends State<CompanyProfileSections> {
  late CompanyProfileRepository _repo;
  CompanyProfileData _data = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final TextEditingController _specialtyController = TextEditingController();
  final TextEditingController _certificationNameController =
      TextEditingController();
  final TextEditingController _certificationIssuerController =
      TextEditingController();
  final TextEditingController _certificationIssuedController =
      TextEditingController();
  final TextEditingController _certificationExpiresController =
      TextEditingController();

  @override
  void dispose() {
    _specialtyController.dispose();
    _certificationNameController.dispose();
    _certificationIssuerController.dispose();
    _certificationIssuedController.dispose();
    _certificationExpiresController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _repo =
        widget.repository ??
        SupabaseCompanyProfileRepository(Supabase.instance.client);
    _load();
  }

  @override
  void didUpdateWidget(covariant CompanyProfileSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId ||
        oldWidget.repository != widget.repository) {
      _repo =
          widget.repository ??
          SupabaseCompanyProfileRepository(Supabase.instance.client);
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await _repo.load(widget.companyId);
      if (mounted) {
        setState(() {
          _data = next;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              e is PostgrestException &&
                  const [
                    '42P01',
                    '42703',
                    '42883',
                    'PGRST202',
                    'PGRST205',
                  ].contains(e.code)
              ? 'Company profile extensions are not available on this database yet.'
              : 'Unable to load Company profile details.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException
                  ? e.message
                  : 'Unable to save this Company profile change. Please retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSpecialty([Map<String, dynamic>? item]) async {
    _specialtyController.text = item?['specialty'] as String? ?? '';
    final formKey = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var saving = false;
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(item == null ? 'Add specialty' : 'Edit specialty'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _specialtyController,
                    autofocus: true,
                    maxLength: 150,
                    decoration: const InputDecoration(labelText: 'Specialty'),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Enter a specialty.' : null,
                  ),
                  if (error != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final value = _specialtyController.text
                            .trim()
                            .toLowerCase();
                        if ((_data['specialties'] ?? []).any(
                          (row) =>
                              row['specialty_id'] != item?['specialty_id'] &&
                              (row['specialty'] as String)
                                      .trim()
                                      .toLowerCase() ==
                                  value,
                        )) {
                          setDialogState(
                            () => error = 'This specialty already exists.',
                          );
                          return;
                        }
                        setDialogState(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await _repo.saveSpecialty(
                            widget.companyId,
                            item?['specialty_id'] as String?,
                            _specialtyController.text,
                          );
                          await _load();
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        } catch (_) {
                          setDialogState(() {
                            saving = false;
                            error = 'Unable to save specialty. Your text is still here; retry or edit it.';
                          });
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _editCertification([Map<String, dynamic>? item]) async {
    final id = item?['certification_id'] as String? ?? const Uuid().v4();
    _certificationNameController.text =
        item?['certification_name'] as String? ?? '';
    _certificationIssuerController.text = item?['issuer'] as String? ?? '';
    _certificationIssuedController.text = item?['issued_on']?.toString() ?? '';
    _certificationExpiresController.text =
        item?['expires_on']?.toString() ?? '';
    XFile? attachment;
    String? validation(String value) =>
        value.isEmpty || DateTime.tryParse(value) != null
        ? null
        : 'Use YYYY-MM-DD.';
    final form = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var saving = false;
        String? saveError;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              item == null ? 'Add certification' : 'Edit certification',
            ),
            content: SizedBox(
              width: 420,
              child: Form(
                key: form,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _certificationNameController,
                        maxLength: 200,
                        decoration: const InputDecoration(
                          labelText: 'Certificate name',
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Enter a certificate name.'
                            : null,
                      ),
                      TextFormField(
                        controller: _certificationIssuerController,
                        maxLength: 200,
                        decoration: const InputDecoration(
                          labelText: 'Issuing organization',
                        ),
                      ),
                      TextFormField(
                        controller: _certificationIssuedController,
                        decoration: const InputDecoration(
                          labelText: 'Issue date (YYYY-MM-DD)',
                        ),
                        validator: (v) => validation((v ?? '').trim()),
                      ),
                      TextFormField(
                        controller: _certificationExpiresController,
                        decoration: const InputDecoration(
                          labelText: 'Expiry date (YYYY-MM-DD)',
                        ),
                        validator: (v) => validation((v ?? '').trim()),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            const type = XTypeGroup(
                              label: 'Certificate documents',
                              extensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
                            );
                            final chosen = await openFile(
                              acceptedTypeGroups: [type],
                            );
                            if (chosen != null) {
                              setDialogState(() => attachment = chosen);
                            }
                          },
                          icon: const Icon(Icons.attach_file),
                          label: Text(
                            attachment?.name ??
                                (item?['document_storage_path'] == null
                                    ? 'Attach document (optional)'
                                    : 'Replace private document'),
                          ),
                        ),
                      ),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Self-submitted · Unverified'),
                      ),
                      if (saveError != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            saveError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        final start = DateTime.tryParse(
                          _certificationIssuedController.text.trim(),
                        );
                        final end = DateTime.tryParse(
                          _certificationExpiresController.text.trim(),
                        );
                        if (start != null &&
                            end != null &&
                            end.isBefore(start)) {
                          setDialogState(
                            () => saveError =
                                'Expiry date must be on or after issue date.',
                          );
                          return;
                        }
                        setDialogState(() {
                          saving = true;
                          saveError = null;
                        });
                        try {
                          var path = item?['document_storage_path'] as String?;
                          if (attachment != null) {
                            path = await _repo.uploadCertificate(
                              widget.companyId,
                              id,
                              attachment!,
                            );
                          }
                          await _repo.saveCertification(widget.companyId, {
                            'certification_id': id,
                            'certification_name': _certificationNameController
                                .text
                                .trim(),
                            'issuer':
                                _certificationIssuerController.text
                                    .trim()
                                    .isEmpty
                                ? null
                                : _certificationIssuerController.text.trim(),
                            'issued_on':
                                _certificationIssuedController.text
                                    .trim()
                                    .isEmpty
                                ? null
                                : _certificationIssuedController.text.trim(),
                            'expires_on':
                                _certificationExpiresController.text
                                    .trim()
                                    .isEmpty
                                ? null
                                : _certificationExpiresController.text.trim(),
                            'document_storage_path': path,
                          });
                          await _load();
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        } catch (e) {
                          setDialogState(() {
                            saving = false;
                            saveError = e is FormatException ? e.message : 'Unable to save certification. Your entries are preserved; retry when ready.';
                          });
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final specialties = _data['specialties'] ?? [];
    final certifications = _data['certifications'] ?? [];
    if (_loading) {
      return const WorkspaceCard(
        title: 'Company profile details',
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return WorkspaceCard(
        title: 'Company profile details',
        child: Column(
          children: [
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspaceCard(
          title: 'Specialties',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (specialties.isEmpty) const Text('No specialties added.'),
              for (final row in specialties)
                ListTile(
                  key: ValueKey('specialty-${row['specialty_id']}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(row['specialty'] as String),
                  trailing: widget.canEdit
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit ${row['specialty']}',
                              onPressed: _busy
                                  ? null
                                  : () => _editSpecialty(row),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Remove ${row['specialty']}',
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      if (await _confirm('Remove specialty?')) {
                                        await _run(
                                          () => _repo.deleteSpecialty(
                                            widget.companyId,
                                            row['specialty_id'] as String,
                                          ),
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        )
                      : null,
                ),
              if (widget.canEdit)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _editSpecialty(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add specialty'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        WorkspaceCard(
          title: 'Certifications',
          subtitle: 'Company-provided certifications are self-submitted and are not independently verified.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (certifications.isEmpty)
                const Text('No certifications added.'),
              for (final row in certifications) _certificateCard(row),
              if (widget.canEdit)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _editCertification(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add certification'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _certificateCard(Map<String, dynamic> row) {
    final date = [
      row['issued_on'],
      row['expires_on'],
    ].where((v) => v != null).join(' – ');
    return Card(
      key: ValueKey('cert-${row['certification_id']}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              row['certification_name'] as String,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if ((row['issuer'] as String? ?? '').isNotEmpty)
              Text(row['issuer'] as String),
            Text(date.isEmpty ? 'Dates not provided' : date),
            const Text('Self-submitted · Unverified'),
            Wrap(
              children: [
                if (row['document_storage_path'] != null)
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            try {
                              final url = await _repo.certificateUrl(
                                row['document_storage_path'] as String,
                              );
                              await launchUrl(
                                Uri.parse(url),
                                mode: LaunchMode.platformDefault,
                              );
                            } catch (_) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Private document is unavailable.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('View private document'),
                  ),
                if (widget.canEdit) ...[
                  TextButton.icon(
                    onPressed: _busy ? null : () => _editCertification(row),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (await _confirm(
                              'Remove certification metadata?',
                            )) {
                              await _run(
                                () => _repo.deleteCertification(
                                  widget.companyId,
                                  row['certification_id'] as String,
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

abstract interface class PublicCompanyProfileRepository {
  Future<Map<String, dynamic>> load(String companyId);
  Future<String?> logoUrl(String? storagePath);
}

class SupabasePublicCompanyProfileRepository
    implements PublicCompanyProfileRepository {
  SupabasePublicCompanyProfileRepository(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>> load(String companyId) async =>
      Map<String, dynamic>.from(
        await client.rpc(
          'get_public_company_profile_v1',
          params: {'p_company_id': companyId},
        ) as Map,
      );
  @override
  Future<String?> logoUrl(String? storagePath) async => storagePath == null
      ? null
      : client.storage
            .from('jobmate-company-logos')
            .createSignedUrl(storagePath, 300);
}

class PublicCompanyProfileButton extends StatelessWidget {
  const PublicCompanyProfileButton({
    required this.companyId,
    this.repository,
    super.key,
  });
  final String companyId;
  final PublicCompanyProfileRepository? repository;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: const ValueKey('view-public-company-profile'),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) =>
          _PublicCompanyDialog(companyId: companyId, repository: repository),
    ),
    icon: const Icon(Icons.business_outlined),
    label: const Text('View Company profile'),
  );
}

class _PublicCompanyDialog extends StatefulWidget {
  const _PublicCompanyDialog({required this.companyId, this.repository});
  final String companyId;
  final PublicCompanyProfileRepository? repository;
  @override
  State<_PublicCompanyDialog> createState() => _PublicCompanyDialogState();
}

class _PublicCompanyDialogState extends State<_PublicCompanyDialog> {
  late final repo =
      widget.repository ??
      SupabasePublicCompanyProfileRepository(Supabase.instance.client);
  Map<String, dynamic>? profile;
  String? logo;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        profile = null;
        error = null;
      });
    }
    try {
      final value = await repo.load(widget.companyId);
      final signed = await repo.logoUrl(value['logo_storage_path'] as String?);
      if (mounted) {
        setState(() {
          profile = value;
          logo = signed;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Company profile details are unavailable.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(profile?['company_name'] as String? ?? 'Company profile'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              )
            : profile == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (logo != null)
                    Center(
                      child: Image.network(
                        logo!,
                        height: 100,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.business_outlined, size: 64),
                      ),
                    ),
                  Text(
                    profile!['company_description'] as String? ??
                        'Description not provided.',
                  ),
                  if ((profile!['industry'] as String? ?? '').isNotEmpty)
                    Text('Industry: ${profile!['industry']}'),
                  const SizedBox(height: 12),
                  const Text(
                    'Specialties',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final item
                      in (profile!['specialties'] as List? ?? [])
                          .whereType<String>())
                    Text('• $item'),
                  const SizedBox(height: 12),
                  const Text(
                    'Certifications',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final item
                      in (profile!['certifications'] as List? ?? [])
                          .whereType<Map>())
                    Text(
                      '${item['certification_name']}${item['issuer'] == null ? '' : ' · ${item['issuer']}'}${item['independently_verified'] == true ? '' : ' · Self-submitted, unverified'}',
                    ),
                ],
              ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
