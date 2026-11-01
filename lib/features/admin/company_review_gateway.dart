import 'package:supabase_flutter/supabase_flutter.dart';

/// The review page has no direct table-write capability.
abstract class CompanyReviewGateway {
  void checkSession();
  Future<List<Map<String, dynamic>>> pending({
    required int limit,
    required int offset,
  });
  Future<String> review({
    required String requestId,
    required String decision,
    String? comment,
  });
  Future<Uri> documentUrl(String path, {required bool download});
}

class SupabaseCompanyReviewGateway implements CompanyReviewGateway {
  SupabaseCompanyReviewGateway(this.client)
    : _actorId = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _actorId;

  @override
  void checkSession() {
    if (_actorId == null || client.auth.currentUser?.id != _actorId) {
      throw StateError(
        'Your signed-in account has changed. Reopen Company Verification.',
      );
    }
  }

  @override
  Future<List<Map<String, dynamic>>> pending({
    required int limit,
    required int offset,
  }) async {
    checkSession();
    final result = await client.rpc(
      'list_company_review_requests',
      params: {'p_limit': limit, 'p_offset': offset},
    );
    checkSession();
    if (result is! List) {
      throw const FormatException('Unexpected company review response.');
    }
    return result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<String> review({
    required String requestId,
    required String decision,
    String? comment,
  }) async {
    checkSession();
    final trimmed = comment?.trim();
    if (decision != 'verified' && decision != 'rejected') {
      throw ArgumentError('Invalid review decision.');
    }
    if (decision == 'rejected' && (trimmed == null || trimmed.isEmpty)) {
      throw ArgumentError('A rejection reason is required.');
    }
    if ((trimmed?.runes.length ?? 0) > 2000) {
      throw ArgumentError('Review comments must be 2000 characters or fewer.');
    }
    final result = await client.rpc(
      'review_company_request',
      params: {
        'p_request_id': requestId,
        'p_decision': decision,
        'p_review_comment': trimmed == null || trimmed.isEmpty ? null : trimmed,
      },
    );
    checkSession();
    if (result != decision) {
      throw const FormatException(
        'Unable to confirm the review result. Refresh the queue.',
      );
    }
    return result as String;
  }

  @override
  Future<Uri> documentUrl(String path, {required bool download}) async {
    checkSession();
    if (path.trim().isEmpty) {
      throw StateError('No supporting document is attached.');
    }
    final url = await client.storage
        .from('jobmate-company-verification')
        .createSignedUrl(
          path,
          60,
          download: download ? DownloadBehavior.withOriginalName : null,
        );
    checkSession();
    return Uri.parse(url);
  }
}
