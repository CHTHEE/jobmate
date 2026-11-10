/// Display/onboarding context only. Never establishes management authorization.
/// Prefer the single owned company; preserve a single legacy Employer context.
/// Ordinary affiliations never select an onboarding company.
Map<String, dynamic>? selectCompanyProfileMembership(
  List<Map<String, dynamic>> memberships,
) {
  final eligible = memberships.where((row) {
    final status = row['membership_status'];
    return (status == null || status == 'active') &&
        const ['owner', 'employer'].contains(row['member_role']);
  }).toList();
  final owners = eligible
      .where((row) => row['member_role'] == 'owner')
      .toList();
  final candidates = owners.isNotEmpty ? owners : eligible;
  if (candidates.length > 1) {
    throw const FormatException('Choose an explicit company context.');
  }
  if (candidates.isEmpty) return null;
  final selected = candidates.single;
  if (selected['company_id'] is! String ||
      (selected['company_id'] as String).isEmpty) {
    throw const FormatException('Invalid company context.');
  }
  return Map<String, dynamic>.unmodifiable(selected);
}
