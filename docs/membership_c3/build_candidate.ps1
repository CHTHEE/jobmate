# DRAFT / NOT APPROVED FOR DEPLOYMENT. Local text assembly ONLY, no SQL execution.
$ErrorActionPreference='Stop'
$target=Join-Path $PSScriptRoot 'candidate'
New-Item -ItemType Directory -Path $target -Force | Out-Null
$sql=@'
-- DRAFT / NOT APPROVED FOR DEPLOYMENT. EXECUTABLE-FORMAT SUPPORTED CANDIDATE.
-- UNEXECUTED. Outside supabase/migrations. NOT a complete production release.
-- This NEW artifact assembles supported changes; original C3 guards remain intact.
-- BLOCKERS: KZ onboarding/Home/Admin; alternate Hired writers; full Module 4,
-- evaluation/dispute lifecycle compatibility; isolated SQL/security/concurrency QA.
-- Must not deploy independently or use Flutter flag as protection for old clients.
BEGIN;
SET LOCAL search_path = pg_catalog, public;
DO $candidate_approval_guard$
BEGIN
  IF pg_catalog.current_setting('jobmate.c3_candidate_approved',true)
       IS DISTINCT FROM 'explicit-ch-and-kz-approval' THEN
    RAISE EXCEPTION 'DRAFT / NOT APPROVED FOR DEPLOYMENT';
  END IF;
END;
$candidate_approval_guard$;
-- Proposed operator-only session acknowledgement is NOT evidence of approval.
-- It must not be supplied until exact artifacts, compatibility and tests are signed off.

'@
foreach ($name in @('01_schema.sql','02_acceptance.sql','03_authorization.sql')) {
  $body=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $name))
  $guard='(?s)DO \$c3_draft_guard\$.*?\$c3_draft_guard\$;'
  if ([regex]::Matches($body,$guard).Count -ne 1) { throw ('Missing original guard: '+$name) }
  $body=[regex]::Replace($body,$guard,'-- Original draft guard retained in SOURCE; this is a new review candidate.')
  $body=([regex]'(?m)^BEGIN;\r?\n').Replace($body,'',1)
  $body=[regex]::Replace($body,'COMMIT;\s*\z','')
  $sql+="`n-- Source: $name (exact function/policy bodies retained).`n"+$body+"`n"
}
$sql+=@'
-- NEW candidate contract for the flag-gated worker membership view.
-- Hired application scope belongs to caller; no management rights or mutation.
CREATE FUNCTION public.get_my_hiring_membership(p_application_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_company uuid;
  v_membership public.company_memberships%ROWTYPE;
  v_recorded boolean;
BEGIN
  IF v_actor IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.users u WHERE u.user_id=v_actor
      AND u.role='job_seeker'::public.user_role
      AND u.status='active'::public.account_status
  ) THEN RAISE EXCEPTION 'Application access denied.' USING ERRCODE='42501'; END IF;
  SELECT j.company_id INTO v_company
  FROM public.job_applications a JOIN public.job_postings j ON j.job_id=a.job_id
  WHERE a.application_id=p_application_id AND a.applicant_id=v_actor
    AND a.status='hired';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application access denied.' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_membership FROM public.company_memberships m
    WHERE m.company_id=v_company AND m.user_id=v_actor;
  SELECT EXISTS(SELECT 1 FROM private.hiring_membership_acceptances r
    WHERE r.application_id=p_application_id AND r.company_id=v_company
      AND r.user_id=v_actor) INTO v_recorded;
  RETURN pg_catalog.jsonb_build_object(
    'contract_version',1,'application_id',p_application_id,
    'company_id',v_company,'user_id',v_actor,
    'member_role',v_membership.member_role,
    'membership_status',v_membership.membership_status,
    'acceptance_recorded',v_recorded
  );
END;
$function$;
-- New object ACL, not a change to original EXECUTE grants.
REVOKE ALL ON FUNCTION public.get_my_hiring_membership(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_my_hiring_membership(uuid) TO authenticated;
COMMIT;
'@
[IO.File]::WriteAllText((Join-Path $target '001_hiring_membership_supported_candidate.sql'),$sql)
Write-Output 'Candidate text built. Original guarded SQL files unchanged. No SQL executed.'
