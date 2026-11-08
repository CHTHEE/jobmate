# C3 final evidence and isolated PostgreSQL test status

**DRAFT / NOT APPROVED FOR DEPLOYMENT. No remote database access.**

## Evidence integration: PASS (local metadata validation)

Source located as `C:\Users\theec\Desktop\jobmate_final_evidence.txt.txt`, 9,983
bytes. One CSV evidence cell parses as JSON with both found flags true.

- final_evidence_snapshot.json preserves the 19 added objects with source hash:
  2 relations, 8 constraints, 3 indexes, 6 internal FK triggers. No custom trigger
  or enum/domain object is returned for these two tables.
- combined_evidence_snapshot.json contains all 110 objects and the original
  snapshot hash. evidence_snapshot.json is unchanged and retains its 91 objects.
- History INSERT columns are application_id UUID, previous_status TEXT,
  new_status TEXT, changed_by UUID. Omitted history_id has gen_random_uuid(),
  changed_at has now(), note is nullable. Hired/declined/withdrawn are allowed.
- Notification INSERT columns user_id UUID, notification_type/title/message TEXT
  match. Omitted notification_id has gen_random_uuid(), created_at has now(),
  read_at is nullable. There is no notification-type check in this result.
- FKs match the referenced application/user identities. History application FK
  cascades; notification user FK cascades. These existing definitions are retained.
- notifications ACL has postgres/service_role access only; history has broader
  API ACLs with RLS enabled. Policies are absent in this export, not guessed.

The two original INSERT blocks therefore have column/default/constraint coverage
in real metadata. This is NOT proof of successful execution, atomicity or concurrency.

## Actual database attempt: BLOCKED before any test SQL

PostgreSQL binaries are installed at `C:\Program Files\PostgreSQL\18\bin` and
postgres --version reports PostgreSQL 18.6. There is no suitable complete local
installation for a fresh disposable cluster:

1. Sandboxed initdb failed creating its restricted token (Windows error 87).
2. An approved outside-sandbox retry failed because
   `C:/Program Files/PostgreSQL/18/share/postgres.bki` does not exist. The share
   directory is absent. No local server started and no fixture/test SQL ran.

No existing PostgreSQL service/database was connected to. No remote connection,
credentials, installation or download was attempted. Failed temporary directories
were retained, not deleted. The runner now checks bootstrap availability before
attempting initialization, and accepts no remote host/connection-string parameter.

## Prepared but UNRUN cases

| Case | Status |
| --- | --- |
| Fresh authenticated Offered -> Hired, one ordinary membership | UNRUN |
| Account role unchanged and can_manage_company_jobs denies worker | UNRUN |
| Replay produces one receipt/history/notification | UNRUN |
| Same worker hired into two different companies | UNRUN |
| Inactive/revoked conflict preserves Offered and membership lifecycle | UNRUN |
| Replay after later revocation does not reactivate | UNRUN |
| Decline/withdraw behavior, timestamps and original employer notifications | UNRUN |
| Forced member/history/notification write failures roll back all writes | UNRUN |
| Independent Owner-company and Owner-user uniqueness plus account-role guard | UNRUN |
| Two authenticated acceptance sessions; observed row-lock wait; one side effect each | UNRUN |

No simulated result is reported as a passed PostgreSQL test. PowerShell AST,
metadata validation, draft-preservation assertions and whitespace checks are the
only successful tests in this pass.

## Disposable harness scope and limitations

`local_tests/run_disposable.ps1` creates a unique temp cluster, binds only
127.0.0.1 on a selected port and creates jobmate_c3_disposable there. It uses
explicit host/port/user/db flags, never a remote connection string. Any started
server is stopped in finally; no cluster or repository file is deleted.

It prepares exact exported columns/defaults and all 40 exported constraints for
seven relations, original membership indexes and the original Owner/acceptance/
management functions with API EXECUTE ACLs. Only copied test SQL omits the draft
exception; the three original review files remain byte-checked with guards intact.

Supabase auth.uid, auth.users, personal_resumes and the enum label sets are
explicit synthetic support fixtures. JWT verification is NOT implemented:
request.jwt.claim.sub is a local test setting. Unrelated application triggers,
full RLS policies, Storage, KZ onboarding/Admin and Module 4/evaluation execution
are NOT reconstructed or claimed tested. Only the management helper is extracted
from 03; full policy migration remains untested. This harness would establish
focused local acceptance behavior, not live Supabase release readiness.

## Next action and remaining production gates

Provide a complete local PostgreSQL distribution matching the chosen test version
(including share/postgres.bki and supporting files), or approve a separately
identified disposable local environment. Then run the prepared harness and
address actual SQL/runtime failures. No shared database testing is required.

History/notification source is no longer an evidence blocker. Remaining CH/KZ
production gates are exact onboarding/Admin/alternate-Hired-writer source and
compatibility patches; lifecycle-aware Module 4/evaluation/affected policy-helper
source and regressions; schema/default-privilege/dependency review; approval of
existing-row lifecycle initialization, retention/reactivation and legacy Hired
handling; Owner safeguard corrections; real authorization/concurrency evidence;
coordinated old-client cutover, non-destructive recovery, exact artifacts/window
and explicit CH/KZ deployment approval. Flutter activation remains disabled.
