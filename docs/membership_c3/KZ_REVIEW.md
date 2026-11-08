# KZ review checklist

**DRAFT / NOT APPROVED FOR DEPLOYMENT. No KZ application changes implemented.**

Actual-evidence update: see EVIDENCE_INTEGRATION.md and evidence_snapshot.json.
Acceptance notifies exactly job_postings.created_by, not all company members.
The supplied user trigger list omits jobmate_owner_must_remain_employer; the Owner
trigger also uses incorrect lowercase TG_OP comparisons. Review the proposed
account-role guard and uppercase correction in 01_schema.sql explicitly.
History/notification schemas and onboarding/Admin definitions are still absent
from this bundle; do not infer those contracts from checked-in SQL alone.

- [ ] Attach complete deployed submit_company_for_review and v2 bodies, including
  conflict targets and helper calls. Change user-only ownership lookup to explicit
  owner membership, not first membership or any-membership rejection. Keep one
  owned company and verification requirements. Owner of A may belong to B.
- [ ] `lib/features/company/create_company_page.dart` `_loadCompany`: owned-company
  onboarding selection; ordinary affiliations must not replace onboarding context.
- [ ] `lib/features/home/home_page.dart` `_loadAccountRole`: explicit authorized
  company selection, no user-only maybeSingle. No arbitrary LIMIT 1 fallback.
- [ ] `company_logo_editor.dart` `_checkOwnerAccess`: existing user+company lookup
  remains cardinality-safe; lifecycle and Owner checks stay authoritative.
- [ ] `get_managed_company`/`list_managed_companies` and profile/logo/document reads:
  preserve private-data projection, role/verification and selected-company scope.
- [ ] `get_user_account_details`: versioned one-account response with memberships
  array; preserve Admin permissions, account privacy and restriction history.
- [ ] `lib/features/admin/user_management_gateway.dart` `details` and
  `user_account_details_dialog.dart`: compatible versioned display, no weakening
  of the current >1-row error until new contract is installed.
- [ ] `company_management_gateway.dart`/`company_management_page.dart` and directory
  RPCs: lifecycle labels, accurate active vs historical counts, unchanged Admin
  visibility/permissions, no duplicated users or pagination corruption.
- [ ] Company/logo review conflict helpers: review ordinary AND historical
  affiliation scope separately from active operational membership.
- [ ] `lib/features/disputes/dispute_gateway.dart` RPCs and private evidence:
  preserve case parties, historical obligations and platform Admin scopes;
  ordinary membership alone never authorizes company disputes.
- [ ] Notification emitters/recipient helpers: no ordinary-member fan-out of
  private hiring/case messages; preserve actor/party notifications and deduping.
  `notifications_repository.dart` is read/mark-only and needs no enrollment writes.
- [ ] Owner/account trigger changes reviewed with KZ; preserve Owner immutability,
  Employer role and company creator audit fields, including new lifecycle fields.
- [ ] Shared navigation/main.dart changes, if needed later, receive separate
  approval. C3 does not enable delegated Job Seeker management routes.
- [ ] Verify old clients, URLs, Android/Web layouts and dirty-form guards during
  later implementation; no routing changes are included in this package.

KZ approval of this checklist is not production deployment authorization.
