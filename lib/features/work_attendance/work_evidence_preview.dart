import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../applications/resume_pdf_opener.dart';
import 'work_attendance_models.dart';
import 'work_evidence_repository.dart';

abstract class WorkEvidencePreviewSource {
  String? get userId;
  Stream<String?> get accountChanges;
  Future<bool> canRead(String path);
  Future<Uri> sign(String path, int seconds);
}

class SupabaseWorkEvidencePreviewSource implements WorkEvidencePreviewSource {
  SupabaseWorkEvidencePreviewSource(this.client);
  final SupabaseClient client;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((e) => e.session?.user.id);
  @override
  Future<bool> canRead(String path) async {
    if (userId == null) return false;
    final value = await client.rpc(
      'can_read_work_evidence_file',
      params: {'p_storage_path': path},
    );
    return value == true;
  }

  @override
  Future<Uri> sign(String path, int seconds) async {
    if (userId == null) throw const AuthException('Sign in required');
    final uri = Uri.parse(
      await client.storage.from('work-evidence').createSignedUrl(path, seconds),
    );
    final origin = Uri.parse(client.storage.url);
    if (uri.origin != origin.origin ||
        !['https', 'http'].contains(uri.scheme) ||
        !uri.path.contains('/object/sign/work-evidence/') ||
        !uri.queryParameters.containsKey('token')) {
      throw const FormatException('Invalid private link');
    }
    return uri;
  }
}

/// No public URLs, protected-table queries or cached authorization. Own per
/// preview. Account changes invalidate the link and any stale signing response.
class WorkEvidencePreviewRepository extends ChangeNotifier {
  WorkEvidencePreviewRepository(this.source) {
    _account = source.accountChanges.listen((_) {
      ++_generation;
      _clear();
      error = 'Your account changed. Close this preview and sign in again.';
      if (!_disposed) notifyListeners();
    });
  }
  static const lifetimeSeconds = 90;
  final WorkEvidencePreviewSource source;
  late final StreamSubscription<String?> _account;
  int _generation = 0;
  bool _disposed = false;
  Timer? _expiry;
  Uri? _link;
  String? _actor;
  DateTime? _expires;
  WorkEvidence? file;
  bool loading = false;
  String? error;
  Uri? get link =>
      !_disposed &&
          source.userId == _actor &&
          _expires != null &&
          DateTime.now().isBefore(_expires!)
      ? _link
      : null;
  void _clear() {
    _expiry?.cancel();
    _link = null;
    file = null;
    loading = false;
  }

  Future<void> load(WorkEvidenceRepository viewer, String evidenceId) async {
    if (_disposed) return;
    final generation = ++_generation, actor = source.userId;
    final company = viewer.companyId, assignment = viewer.assignmentId;
    _clear();
    _actor = actor;
    error = null;
    loading = true;
    notifyListeners();
    bool current() =>
        !_disposed &&
        generation == _generation &&
        actor != null &&
        actor == source.userId &&
        actor == viewer.attendance.source.userId &&
        viewer.companyId == company &&
        viewer.assignmentId == assignment;
    try {
      if (!current()) throw const AuthException('Sign in required');
      await viewer.load().timeout(const Duration(seconds: 20));
      if (!current()) return;
      if (viewer.error != null ||
          viewer.loading ||
          viewer.assignment?.assignmentId != assignment) {
        throw const FormatException('Access unavailable');
      }
      final matches = viewer.evidence
          .where((e) => e.evidenceId == evidenceId)
          .toList();
      if (matches.length != 1) throw const FormatException('File unavailable');
      final selected = matches.single;
      if (![
            'application/pdf',
            'image/jpeg',
            'image/png',
            'image/webp',
          ].contains(selected.mimeType) ||
          !selected.storagePath.startsWith('$assignment/')) {
        throw const FormatException('Unsupported file');
      }
      final allowed = await source
          .canRead(selected.storagePath)
          .timeout(const Duration(seconds: 20));
      if (!current()) return;
      if (!allowed) throw const FormatException('Private file access denied');
      final issued = DateTime.now();
      final signed = await source
          .sign(selected.storagePath, lifetimeSeconds)
          .timeout(const Duration(seconds: 20));
      if (!current()) return;
      if (viewer.assignment?.assignmentId != assignment ||
          viewer.error != null) {
        return;
      }
      _expires = issued.add(const Duration(seconds: lifetimeSeconds));
      if (!DateTime.now().isBefore(_expires!)) {
        throw const FormatException('Link expired');
      }
      file = selected;
      _link = signed;
      _expiry = Timer(_expires!.difference(DateTime.now()), () {
        if (_disposed) return;
        _clear();
        error = 'This private preview has expired. Check access again to reopen it.';
        notifyListeners();
      });
    } catch (_) {
      if (current()) error = 'Unable to open this private file. It may be missing, unsupported, or access may have changed.';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _clear();
    unawaited(_account.cancel());
    super.dispose();
  }
}

class WorkEvidencePreviewDialog extends StatefulWidget {
  const WorkEvidencePreviewDialog({
    super.key,
    required this.viewer,
    required this.evidenceId,
    required this.repository,
    this.opener,
    this.imageBuilder,
  });
  final WorkEvidenceRepository viewer;
  final String evidenceId;
  final WorkEvidencePreviewRepository repository;
  final ResumePdfOpener? opener;
  final Widget Function(Uri)? imageBuilder;
  @override
  State<WorkEvidencePreviewDialog> createState() =>
      _WorkEvidencePreviewDialogState();
}

class _WorkEvidencePreviewDialogState extends State<WorkEvidencePreviewDialog> {
  late final _opener = widget.opener ?? createResumePdfOpener();
  bool _opening = false;
  String? _openError;
  Uri? _imageUri;
  void _evictImage() {
    final uri = _imageUri;
    _imageUri = null;
    if (uri != null) {
      unawaited(
        NetworkImage(uri.toString())
            .evict()
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    widget.repository.load(widget.viewer, widget.evidenceId);
  }

  Future<void> _open() async {
    final uri = widget.repository.link;
    if (uri == null || _opening) return;
    setState(() {
      _opening = true;
      _openError = null;
    });
    try {
      if (!await _opener.open(uri) && mounted) {
        setState(
          () => _openError = 'Your device could not open this file. Allow a new tab or try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _openError = 'Unable to open the private file.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _evictImage();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.repository,
    builder: (context, _) {
      final repo = widget.repository, uri = widget.repository.link;
      if (_imageUri != uri) {
        _evictImage();
        if (uri != null && repo.file?.mimeType.startsWith('image/') == true) {
          _imageUri = uri;
        }
      }
      return AlertDialog(
        title: const Text('Private evidence preview'),
        content: SizedBox(
          width: 640,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .65,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Private access expires after 90 seconds. Opening a PDF uses your browser or PDF app.',
                  ),
                  if (repo.loading)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Checking private file access',
                    ),
                  if (repo.error != null) Text(repo.error!),
                  if (_openError != null) Text(_openError!),
                  if (uri != null && repo.file != null) ...[
                    Text(repo.file!.fileName),
                    if (repo.file!.mimeType.startsWith('image/'))
                      widget.imageBuilder?.call(uri) ??
                          Image.network(
                            uri.toString(),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Text(
                              'This image could not be loaded. It may be missing or the preview may have expired.',
                            ),
                          ),
                    OutlinedButton(
                      onPressed: _opening ? null : _open,
                      child: Text(
                        repo.file!.mimeType == 'application/pdf'
                            ? 'Open PDF'
                            : 'Open image',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (!repo.loading && uri == null)
            TextButton(
              onPressed: () => repo.load(widget.viewer, widget.evidenceId),
              child: const Text('Check access again'),
            ),
        ],
      );
    },
  );
}
