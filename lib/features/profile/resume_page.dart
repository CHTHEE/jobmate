import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/mobile_back_action.dart';
import 'resume_repository.dart';

class ResumePage extends StatefulWidget {
  const ResumePage({super.key, this.gateway, this.pickFile, this.openUrl});
  final ResumeGateway? gateway;
  final Future<XFile?> Function()? pickFile;
  final Future<bool> Function(Uri)? openUrl;

  @override
  State<ResumePage> createState() => _ResumePageState();
}

class _ResumePageState extends State<ResumePage> {
  late final _gateway =
      widget.gateway ?? SupabaseResumeGateway(Supabase.instance.client);
  List<ResumeFile> _files = [];
  ResumeUpload? _selected;
  bool _loading = true, _working = false, _allowed = false;
  bool _uploaded = false, _retryRequired = false;
  bool _confirmingExit = false;
  String? _error;
  String _message = 'Loading resume...';
  final _links = <String, (Uri, DateTime)>{};
  bool get _busy => _loading || _working;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _allowed = false;
    });
    try {
      final account = await _gateway.loadAccount();
      _gateway.checkSession();
      if (account['role'] != 'job_seeker' || account['status'] != 'active') {
        throw StateError(
          'An active Job Seeker account is required to manage a resume.',
        );
      }
      final files = await _gateway.list();
      _gateway.checkSession();
      if (!mounted) return;
      setState(() {
        _files = files;
        _allowed = true;
        _links.clear();
      });
    } catch (error) {
      debugPrint('Resume load failed: $error');
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : 'Resume management is unavailable. Please retry later.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choose() async {
    if (_busy || !_allowed || _retryRequired) return;
    setState(() {
      _working = true;
      _message = 'Reading PDF...';
    });
    try {
      const type = XTypeGroup(
        label: 'PDF',
        extensions: ['pdf'],
        mimeTypes: ['application/pdf'],
        uniformTypeIdentifiers: ['com.adobe.pdf'],
      );
      final file =
          await (widget.pickFile?.call() ??
              openFile(acceptedTypeGroups: [type]));
      if (file == null || !mounted) return;
      if (await file.length() > 5 * 1024 * 1024) {
        throw const FormatException('Choose a PDF of at most 5 MiB.');
      }
      final bytes = await file.readAsBytes();
      validateResume(file.name, bytes);
      _gateway.checkSession();
      if (!mounted) return;
      setState(() {
        _selected = ResumeUpload(
          id: const Uuid().v4(),
          name: file.name,
          bytes: bytes,
        );
        _uploaded = false;
      });
    } catch (error) {
      _show(
        error is FormatException
            ? error.message
            : error is StateError
            ? error.message.toString()
            : 'Unable to read this PDF. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _save() async {
    final file = _selected;
    if (_busy || !_allowed || file == null) return;
    setState(() {
      _working = true;
      _retryRequired = true;
      _message = 'Saving resume...';
    });
    try {
      _gateway.checkSession();
      if (!_uploaded) {
        await _gateway.upload(file);
        _uploaded = true;
      }
      await _gateway.save(file);
      _gateway.checkSession();
      if (!mounted) return;
      setState(() {
        _selected = null;
        _uploaded = false;
        _retryRequired = false;
      });
      _show('Resume saved. No administrator approval is required.');
      await _load();
    } catch (error) {
      debugPrint('Resume save failed: $error');
      if (error is PostgrestException && error.code == 'P0001') {
        if (mounted) setState(() => _retryRequired = false);
        _show(error.message);
      } else {
        _show(
          error is StateError ? error.message.toString() : 'Unable to confirm the save. Your selected file is kept; retry the same resume.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _open(ResumeFile file) async {
    if (_busy) return;
    try {
      _gateway.checkSession();
      final cached = _links[file.id];
      final url = cached != null && DateTime.now().isBefore(cached.$2)
          ? cached.$1
          : await _gateway.documentUrl(file);
      _links[file.id] = (url, DateTime.now().add(const Duration(seconds: 45)));
      if (!mounted) return;
      _gateway.checkSession();
      final opened =
          await (widget.openUrl?.call(url) ??
              launchUrl(
                url,
                mode: LaunchMode.externalApplication,
                webOnlyWindowName: '_blank',
              ));
      if (!opened) {
        _show(
          'The PDF link is ready. Allow the document window and tap Open PDF again.',
        );
      }
    } catch (_) {
      _show('Unable to open the PDF. Please retry.');
    }
  }

  void _show(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _back() async {
    if (_busy || _confirmingExit) return;
    _confirmingExit = true;
    final leave = await confirmDiscardChanges(context, _selected != null);
    _confirmingExit = false;
    if (!leave || !mounted) return;
    setState(() {
      _selected = null;
      _retryRequired = false;
    });
    // Rebuild PopScope before asking Navigator to pop the now-clean page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) returnToPage(context, AppRoutes.profile);
    });
  }

  Widget _file(ResumeFile file, {required bool current}) => WorkspaceCard(
    title: current ? 'Current resume' : file.name,
    subtitle: current ? file.name : null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${(file.size / 1024).toStringAsFixed(0)} KiB'),
        if (file.uploadedAt != null)
          Text(
            'Uploaded: ${MaterialLocalizations.of(context).formatMediumDate(file.uploadedAt!.toLocal())}',
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _open(file),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Open PDF'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && _selected == null,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: LoadingOverlay(
      isLoading: _busy,
      message: _message,
      child: Scaffold(
        appBar: ResponsivePageAppBar(
          title: const Text('My Resume'),
          enabled: !_busy,
          fallback: AppRoutes.profile,
          hasUnsavedChanges: () => _selected != null,
        ),
        body: WorkspaceContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Upload or replace your resume at any time. No administrator review is required. PDF only, maximum 5 MiB.',
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Text(_error!),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Retry'),
                ),
              ],
              if (_allowed) ...[
                if (_files.isNotEmpty)
                  _file(_files.first, current: true)
                else
                  const Text('You have not uploaded a resume yet.'),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _busy || _retryRequired ? null : _choose,
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    _selected == null ? 'Choose PDF' : 'Replace selected PDF',
                  ),
                ),
                if (_selected != null) ...[
                  const SizedBox(height: 12),
                  Text('Selected: ${_selected!.name}'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(
                      _retryRequired ? 'Retry same resume' : 'Save resume',
                    ),
                  ),
                  if (_retryRequired)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'The request result is uncertain. Retry continues the same upload.',
                      ),
                    ),
                  if (!_retryRequired)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _selected = null),
                      child: const Text('Cancel selection'),
                    ),
                ],
                if (_files.length > 1) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Previous resumes',
                    style: TextStyle(fontSize: 20),
                  ),
                  const SizedBox(height: 12),
                  for (final file in _files.skip(1)) ...[
                    _file(file, current: false),
                    const SizedBox(height: 12),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
