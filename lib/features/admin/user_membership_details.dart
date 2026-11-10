import 'package:flutter/foundation.dart';

/// Groups the existing authorized RPC's membership rows without discarding any.
/// Rejects differing account fields or another user's records, rather than
/// assuming that a multi-row response is safe to merge.
Map<String, dynamic>? normalizeUserMembershipDetails(
  Object? result,
  String userId,
) {
  if (result is! List) {
    throw const FormatException('Unexpected account details.');
  }
  if (result.isEmpty) return null;
  const companyFields = {'company_id', 'company_name', 'member_role'};
  Map<String, dynamic>? account;
  final memberships = <Map<String, dynamic>>[];
  final companies = <String>{};
  for (final raw in result) {
    if (raw is! Map) throw const FormatException('Invalid account row.');
    final row = Map<String, dynamic>.from(raw);
    if (row['user_id'] != userId) {
      throw const FormatException('Unexpected account scope.');
    }
    final fields = Map<String, dynamic>.from(row)
      ..removeWhere((key, _) => companyFields.contains(key));
    if (account != null && !mapEquals(account, fields)) {
      throw const FormatException('Inconsistent account details.');
    }
    account = fields;
    final companyId = row['company_id'];
    if (companyId == null) {
      if (result.length != 1 ||
          row['member_role'] != null ||
          row['company_name'] != null) {
        throw const FormatException('Invalid empty membership.');
      }
    } else {
      if (companyId is! String ||
          companyId.isEmpty ||
          !companies.add(companyId) ||
          !const ['owner', 'employer', 'member'].contains(row['member_role'])) {
        throw const FormatException('Invalid or duplicate membership.');
      }
      memberships.add({for (final key in companyFields) key: row[key]});
    }
  }
  return {
    ...account!,
    // Retain legacy single-company presentation for existing consumers.
    for (final key in companyFields)
      key: memberships.length == 1 ? memberships.single[key] : null,
    'memberships': memberships,
  };
}
