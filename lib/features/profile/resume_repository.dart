import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class ResumeFile {
  const ResumeFile({
    required this.id,
    required this.path,
    required this.name,
    required this.size,
    required this.bucket,
    required this.uploadedAt,
    this.legacy = false,
  });
  final String id, path, name, bucket;
  final int size;
  final DateTime? uploadedAt;
  final bool legacy;

  factory ResumeFile.fromJson(Map<String, dynamic> value) => ResumeFile(
    id: value['resume_id'] as String,
    path: value['storage_path'] as String,
    name: value['original_name'] as String,
    size: (value['size_bytes'] as num).toInt(),
    bucket: value['bucket_id'] as String,
    uploadedAt: DateTime.tryParse(value['uploaded_at']?.toString() ?? ''),
    legacy: value['legacy'] == true,
  );
}

class ResumeUpload {
  ResumeUpload({required this.id, required this.name, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes);
  final String id, name;
  final Uint8List bytes;
}

void validateResume(String name, Uint8List bytes) {
  if (name.trim().isEmpty || name.runes.length > 255) {
    throw const FormatException('Use a filename of 1 to 255 characters.');
  }
  if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
    throw const FormatException('Choose a non-empty PDF of at most 5 MiB.');
  }
  // A basic header check, not a complete PDF parser or malware scan.
  if (!name.toLowerCase().endsWith('.pdf') ||
      String.fromCharCodes(bytes.take(5)) != '%PDF-') {
    throw const FormatException('Choose a PDF resume.');
  }
}

abstract class ResumeGateway {
  Future<Map<String, dynamic>> loadAccount();
  Future<List<ResumeFile>> list();
  Future<void> upload(ResumeUpload file);
  Future<void> save(ResumeUpload file);
  Future<Uri> documentUrl(ResumeFile file);
  void checkSession();
}

class SupabaseResumeGateway implements ResumeGateway {
  SupabaseResumeGateway(this.client) : actorId = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? actorId;

  @override
  void checkSession() {
    if (actorId == null || client.auth.currentUser?.id != actorId) {
      throw StateError(
        'Your account changed. Reopen this page and sign in again.',
      );
    }
  }

  String _path(ResumeUpload file) => '$actorId/${file.id}/document.pdf';

  @override
  Future<Map<String, dynamic>> loadAccount() async {
    checkSession();
    final profile = await client
        .from('users')
        .select('role, status')
        .eq('user_id', actorId!)
        .single();
    checkSession();
    return profile;
  }

  @override
  Future<List<ResumeFile>> list() async {
    checkSession();
    final data = await client.rpc(
      'list_personal_resumes',
      params: {'p_limit': 10},
    );
    checkSession();
    if (data is! List) throw const FormatException('Invalid resume list.');
    return data
        .map(
          (row) => ResumeFile.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<void> upload(ResumeUpload file) async {
    checkSession();
    validateResume(file.name, file.bytes);
    try {
      await client.storage
          .from('jobmate-resumes')
          .uploadBinary(
            _path(file),
            file.bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: false,
            ),
          );
    } on StorageException catch (error) {
      if (error.statusCode != '409' &&
          error.error != 'Duplicate' &&
          error.error != 'ResourceAlreadyExists') {
        rethrow;
      }
    }
    checkSession();
  }

  @override
  Future<void> save(ResumeUpload file) async {
    checkSession();
    final id = await client.rpc(
      'save_personal_resume',
      params: {
        'p_resume_id': file.id,
        'p_storage_path': _path(file),
        'p_original_name': file.name,
      },
    );
    checkSession();
    if (id != file.id) {
      throw const FormatException('Unable to confirm the saved resume.');
    }
  }

  @override
  Future<Uri> documentUrl(ResumeFile file) async {
    checkSession();
    if (!['jobmate-resumes', 'jobmate-verification'].contains(file.bucket) ||
        !file.path.startsWith('$actorId/')) {
      throw StateError('This resume is not available to your account.');
    }
    final url = await client.storage
        .from(file.bucket)
        .createSignedUrl(file.path, 60);
    checkSession();
    return Uri.parse(url);
  }
}
