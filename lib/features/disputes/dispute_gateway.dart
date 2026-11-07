import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class DisputeGateway {
  Future<List<Map<String, dynamic>>> list(
    bool admin, {
    required int limit,
    required int offset,
  });
  Future<List<Map<String, dynamic>>> eligible(
    String category, {
    required int limit,
    required int offset,
  });
  Future<Map<String, dynamic>> details(String id, bool admin);
  Future<List<Map<String, dynamic>>> history(String id, bool admin);
  Future<List<Map<String, dynamic>>> evidence(String id, bool admin);
  Future<List<Map<String, dynamic>>> evidenceHistory(String id, bool admin);
  Future<String> submit(String category, String relatedId, String description);
  Future<String> action(String id, String action, String note);
  Future<void> uploadEvidence(
    String disputeId,
    String evidenceId,
    String name,
    Uint8List bytes,
  );
  Future<Uri> evidenceUrl(String path);
}

String validateDisputeEvidence(String name, Uint8List bytes) {
  if (name.trim().isEmpty || name.runes.length > 255) {
    throw const FormatException('Use a filename of 1 to 255 characters.');
  }
  if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
    throw const FormatException('Choose a non-empty file of at most 5 MiB.');
  }
  final mime = lookupMimeType(name, headerBytes: bytes.take(16).toList());
  if (!const {
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
  }.contains(mime)) {
    throw const FormatException('Choose a PDF, JPG, PNG or WebP file.');
  }
  return mime!;
}

class SupabaseDisputeGateway implements DisputeGateway {
  SupabaseDisputeGateway(this.client) : _actor = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _actor;
  void _check() {
    if (_actor == null || client.auth.currentUser?.id != _actor) {
      throw StateError('Your account changed. Please reopen disputes.');
    }
  }

  Future<dynamic> _call(String name, Map<String, dynamic> params) async {
    _check();
    final result = await client.rpc(name, params: params);
    _check();
    return result;
  }

  List<Map<String, dynamic>> _rows(dynamic result) =>
      (result as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  Future<List<Map<String, dynamic>>> list(
    bool admin, {
    required int limit,
    required int offset,
  }) async => _rows(
    await _call('list_disputes_page', {
      'p_admin': admin,
      'p_limit': limit,
      'p_offset': offset,
    }),
  );
  @override
  Future<List<Map<String, dynamic>>> eligible(
    String category, {
    required int limit,
    required int offset,
  }) async => _rows(
    await _call('list_dispute_eligible_records', {
      'p_category': category,
      'p_limit': limit,
      'p_offset': offset,
    }),
  );
  @override
  Future<Map<String, dynamic>> details(String id, bool admin) async =>
      Map<String, dynamic>.from(
        await _call('get_dispute', {'p_id': id, 'p_admin': admin}) as Map,
      );
  @override
  Future<List<Map<String, dynamic>>> history(String id, bool admin) async =>
      _rows(await _call('get_dispute_history', {'p_id': id, 'p_admin': admin}));
  @override
  Future<List<Map<String, dynamic>>> evidence(String id, bool admin) async =>
      _rows(
        await _call('list_dispute_evidence', {
          'p_dispute_id': id,
          'p_admin': admin,
        }),
      );
  @override
  Future<List<Map<String, dynamic>>> evidenceHistory(
    String id,
    bool admin,
  ) async => _rows(
    await _call('list_dispute_evidence_history', {
      'p_dispute_id': id,
      'p_admin': admin,
    }),
  );
  @override
  Future<String> submit(
    String category,
    String relatedId,
    String description,
  ) async => (await _call('submit_dispute', {
    'p_category': category,
    'p_related_id': relatedId,
    'p_description': description,
  })) as String;
  @override
  Future<String> action(String id, String action, String note) async =>
      (await _call('act_on_dispute', {
        'p_id': id,
        'p_action': action,
        'p_note': note,
      })) as String;

  @override
  Future<void> uploadEvidence(
    String disputeId,
    String evidenceId,
    String name,
    Uint8List bytes,
  ) async {
    _check();
    final mime = validateDisputeEvidence(name, bytes);
    final path = await _call('prepare_dispute_evidence', {
      'p_dispute_id': disputeId,
      'p_evidence_id': evidenceId,
      'p_original_name': name,
      'p_mime_type': mime,
      'p_size_bytes': bytes.length,
    });
    if (path is! String || path.isEmpty) {
      throw const FormatException('Unable to prepare dispute evidence.');
    }
    try {
      await client.storage
          .from('jobmate-dispute-evidence')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
    } on StorageException catch (error) {
      final duplicate =
          error.statusCode == '409' ||
          error.error == 'Duplicate' ||
          error.error == 'ResourceAlreadyExists';
      if (!duplicate) rethrow;
    }
    _check();
    final saved = await _call('finalize_dispute_evidence', {
      'p_evidence_id': evidenceId,
    });
    if (saved != evidenceId) {
      throw const FormatException('Unable to confirm dispute evidence.');
    }
  }

  @override
  Future<Uri> evidenceUrl(String path) async {
    _check();
    if (path.trim().isEmpty) throw StateError('Evidence path is missing.');
    final url = await client.storage
        .from('jobmate-dispute-evidence')
        .createSignedUrl(path, 60);
    _check();
    return Uri.parse(url);
  }
}
