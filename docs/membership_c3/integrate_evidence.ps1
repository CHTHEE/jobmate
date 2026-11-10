# DRAFT / NOT APPROVED FOR DEPLOYMENT.
# Local CSV/JSON transformation only. Does NOT execute SQL or connect to a DB.
param([Parameter(Mandatory=$true)][string]$EvidencePath)
$ErrorActionPreference = 'Stop'
$rows = @(Import-Csv -LiteralPath $EvidencePath)
if ($rows.Count -ne 1 -or -not $rows[0].evidence) { throw 'Expected one evidence CSV cell' }
$bundle = $rows[0].evidence | ConvertFrom-Json
if (-not $bundle.acceptance_found -or -not $bundle.membership_found) { throw 'Required object missing' }
$items = @($bundle.items)
$duplicates = @($items | Group-Object { $_.kind + ':' + $_.identity } | Where-Object Count -gt 1)
if ($duplicates.Count) { throw 'Duplicate evidence identities' }
foreach ($i in $items) {
  if ($i.kind -in @('function','constraint','index','trigger') -and -not $i.details.definition) { throw ('Missing definition: '+$i.identity) }
  if ($i.kind -eq 'function' -and -not $i.details.definition.TrimEnd().EndsWith('$function$')) {
    # pg_get_functiondef output in this bundle ends with $function$ + newline.
    throw ('Unexpected/truncated function ending: '+$i.identity)
  }
}
function Item([string]$kind,[string]$identity) {
  $matches = @($items | Where-Object { $_.kind -eq $kind -and $_.identity -eq $identity })
  if ($matches.Count -ne 1) { throw ('Expected exact evidence: '+$kind+' '+$identity) }
  return $matches[0]
}
function Replace-Once([string]$body,[string]$old,[string]$new) {
  $count = ([regex]::Matches($body,[regex]::Escape($old))).Count
  if ($count -ne 1) { throw ('Patch anchor count '+$count+': '+$old) }
  return $body.Replace($old,$new)
}
function Definition([string]$identity) {
  $i = Item 'function' $identity
  if ($i.details.owner -ne 'postgres' -or -not $i.details.security_definer -or
      $i.details.settings.Count -ne 1 -or $i.details.settings[0] -ne 'search_path=""') { throw 'Unexpected function security metadata' }
  return $i.details.definition.Replace("`r`n","`n").TrimEnd()+";`n"
}
$guard = @'
-- DRAFT / NOT APPROVED FOR DEPLOYMENT. UNEXECUTED REVIEW SQL.
-- Source/evidence/remaining release blockers: EVIDENCE_INTEGRATION.md.
-- Not deployable as a partial release. Intentional unconditional execution stop.
BEGIN;
SET LOCAL search_path = pg_catalog, public;
DO $c3_draft_guard$
BEGIN
  RAISE EXCEPTION 'DRAFT / NOT APPROVED FOR DEPLOYMENT: unresolved release gates';
END;
$c3_draft_guard$;

'@
$owner = Definition 'private.protect_jobmate_company_owner()'
if ((Item 'function' 'private.protect_jobmate_company_owner()').details.acl -ne '{postgres=X/postgres}') { throw 'Owner ACL drift' }
# PostgreSQL TG_OP is uppercase; original export compares lowercase literals.
# Correct those comparisons in this review patch rather than preserving the bug.
$owner = Replace-Once $owner "tg_op = 'delete'" "tg_op = 'DELETE'"
$owner = Replace-Once $owner "tg_op = 'update'" "tg_op = 'UPDATE'"
$owner = Replace-Once $owner '    return old;' "    raise exception 'Retain membership history; use lifecycle instead of deletion.';"
$owner = Replace-Once $owner "  if new.member_role = 'owner' then" @'
  if tg_op = 'UPDATE' then
    if new.user_id is distinct from old.user_id
       or new.company_id is distinct from old.company_id
       or new.created_at is distinct from old.created_at then
      raise exception 'Membership identity and creation history are immutable.';
    end if;
    if old.member_role <> 'owner' and new.member_role = 'owner' then
      raise exception 'Membership updates cannot create ownership.';
    end if;
    if old.membership_status in ('inactive','revoked')
       and new.membership_status = 'active' then
      raise exception 'Reactivation requires a separately reviewed workflow.';
    end if;
  end if;
  if new.member_role = 'owner' then
    if new.membership_status <> 'active' then
      raise exception 'A Company Owner must remain active.';
    end if;
'@
$owner = Replace-Once $owner '    where user_id = new.user_id;' '    where user_id = new.user_id for share;'
$schema = @'
-- PROPOSED mapping of all existing rows to active requires explicit CH/KZ approval.
LOCK TABLE public.company_memberships IN ACCESS EXCLUSIVE MODE;
DO $c3_preflight$
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Review requires postgres operator to preserve intended object ownership';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid='public.company_memberships'::regclass
      AND conname='company_memberships_pkey' AND contype='p'
      AND pg_catalog.pg_get_constraintdef(oid)='PRIMARY KEY (user_id)')
  THEN RAISE EXCEPTION 'Membership PK differs from evidence'; END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_constraint
    WHERE confrelid='public.company_memberships'::regclass AND contype='f')
  THEN RAISE EXCEPTION 'Unreviewed inbound membership FK'; END IF;
END;
$c3_preflight$;
ALTER TABLE public.company_memberships
  ADD COLUMN membership_status text NOT NULL DEFAULT 'active',
  ADD CONSTRAINT c3_membership_status_check
    CHECK(membership_status IN ('active','inactive','revoked'));
CREATE UNIQUE INDEX c3_one_owned_company_per_user_idx
  ON public.company_memberships(user_id) WHERE member_role='owner';
-- Retain jobmate_one_owner_per_company_idx and existing outbound CASCADE FKs.
ALTER TABLE public.company_memberships
  DROP CONSTRAINT company_memberships_pkey,
  ADD CONSTRAINT company_memberships_pkey PRIMARY KEY(company_id,user_id),
  DROP CONSTRAINT company_memberships_member_role_check,
  ADD CONSTRAINT company_memberships_member_role_check
    CHECK(member_role IN ('owner','employer','member'));

'@
$newObjects = @'
-- NEW proposed safeguard: exported users trigger list omits the checked-in
-- jobmate_owner_must_remain_employer trigger. Do not claim it is deployed.
-- KZ review + isolated Owner creation/account-role race tests are release gates.
CREATE FUNCTION private.c3_require_owner_employer_role()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  IF NEW.role::text IS DISTINCT FROM 'employer' AND EXISTS (
    SELECT 1 FROM public.company_memberships m
    WHERE m.user_id=OLD.user_id AND m.member_role='owner'
  ) THEN RAISE EXCEPTION 'A Company Owner must keep the Employer role.'; END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.c3_require_owner_employer_role()
  FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER c3_owner_must_remain_employer BEFORE UPDATE OF role ON public.users
  FOR EACH ROW EXECUTE FUNCTION private.c3_require_owner_employer_role();

-- NEW server-only receipt; new names are proposals, not deployed definitions.
CREATE TABLE private.hiring_membership_acceptances (
  application_id uuid PRIMARY KEY REFERENCES public.job_applications(application_id),
  company_id uuid NOT NULL,
  user_id uuid NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(company_id,user_id)
    REFERENCES public.company_memberships(company_id,user_id)
);
ALTER TABLE private.hiring_membership_acceptances ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.hiring_membership_acceptances FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.hiring_membership_acceptances
  FROM PUBLIC, anon, authenticated, service_role;
-- Intended reviewed operator/new object owner: postgres, matching original
-- SECURITY DEFINER owners. No ordinary role receives management or receipt access.
-- Receipt FKs do not cascade: retain hiring history; no backfill in this draft.
-- No client lifecycle/reactivation API is exposed. Audit/authorization for future
-- administrative lifecycle operations remains a separate approved contract.
COMMIT;
'@
[IO.File]::WriteAllText((Join-Path $PSScriptRoot '01_schema.sql'), $guard+$schema+$owner+$newObjects)

$acceptance = Definition 'public.respond_to_job_application(p_application_id uuid, p_action text)'
$expectedAcl = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
if ((Item 'function' 'public.respond_to_job_application(p_application_id uuid, p_action text)').details.acl -ne $expectedAcl) { throw 'Acceptance ACL drift' }
$acceptance = Replace-Once $acceptance '    v_new_status text;' @'
    v_new_status text;
    v_membership public.company_memberships%ROWTYPE;
'@
$acceptance = Replace-Once $acceptance '    -- Validate the requested action and current status.' @'
    -- C3 replay requires server-only provenance, not Hired status alone.
    -- Applicant authorization above is unchanged and precedes this early return.
    IF p_action = 'accept_offer' AND v_application.status = 'hired' THEN
        IF EXISTS (SELECT 1 FROM private.hiring_membership_acceptances r
                   WHERE r.application_id=p_application_id
                     AND r.user_id=v_actor_id) THEN
            RETURN 'hired'; -- Never reactivate a subsequently revoked pair.
        END IF;
        RAISE EXCEPTION 'Legacy Hired application requires reviewed reconciliation.';
    END IF;

    -- Validate the requested action and current status.
'@
$acceptance = Replace-Once $acceptance '    -- Update application.' @'
    -- C3 atomic enrollment. App lock above serializes same-offer replay.
    IF v_new_status = 'hired' THEN
        -- Re-read/lock job only on acceptance; decline/withdraw locking unchanged.
        SELECT * INTO v_job FROM public.job_postings j
        WHERE j.job_id=v_application.job_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Job posting not found.'; END IF;
        INSERT INTO public.company_memberships(user_id,company_id,member_role,membership_status)
        VALUES(v_actor_id,v_job.company_id,'member','active')
        ON CONFLICT(company_id,user_id) DO NOTHING;
        -- Separate statement sees a concurrently committed pair at READ COMMITTED.
        SELECT * INTO v_membership FROM public.company_memberships m
        WHERE m.company_id=v_job.company_id AND m.user_id=v_actor_id FOR UPDATE;
        IF NOT FOUND OR v_membership.membership_status IS DISTINCT FROM 'active' THEN
            RAISE EXCEPTION 'Inactive or revoked membership requires separate review.';
        END IF;
        -- Existing role/created_at/account role are never changed.
        INSERT INTO private.hiring_membership_acceptances(application_id,company_id,user_id)
        VALUES(p_application_id,v_job.company_id,v_actor_id);
    END IF;

    -- Update application.
'@
$acceptanceNotes = @'
-- ORIGINAL function patched at four exact anchors; original history/notification
-- SQL and decline/withdraw branches retained verbatim (line endings normalized).
-- History/notification schemas are now supplied in final_evidence_snapshot.json;
-- column/default/FK coverage passes. SQL/runtime tests remain unrun: local
-- PostgreSQL bootstrap files are missing. See ISOLATED_TEST_RESULTS.md.
-- New table/security/lifecycle predicates require 01 + coordinated 03/KZ rollout.
-- CREATE OR REPLACE retains exact original owner/ACL: postgres; authenticated
-- and service_role EXECUTE, no PUBLIC/anon. No existing grant is modified here.
-- Isolation above READ COMMITTED may raise serialization errors; no auto-retry.
-- Job/application/membership/lifecycle lock order needs isolated concurrency QA.

'@
[IO.File]::WriteAllText((Join-Path $PSScriptRoot '02_acceptance.sql'),$guard+$acceptanceNotes+$acceptance+"`nCOMMIT;`n")

$manage = Definition 'public.can_manage_company_jobs(p_company_id uuid)'
if ((Item 'function' 'public.can_manage_company_jobs(p_company_id uuid)').details.acl -ne $expectedAcl) { throw 'Management ACL drift' }
$manage = Replace-Once $manage '      and cm.company_id = p_company_id' "      and cm.company_id = p_company_id`n      and cm.membership_status = 'active'"
$auth = $guard + @'
-- PARTIAL evidence-backed patch only; not a complete authorization rollout.
-- Preserve existing routine OID/ACL/owner/settings; no legacy grant restoration.

'@ + $manage
$policyNames = @('public.companies.companies_select_internal',
  'public.company_logo_change_requests.company_logo_requests_read',
  'storage.objects.company_logos_insert','storage.objects.company_logos_select',
  'storage.objects.company_profile_logo_insert','storage.objects.company_verification_files_insert')
foreach ($name in $policyNames) {
  $p = Item 'policy' $name
  if ($p.details.permissive -ne 'PERMISSIVE' -or $p.details.roles.Count -ne 1 -or $p.details.roles[0] -ne 'authenticated') { throw 'Policy shape differs' }
  $parts=$name.Split('.')
  $using=$p.details.using
  $check=$p.details.check
  if ($name -eq 'public.companies.companies_select_internal') {
    $using=Replace-Once $using '(m.company_id = companies.company_id)' "(m.membership_status = 'active'::text) AND (m.company_id = companies.company_id)"
  } elseif ($name -eq 'public.company_logo_change_requests.company_logo_requests_read') {
    $using=Replace-Once $using "(m.member_role = 'owner'::text)" "(m.membership_status = 'active'::text) AND (m.member_role = 'owner'::text)"
  } elseif ($name -eq 'storage.objects.company_logos_select') {
    # Deliberately narrow only the affiliation branch; keep admin/own-path branches.
    $using=Replace-Once $using '(m.user_id = u.user_id)' "(m.membership_status = 'active'::text) AND (m.user_id = u.user_id)"
  } elseif ($name -eq 'storage.objects.company_profile_logo_insert') {
    $check=Replace-Once $check "(m.member_role = 'owner'::text)" "(m.membership_status = 'active'::text) AND (m.member_role = 'owner'::text)"
  } else {
    if ($name -in @('storage.objects.company_logos_insert','storage.objects.company_verification_files_insert')) {
      # Onboarding absence means no OWNED company, not no ordinary affiliation.
      $check=Replace-Once $check 'WHERE (m.user_id = u.user_id)' "WHERE ((m.user_id = u.user_id) AND (m.member_role = 'owner'::text))"
      # Do not let a Job Seeker's new ordinary affiliation open onboarding uploads.
      $check=Replace-Once $check "(u.status = 'active'::account_status)" "(u.status = 'active'::account_status) AND (u.role = 'employer'::user_role)"
    }
    $check=Replace-Once $check "(m.member_role = 'owner'::text) AND (c.verification_status" "(m.membership_status = 'active'::text) AND (m.member_role = 'owner'::text) AND (c.verification_status"
  }
  # Profile upload has no rejected-company branch; add lifecycle there separately.
  $statement="`n-- Original command/roles/permissive mode retained; other policies untouched.`nALTER POLICY " + $parts[2] + ' ON ' + $parts[0]+'.'+$parts[1]
  if ($using) { $statement += "`n  USING ("+$using+')' }
  if ($check) { $statement += "`n  WITH CHECK ("+$check+')' }
  $auth += $statement+";`n"
}
$auth += @'

-- Unchanged: company_memberships_select permits own historical membership reads
-- and existing Admin reads; it confers no write/management grant. Original
-- membership ACL gives authenticated SELECT only, no anon grant.
-- Unchanged: company_verification_files_select historical conflict exclusion;
-- inactive affiliation is NOT automatically removed from conflict checks.
-- All 22 exported Storage policies are retained, including restrictive no-delete/
-- overwrite gates and original worker/private evidence policies.
-- BLOCKED: actual Module 4 inline checks, evaluation/dispute helper bodies,
-- onboarding/Admin replacements and private notification audiences are absent.
-- New member rows cannot be enabled until those compatibility gates are resolved.
COMMIT;
'@
[IO.File]::WriteAllText((Join-Path $PSScriptRoot '03_authorization.sql'),$auth)

$snapshot=[ordered]@{status='DRAFT / NOT APPROVED FOR DEPLOYMENT';source_file=(Split-Path $EvidencePath -Leaf);source_sha256=(Get-FileHash -LiteralPath $EvidencePath -Algorithm SHA256).Hash; evidence=$bundle}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'evidence_snapshot.json'),($snapshot | ConvertTo-Json -Depth 32))
$inventory=@('# Evidence inventory', '', '**DRAFT / NOT APPROVED FOR DEPLOYMENT.**', '', '| Kind | Exact identity |', '| --- | --- |')
$inventory += $items | ForEach-Object { '| '+$_.kind+' | `'+$_.identity+'` |' }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'EVIDENCE_INVENTORY.md'),($inventory -join "`n"))
Write-Output ('Validated '+$items.Count+' unique objects; review drafts generated locally; no SQL executed.')
