import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Local debug opt-in only. Release/profile builds remain on the existing path
// even if the define is supplied; production cutover requires an explicit
// reviewed code change.
const structuredDisputeFinalizationEnabled =
    kDebugMode &&
    bool.fromEnvironment(
      'ENABLE_STRUCTURED_DISPUTE_FINALIZATION',
      defaultValue: false,
    );

// Related Cases is an independent, debug-only opt-in. Supplying the define to
// a profile or release build cannot enable the feature.
const relatedCasesEnabled =
    kDebugMode &&
    bool.fromEnvironment('ENABLE_RELATED_CASES', defaultValue: false);

// Historical classification remains an explicit local Debug opt-in. Release
// and profile builds cannot enable it by supplying the define alone.
const historicalClassificationEnabled =
    kDebugMode &&
    bool.fromEnvironment(
      'ENABLE_HISTORICAL_CLASSIFICATION',
      defaultValue: false,
    );

// Grouped Admin pagination requires the separately reviewed Step 11B RPC.
// Keep it opt-in until that additive read-only contract is deployed.
const groupedDisputeListEnabled =
    kDebugMode &&
    bool.fromEnvironment('ENABLE_GROUPED_DISPUTE_LIST', defaultValue: false);

enum DisputeFindingOutcome {
  jobSeekerAtFault('job_seeker_at_fault', 'Job Seeker at fault'),
  employerAtFault('employer_at_fault', 'Employer at fault'),
  bothAtFault('both_at_fault', 'Both parties at fault'),
  noViolation('no_violation', 'No violation'),
  resolvedByAgreement('resolved_by_agreement', 'Resolved by agreement'),
  inconclusive('inconclusive', 'Inconclusive');

  const DisputeFindingOutcome(this.value, this.label);

  final String value;
  final String label;

  bool get allowedForReject =>
      this == DisputeFindingOutcome.noViolation ||
      this == DisputeFindingOutcome.inconclusive;
}

Map<String, dynamic> disputeFinalizationRpcParams({
  required String disputeId,
  required DisputeFindingOutcome outcome,
  required String reason,
  required String terminalAction,
}) {
  final trimmedReason = reason.trim();
  if (disputeId.isEmpty ||
      !const {'resolve', 'reject'}.contains(terminalAction) ||
      trimmedReason.isEmpty ||
      trimmedReason.runes.length > 2000 ||
      (terminalAction == 'reject' && !outcome.allowedForReject)) {
    throw const FormatException('Invalid structured dispute finalization.');
  }
  return {
    'p_dispute_id': disputeId,
    'p_outcome': outcome.value,
    'p_reason': trimmedReason,
    'p_terminal_action': terminalAction,
  };
}

Map<String, dynamic> disputeIncidentLinkRpcParams({
  required String disputeId,
  required String? incidentId,
  required String reason,
}) {
  final trimmedIncidentId = incidentId?.trim();
  final trimmedReason = reason.trim();
  if (disputeId.isEmpty ||
      (incidentId != null && trimmedIncidentId!.isEmpty) ||
      trimmedReason.isEmpty ||
      trimmedReason.runes.length > 2000) {
    throw const FormatException('Invalid dispute incident link.');
  }
  return {
    'p_dispute_id': disputeId,
    'p_incident_id': trimmedIncidentId,
    'p_reason': trimmedReason,
  };
}

Map<String, dynamic> relatedCaseRpcParams({
  required String sourceDisputeId,
  required String targetIncidentId,
  required String reason,
}) {
  final disputeId = sourceDisputeId.trim();
  final incidentId = targetIncidentId.trim();
  final trimmedReason = reason.trim();
  if (disputeId.isEmpty ||
      incidentId.isEmpty ||
      trimmedReason.isEmpty ||
      trimmedReason.runes.length > 2000) {
    throw const FormatException('Invalid Related Case request.');
  }
  return {
    'p_source_dispute_id': disputeId,
    'p_target_incident_id': incidentId,
    'p_reason': trimmedReason,
  };
}

Map<String, dynamic> historicalClassificationRpcParams({
  required String disputeId,
  required DisputeFindingOutcome outcome,
  required String reason,
}) {
  final trimmedDisputeId = disputeId.trim();
  final trimmedReason = reason.trim();
  if (trimmedDisputeId.isEmpty ||
      trimmedReason.isEmpty ||
      trimmedReason.runes.length > 2000) {
    throw const FormatException('Invalid historical finding classification.');
  }
  return {
    'p_dispute_id': trimmedDisputeId,
    'p_outcome': outcome.value,
    'p_reason': trimmedReason,
  };
}

Map<String, dynamic> groupedDisputeListRpcParams({
  required String? search,
  required String? category,
  required String? status,
  required int limit,
  required int offset,
}) {
  final trimmedSearch = search?.trim();
  if (limit < 1 ||
      limit > 100 ||
      offset < 0 ||
      (trimmedSearch != null && trimmedSearch.runes.length > 100) ||
      (category != null &&
          !const {'recruitment', 'work', 'payment'}.contains(category)) ||
      (status != null &&
          !const {
            'open',
            'investigating',
            'pending_information',
            'resolved',
            'rejected',
          }.contains(status))) {
    throw const FormatException('Invalid grouped Dispute list filters.');
  }
  return {
    'p_search': trimmedSearch == null || trimmedSearch.isEmpty
        ? null
        : trimmedSearch,
    'p_category': category,
    'p_status': status,
    'p_limit': limit,
    'p_offset': offset,
  };
}

List<Map<String, dynamic>> relatedCaseRowsFromRpc(dynamic result) {
  if (result == null) return const [];
  if (result is! List) {
    throw const FormatException('Related Cases RPC returned a non-list value.');
  }
  return result
      .map((value) {
        if (value is! Map) {
          throw const FormatException(
            'Related Cases RPC returned an invalid row.',
          );
        }
        final row = Map<String, dynamic>.from(value);
        final incidentId = row['incident_id'];
        if (incidentId is! String || incidentId.isEmpty) {
          throw const FormatException('Related Case Incident ID is missing.');
        }
        dynamic rawStatuses = row['statuses'];
        if (rawStatuses is String) {
          try {
            rawStatuses = jsonDecode(rawStatuses);
          } on FormatException {
            throw const FormatException(
              'Related Case statuses are invalid JSON.',
            );
          }
        }
        if (rawStatuses != null && rawStatuses is! List) {
          throw const FormatException('Related Case statuses are invalid.');
        }
        final statuses = rawStatuses == null
            ? <String>[]
            : (rawStatuses as List)
                  .where((status) => status != null)
                  .map((status) => status.toString())
                  .toList(growable: false);
        final count = row['dispute_count'];
        return <String, dynamic>{
          'incident_id': incidentId,
          'category': row['category']?.toString() ?? 'Unknown',
          'statuses': statuses,
          'dispute_count': count is num ? count.toInt() : 0,
        };
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> groupedDisputeRowsFromRpc(dynamic result) {
  if (result is! List) {
    throw const FormatException(
      'Grouped Dispute RPC returned a non-list value.',
    );
  }
  return result
      .map((value) {
        if (value is! Map) {
          throw const FormatException(
            'Grouped Dispute RPC returned an invalid row.',
          );
        }
        final row = Map<String, dynamic>.from(value);
        final entryKey = row['entry_key'];
        final statusSummary = row['status_summary'];
        final disputeCount = row['dispute_count'];
        final totalCount = row['total_count'];
        final totalDisputeCount = row['total_dispute_count'];
        dynamic rawCategories = row['categories'];
        dynamic rawChildren = row['children'];
        if (rawCategories is String) rawCategories = jsonDecode(rawCategories);
        if (rawChildren is String) rawChildren = jsonDecode(rawChildren);
        if (entryKey is! String ||
            entryKey.isEmpty ||
            statusSummary is! String ||
            disputeCount is! num ||
            totalCount is! num ||
            totalDisputeCount is! num ||
            rawCategories is! List ||
            rawChildren is! List ||
            rawChildren.isEmpty) {
          throw const FormatException('Grouped Dispute RPC row is incomplete.');
        }
        final children = rawChildren
            .map((child) {
              if (child is! Map) {
                throw const FormatException(
                  'Grouped Dispute child is invalid.',
                );
              }
              final mapped = Map<String, dynamic>.from(child);
              if (mapped['dispute_id'] is! String ||
                  mapped['category'] is! String ||
                  mapped['status'] is! String ||
                  mapped['created_at'] is! String) {
                throw const FormatException(
                  'Grouped Dispute child is incomplete.',
                );
              }
              final incidentId = mapped['incident_id'];
              if (incidentId != null && incidentId is! String) {
                throw const FormatException(
                  'Grouped Dispute Incident ID is invalid.',
                );
              }
              return mapped;
            })
            .toList(growable: false);
        if (children.length != disputeCount.toInt()) {
          throw const FormatException(
            'Grouped Dispute count does not match children.',
          );
        }
        return <String, dynamic>{
          'entry_key': entryKey,
          'related_group_id': row['related_group_id']?.toString(),
          'categories': rawCategories.map((value) => value.toString()).toList(),
          'status_summary': statusSummary,
          'dispute_count': disputeCount.toInt(),
          'latest_created_at': row['latest_created_at']?.toString(),
          'children': children,
          'total_count': totalCount.toInt(),
          'total_dispute_count': totalDisputeCount.toInt(),
        };
      })
      .toList(growable: false);
}

void _debugDisputeFailure(String operation, Object error) {
  if (!kDebugMode) return;
  if (error is PostgrestException) {
    debugPrint(
      'JobMate dispute RPC failed [$operation]: '
      'code=${error.code}; message=${error.message}; '
      'details=${error.details}; hint=${error.hint}',
    );
    return;
  }
  debugPrint(
    'JobMate dispute operation failed [$operation]: ${error.runtimeType}',
  );
}

abstract interface class DisputeGateway {
  Future<List<Map<String, dynamic>>> list(
    bool admin, {
    required int limit,
    required int offset,
  });
  Future<List<Map<String, dynamic>>> groupedAdminList({
    required String? search,
    required String? category,
    required String? status,
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
  Future<Map<String, dynamic>> incidentCase(String id);
  Future<List<Map<String, dynamic>>> relatedCaseCandidates(String disputeId);
  Future<List<Map<String, dynamic>>> relatedCases(String disputeId);
  Future<String> linkRelatedCase(
    String sourceDisputeId, {
    required String targetIncidentId,
    required String reason,
  });
  Future<String> removeRelatedCase(
    String sourceDisputeId, {
    required String targetIncidentId,
    required String reason,
  });
  Future<String> linkIncident(
    String disputeId, {
    required String? incidentId,
    required String reason,
  });
  Future<Map<String, dynamic>> finalize(
    String id,
    DisputeFindingOutcome outcome,
    String reason,
    String terminalAction,
  );
  Future<Map<String, dynamic>> classifyHistoricalFinding(
    String disputeId,
    DisputeFindingOutcome outcome,
    String reason,
  );
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

  Future<dynamic> _call(
    String name,
    Map<String, dynamic> params, {
    bool diagnose = false,
  }) async {
    try {
      _check();
      final result = await client.rpc(name, params: params);
      _check();
      return result;
    } catch (error) {
      if (diagnose) _debugDisputeFailure(name, error);
      rethrow;
    }
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
  Future<List<Map<String, dynamic>>> groupedAdminList({
    required String? search,
    required String? category,
    required String? status,
    required int limit,
    required int offset,
  }) async {
    const operation = 'list_admin_dispute_groups_v1';
    final result = await _call(
      operation,
      groupedDisputeListRpcParams(
        search: search,
        category: category,
        status: status,
        limit: limit,
        offset: offset,
      ),
      diagnose: true,
    );
    try {
      return groupedDisputeRowsFromRpc(result);
    } catch (error) {
      _debugDisputeFailure('$operation response', error);
      rethrow;
    }
  }

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
  Future<Map<String, dynamic>> incidentCase(String id) async =>
      Map<String, dynamic>.from(
        await _call('get_dispute_case_v1', {'p_dispute_id': id}, diagnose: true)
            as Map,
      );

  @override
  Future<List<Map<String, dynamic>>> relatedCaseCandidates(
    String disputeId,
  ) async {
    const operation = 'list_related_case_candidates_v1';
    final result = await _call(operation, {
      'p_dispute_id': disputeId,
    }, diagnose: true);
    try {
      return relatedCaseRowsFromRpc(result);
    } catch (error) {
      _debugDisputeFailure('$operation response', error);
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> relatedCases(String disputeId) async {
    const operation = 'get_related_cases_v1';
    final result = await _call(operation, {
      'p_dispute_id': disputeId,
    }, diagnose: true);
    try {
      return relatedCaseRowsFromRpc(result);
    } catch (error) {
      _debugDisputeFailure('$operation response', error);
      rethrow;
    }
  }

  @override
  Future<String> linkRelatedCase(
    String sourceDisputeId, {
    required String targetIncidentId,
    required String reason,
  }) async => (await _call(
    'link_related_cases_v1',
    relatedCaseRpcParams(
      sourceDisputeId: sourceDisputeId,
      targetIncidentId: targetIncidentId,
      reason: reason,
    ),
  )) as String;

  @override
  Future<String> removeRelatedCase(
    String sourceDisputeId, {
    required String targetIncidentId,
    required String reason,
  }) async => (await _call(
    'remove_related_case_v1',
    relatedCaseRpcParams(
      sourceDisputeId: sourceDisputeId,
      targetIncidentId: targetIncidentId,
      reason: reason,
    ),
  )) as String;

  @override
  Future<String> linkIncident(
    String disputeId, {
    required String? incidentId,
    required String reason,
  }) async => (await _call(
    'link_dispute_incident_v1',
    disputeIncidentLinkRpcParams(
      disputeId: disputeId,
      incidentId: incidentId,
      reason: reason,
    ),
  )) as String;

  @override
  Future<Map<String, dynamic>> finalize(
    String id,
    DisputeFindingOutcome outcome,
    String reason,
    String terminalAction,
  ) async => Map<String, dynamic>.from(
    await _call(
      'finalize_dispute_finding_v1',
      disputeFinalizationRpcParams(
        disputeId: id,
        outcome: outcome,
        reason: reason,
        terminalAction: terminalAction,
      ),
      diagnose: true,
    ) as Map,
  );

  @override
  Future<Map<String, dynamic>> classifyHistoricalFinding(
    String disputeId,
    DisputeFindingOutcome outcome,
    String reason,
  ) async => Map<String, dynamic>.from(
    await _call(
      'classify_historical_dispute_finding_v1',
      historicalClassificationRpcParams(
        disputeId: disputeId,
        outcome: outcome,
        reason: reason,
      ),
    ) as Map,
  );

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
