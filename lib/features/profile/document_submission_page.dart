import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../shared/widgets/auth_layout.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/mobile_back_action.dart';
import 'resume_page.dart';

class DocumentSubmissionPage extends StatefulWidget {
  const DocumentSubmissionPage({super.key});

  @override
  State<DocumentSubmissionPage> createState() => _DocumentSubmissionPageState();
}

class _DocumentSubmissionPageState extends State<DocumentSubmissionPage> {
  final _supabase = Supabase.instance.client;
  final _user = Supabase.instance.client.auth.currentUser;

  bool _isLoading = true;
  bool _isWorking = false;

  String _loadingMessage = 'Loading submissions...';
  String? _loadError;

  String _role = '';
  String _accountStatus = '';
  String _verificationStatus = '';

  Uint8List? _fileBytes;
  String? _fileName;
  String? _requestId;
  bool _fileUploaded = false;

  List<Map<String, dynamic>> _history = [];

  bool get _isBusy => _isLoading || _isWorking;

  bool get _canChoose =>
      !_isBusy &&
      _loadError == null &&
      _accountStatus == 'active' &&
      (_role == 'job_seeker' || _role == 'employer') &&
      (_verificationStatus == 'not_submitted' ||
          _verificationStatus == 'rejected');

  bool get _canSubmit => _canChoose && _fileBytes != null;

  String get _documentTitle =>
      _role == 'employer' ? 'Company Supporting Document' : 'Resume';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final user = _user;

      if (user == null || _supabase.auth.currentUser?.id != user.id) {
        throw StateError('Please log in again.');
      }

      final profile = await _supabase
          .from('users')
          .select('role, status, verification_status')
          .eq('user_id', user.id)
          .single();

      final history = profile['role'] == 'job_seeker'
          ? <Map<String, dynamic>>[]
          : await _supabase
                .from('verification_requests')
                .select('request_id, status, submitted_at, review_comment')
                .eq('user_id', user.id)
                .order('submitted_at', ascending: false)
                .limit(5);

      if (!mounted) return;
      if (_supabase.auth.currentUser?.id != user.id) {
        throw StateError('Your account changed. Reopen this page.');
      }

      setState(() {
        _role = (profile['role'] as String?) ?? '';
        _accountStatus = (profile['status'] as String?) ?? '';
        _verificationStatus = (profile['verification_status'] as String?) ?? '';

        _history = List<Map<String, dynamic>>.from(history);
      });
    } catch (error) {
      debugPrint('Submission load failed: $error');

      if (!mounted) return;

      setState(() {
        _loadError = 'Unable to load submissions. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _choosePdf() async {
    if (!_canChoose) return;

    setState(() {
      _isWorking = true;
      _loadingMessage = 'Reading PDF...';
    });

    try {
      const pdfType = XTypeGroup(
        label: 'PDF',
        extensions: ['pdf'],
        mimeTypes: ['application/pdf'],
        uniformTypeIdentifiers: ['com.adobe.pdf'],
      );

      final file = await openFile(acceptedTypeGroups: [pdfType]);

      if (file == null) return;

      final size = await file.length();

      if (size == 0 || size > 5 * 1024 * 1024) {
        throw const FormatException('Choose a non-empty PDF below 5 MiB.');
      }

      if (file.name.runes.length > 255) {
        throw const FormatException('Please shorten the filename.');
      }

      final bytes = await file.readAsBytes();

      // 基础 PDF header 检查，不是完整文件内容验证。
      if (String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        throw const FormatException('This file does not appear to be a PDF.');
      }

      if (!mounted) return;

      setState(() {
        _fileBytes = bytes;
        _fileName = file.name;
        _requestId = const Uuid().v4();
        _fileUploaded = false;
      });
    } on FormatException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      debugPrint('PDF selection failed: $error');
      _showMessage('Unable to read this file.');
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final user = _user;
    final bytes = _fileBytes;
    final filename = _fileName;
    final requestId = _requestId;

    if (user == null || _supabase.auth.currentUser?.id != user.id) {
      _showMessage('Please log in again.');
      return;
    }

    if (bytes == null || filename == null || requestId == null) {
      return;
    }

    final path = '${user.id}/$requestId/document.pdf';

    setState(() {
      _isWorking = true;
      _loadingMessage = 'Submitting document...';
    });

    try {
      if (!_fileUploaded) {
        try {
          await _supabase.storage
              .from('jobmate-verification')
              .uploadBinary(
                path,
                bytes,
                fileOptions: const FileOptions(
                  contentType: 'application/pdf',
                  upsert: false,
                  // 不覆盖已存在的审核文件。
                ),
              );
        } on StorageException catch (error) {
          // 同一文件、同一路径重试：
          // 上次上传可能已成功，但 response 丢失。
          final alreadyExists =
              error.statusCode == '409' ||
              error.error == 'Duplicate' ||
              error.error == 'ResourceAlreadyExists';

          if (!alreadyExists) rethrow;
        }

        _fileUploaded = true;
      }

      await _supabase.rpc(
        'submit_verification_document',
        params: {
          'p_request_id': requestId,
          'p_storage_path': path,
          'p_original_name': filename,
        },
      );

      if (!mounted) return;

      setState(() {
        _fileBytes = null;
        _fileName = null;
        _requestId = null;
        _fileUploaded = false;
      });

      await _loadData();

      _showMessage('Your submission has been recorded.');
    } on PostgrestException catch (error) {
      debugPrint('Submission rejected: $error');
      _showMessage(error.message);
    } on StorageException catch (error) {
      debugPrint('Document upload failed: $error');
      _showMessage('Upload failed. Please try again.');
    } catch (error) {
      debugPrint('Document submission failed: $error');
      _showMessage('Unable to submit. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  String _statusLabel(String value) {
    const labels = {
      'not_submitted': 'Not submitted',
      'pending': 'Pending review',
      'verified': 'Verified',
      'rejected': 'Rejected',
    };

    return labels[value] ?? 'Unknown';
  }

  String _formatDate(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();

    if (date == null) return 'Not available';

    final formatter = MaterialLocalizations.of(context);

    return '${formatter.formatMediumDate(date)}, '
        '${formatter.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true)}';
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_role == 'job_seeker' && !_isLoading && _loadError == null) {
      return const ResumePage();
    }
    return LoadingOverlay(
      isLoading: _isBusy,
      message: _isWorking ? _loadingMessage : 'Loading submissions...',
      child: Scaffold(
        appBar: ResponsivePageAppBar(
          enabled: !_isBusy,
          hasUnsavedChanges: () => _fileBytes != null,
          title: const Text('Verification Documents'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _isBusy ? null : _loadData,
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
                Text(_loadError ?? ''),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _isBusy ? null : _loadData,
                  child: const Text('Try again'),
                ),
              ] else ...[
                Text(_documentTitle, style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 12),

                Text(
                  'Verification: '
                  '${_statusLabel(_verificationStatus)}',
                ),
                const SizedBox(height: 16),

                const Text(
                  'Upload one PDF, maximum 5 MiB. '
                  'An administrator will review your submission.',
                ),
                const SizedBox(height: 20),

                OutlinedButton.icon(
                  onPressed: _canChoose ? _choosePdf : null,
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    _fileBytes == null ? 'Choose PDF' : 'Replace selected PDF',
                  ),
                ),
                const SizedBox(height: 12),

                Text(_fileName ?? 'No file selected'),

                if (_fileBytes != null)
                  Text('${(_fileBytes!.length / 1024).toStringAsFixed(0)} KiB'),

                const SizedBox(height: 20),

                FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  child: Text(
                    _fileUploaded ? 'Retry submission' : 'Submit for review',
                  ),
                ),

                if (_verificationStatus == 'pending')
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text('Your documents are awaiting review.'),
                  ),

                if (_verificationStatus == 'verified')
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text('Your account has been verified.'),
                  ),

                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 12),

                const Text(
                  'Submission History',
                  style: TextStyle(fontSize: 20),
                ),

                if (_history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('No submissions yet.'),
                  ),

                for (final request in _history)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _statusLabel((request['status'] as String?) ?? ''),
                    ),
                    subtitle: Text(
                      '${_formatDate(request['submitted_at'])}\n'
                      '${request['review_comment'] ?? ''}',
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
