import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class CompanyLogoUpload {
  CompanyLogoUpload({
    required this.id,
    required Uint8List bytes,
    required this.extension,
    required this.mimeType,
    required this.expectedPath,
  }) : bytes = Uint8List.fromList(bytes);
  final String id, extension, mimeType;
  final String? expectedPath;
  final Uint8List bytes;
}

abstract class CompanyLogoGateway {
  void checkSession();
  Future<Map<String, dynamic>?> latestRequest();
  Future<void> upload(CompanyLogoUpload image);
  Future<String> save(CompanyLogoUpload image);
}

class SupabaseCompanyLogoGateway implements CompanyLogoGateway {
  SupabaseCompanyLogoGateway(
    this.client, {
    required this.companyId,
    required this.actorId,
  });
  final SupabaseClient client;
  final String companyId, actorId;
  @override
  void checkSession() {
    if (client.auth.currentUser?.id != actorId) {
      throw StateError('Your account changed. Reopen the Company page.');
    }
  }

  String _path(CompanyLogoUpload image) =>
      '$actorId/profile-${image.id}/logo.${image.extension}';

  Future<void> _checkOwnerAccess() async {
    checkSession();
    final account = await client
        .from('users')
        .select('role, status')
        .eq('user_id', actorId)
        .maybeSingle();
    checkSession();
    if (account?['role'] != 'employer' || account?['status'] != 'active') {
      throw StateError(
        'An active Employer account is required to change this photo.',
      );
    }
    final membership = await client
        .from('company_memberships')
        .select('member_role')
        .eq('user_id', actorId)
        .eq('company_id', companyId)
        .maybeSingle();
    checkSession();
    if (membership?['member_role'] != 'owner') {
      throw StateError('Only the Company Owner can change this photo.');
    }
  }

  @override
  Future<Map<String, dynamic>?> latestRequest() async {
    checkSession();
    final rows = await client
        .from('company_logo_change_requests')
        .select('request_id, status, review_comment, submitted_at')
        .eq('company_id', companyId)
        .order('submitted_at', ascending: false)
        .limit(1);
    checkSession();
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<void> upload(CompanyLogoUpload image) async {
    // A helpful preflight; Storage RLS remains the actual authorization check.
    await _checkOwnerAccess();
    await client.storage
        .from('jobmate-company-logos')
        .uploadBinary(
          _path(image),
          image.bytes,
          fileOptions: FileOptions(contentType: image.mimeType, upsert: false),
        );
    checkSession();
  }

  @override
  Future<String> save(CompanyLogoUpload image) async {
    checkSession();
    final status = await client.rpc(
      'submit_company_logo_change',
      params: {
        'p_company_id': companyId,
        'p_upload_id': image.id,
        'p_storage_path': _path(image),
        'p_expected_logo_path': image.expectedPath,
      },
    );
    checkSession();
    if (!const ['pending', 'verified', 'rejected'].contains(status)) {
      throw const FormatException('Unable to confirm the logo request.');
    }
    return status as String;
  }
}

/// Only an approved request can replace the published Company photo.
class CompanyLogoEditor extends StatefulWidget {
  const CompanyLogoEditor({
    super.key,
    required this.gateway,
    required this.canEdit,
    this.currentPath,
    this.initialBytes,
    this.showRequestStatus = true,
    this.onSubmitted,
    this.onBusyChanged,
    this.pickImage,
  });
  final CompanyLogoGateway gateway;
  final bool canEdit;
  final String? currentPath;
  final Uint8List? initialBytes;
  final bool showRequestStatus;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<bool>? onBusyChanged;
  final Future<XFile?> Function()? pickImage;
  @override
  State<CompanyLogoEditor> createState() => _CompanyLogoEditorState();
}

class _CompanyLogoEditorState extends State<CompanyLogoEditor> {
  late Uint8List? _savedBytes = widget.initialBytes;
  CompanyLogoUpload? _attempt;
  bool _working = false, _uploaded = false;
  bool _loadingStatus = true;
  Map<String, dynamic>? _request;
  String? _statusError;
  String? _error;

  bool get _canChoose =>
      widget.canEdit &&
      !_working &&
      !_loadingStatus &&
      _statusError == null &&
      _attempt == null &&
      (_request == null ||
          const ['verified', 'rejected'].contains(_request!['status']));

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    if (!widget.showRequestStatus) {
      _loadingStatus = false;
      return;
    }
    setState(() {
      _loadingStatus = true;
      _statusError = null;
    });
    try {
      final request = await widget.gateway.latestRequest();
      if (mounted) setState(() => _request = request);
    } catch (_) {
      if (mounted) {
        setState(
          () => _statusError = 'Unable to load logo review status. Refresh the status before choosing a photo.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  @override
  void didUpdateWidget(covariant CompanyLogoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPath != oldWidget.currentPath ||
        widget.initialBytes != oldWidget.initialBytes) {
      _savedBytes = widget.initialBytes;
    }
  }

  void _busy(bool value) {
    if (!mounted) return;
    setState(() => _working = value);
    widget.onBusyChanged?.call(value);
  }

  Future<void> _pick() async {
    if (!_canChoose) return;
    _busy(true);
    setState(() => _error = null);
    try {
      widget.gateway.checkSession();
      final image =
          await (widget.pickImage?.call() ??
              ImagePicker().pickImage(
                source: ImageSource.gallery,
                maxWidth: 800,
                maxHeight: 800,
                imageQuality: 90,
                requestFullMetadata: false,
              ));
      if (image == null || !mounted) return;
      if (await image.length() > 2 * 1024 * 1024) {
        throw const FormatException('Choose an image of at most 2 MiB.');
      }
      final bytes = await image.readAsBytes();
      final mime = lookupMimeType(image.name, headerBytes: bytes);
      const extensions = {
        'image/jpeg': 'jpg',
        'image/png': 'png',
        'image/webp': 'webp',
      };
      final extension = extensions[mime];
      if (bytes.isEmpty || extension == null) {
        throw const FormatException(
          'Choose a non-empty JPG, PNG or WebP image.',
        );
      }
      widget.gateway.checkSession();
      if (!mounted) return;
      _attempt = CompanyLogoUpload(
        id: const Uuid().v4(),
        bytes: bytes,
        extension: extension,
        mimeType: mime!,
        expectedPath: widget.currentPath,
      );
      _uploaded = false;
      await _save();
    } catch (error) {
      await _handleError(error);
    } finally {
      _busy(false);
    }
  }

  Future<void> _save() async {
    final image = _attempt!;
    widget.gateway.checkSession();
    await widget.gateway.upload(image);
    _uploaded = true;
    final status = await widget.gateway.save(image);
    widget.gateway.checkSession();
    if (!mounted) return;
    setState(() {
      // Keep the current photo until an Admin approves the proposed image.
      _request = {'request_id': image.id, 'status': status};
      _attempt = null;
      _uploaded = false;
      _error = null;
    });
    widget.onSubmitted?.call(status);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Logo request saved. The current photo stays until approval.',
        ),
      ),
    );
    await _loadStatus();
  }

  Future<void> _handleError(Object error) async {
    if (!mounted) return;
    debugPrint('Company logo update failed: $error');
    final requestId = _attempt?.id;
    // Only the RPC can create an approval request. A failed upload has never
    // reached that stage, even if a file was stored before a response was lost.
    final submissionStarted = _uploaded;
    setState(() {
      _attempt = null;
      _uploaded = false;
      if (error is StorageException) {
        _error = switch (error.statusCode) {
          '401' => 'Your session could not be verified. Sign in again, then choose the photo again.',
          '403' => 'Photo upload was denied. Check that you are signed in as the Company Owner, then choose the photo again.',
          '413' => 'Choose an image of at most 2 MiB.',
          _ =>
            'Unable to upload this photo. You can choose the same photo again.',
        };
      } else if (error is PostgrestException && error.code == 'P0001') {
        _error = error.message;
      } else {
        _error = error is FormatException
            ? error.message
            : error is StateError
            ? error.message.toString()
            : submissionStarted
            ? 'Unable to confirm submission. Checking review status before you choose a photo again.'
            : 'Unable to read or upload this photo. You can choose the same photo again.';
      }
    });
    if (submissionStarted) {
      // Read only: never automatically upload or resubmit a failed operation.
      await _loadStatus();
      if (!mounted) return;
      setState(() {
        if (_request?['request_id'] == requestId ||
            _request?['status'] == 'pending') {
          _error =
              null; // The actual request status is displayed below the photo.
        } else if (_statusError == null && error is! PostgrestException) {
          _error = 'Unable to confirm submission. You can choose the same photo again.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Tooltip(
            message: widget.canEdit ? 'Change company photo' : 'Company photo',
            child: Material(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _canChoose ? _pick : null,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _savedBytes == null
                              ? const Icon(Icons.business_outlined, size: 56)
                              : Image.memory(
                                  _savedBytes!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.broken_image_outlined,
                                    size: 48,
                                  ),
                                ),
                        ),
                      ),
                      if (widget.canEdit)
                        Positioned(
                          left: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: colors.primary,
                            child: Icon(
                              Icons.camera_alt_outlined,
                              size: 18,
                              color: colors.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.canEdit
              ? 'Click the photo to submit a new logo for Admin approval.'
              : 'Only the Company Owner can change this photo.',
          textAlign: TextAlign.center,
        ),
        const Text(
          'JPG, PNG or WebP, maximum 2 MiB.',
          textAlign: TextAlign.center,
        ),
        if (widget.showRequestStatus) ...[
          const SizedBox(height: 12),
          if (_loadingStatus) const LinearProgressIndicator(),
          if (_request != null)
            Text(switch (_request!['status']) {
              'pending' =>
                'Pending approval. Your current photo remains unchanged.',
              'verified' => 'Logo approved. Refresh Company profile to load the latest photo.',
              'rejected' =>
                'Logo rejected. ${_request!['review_comment'] ?? 'Refresh the review status for the reason.'} You may submit another photo.',
              _ => 'Unknown review status. Refresh before continuing.',
            }, textAlign: TextAlign.center),
          if (_statusError != null)
            Text(_statusError!, style: TextStyle(color: colors.error)),
          TextButton.icon(
            onPressed: _working || _loadingStatus ? null : _loadStatus,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh logo review status'),
          ),
        ],
        if (_working)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: colors.error)),
          ),
        if (widget.canEdit)
          OutlinedButton.icon(
            onPressed: _canChoose ? _pick : null,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_error == null ? 'Choose photo' : 'Choose photo again'),
          ),
      ],
    );
  }
}
