import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import '../../shared/widgets/auth_layout.dart';
import '../../shared/widgets/loading_overlay.dart';

class CreateCompanyPage extends StatefulWidget {
  const CreateCompanyPage({super.key});

  @override
  State<CreateCompanyPage> createState() => _CreateCompanyPageState();
}

class _CreateCompanyPageState extends State<CreateCompanyPage> {
  // A. Services, controllers and page state
  final _supabase = Supabase.instance.client;
  final _user = Supabase.instance.client.auth.currentUser;

  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _industryController = TextEditingController();
  final _locationController = TextEditingController();
  final _registrationController = TextEditingController();
  final _yearController = TextEditingController();
  final _websiteController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactPhoneController = TextEditingController();

  final _imagePicker = ImagePicker();

  Uint8List? _selectedLogoBytes;
  Uint8List? _savedLogoBytes;

  String? _logoMimeType;
  String? _logoExtension;

  bool _logoUploaded = false;
  bool _logoLoadFailed = false;

  bool _isLoading = true;
  bool _isWorking = false;
  String _message = 'Please wait...';
  String? _loadError;

  Map<String, dynamic>? _company;
  String _memberRole = '';
  String? _reviewComment;

  Uint8List? _fileBytes;
  String? _fileName;
  bool _fileUploaded = false;

  // Frozen parameters for one submission attempt.
  Map<String, dynamic>? _attempt;

  bool get _isBusy => _isLoading || _isWorking;

  String get _status => (_company?['verification_status'] as String?) ?? '';

  bool get _eligible =>
      _company == null || (_memberRole == 'owner' && _status == 'rejected');

  bool get _canEdit =>
      !_isBusy && _loadError == null && _eligible && _attempt == null;

  bool get _canSubmit =>
      !_isBusy &&
      _loadError == null &&
      _fileBytes != null &&
      (_eligible || _attempt != null);

  @override
  void initState() {
    super.initState();
    _loadCompany();
  }

  // B. Check that this is still the same signed-in user.
  User _requireUser() {
    final user = _user;

    if (user == null || _supabase.auth.currentUser?.id != user.id) {
      throw const FormatException(
        'Your session changed. Please reopen this page.',
      );
    }

    return user;
  }

  // C. Load membership, company and rejection comment.
  Future<void> _loadCompany() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final user = _requireUser();

      final profile = await _supabase
          .from('users')
          .select('status')
          .eq('user_id', user.id)
          .single();

      if (profile['status'] != 'active') {
        throw const FormatException('Your account is not active.');
      }

      final membership = await _supabase
          .from('company_memberships')
          .select('company_id, member_role')
          .eq('user_id', user.id)
          .maybeSingle();

      Map<String, dynamic>? company;
      String? reviewComment;

      Uint8List? savedLogoBytes;
      bool logoLoadFailed = false;

      if (membership != null) {
        company = await _supabase
            .from('companies')
            .select(
              'company_id, company_name, company_description, '
              'industry, location, verification_status, '
              'registration_number, established_year, website_url, '
              'contact_email, contact_phone, logo_storage_path',
            )
            .eq('company_id', membership['company_id'])
            .single();

        final logoPath = company['logo_storage_path'] as String?;

        if (logoPath != null && logoPath.isNotEmpty) {
          try {
            savedLogoBytes = await _supabase.storage
                .from('jobmate-company-logos')
                .download(logoPath);
          } catch (error) {
            debugPrint('Company logo download failed: $error');
            logoLoadFailed = true;
          }
        }

        if (membership['member_role'] == 'owner' &&
            company['verification_status'] == 'rejected') {
          final review = await _supabase
              .from('company_verification_requests')
              .select('review_comment')
              .eq('company_id', company['company_id'])
              .eq('submitted_by', user.id)
              .order('submitted_at', ascending: false)
              .limit(1)
              .maybeSingle();

          reviewComment = review?['review_comment'] as String?;
        }
      }

      _requireUser();
      if (!mounted) return;

      setState(() {
        _company = company;
        _memberRole = (membership?['member_role'] as String?) ?? '';
        _reviewComment = reviewComment;
        _savedLogoBytes = savedLogoBytes;
        _logoLoadFailed = logoLoadFailed;

        // Keep retry parameters and displayed inputs unchanged.
        if (_attempt == null && company != null) {
          _nameController.text = (company['company_name'] as String?) ?? '';
          _descriptionController.text =
              (company['company_description'] as String?) ?? '';
          _industryController.text = (company['industry'] as String?) ?? '';
          _locationController.text = (company['location'] as String?) ?? '';
          _registrationController.text =
              (company['registration_number'] as String?) ?? '';

          _yearController.text = company['established_year']?.toString() ?? '';

          _websiteController.text = (company['website_url'] as String?) ?? '';

          _contactEmailController.text =
              (company['contact_email'] as String?) ?? '';

          _contactPhoneController.text =
              (company['contact_phone'] as String?) ?? '';
        }
      });
    } catch (error) {
      debugPrint('Company load failed: $error');

      if (!mounted) return;

      setState(() {
        _loadError = error is FormatException
            ? error.message
            : 'Unable to load company details. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // D. Choose and read one PDF.
  Future<void> _pickPdf() async {
    if (!_canEdit) return;

    setState(() {
      _isWorking = true;
      _message = 'Reading PDF...';
    });

    try {
      const pdfType = XTypeGroup(
        label: 'PDF',
        extensions: ['pdf'],
        mimeTypes: ['application/pdf'],
        uniformTypeIdentifiers: ['com.adobe.pdf'],
      );

      final file = await openFile(acceptedTypeGroups: [pdfType]);

      // The user cancelled the picker.
      if (file == null) return;

      final size = await file.length();

      if (size == 0 || size > 5 * 1024 * 1024) {
        throw const FormatException('Choose a non-empty PDF up to 5 MiB.');
      }

      if (file.name.runes.length > 255) {
        throw const FormatException('Please shorten the filename.');
      }

      final bytes = await file.readAsBytes();

      // Basic file-header check, not document verification.
      if (String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        throw const FormatException('This file does not appear to be a PDF.');
      }

      if (!mounted) return;

      setState(() {
        _fileBytes = bytes;
        _fileName = file.name;
        _fileUploaded = false;
      });
    } on FormatException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      debugPrint('Company PDF selection failed: $error');
      _showMessage('Unable to read this file.');
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  Future<void> _pickLogo() async {
    if (!_canEdit) return;

    setState(() {
      _isWorking = true;
      _message = 'Reading company logo...';
    });

    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        // Alternative: ImageSource.camera.
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 90,
        requestFullMetadata: false,
      );

      if (image == null) return;

      final size = await image.length();

      if (size == 0 || size > 2 * 1024 * 1024) {
        throw const FormatException('Choose a non-empty logo up to 2 MiB.');
      }

      final bytes = await image.readAsBytes();

      final mimeType = lookupMimeType(image.name, headerBytes: bytes);

      const extensions = {
        'image/jpeg': 'jpg',
        'image/png': 'png',
        'image/webp': 'webp',
      };

      final extension = extensions[mimeType];

      if (extension == null) {
        throw const FormatException('Choose a JPG, PNG or WebP image.');
      }

      if (!mounted) return;

      setState(() {
        _attempt = null;

        _fileBytes = null;
        _fileName = null;
        _fileUploaded = false;

        _selectedLogoBytes = null;
        _logoMimeType = null;
        _logoExtension = null;
        _logoUploaded = false;
      });
    } on FormatException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      debugPrint('Company logo selection failed: $error');
      _showMessage('Unable to read this image.');
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  Future<void> _uploadOnce({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      await _supabase.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
    } on StorageException catch (error) {
      final alreadyExists =
          error.statusCode == '409' ||
          error.error == 'Duplicate' ||
          error.error == 'ResourceAlreadyExists';

      if (!alreadyExists) rethrow;
    }
  }

  String? _optionalText(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  // E. Upload and submit, or retry the same attempt.
  Future<void> _submit() async {
    final bytes = _fileBytes;
    final filename = _fileName;

    if (!_canSubmit || bytes == null || filename == null) {
      return;
    }

    if (_attempt == null && _formKey.currentState?.validate() != true) {
      return;
    }

    setState(() {
      _isWorking = true;
      _message = 'Uploading PDF...';
    });

    try {
      final user = _requireUser();

      _attempt ??= Map<String, dynamic>.unmodifiable({
        'p_request_id': const Uuid().v4(),

        'p_company_name': _nameController.text.trim(),
        'p_company_description': _optionalText(_descriptionController),
        'p_industry': _optionalText(_industryController),
        'p_location': _optionalText(_locationController),
        'p_original_name': filename,

        'p_registration_number': _registrationController.text.trim(),

        'p_established_year': _yearController.text.trim().isEmpty
            ? null
            : int.tryParse(_yearController.text.trim(), radix: 10),

        'p_website_url': _optionalText(_websiteController),
        'p_contact_email': _optionalText(_contactEmailController),
        'p_contact_phone': _optionalText(_contactPhoneController),
      });

      final params = _attempt!;
      final requestId = params['p_request_id'] as String;
      final path = '${user.id}/$requestId/document.pdf';

      final logoBytes = _selectedLogoBytes;

      if (logoBytes != null && !_logoUploaded) {
        if (mounted) {
          setState(() {
            _message = 'Uploading company logo...';
          });
        }

        await _uploadOnce(
          bucket: 'jobmate-company-logos',
          path: '${user.id}/$requestId/logo.${_logoExtension!}',
          bytes: logoBytes,
          contentType: _logoMimeType!,
        );

        _logoUploaded = true;
      }

      if (!_fileUploaded) {
        if (mounted) {
          setState(() {
            _message = 'Uploading PDF...';
          });
        }

        await _uploadOnce(
          bucket: 'jobmate-company-verification',
          path: path,
          bytes: bytes,
          contentType: 'application/pdf',
        );

        _fileUploaded = true;
      }

      _requireUser();

      if (mounted) {
        setState(() {
          _message = 'Submitting company for review...';
        });
      }

      await _supabase.rpc('submit_company_for_review_v2', params: params);

      if (!mounted) return;

      setState(() {
        _attempt = null;
        _fileBytes = null;
        _fileName = null;
        _fileUploaded = false;
      });

      await _loadCompany();
      _showMessage('Your company submission has been recorded.');
    } on PostgrestException catch (error) {
      debugPrint('Company submission failed: $error');

      if (!mounted) return;

      if (error.code == 'P0001') {
        // Our Function explicitly rejected this call.
        // Its Database writes were rolled back.
        setState(() {
          _attempt = null;
          _fileUploaded = false;
          _logoUploaded = false;
        });

        _showMessage(error.message);
        await _loadCompany();
      } else {
        // Keep the same attempt when the outcome is uncertain.
        _showMessage('Unable to confirm submission. Please retry.');
      }
    } on StorageException catch (error) {
      debugPrint('Company upload failed: $error');
      _showMessage('Upload failed. Please retry.');
    } on FormatException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      debugPrint('Company submission error: $error');
      _showMessage('Unable to confirm submission. Please retry.');
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  String? _validateYear(String text) {
    if (text.isEmpty) return null;

    final year = int.tryParse(text, radix: 10);
    final currentYear = DateTime.now().year;

    if (year == null || year < 1 || year > currentYear) {
      return 'Enter a year from 1 to $currentYear.';
    }

    return null;
  }

  String? _validateWebsite(String text) {
    if (text.isEmpty) return null;

    final uri = Uri.tryParse(text);

    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        RegExp(r'\s').hasMatch(text)) {
      return 'Enter a website such as https://example.com.';
    }

    return null;
  }

  String? _validateContactEmail(String text) {
    if (text.isEmpty) return null;

    final pattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    if (!pattern.hasMatch(text)) {
      return 'Enter a valid contact email.';
    }

    return null;
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int? limit,
    bool isRequired = false,
    bool multiline = false,
    TextInputType keyboardType = TextInputType.text,
    String? hint,
    String? Function(String value)? extraValidator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        enabled: _canEdit,
        maxLength: limit,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 5 : 1,
        keyboardType: multiline ? TextInputType.multiline : keyboardType,
        decoration: InputDecoration(
          labelText: isRequired ? '$label *' : label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          final text = (value ?? '').trim();

          if (isRequired && text.isEmpty) {
            return 'Please enter $label.';
          }

          if (limit != null && text.runes.length > limit) {
            return 'Use no more than $limit characters.';
          }

          return extraValidator?.call(text);
        },
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(_nameController, 'Company name', limit: 255, isRequired: true),
          _field(
            _descriptionController,
            'Company description',
            multiline: true,
          ),
          _field(
            _registrationController,
            'Registration number',
            limit: 100,
            isRequired: true,
          ),
          _field(_industryController, 'Industry', limit: 100),
          _field(_locationController, 'Location', limit: 255),
          _field(
            _yearController,
            'Established year',
            limit: 4,
            keyboardType: TextInputType.number,
            hint: '2018',
            extraValidator: _validateYear,
          ),

          _field(
            _websiteController,
            'Website',
            keyboardType: TextInputType.url,
            hint: 'https://example.com',
            extraValidator: _validateWebsite,
          ),

          _field(
            _contactEmailController,
            'Company contact email',
            limit: 254,
            keyboardType: TextInputType.emailAddress,
            extraValidator: _validateContactEmail,
          ),

          _field(
            _contactPhoneController,
            'Company contact phone',
            limit: 30,
            keyboardType: TextInputType.phone,
          ),
          const Text(
            'Upload one company supporting document. '
            'PDF only, maximum 5 MiB.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _canEdit ? _pickPdf : null,
            icon: const Icon(Icons.attach_file),
            label: Text(_fileName == null ? 'Choose PDF' : 'Replace PDF'),
          ),
          const SizedBox(height: 8),
          Text(_fileName ?? 'No file selected'),
          if (_fileBytes != null)
            Text('${(_fileBytes!.length / 1024).toStringAsFixed(0)} KiB'),
          const SizedBox(height: 20),
          if (_attempt != null) ...[
            const Text(
              'This submission has not been confirmed. '
              'Details are locked so you can retry.',
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(
              _attempt != null
                  ? 'Retry submission'
                  : _company == null
                  ? 'Create and submit'
                  : 'Resubmit for review',
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    const labels = {
      'not_submitted': 'Not submitted',
      'pending': 'Pending review',
      'verified': 'Verified',
      'rejected': 'Rejected',
    };

    return labels[status] ?? 'Unknown';
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _industryController.dispose();
    _locationController.dispose();
    _registrationController.dispose();
    _yearController.dispose();
    _websiteController.dispose();
    _contactEmailController.dispose();
    _contactPhoneController.dispose();
    super.dispose();
  }

  Widget _buildLogo() {
    final bytes = _selectedLogoBytes ?? _savedLogoBytes;
    final colors = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Tooltip(
            message: _canEdit ? 'Choose company logo' : 'Company logo',
            child: InkWell(
              onTap: _canEdit ? _pickLogo : null,
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: bytes == null
                        ? const Icon(Icons.business_outlined, size: 56)
                        : Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.broken_image_outlined,
                                size: 48,
                              );
                            },
                          ),
                  ),
                  if (_canEdit)
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        child: const Icon(Icons.camera_alt_outlined, size: 18),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Company logo — optional'),
        const Text(
          'JPG, PNG or WebP, maximum 2 MiB.',
          textAlign: TextAlign.center,
        ),
        if (bytes == null && _logoLoadFailed)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Logo unavailable. Use Refresh to try again.'),
          ),
        if (_selectedLogoBytes != null && _canEdit)
          TextButton(
            onPressed: () {
              setState(() {
                _selectedLogoBytes = null;
                _logoMimeType = null;
                _logoExtension = null;
                _logoUploaded = false;
              });
            },
            child: const Text('Clear new selection'),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  // G. Page layout
  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isBusy,
      message: _isWorking ? _message : 'Loading company details...',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Company registration'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _isBusy ? null : _loadCompany,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: AuthLayout(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loadError != null) ...[
                Text(_loadError!),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _isBusy ? null : _loadCompany,
                  child: const Text('Try again'),
                ),
              ] else if (!_isLoading) ...[
                Text(
                  _company == null ? 'Create company' : 'Company verification',
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 16),

                _buildLogo(),
                if (_company != null) ...[
                  Text('Company: ${_company!['company_name']}'),
                  Text('Verification: ${_statusLabel(_status)}'),
                  Text(
                    'Registration number: '
                    '${_company!['registration_number'] ?? 'Not provided'}',
                  ),

                  Text(
                    'Established year: '
                    '${_company!['established_year'] ?? 'Not provided'}',
                  ),

                  Text(
                    'Website: '
                    '${_company!['website_url'] ?? 'Not provided'}',
                  ),

                  Text(
                    'Contact email: '
                    '${_company!['contact_email'] ?? 'Not provided'}',
                  ),

                  Text(
                    'Contact phone: '
                    '${_company!['contact_phone'] ?? 'Not provided'}',
                  ),
                  if ((_reviewComment ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('Review comment: $_reviewComment'),
                    ),
                  const SizedBox(height: 24),
                ],
                if (_eligible || _attempt != null)
                  _buildForm()
                else
                  Text(
                    _status == 'pending'
                        ? 'Your company is awaiting review. '
                              'Changes are locked during review.'
                        : 'This page is for company registration '
                              'and resubmission.',
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
