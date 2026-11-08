enum HiringMembershipState { active, inactive, revoked, notRecorded }

/// Projection of the NEW candidate read RPC, not evidence of deployed support.
/// Membership role is displayed only; it never grants management authority.
class HiringMembershipSnapshot {
  HiringMembershipSnapshot.fromJson(
    Map<String, dynamic> row, {
    required String applicationId,
    required String userId,
  }) {
    if (row['contract_version'] != 1 ||
        row['application_id'] != applicationId ||
        row['user_id'] != userId ||
        row['company_id'] is! String ||
        (row['company_id'] as String).isEmpty ||
        row['acceptance_recorded'] is! bool) {
      throw const FormatException('Invalid hiring membership scope.');
    }
    companyId = row['company_id'] as String;
    acceptanceRecorded = row['acceptance_recorded'] as bool;
    role = row['member_role'] as String?;
    final status = row['membership_status'];
    if (status == null && role == null) {
      state = HiringMembershipState.notRecorded;
    } else {
      if (!const ['member', 'owner', 'employer'].contains(role)) {
        throw const FormatException('Invalid membership role.');
      }
      state = switch (status) {
        'active' => HiringMembershipState.active,
        'inactive' => HiringMembershipState.inactive,
        'revoked' => HiringMembershipState.revoked,
        _ => throw const FormatException('Invalid membership status.'),
      };
    }
  }

  late final String companyId;
  late final String? role;
  late final bool acceptanceRecorded;
  late final HiringMembershipState state;
}

abstract interface class HiringMembershipStatusSource {
  Future<HiringMembershipSnapshot> loadMembership(String applicationId);
}
