import 'package:supabase_flutter/supabase_flutter.dart';

import '../profile/resume_repository.dart';

abstract class JobApplicationGateway {
  String? get actorId;
  Stream<String?> get accountChanges;
  void checkSession();
  Future<List<ResumeFile>> listResumes();
  Future<String> submit(String jobId, {String? resumeId, String? coverNote});
}

class SupabaseJobApplicationGateway implements JobApplicationGateway {
  SupabaseJobApplicationGateway(this.client)
    : actorId = client.auth.currentUser?.id,
      resumes = SupabaseResumeGateway(client);
  final SupabaseClient client;
  final ResumeGateway resumes;
  @override
  final String? actorId;
  @override
  Stream<String?> get accountChanges =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);
  @override
  void checkSession() {
    resumes.checkSession();
  }

  @override
  Future<List<ResumeFile>> listResumes() async {
    checkSession();
    final account = await resumes.loadAccount();
    checkSession();
    if (account['role'] != 'job_seeker' || account['status'] != 'active') {
      throw StateError('An active Job Seeker account is required to apply.');
    }
    return resumes.list();
  }

  @override
  Future<String> submit(
    String jobId, {
    String? resumeId,
    String? coverNote,
  }) async {
    checkSession();
    if ((coverNote?.length ?? 0) > 1000) {
      throw StateError('Keep the cover note within 1,000 characters.');
    }
    final note = coverNote?.trim();
    final id = await client.rpc(
      'submit_job_application',
      params: {
        'p_job_id': jobId,
        'p_resume_id': resumeId,
        'p_cover_note': note == null || note.isEmpty ? null : note,
      },
    );
    checkSession();
    if (id is! String || id.isEmpty) {
      throw StateError(
        'Unable to confirm submission. Refresh before retrying.',
      );
    }
    return id;
  }
}

String jobApplicationError(Object failure) {
  if (failure is StateError) return failure.message.toString();
  if (failure is PostgrestException) {
    if (failure.code == '23505') {
      return 'You have already applied for this job.';
    }
    if (failure.code == '42501') {
      return 'Permission denied. An active Job Seeker account and your own resume are required.';
    }
    return failure.message;
  }
  return 'Unable to confirm submission. Your note is preserved. A retry may report an existing application if the first request succeeded.';
}
