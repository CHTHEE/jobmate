import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../company/company_logo.dart';
import 'job_validation.dart';
import 'job_ai_formatter.dart';

class JobAccess {
  const JobAccess(this.company, this.message, {this.logo});
  final Uint8List? logo;
  final Map<String, dynamic>? company;
  final String? message;
  bool get allowed => company != null && message == null;
}

class JobPostingsRepository {
  JobPostingsRepository(this.client, {this.companyContext}) {
    if (companyContext != null && companyContext!.trim().isEmpty) {
      throw ArgumentError.value(companyContext, 'companyContext');
    }
  }
  final SupabaseClient client;

  /// Optional company identity for this repository's entire lifetime. This is
  /// selection, never authorization: existing account/membership checks and RPC
  /// authorization still apply. Omitted context retains the legacy unique-
  /// membership lookup, which fails closed on multiple rows. No selection is
  /// cached globally or inferred from an ordinary membership.
  final String? companyContext;

  bool get signedIn =>
      client.auth.currentSession != null && client.auth.currentUser != null;

  Future<Map<String, String>> formatDescription(String description) async {
    if (!signedIn) throw StateError('Sign in to use AI formatting.');
    final userId = client.auth.currentUser!.id;
    final response = await client.functions.invoke(
      'format-job-description',
      body: {'original_description': description.trim()},
    );
    if (!signedIn || client.auth.currentUser?.id != userId) {
      throw StateError(
        'Your session changed. Sign in again to use AI formatting.',
      );
    }
    if (response.status < 200 || response.status >= 300) {
      throw FunctionException(status: response.status);
    }
    return parseJobFormatting(response.data);
  }

  Future<JobAccess> loadAccess() async {
    final user = client.auth.currentUser;
    if (user == null) {
      return const JobAccess(null, 'Sign in to manage job postings.');
    }
    final profile = await client
        .from('users')
        .select('role, status')
        .eq('user_id', user.id)
        .single();
    if (profile['role'] != 'employer' || profile['status'] != 'active') {
      return const JobAccess(
        null,
        'An active employer account is required to manage jobs.',
      );
    }
    var membershipQuery = client
        .from('company_memberships')
        .select('company_id, member_role')
        .eq('user_id', user.id);
    if (companyContext != null) {
      membershipQuery = membershipQuery.eq('company_id', companyContext!);
    }
    final membership = await membershipQuery.maybeSingle();
    if (membership == null) {
      return const JobAccess(
        null,
        'Complete your existing company onboarding in Company profile before creating jobs.',
      );
    }
    final company = await client
        .from('companies')
        .select(
          'company_id, company_name, verification_status, logo_storage_path',
        )
        .eq('company_id', membership['company_id'])
        .single();
    if (!['owner', 'employer'].contains(membership['member_role'])) {
      return JobAccess(
        company,
        'Your company membership does not allow job management. Contact your company owner.',
      );
    }
    if (company['verification_status'] != 'verified') {
      return JobAccess(
        company,
        'Company verification: ${company['verification_status'] ?? 'not submitted'}. Open Company profile to review your verification status. Job creation is available after approval.',
      );
    }
    Uint8List? logo;
    try {
      logo = await loadCompanyLogo(
        client,
        company['logo_storage_path'] as String?,
      );
    } catch (_) {
      // A missing/inaccessible logo must not block job management.
    }
    return JobAccess(company, null, logo: logo);
  }

  Future<List<Map<String, dynamic>>> list(String companyId) async {
    if (companyContext != null && companyId != companyContext) {
      throw StateError('Company context changed. Reopen job postings.');
    }
    final rows = await client.rpc(
      'list_employer_job_postings',
      params: {'p_company_id': companyId},
    );
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> save(
    Map<String, dynamic> values, {
    String? jobId,
    String expectedStatus = 'draft',
  }) async {
    final access = await loadAccess();
    if (!access.allowed) throw StateError(access.message!);
    final companyId = access.company!['company_id'];
    final data = Map<String, dynamic>.from(values)
      ..remove('company_id')
      ..remove('created_by')
      ..remove('published_at')
      ..remove('created_at')
      ..remove('job_id');
    if (jobId != null && !['draft', 'published'].contains(expectedStatus)) {
      throw StateError('Closed jobs cannot be edited.');
    }
    if (jobId != null && expectedStatus == 'published') {
      final validation = jobPublishError(data);
      if (validation != null) throw StateError(validation);
      data['status'] = 'published';
    }
    if (jobId == null) data['ai_assisted'] = data['ai_assisted'] == true;
    // The RPC scopes ownership and compares status atomically. Keep updates
    // partial: publishing from the list sends only the status field.
    return await client
        .rpc(
          'save_employer_job_posting',
          params: {
            'p_company_id': companyId,
            'p_values': data,
            'p_job_id': jobId,
            'p_expected_status': expectedStatus,
          },
        )
        .single();
  }

  Future<void> close(String jobId) async {
    final access = await loadAccess();
    if (!access.allowed) throw StateError(access.message!);
    await client.rpc(
      'close_employer_job_posting',
      params: {
        'p_company_id': access.company!['company_id'],
        'p_job_id': jobId,
      },
    );
  }
}

List<String> jobLines(String value) => value
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList();

String jobError(Object error) {
  if (error is PostgrestException) {
    if (error.code == '42501') {
      return 'Permission denied. Check your employer membership and company verification, then refresh.';
    }
    if (error.code == 'PGRST116') {
      return 'This job may have changed or is no longer editable. Refresh and try again.';
    }
    return 'Unable to save or load jobs: ${error.message}';
  }
  if (error is StateError) return error.message.toString();
  return 'Unable to connect. Please try again.';
}
