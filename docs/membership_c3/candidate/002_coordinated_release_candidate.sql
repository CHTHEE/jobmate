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

-- Coordinated release remains incomplete. Agreement in principle is not artifact approval.
DO $coordinated_release_stop$
BEGIN
 RAISE EXCEPTION 'DRAFT: evaluation source, remaining authorization coverage, historical source match, policy approval and database tests outstanding';
END;
$coordinated_release_stop$;
-- Source: 01_schema.sql (exact function/policy bodies retained).
-- DRAFT / NOT APPROVED FOR DEPLOYMENT. UNEXECUTED REVIEW SQL.
-- Source/evidence/remaining release blockers: EVIDENCE_INTEGRATION.md.
-- Not deployable as a partial release. Intentional unconditional execution stop.
SET LOCAL search_path = pg_catalog, public;
-- Original draft guard retained in SOURCE; this is a new review candidate.
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
CREATE OR REPLACE FUNCTION private.protect_jobmate_company_owner()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text;
begin
  if tg_op = 'DELETE' then
    if old.member_role = 'owner' then
      raise exception 'A Company Owner cannot be removed.'
        using errcode = 'P0001';
    end if;

    raise exception 'Retain membership history; use lifecycle instead of deletion.';
  end if;

  if tg_op = 'UPDATE'
     and old.member_role = 'owner'
     and (
       new.member_role is distinct from old.member_role
       or new.company_id is distinct from old.company_id
       or new.user_id is distinct from old.user_id
     ) then
    raise exception 'Company ownership cannot be transferred or changed.'
      using errcode = 'P0001';
  end if;

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
    select role::text
    into v_role
    from public.users
    where user_id = new.user_id for share;

    if v_role is distinct from 'employer' then
      raise exception 'Only an Employer can become a Company Owner.'
        using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$function$;
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


-- Source: 02_acceptance.sql (exact function/policy bodies retained).
-- DRAFT / NOT APPROVED FOR DEPLOYMENT. UNEXECUTED REVIEW SQL.
-- Source/evidence/remaining release blockers: EVIDENCE_INTEGRATION.md.
-- Not deployable as a partial release. Intentional unconditional execution stop.
SET LOCAL search_path = pg_catalog, public;
-- Original draft guard retained in SOURCE; this is a new review candidate.
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
CREATE OR REPLACE FUNCTION public.respond_to_job_application(p_application_id uuid, p_action text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_actor_id uuid := auth.uid();
    v_application public.job_applications%ROWTYPE;
    v_job public.job_postings%ROWTYPE;
    v_new_status text;
    v_membership public.company_memberships%ROWTYPE;
BEGIN
    -- Lock the application to prevent concurrent changes.
    SELECT *
    INTO v_application
    FROM public.job_applications a
    WHERE a.application_id = p_application_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Application not found.';
    END IF;

    -- Only the applicant may respond.
    IF v_actor_id IS NULL
       OR v_application.applicant_id <> v_actor_id
       OR NOT EXISTS (
           SELECT 1
           FROM public.users u
           WHERE u.user_id = v_actor_id
             AND u.role = 'job_seeker'::public.user_role
             AND u.status = 'active'::public.account_status
       )
    THEN
        RAISE EXCEPTION
            'You are not authorized to manage this application.';
    END IF;

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
    IF p_action = 'accept_offer'
       AND v_application.status = 'offered' THEN
        v_new_status := 'hired';

    ELSIF p_action = 'decline_offer'
       AND v_application.status = 'offered' THEN
        v_new_status := 'declined';

    ELSIF p_action = 'withdraw'
       AND v_application.status IN (
           'submitted',
           'shortlisted',
           'interview',
           'offered'
       ) THEN
        v_new_status := 'withdrawn';

    ELSE
        RAISE EXCEPTION
            'This action is not allowed for the current application status.';
    END IF;

    -- Retrieve job details for the notification.
    SELECT *
    INTO v_job
    FROM public.job_postings j
    WHERE j.job_id = v_application.job_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job posting not found.';
    END IF;

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
    UPDATE public.job_applications
    SET
        status = v_new_status,
        updated_at = now(),
        withdrawn_at = CASE
            WHEN v_new_status = 'withdrawn' THEN now()
            ELSE withdrawn_at
        END
    WHERE application_id = p_application_id;

    -- Record status history.
    INSERT INTO public.application_status_history (
        application_id,
        previous_status,
        new_status,
        changed_by
    )
    VALUES (
        p_application_id,
        v_application.status,
        v_new_status,
        v_actor_id
    );

    -- Notify the employer who created the job.
    INSERT INTO public.notifications (
        user_id,
        notification_type,
        title,
        message
    )
    VALUES (
        v_job.created_by,
        'application_' || v_new_status,
        'Application Response',
        'An applicant for '
            || v_job.title
            || ' has '
            || CASE v_new_status
                WHEN 'hired' THEN 'accepted the job offer'
                WHEN 'declined' THEN 'declined the job offer'
                WHEN 'withdrawn' THEN 'withdrawn their application'
               END
            || '.'
    );

    RETURN v_new_status;
END;
$function$;



-- Source: 03_authorization.sql (exact function/policy bodies retained).
-- DRAFT / NOT APPROVED FOR DEPLOYMENT. UNEXECUTED REVIEW SQL.
-- Source/evidence/remaining release blockers: EVIDENCE_INTEGRATION.md.
-- Not deployable as a partial release. Intentional unconditional execution stop.
SET LOCAL search_path = pg_catalog, public;
-- Original draft guard retained in SOURCE; this is a new review candidate.
-- PARTIAL evidence-backed patch only; not a complete authorization rollout.
-- Preserve existing routine OID/ACL/owner/settings; no legacy grant restoration.
CREATE OR REPLACE FUNCTION public.can_manage_company_jobs(p_company_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.users u
    join public.company_memberships cm
      on cm.user_id = u.user_id
    join public.companies c
      on c.company_id = cm.company_id
    where u.user_id = auth.uid()
      and u.role = 'employer'::public.user_role
      and u.status = 'active'::public.account_status
      and cm.company_id = p_company_id
      and cm.membership_status = 'active'
      and cm.member_role in ('owner', 'employer')
      and c.verification_status = 'verified'::public.verification_status
  );
$function$;

-- Original command/roles/permissive mode retained; other policies untouched.
ALTER POLICY companies_select_internal ON public.companies
  USING ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.user_id = ( SELECT auth.uid() AS uid)) AND (u.status = 'active'::account_status) AND ((EXISTS ( SELECT 1
           FROM company_memberships m
          WHERE ((m.membership_status = 'active'::text) AND (m.company_id = companies.company_id) AND (m.user_id = u.user_id)))) OR ((u.role = 'administrator'::user_role) AND (EXISTS ( SELECT 1
           FROM administrator_profiles ap
          WHERE ((ap.user_id = u.user_id) AND (ap.can_review_companies = true))))))))));

-- Original command/roles/permissive mode retained; other policies untouched.
ALTER POLICY company_logo_requests_read ON public.company_logo_change_requests
  USING ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.user_id = ( SELECT auth.uid() AS uid)) AND ((u.status)::text = 'active'::text) AND ((((u.role)::text = 'employer'::text) AND (EXISTS ( SELECT 1
           FROM company_memberships m
          WHERE ((m.user_id = u.user_id) AND (m.company_id = company_logo_change_requests.company_id) AND (m.membership_status = 'active'::text) AND (m.member_role = 'owner'::text))))) OR (((u.role)::text = 'administrator'::text) AND (EXISTS ( SELECT 1
           FROM administrator_profiles ap
          WHERE ((ap.user_id = u.user_id) AND (ap.can_review_companies = true))))))))));

-- Original command/roles/permissive mode retained; other policies untouched.
ALTER POLICY company_logos_insert ON storage.objects
  WITH CHECK (((bucket_id = 'jobmate-company-logos'::text) AND ((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text) AND (array_length(storage.foldername(name), 1) = 2) AND (split_part(name, '/'::text, 3) = ANY (ARRAY['logo.jpg'::text, 'logo.png'::text, 'logo.webp'::text])) AND (EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.user_id = ( SELECT auth.uid() AS uid)) AND (u.status = 'active'::account_status) AND (u.role = 'employer'::user_role) AND ((NOT (EXISTS ( SELECT 1
           FROM company_memberships m
          WHERE ((m.user_id = u.user_id) AND (m.member_role = 'owner'::text))))) OR (EXISTS ( SELECT 1
           FROM (company_memberships m
             JOIN companies c ON ((c.company_id = m.company_id)))
          WHERE ((m.user_id = u.user_id) AND (m.membership_status = 'active'::text) AND (m.member_role = 'owner'::text) AND (c.verification_status = 'rejected'::verification_status))))))))));

-- Original command/roles/permissive mode retained; other policies untouched.
ALTER POLICY company_logos_select ON storage.objects
  USING (((bucket_id = 'jobmate-company-logos'::text) AND (EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.user_id = ( SELECT auth.uid() AS uid)) AND (u.status = 'active'::account_status) AND ((u.role = 'administrator'::user_role) OR ((storage.foldername(objects.name))[1] = (u.user_id)::text) OR (EXISTS ( SELECT 1
           FROM (company_memberships m
             JOIN companies c ON ((c.company_id = m.company_id)))
          WHERE ((m.membership_status = 'active'::text) AND (m.user_id = u.user_id) AND (c.logo_storage_path = objects.name))))))))));

-- Original command/roles/permissive mode retained; other policies untouched.
ALTER POLICY company_profile_logo_insert ON storage.objects
  WITH CHECK (((bucket_id = 'jobmate-company-logos'::text) AND ((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text) AND (array_length(storage.foldername(name), 1) = 2) AND ((storage.foldername(name))[2] ~ '^profile-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'::text) AND (split_part(name, '/'::text, 3) = ANY (ARRAY['logo.jpg'::text, 'logo.png'::text, 'logo.webp'::text])) AND (EXISTS ( SELECT 1
   FROM (users u
     JOIN company_memberships m ON ((m.user_id = u.user_id)))
  WHERE ((u.user_id = ( SELECT auth.uid() AS uid)) AND ((u.status)::text = 'active'::text) AND ((u.role)::text = 'employer'::text) AND (m.membership_status = 'active'::text) AND (m.member_role = 'owner'::text))))));

-- Original command/roles/permissive mode retained; other policies untouched.
ALTER POLICY company_verification_files_insert ON storage.objects
  WITH CHECK (((bucket_id = 'jobmate-company-verification'::text) AND ((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text) AND (array_length(storage.foldername(name), 1) = 2) AND (split_part(name, '/'::text, 3) = 'document.pdf'::text) AND (EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.user_id = ( SELECT auth.uid() AS uid)) AND (u.status = 'active'::account_status) AND (u.role = 'employer'::user_role) AND ((NOT (EXISTS ( SELECT 1
           FROM company_memberships m
          WHERE ((m.user_id = u.user_id) AND (m.member_role = 'owner'::text))))) OR (EXISTS ( SELECT 1
           FROM (company_memberships m
             JOIN companies c ON ((c.company_id = m.company_id)))
          WHERE ((m.user_id = u.user_id) AND (m.membership_status = 'active'::text) AND (m.member_role = 'owner'::text) AND (c.verification_status = 'rejected'::verification_status))))))))));

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

-- LOCAL SOURCE: supabase/migrations/20261106000300_work_evidence_workflow.sql. NOT a claimed live definition.
-- Apply ONLY when the actual body matches exactly (line endings normalized).
-- Existing OID, owner, ACL and SECURITY DEFINER configuration are preserved.
DO $compatibility_patch$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.can_review_work_evidence_company(uuid)');
 old_body text := $expected_body$
    SELECT auth.uid() IS NOT NULL
    AND public.can_manage_company_jobs(p_company_id) IS TRUE
    AND EXISTS (SELECT 1 FROM public.users u
        JOIN public.company_memberships m ON m.user_id = u.user_id
        JOIN public.companies c ON c.company_id = m.company_id
        WHERE u.user_id = auth.uid() AND u.role = 'employer' AND u.status = 'active'
        AND m.company_id = p_company_id AND m.member_role IN ('owner', 'employer')
        AND c.verification_status = 'verified');
$expected_body$;
 new_body text := $replacement_body$
    SELECT auth.uid() IS NOT NULL
    AND public.can_manage_company_jobs(p_company_id) IS TRUE
    AND EXISTS (SELECT 1 FROM public.users u
        JOIN public.company_memberships m ON m.user_id = u.user_id
        JOIN public.companies c ON c.company_id = m.company_id
        WHERE u.user_id = auth.uid() AND u.role = 'employer' AND u.status = 'active'
        AND m.company_id = p_company_id AND m.membership_status = 'active' AND m.member_role IN ('owner', 'employer')
        AND c.verification_status = 'verified');
$replacement_body$;
 original_definition text; original_owner oid; original_acl aclitem[];
 original_config text[]; original_definer boolean;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required Module 4 function missing: can_review_work_evidence_company'; END IF;
 SELECT p.proowner,p.proacl,p.proconfig,p.prosecdef,pg_catalog.pg_get_functiondef(p.oid)
 INTO original_owner,original_acl,original_config,original_definer,original_definition
 FROM pg_catalog.pg_proc p WHERE p.oid=f;
 IF NOT original_definer OR original_config IS DISTINCT FROM ARRAY['search_path=""']::text[]
 OR (SELECT replace(p.prosrc,E'\r\n',E'\n') FROM pg_catalog.pg_proc p WHERE p.oid=f) IS DISTINCT FROM old_body
 THEN RAISE EXCEPTION 'Source/security drift: can_review_work_evidence_company; use the existing exact export, do not approximate'; END IF;
 -- Replace the body inside the server-rendered definition, preserving header/settings.
 EXECUTE replace(original_definition,(SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=f),new_body);
 IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=original_owner AND p.proacl IS NOT DISTINCT FROM original_acl
   AND p.proconfig IS NOT DISTINCT FROM original_config AND p.prosecdef=original_definer)
 THEN RAISE EXCEPTION 'Unexpected security boundary change'; END IF;
END;
$compatibility_patch$;
-- LOCAL SOURCE: supabase/migrations/20261106000200_employer_attendance_gps.sql. NOT a claimed live definition.
-- Apply ONLY when the actual body matches exactly (line endings normalized).
-- Existing OID, owner, ACL and SECURITY DEFINER configuration are preserved.
DO $compatibility_patch$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.read_employer_work_attendance_gps(uuid,uuid)');
 old_body text := $expected_body$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
    END IF;
    IF p_company_id IS NULL OR p_assignment_id IS NULL
       OR public.can_manage_company_jobs(p_company_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Not authorized to view attendance GPS' USING ERRCODE = '42501';
    END IF;
    -- Retain the existing helper and the same explicit eligibility used by
    -- JobPostingsRepository.loadAccess. GPS is for active company employers.
    IF NOT EXISTS (
        SELECT 1
        FROM public.users u
        JOIN public.company_memberships m ON m.user_id = u.user_id
        JOIN public.companies c ON c.company_id = m.company_id
        WHERE u.user_id = auth.uid()
          AND u.role = 'employer' AND u.status = 'active'
          AND m.company_id = p_company_id
          AND m.member_role IN ('owner', 'employer')
          AND c.verification_status = 'verified'
    ) THEN
        RAISE EXCEPTION 'Not authorized to view attendance GPS' USING ERRCODE = '42501';
    END IF;
    -- Scope the assignment as well as the caller. A supplied company UUID
    -- never authorizes an assignment belonging to another company.
    IF NOT EXISTS (
        SELECT 1 FROM public.work_assignments a
        WHERE a.assignment_id = p_assignment_id AND a.company_id = p_company_id
    ) THEN
        RAISE EXCEPTION 'Not authorized to view attendance GPS' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT a.assignment_id, a.company_id,
        att.check_in_at, att.check_in_location_status,
        att.check_in_latitude, att.check_in_longitude,
        att.check_out_at, att.check_out_location_status,
        att.check_out_latitude, att.check_out_longitude
    FROM public.work_assignments a
    LEFT JOIN public.work_attendance att ON att.assignment_id = a.assignment_id
    WHERE a.assignment_id = p_assignment_id AND a.company_id = p_company_id;
END;
$expected_body$;
 new_body text := $replacement_body$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
    END IF;
    IF p_company_id IS NULL OR p_assignment_id IS NULL
       OR public.can_manage_company_jobs(p_company_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Not authorized to view attendance GPS' USING ERRCODE = '42501';
    END IF;
    -- Retain the existing helper and the same explicit eligibility used by
    -- JobPostingsRepository.loadAccess. GPS is for active company employers.
    IF NOT EXISTS (
        SELECT 1
        FROM public.users u
        JOIN public.company_memberships m ON m.user_id = u.user_id
        JOIN public.companies c ON c.company_id = m.company_id
        WHERE u.user_id = auth.uid()
          AND u.role = 'employer' AND u.status = 'active'
          AND m.company_id = p_company_id
          AND m.membership_status = 'active' AND m.member_role IN ('owner', 'employer')
          AND c.verification_status = 'verified'
    ) THEN
        RAISE EXCEPTION 'Not authorized to view attendance GPS' USING ERRCODE = '42501';
    END IF;
    -- Scope the assignment as well as the caller. A supplied company UUID
    -- never authorizes an assignment belonging to another company.
    IF NOT EXISTS (
        SELECT 1 FROM public.work_assignments a
        WHERE a.assignment_id = p_assignment_id AND a.company_id = p_company_id
    ) THEN
        RAISE EXCEPTION 'Not authorized to view attendance GPS' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT a.assignment_id, a.company_id,
        att.check_in_at, att.check_in_location_status,
        att.check_in_latitude, att.check_in_longitude,
        att.check_out_at, att.check_out_location_status,
        att.check_out_latitude, att.check_out_longitude
    FROM public.work_assignments a
    LEFT JOIN public.work_attendance att ON att.assignment_id = a.assignment_id
    WHERE a.assignment_id = p_assignment_id AND a.company_id = p_company_id;
END;
$replacement_body$;
 original_definition text; original_owner oid; original_acl aclitem[];
 original_config text[]; original_definer boolean;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required Module 4 function missing: read_employer_work_attendance_gps'; END IF;
 SELECT p.proowner,p.proacl,p.proconfig,p.prosecdef,pg_catalog.pg_get_functiondef(p.oid)
 INTO original_owner,original_acl,original_config,original_definer,original_definition
 FROM pg_catalog.pg_proc p WHERE p.oid=f;
 IF NOT original_definer OR original_config IS DISTINCT FROM ARRAY['search_path=""']::text[]
 OR (SELECT replace(p.prosrc,E'\r\n',E'\n') FROM pg_catalog.pg_proc p WHERE p.oid=f) IS DISTINCT FROM old_body
 THEN RAISE EXCEPTION 'Source/security drift: read_employer_work_attendance_gps; use the existing exact export, do not approximate'; END IF;
 -- Replace the body inside the server-rendered definition, preserving header/settings.
 EXECUTE replace(original_definition,(SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=f),new_body);
 IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=original_owner AND p.proacl IS NOT DISTINCT FROM original_acl
   AND p.proconfig IS NOT DISTINCT FROM original_config AND p.prosecdef=original_definer)
 THEN RAISE EXCEPTION 'Unexpected security boundary change'; END IF;
END;
$compatibility_patch$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.submit_company_for_review: narrow compatibility replacement.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.submit_company_for_review(uuid,text,text,text,text,text)');
 expected text := $historical_body$
declare
  v_user_id uuid := auth.uid();
  v_account_status text;

  v_company_id uuid;
  v_member_role text;
  v_company_status text;

  v_name text := nullif(btrim(p_company_name), '');
  v_description text :=
    nullif(btrim(p_company_description), '');
  v_industry text := nullif(btrim(p_industry), '');
  v_location text := nullif(btrim(p_location), '');
  v_filename text := nullif(btrim(p_original_name), '');

  v_snapshot jsonb;

  v_existing public.company_verification_requests%rowtype;

  v_path text;
  v_metadata jsonb;
  v_size bigint;
begin
  -- 1. Identify the caller.
  if v_user_id is null then
    raise exception 'Please log in again.';
  end if;

  -- Serializes company submission attempts by this user.
  select u.status::text
  into v_account_status
  from public.users as u
  where u.user_id = v_user_id
  for update;

  if not found or v_account_status <> 'active' then
    raise exception 'Your account is not active.';
  end if;

  -- 2. Validate the submitted fields.
  if p_request_id is null then
    raise exception 'A submission ID is required.';
  end if;

  if v_name is null
     or char_length(v_name) not between 1 and 255 then
    raise exception 'Company name must contain 1 to 255 characters.';
  end if;

  if char_length(v_industry) > 100 then
    raise exception 'Industry must not exceed 100 characters.';
  end if;

  if char_length(v_location) > 255 then
    raise exception 'Location must not exceed 255 characters.';
  end if;

  if v_filename is null
     or char_length(v_filename) > 255 then
    raise exception 'A filename of 1 to 255 characters is required.';
  end if;

  v_snapshot := jsonb_build_object(
    'company_name', v_name,
    'company_description', v_description,
    'industry', v_industry,
    'location', v_location
  );

  -- 3. Handle a retry of an already successful submission.
  select r.*
  into v_existing
  from public.company_verification_requests as r
  where r.request_id = p_request_id;

  if found then
    if v_existing.submitted_by = v_user_id
       and v_existing.profile_snapshot = v_snapshot
       and v_existing.original_name = v_filename then
      return v_existing.company_id;
    end if;

    raise exception 'This submission ID has already been used.';
  end if;

  -- 4. Check existing company membership.
  select m.company_id, m.member_role
  into v_company_id, v_member_role
  from public.company_memberships as m
  where m.user_id = v_user_id;

  if v_company_id is not null then
    if v_member_role <> 'owner' then
      raise exception 'You already belong to a company.';
    end if;

    select c.verification_status::text
    into v_company_status
    from public.companies as c
    where c.company_id = v_company_id
    for update;

    if not found or v_company_status <> 'rejected' then
      raise exception
        'Only rejected company submissions can be revised here.';
    end if;
  end if;

  -- 5. Find the uploaded file.
  -- The caller does not choose an arbitrary storage path.
  v_path :=
    v_user_id::text || '/' ||
    p_request_id::text || '/document.pdf';

  select o.metadata
  into v_metadata
  from storage.objects as o
  where o.bucket_id = 'jobmate-company-verification'
    and o.name = v_path;

  if not found then
    raise exception 'Please upload the company PDF first.';
  end if;

  v_size := coalesce(
    (v_metadata ->> 'size')::bigint,
    0
  );

  if v_size not between 1 and 5242880 then
    raise exception 'The PDF must be non-empty and at most 5 MiB.';
  end if;

  if (v_metadata ->> 'mimetype')
     is distinct from 'application/pdf' then
    raise exception 'Only PDF documents are accepted.';
  end if;

  -- 6. Create the company, or revise a rejected company.
  if v_company_id is null then
    insert into public.companies (
      company_name,
      company_description,
      industry,
      location,
      verification_status,
      created_by
    )
    values (
      v_name,
      v_description,
      v_industry,
      v_location,
      'pending',
      v_user_id
    )
    returning company_id into v_company_id;

    insert into public.company_memberships (
      user_id,
      company_id,
      member_role
    )
    values (
      v_user_id,
      v_company_id,
      'owner'
    );
  else
    update public.companies
    set
      company_name = v_name,
      company_description = v_description,
      industry = v_industry,
      location = v_location,
      verification_status = 'pending'
    where company_id = v_company_id;
  end if;

  -- 7. Record this submission.
  insert into public.company_verification_requests (
    request_id,
    company_id,
    submitted_by,
    status,
    profile_snapshot,
    storage_path,
    original_name,
    mime_type,
    size_bytes
  )
  values (
    p_request_id,
    v_company_id,
    v_user_id,
    'pending',
    v_snapshot,
    v_path,
    v_filename,
    'application/pdf',
    v_size
  );

  return v_company_id;
end;
$historical_body$;
 replacement text := $historical_new$
declare
  v_user_id uuid := auth.uid();
  v_account_status text;

  v_company_id uuid;
  v_member_role text;
  v_company_status text;

  v_name text := nullif(btrim(p_company_name), '');
  v_description text :=
    nullif(btrim(p_company_description), '');
  v_industry text := nullif(btrim(p_industry), '');
  v_location text := nullif(btrim(p_location), '');
  v_filename text := nullif(btrim(p_original_name), '');

  v_snapshot jsonb;

  v_existing public.company_verification_requests%rowtype;

  v_path text;
  v_metadata jsonb;
  v_size bigint;
begin
  -- 1. Identify the caller.
  if v_user_id is null then
    raise exception 'Please log in again.';
  end if;

  -- Serializes company submission attempts by this user.
  select u.status::text
  into v_account_status
  from public.users as u
  where u.user_id = v_user_id
  for update;

  if not found or v_account_status <> 'active' then
    raise exception 'Your account is not active.';
  end if;

  -- 2. Validate the submitted fields.
  if p_request_id is null then
    raise exception 'A submission ID is required.';
  end if;

  if v_name is null
     or char_length(v_name) not between 1 and 255 then
    raise exception 'Company name must contain 1 to 255 characters.';
  end if;

  if char_length(v_industry) > 100 then
    raise exception 'Industry must not exceed 100 characters.';
  end if;

  if char_length(v_location) > 255 then
    raise exception 'Location must not exceed 255 characters.';
  end if;

  if v_filename is null
     or char_length(v_filename) > 255 then
    raise exception 'A filename of 1 to 255 characters is required.';
  end if;

  v_snapshot := jsonb_build_object(
    'company_name', v_name,
    'company_description', v_description,
    'industry', v_industry,
    'location', v_location
  );

  -- 3. Handle a retry of an already successful submission.
  select r.*
  into v_existing
  from public.company_verification_requests as r
  where r.request_id = p_request_id;

  if found then
    if v_existing.submitted_by = v_user_id
       and v_existing.profile_snapshot = v_snapshot
       and v_existing.original_name = v_filename then
      return v_existing.company_id;
    end if;

    raise exception 'This submission ID has already been used.';
  end if;

  -- 4. Check existing company membership.
  select m.company_id, m.member_role
  into v_company_id, v_member_role
  from public.company_memberships as m
  where m.user_id = v_user_id and m.member_role = 'owner';

  if v_company_id is not null then
    if v_member_role <> 'owner' then
      raise exception 'You already belong to a company.';
    end if;

    select c.verification_status::text
    into v_company_status
    from public.companies as c
    where c.company_id = v_company_id
    for update;

    if not found or v_company_status <> 'rejected' then
      raise exception
        'Only rejected company submissions can be revised here.';
    end if;
  end if;

  -- 5. Find the uploaded file.
  -- The caller does not choose an arbitrary storage path.
  v_path :=
    v_user_id::text || '/' ||
    p_request_id::text || '/document.pdf';

  select o.metadata
  into v_metadata
  from storage.objects as o
  where o.bucket_id = 'jobmate-company-verification'
    and o.name = v_path;

  if not found then
    raise exception 'Please upload the company PDF first.';
  end if;

  v_size := coalesce(
    (v_metadata ->> 'size')::bigint,
    0
  );

  if v_size not between 1 and 5242880 then
    raise exception 'The PDF must be non-empty and at most 5 MiB.';
  end if;

  if (v_metadata ->> 'mimetype')
     is distinct from 'application/pdf' then
    raise exception 'Only PDF documents are accepted.';
  end if;

  -- 6. Create the company, or revise a rejected company.
  if v_company_id is null then
    insert into public.companies (
      company_name,
      company_description,
      industry,
      location,
      verification_status,
      created_by
    )
    values (
      v_name,
      v_description,
      v_industry,
      v_location,
      'pending',
      v_user_id
    )
    returning company_id into v_company_id;

    insert into public.company_memberships (
      user_id,
      company_id,
      member_role
    )
    values (
      v_user_id,
      v_company_id,
      'owner'
    );
  else
    update public.companies
    set
      company_name = v_name,
      company_description = v_description,
      industry = v_industry,
      location = v_location,
      verification_status = 'pending'
    where company_id = v_company_id;
  end if;

  -- 7. Record this submission.
  insert into public.company_verification_requests (
    request_id,
    company_id,
    submitted_by,
    status,
    profile_snapshot,
    storage_path,
    original_name,
    mime_type,
    size_bytes
  )
  values (
    p_request_id,
    v_company_id,
    v_user_id,
    'pending',
    v_snapshot,
    v_path,
    v_filename,
    'application/pdf',
    v_size
  );

  return v_company_id;
end;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.submit_company_for_review(uuid,text,text,text,text,text)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.submit_company_for_review(uuid,text,text,text,text,text); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.submit_company_for_review_v2: compatibility source assertion; no replacement needed.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.submit_company_for_review_v2(uuid,text,text,text,text,text,text,integer,text,text,text)');
 expected text := $historical_body$
declare
  v_user_id uuid := auth.uid();
  v_account_status text;
  v_company_id uuid;

  v_name text := nullif(btrim(p_company_name), '');
  v_description text :=
    nullif(btrim(p_company_description), '');
  v_industry text := nullif(btrim(p_industry), '');
  v_location text := nullif(btrim(p_location), '');
  v_filename text := nullif(btrim(p_original_name), '');

  v_registration text :=
    nullif(btrim(p_registration_number), '');
  v_website text := nullif(btrim(p_website_url), '');
  v_email text := nullif(btrim(p_contact_email), '');
  v_phone text := nullif(btrim(p_contact_phone), '');

  v_snapshot jsonb;
  v_existing public.company_verification_requests%rowtype;
begin
  -- A. Identify and check the caller.
  if v_user_id is null then
    raise exception 'Please log in again.';
  end if;

  select u.status::text
  into v_account_status
  from public.users as u
  where u.user_id = v_user_id
  for update;

  if not found or v_account_status <> 'active' then
    raise exception 'Your account is not active.';
  end if;

  -- B. Validate the new company fields.
  if v_registration is null
     or char_length(v_registration) > 100 then
    raise exception
      'Registration number must contain 1 to 100 characters.';
  end if;

  if p_established_year is not null
     and (
       p_established_year < 1
       or p_established_year > 9999
       or p_established_year >
         extract(year from current_date)::integer
     ) then
    raise exception
      'Established year must be a valid year up to the current year.';
  end if;

  -- Basic HTTP/HTTPS website format check.
  if v_website is not null
     and v_website !~*
       '^https?://[^[:space:]/?#@]+([/?#][^[:space:]]*)?$' then
    raise exception
      'Website must be a valid HTTP or HTTPS address.';
  end if;

  -- Basic contact email format check.
  if v_email is not null
     and (
       char_length(v_email) > 254
       or v_email !~
         '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
     ) then
    raise exception 'Please enter a valid contact email.';
  end if;

  if char_length(v_phone) > 30 then
    raise exception
      'Contact phone must not exceed 30 characters.';
  end if;

  -- C. Freeze all submitted company information.
  v_snapshot := jsonb_build_object(
    'company_name', v_name,
    'company_description', v_description,
    'industry', v_industry,
    'location', v_location,
    'registration_number', v_registration,
    'established_year', p_established_year,
    'website_url', v_website,
    'contact_email', v_email,
    'contact_phone', v_phone
  );

  -- D. Return the original result for an identical retry.
  select r.*
  into v_existing
  from public.company_verification_requests as r
  where r.request_id = p_request_id;

  if found then
    if v_existing.submitted_by = v_user_id
       and v_existing.profile_snapshot = v_snapshot
       and v_existing.original_name = v_filename then
      return v_existing.company_id;
    end if;

    raise exception 'This submission ID has already been used.';
  end if;

  -- E. Reuse the original checked submission operation.
  -- Its writes remain inside this same transaction.
  v_company_id := public.submit_company_for_review(
    p_request_id,
    v_name,
    v_description,
    v_industry,
    v_location,
    v_filename
  );

  -- F. Save the new fields.
  update public.companies
  set
    registration_number = v_registration,
    established_year = p_established_year,
    website_url = v_website,
    contact_email = v_email,
    contact_phone = v_phone
  where company_id = v_company_id;

  -- Extend the request created by the original function.
  update public.company_verification_requests
  set profile_snapshot = v_snapshot
  where request_id = p_request_id
    and submitted_by = v_user_id;

  return v_company_id;
end;
$historical_body$;
 replacement text := $historical_new$
declare
  v_user_id uuid := auth.uid();
  v_account_status text;
  v_company_id uuid;

  v_name text := nullif(btrim(p_company_name), '');
  v_description text :=
    nullif(btrim(p_company_description), '');
  v_industry text := nullif(btrim(p_industry), '');
  v_location text := nullif(btrim(p_location), '');
  v_filename text := nullif(btrim(p_original_name), '');

  v_registration text :=
    nullif(btrim(p_registration_number), '');
  v_website text := nullif(btrim(p_website_url), '');
  v_email text := nullif(btrim(p_contact_email), '');
  v_phone text := nullif(btrim(p_contact_phone), '');

  v_snapshot jsonb;
  v_existing public.company_verification_requests%rowtype;
begin
  -- A. Identify and check the caller.
  if v_user_id is null then
    raise exception 'Please log in again.';
  end if;

  select u.status::text
  into v_account_status
  from public.users as u
  where u.user_id = v_user_id
  for update;

  if not found or v_account_status <> 'active' then
    raise exception 'Your account is not active.';
  end if;

  -- B. Validate the new company fields.
  if v_registration is null
     or char_length(v_registration) > 100 then
    raise exception
      'Registration number must contain 1 to 100 characters.';
  end if;

  if p_established_year is not null
     and (
       p_established_year < 1
       or p_established_year > 9999
       or p_established_year >
         extract(year from current_date)::integer
     ) then
    raise exception
      'Established year must be a valid year up to the current year.';
  end if;

  -- Basic HTTP/HTTPS website format check.
  if v_website is not null
     and v_website !~*
       '^https?://[^[:space:]/?#@]+([/?#][^[:space:]]*)?$' then
    raise exception
      'Website must be a valid HTTP or HTTPS address.';
  end if;

  -- Basic contact email format check.
  if v_email is not null
     and (
       char_length(v_email) > 254
       or v_email !~
         '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
     ) then
    raise exception 'Please enter a valid contact email.';
  end if;

  if char_length(v_phone) > 30 then
    raise exception
      'Contact phone must not exceed 30 characters.';
  end if;

  -- C. Freeze all submitted company information.
  v_snapshot := jsonb_build_object(
    'company_name', v_name,
    'company_description', v_description,
    'industry', v_industry,
    'location', v_location,
    'registration_number', v_registration,
    'established_year', p_established_year,
    'website_url', v_website,
    'contact_email', v_email,
    'contact_phone', v_phone
  );

  -- D. Return the original result for an identical retry.
  select r.*
  into v_existing
  from public.company_verification_requests as r
  where r.request_id = p_request_id;

  if found then
    if v_existing.submitted_by = v_user_id
       and v_existing.profile_snapshot = v_snapshot
       and v_existing.original_name = v_filename then
      return v_existing.company_id;
    end if;

    raise exception 'This submission ID has already been used.';
  end if;

  -- E. Reuse the original checked submission operation.
  -- Its writes remain inside this same transaction.
  v_company_id := public.submit_company_for_review(
    p_request_id,
    v_name,
    v_description,
    v_industry,
    v_location,
    v_filename
  );

  -- F. Save the new fields.
  update public.companies
  set
    registration_number = v_registration,
    established_year = p_established_year,
    website_url = v_website,
    contact_email = v_email,
    contact_phone = v_phone
  where company_id = v_company_id;

  -- Extend the request created by the original function.
  update public.company_verification_requests
  set profile_snapshot = v_snapshot
  where request_id = p_request_id
    and submitted_by = v_user_id;

  return v_company_id;
end;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.submit_company_for_review_v2(uuid,text,text,text,text,text,text,integer,text,text,text)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.submit_company_for_review_v2(uuid,text,text,text,text,text,text,integer,text,text,text); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.get_user_account_details: compatibility source assertion; no replacement needed.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.get_user_account_details(uuid)');
 expected text := $historical_body$
begin
  if not exists (
    select 1 from public.users u
    join public.administrator_profiles ap on ap.user_id = u.user_id
    where u.user_id = auth.uid() and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_manage_user_accounts = true
  ) then
    raise exception 'User Management permission is required.';
  end if;
  if p_target_user_id is null then raise exception 'User ID is required.'; end if;
  return query
  select u.user_id, u.name::text, a.email::text, u.phone_num::text,
         u.role::text, u.status::text, u.verification_status::text,
         u.created_at, m.company_id, c.company_name::text, m.member_role
  from public.users u
  join auth.users a on a.id = u.user_id
  left join public.company_memberships m on m.user_id = u.user_id
  left join public.companies c on c.company_id = m.company_id
  where u.user_id = p_target_user_id
    and u.role in ('job_seeker'::public.user_role, 'employer'::public.user_role);
end;
$historical_body$;
 replacement text := $historical_new$
begin
  if not exists (
    select 1 from public.users u
    join public.administrator_profiles ap on ap.user_id = u.user_id
    where u.user_id = auth.uid() and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_manage_user_accounts = true
  ) then
    raise exception 'User Management permission is required.';
  end if;
  if p_target_user_id is null then raise exception 'User ID is required.'; end if;
  return query
  select u.user_id, u.name::text, a.email::text, u.phone_num::text,
         u.role::text, u.status::text, u.verification_status::text,
         u.created_at, m.company_id, c.company_name::text, m.member_role
  from public.users u
  join auth.users a on a.id = u.user_id
  left join public.company_memberships m on m.user_id = u.user_id
  left join public.companies c on c.company_id = m.company_id
  where u.user_id = p_target_user_id
    and u.role in ('job_seeker'::public.user_role, 'employer'::public.user_role);
end;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.get_user_account_details(uuid)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.get_user_account_details(uuid); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.update_job_application_status: compatibility source assertion; no replacement needed.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.update_job_application_status(uuid,text,text)');
 expected text := $historical_body$
DECLARE
    v_actor_id uuid := auth.uid();
    v_application public.job_applications%ROWTYPE;
    v_job public.job_postings%ROWTYPE;
    v_note text;
BEGIN
    -- Lock the application to prevent concurrent status changes.
    SELECT *
    INTO v_application
    FROM public.job_applications a
    WHERE a.application_id = p_application_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Application not found.';
    END IF;

    -- Identify the job and its company.
    SELECT *
    INTO v_job
    FROM public.job_postings j
    WHERE j.job_id = v_application.job_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job posting not found.';
    END IF;

    -- Reuse existing employer/company authorization.
    IF v_actor_id IS NULL
       OR NOT public.can_manage_company_jobs(v_job.company_id) THEN
        RAISE EXCEPTION
            'You are not authorized to manage this application.';
    END IF;

    -- Only allow supported employer actions.
    IF p_new_status IS NULL OR p_new_status NOT IN (
        'shortlisted',
        'interview',
        'offered',
        'rejected'
    ) THEN
        RAISE EXCEPTION 'Invalid employer application status.';
    END IF;

    -- Enforce valid transitions.
    IF NOT (
        (v_application.status = 'submitted'
            AND p_new_status IN ('shortlisted', 'rejected'))
        OR
        (v_application.status = 'shortlisted'
            AND p_new_status IN ('interview', 'rejected'))
        OR
        (v_application.status = 'interview'
            AND p_new_status IN ('offered', 'rejected'))
    ) THEN
        RAISE EXCEPTION
            'This application status transition is not allowed.';
    END IF;

    v_note := NULLIF(BTRIM(p_note), '');

    IF v_note IS NOT NULL AND LENGTH(v_note) > 2000 THEN
        RAISE EXCEPTION 'Status note must not exceed 2000 characters.';
    END IF;

    -- Update the application.
    UPDATE public.job_applications
    SET
        status = p_new_status,
        updated_at = now()
    WHERE application_id = p_application_id;

    -- Record the status history.
    INSERT INTO public.application_status_history (
        application_id,
        previous_status,
        new_status,
        changed_by,
        note
    )
    VALUES (
        p_application_id,
        v_application.status,
        p_new_status,
        v_actor_id,
        v_note
    );

    -- Notify the applicant.
    INSERT INTO public.notifications (
        user_id,
        notification_type,
        title,
        message
    )
    VALUES (
        v_application.applicant_id,
        'application_' || p_new_status,
        'Application Status Updated',
        'Your application for '
            || v_job.title
            || ' is now '
            || INITCAP(p_new_status)
            || '.'
    );
END;
$historical_body$;
 replacement text := $historical_new$
DECLARE
    v_actor_id uuid := auth.uid();
    v_application public.job_applications%ROWTYPE;
    v_job public.job_postings%ROWTYPE;
    v_note text;
BEGIN
    -- Lock the application to prevent concurrent status changes.
    SELECT *
    INTO v_application
    FROM public.job_applications a
    WHERE a.application_id = p_application_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Application not found.';
    END IF;

    -- Identify the job and its company.
    SELECT *
    INTO v_job
    FROM public.job_postings j
    WHERE j.job_id = v_application.job_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job posting not found.';
    END IF;

    -- Reuse existing employer/company authorization.
    IF v_actor_id IS NULL
       OR NOT public.can_manage_company_jobs(v_job.company_id) THEN
        RAISE EXCEPTION
            'You are not authorized to manage this application.';
    END IF;

    -- Only allow supported employer actions.
    IF p_new_status IS NULL OR p_new_status NOT IN (
        'shortlisted',
        'interview',
        'offered',
        'rejected'
    ) THEN
        RAISE EXCEPTION 'Invalid employer application status.';
    END IF;

    -- Enforce valid transitions.
    IF NOT (
        (v_application.status = 'submitted'
            AND p_new_status IN ('shortlisted', 'rejected'))
        OR
        (v_application.status = 'shortlisted'
            AND p_new_status IN ('interview', 'rejected'))
        OR
        (v_application.status = 'interview'
            AND p_new_status IN ('offered', 'rejected'))
    ) THEN
        RAISE EXCEPTION
            'This application status transition is not allowed.';
    END IF;

    v_note := NULLIF(BTRIM(p_note), '');

    IF v_note IS NOT NULL AND LENGTH(v_note) > 2000 THEN
        RAISE EXCEPTION 'Status note must not exceed 2000 characters.';
    END IF;

    -- Update the application.
    UPDATE public.job_applications
    SET
        status = p_new_status,
        updated_at = now()
    WHERE application_id = p_application_id;

    -- Record the status history.
    INSERT INTO public.application_status_history (
        application_id,
        previous_status,
        new_status,
        changed_by,
        note
    )
    VALUES (
        p_application_id,
        v_application.status,
        p_new_status,
        v_actor_id,
        v_note
    );

    -- Notify the applicant.
    INSERT INTO public.notifications (
        user_id,
        notification_type,
        title,
        message
    )
    VALUES (
        v_application.applicant_id,
        'application_' || p_new_status,
        'Application Status Updated',
        'Your application for '
            || v_job.title
            || ' is now '
            || INITCAP(p_new_status)
            || '.'
    );
END;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.update_job_application_status(uuid,text,text)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.update_job_application_status(uuid,text,text); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.get_managed_company: compatibility source assertion; no replacement needed.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.get_managed_company(uuid)');
 expected text := $historical_body$
declare v_result jsonb;
begin
  if not exists (
    select 1 from public.users u join public.administrator_profiles ap on ap.user_id=u.user_id
    where u.user_id=auth.uid() and u.role='administrator'::public.user_role
      and u.status='active'::public.account_status and ap.can_manage_company_restrictions
  ) then raise exception 'Company Management permission is required.'; end if;
  select jsonb_build_object(
    'company_id',c.company_id,'company_name',c.company_name,'company_description',c.company_description,
    'verification_status',c.verification_status,'created_by',c.created_by,'industry',c.industry,
    'location',c.location,'created_at',c.created_at,
    'restriction_status',r.restriction_status,'restriction_reason',r.restriction_reason,
    'restricted_at',case when r.restriction_status='restricted' then r.changed_at end,
    'members',coalesce((select jsonb_agg(jsonb_build_object(
      'user_id',u.user_id,'name',u.name,'member_role',m.member_role,'account_status',u.status
    ) order by m.member_role,u.name,u.user_id)
      from public.company_memberships m join public.users u on u.user_id=m.user_id
      where m.company_id=c.company_id),'[]'::jsonb)
  ) into v_result
  from public.companies c join public.company_restrictions r on r.company_id=c.company_id
  where c.company_id=p_company_id;
  if v_result is null then raise exception 'Company not found.'; end if;
  return v_result;
end;
$historical_body$;
 replacement text := $historical_new$
declare v_result jsonb;
begin
  if not exists (
    select 1 from public.users u join public.administrator_profiles ap on ap.user_id=u.user_id
    where u.user_id=auth.uid() and u.role='administrator'::public.user_role
      and u.status='active'::public.account_status and ap.can_manage_company_restrictions
  ) then raise exception 'Company Management permission is required.'; end if;
  select jsonb_build_object(
    'company_id',c.company_id,'company_name',c.company_name,'company_description',c.company_description,
    'verification_status',c.verification_status,'created_by',c.created_by,'industry',c.industry,
    'location',c.location,'created_at',c.created_at,
    'restriction_status',r.restriction_status,'restriction_reason',r.restriction_reason,
    'restricted_at',case when r.restriction_status='restricted' then r.changed_at end,
    'members',coalesce((select jsonb_agg(jsonb_build_object(
      'user_id',u.user_id,'name',u.name,'member_role',m.member_role,'account_status',u.status
    ) order by m.member_role,u.name,u.user_id)
      from public.company_memberships m join public.users u on u.user_id=m.user_id
      where m.company_id=c.company_id),'[]'::jsonb)
  ) into v_result
  from public.companies c join public.company_restrictions r on r.company_id=c.company_id
  where c.company_id=p_company_id;
  if v_result is null then raise exception 'Company not found.'; end if;
  return v_result;
end;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.get_managed_company(uuid)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.get_managed_company(uuid); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.list_managed_companies: compatibility source assertion; no replacement needed.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.list_managed_companies(integer,integer)');
 expected text := $historical_body$
begin
  if not exists (
    select 1 from public.users u join public.administrator_profiles ap on ap.user_id=u.user_id
    where u.user_id=auth.uid() and u.role='administrator'::public.user_role
      and u.status='active'::public.account_status and ap.can_manage_company_restrictions
  ) then raise exception 'Company Management permission is required.'; end if;
  if p_limit is null or p_limit not between 1 and 101 or p_offset is null or p_offset < 0 then
    raise exception 'Invalid page size or offset.';
  end if;
  return query
  select c.company_id, c.company_name::text, c.verification_status::text,
    r.restriction_status, r.restriction_reason,
    case when r.restriction_status='restricted' then r.changed_at end,
    c.industry::text, c.location::text, c.created_at,
    (select count(*) from public.company_memberships m where m.company_id=c.company_id)
  from public.companies c join public.company_restrictions r on r.company_id=c.company_id
  order by lower(c.company_name), c.company_id limit p_limit offset p_offset;
end;
$historical_body$;
 replacement text := $historical_new$
begin
  if not exists (
    select 1 from public.users u join public.administrator_profiles ap on ap.user_id=u.user_id
    where u.user_id=auth.uid() and u.role='administrator'::public.user_role
      and u.status='active'::public.account_status and ap.can_manage_company_restrictions
  ) then raise exception 'Company Management permission is required.'; end if;
  if p_limit is null or p_limit not between 1 and 101 or p_offset is null or p_offset < 0 then
    raise exception 'Invalid page size or offset.';
  end if;
  return query
  select c.company_id, c.company_name::text, c.verification_status::text,
    r.restriction_status, r.restriction_reason,
    case when r.restriction_status='restricted' then r.changed_at end,
    c.industry::text, c.location::text, c.created_at,
    (select count(*) from public.company_memberships m where m.company_id=c.company_id)
  from public.companies c join public.company_restrictions r on r.company_id=c.company_id
  order by lower(c.company_name), c.company_id limit p_limit offset p_offset;
end;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.list_managed_companies(integer,integer)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.list_managed_companies(integer,integer); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- private.dispute_can_read: narrow compatibility replacement.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('private.dispute_can_read(uuid,boolean)');
 expected text := $historical_body$
  select exists (select 1 from public.disputes d join public.users u on u.user_id=auth.uid()
    where d.dispute_id=p_dispute and (
      (not p_admin and u.status in ('active','suspended') and (
        (u.role='job_seeker' and d.worker_id=u.user_id) or
        (u.role='employer' and exists(select 1 from public.company_memberships m
          where m.company_id=d.company_id and m.user_id=u.user_id and m.member_role in ('owner','employer')))))
      or (p_admin and u.role='administrator' and u.status='active'
        and u.user_id<>d.worker_id and u.user_id<>d.submitted_by
        and exists(select 1 from public.administrator_profiles ap where ap.user_id=u.user_id and ap.can_manage_disputes)
        and exists(select 1 from public.companies c where c.company_id=d.company_id and c.created_by is distinct from u.user_id)
        and not exists(select 1 from public.company_memberships m where m.company_id=d.company_id and m.user_id=u.user_id))));
$historical_body$;
 replacement text := $historical_new$
  select exists (select 1 from public.disputes d join public.users u on u.user_id=auth.uid()
    where d.dispute_id=p_dispute and (
      (not p_admin and u.status in ('active','suspended') and (
        (u.role='job_seeker' and d.worker_id=u.user_id) or
        (u.role='employer' and exists(select 1 from public.company_memberships m
          where m.company_id=d.company_id and m.user_id=u.user_id and m.membership_status='active' and m.member_role in ('owner','employer')))))
      or (p_admin and u.role='administrator' and u.status='active'
        and u.user_id<>d.worker_id and u.user_id<>d.submitted_by
        and exists(select 1 from public.administrator_profiles ap where ap.user_id=u.user_id and ap.can_manage_disputes)
        and exists(select 1 from public.companies c where c.company_id=d.company_id and c.created_by is distinct from u.user_id)
        and not exists(select 1 from public.company_memberships m where m.company_id=d.company_id and m.user_id=u.user_id))));
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: private.dispute_can_read(uuid,boolean)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: private.dispute_can_read(uuid,boolean); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- private.dispute_notify: narrow compatibility replacement.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('private.dispute_notify(uuid,text,text)');
 expected text := $historical_body$
  insert into public.notifications(user_id,notification_type,title,message)
  select distinct x.user_id,'dispute',p_title,p_message from (
    select d.worker_id as user_id from public.disputes d where d.dispute_id=p_id
    union select m.user_id from public.disputes d join public.company_memberships m on m.company_id=d.company_id
      where d.dispute_id=p_id and m.member_role in ('owner','employer')
  ) x;
$historical_body$;
 replacement text := $historical_new$
  insert into public.notifications(user_id,notification_type,title,message)
  select distinct x.user_id,'dispute',p_title,p_message from (
    select d.worker_id as user_id from public.disputes d where d.dispute_id=p_id
    union select m.user_id from public.disputes d join public.company_memberships m on m.company_id=d.company_id
      where d.dispute_id=p_id and m.membership_status='active' and m.member_role in ('owner','employer')
  ) x;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: private.dispute_notify(uuid,text,text)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: private.dispute_notify(uuid,text,text); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.set_company_restriction: narrow compatibility replacement.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.set_company_restriction(uuid,text,text)');
 expected text := $historical_body$
declare v_actor uuid:=auth.uid(); v_previous text; v_next text; v_reason text:=nullif(pg_catalog.btrim(p_reason),'');
begin
  if v_actor is null or p_company_id is null
     or p_action not in ('restrict','restore') then raise exception 'Choose a valid Company action.'; end if;
  if v_reason is null or pg_catalog.length(v_reason) not between 1 and 2000 then
    raise exception 'A reason of 1 to 2000 characters is required.';
  end if;
  perform u.user_id from public.users u where u.user_id=v_actor for update;
  if not exists (
    select 1 from public.users u join public.administrator_profiles ap on ap.user_id=u.user_id
    where u.user_id=v_actor and u.role='administrator'::public.user_role
      and u.status='active'::public.account_status and ap.can_manage_company_restrictions
  ) then raise exception 'Company Management permission is required.'; end if;
  perform c.company_id from public.companies c where c.company_id=p_company_id for update;
  if not found then raise exception 'Company not found.'; end if;
  select r.restriction_status into v_previous from public.company_restrictions r
    where r.company_id=p_company_id for update;
  if not found then raise exception 'Company restriction record is missing.'; end if;
  if p_action='restrict' and v_previous='active' then v_next:='restricted';
  elsif p_action='restore' and v_previous='restricted' then v_next:='active';
  else raise exception 'Company is already in the requested state.'; end if;
  update public.company_restrictions set restriction_status=v_next,
    restriction_reason=case when v_next='restricted' then v_reason else null end,
    changed_by=v_actor,changed_at=pg_catalog.clock_timestamp()
    where company_id=p_company_id;
  insert into public.company_restriction_history(company_id,actor_user_id,action,previous_status,new_status,reason)
    values(p_company_id,v_actor,case when v_next='restricted' then 'restricted' else 'restored' end,v_previous,v_next,v_reason);
  insert into public.notifications(user_id,notification_type,title,message)
    select distinct m.user_id,'company_restriction',
      case when v_next='restricted' then 'Company access restricted' else 'Company access restored' end,
      case when v_next='restricted'
        then pg_catalog.format('Administrative access restrictions were placed on %s. Reason: %s',(select c.company_name from public.companies c where c.company_id=p_company_id),v_reason)
        else pg_catalog.format('Administrative access restrictions were lifted for %s. Reason: %s',(select c.company_name from public.companies c where c.company_id=p_company_id),v_reason) end
    from public.company_memberships m where m.company_id=p_company_id;
  return v_next;
end;
$historical_body$;
 replacement text := $historical_new$
declare v_actor uuid:=auth.uid(); v_previous text; v_next text; v_reason text:=nullif(pg_catalog.btrim(p_reason),'');
begin
  if v_actor is null or p_company_id is null
     or p_action not in ('restrict','restore') then raise exception 'Choose a valid Company action.'; end if;
  if v_reason is null or pg_catalog.length(v_reason) not between 1 and 2000 then
    raise exception 'A reason of 1 to 2000 characters is required.';
  end if;
  perform u.user_id from public.users u where u.user_id=v_actor for update;
  if not exists (
    select 1 from public.users u join public.administrator_profiles ap on ap.user_id=u.user_id
    where u.user_id=v_actor and u.role='administrator'::public.user_role
      and u.status='active'::public.account_status and ap.can_manage_company_restrictions
  ) then raise exception 'Company Management permission is required.'; end if;
  perform c.company_id from public.companies c where c.company_id=p_company_id for update;
  if not found then raise exception 'Company not found.'; end if;
  select r.restriction_status into v_previous from public.company_restrictions r
    where r.company_id=p_company_id for update;
  if not found then raise exception 'Company restriction record is missing.'; end if;
  if p_action='restrict' and v_previous='active' then v_next:='restricted';
  elsif p_action='restore' and v_previous='restricted' then v_next:='active';
  else raise exception 'Company is already in the requested state.'; end if;
  update public.company_restrictions set restriction_status=v_next,
    restriction_reason=case when v_next='restricted' then v_reason else null end,
    changed_by=v_actor,changed_at=pg_catalog.clock_timestamp()
    where company_id=p_company_id;
  insert into public.company_restriction_history(company_id,actor_user_id,action,previous_status,new_status,reason)
    values(p_company_id,v_actor,case when v_next='restricted' then 'restricted' else 'restored' end,v_previous,v_next,v_reason);
  insert into public.notifications(user_id,notification_type,title,message)
    select distinct m.user_id,'company_restriction',
      case when v_next='restricted' then 'Company access restricted' else 'Company access restored' end,
      case when v_next='restricted'
        then pg_catalog.format('Administrative access restrictions were placed on %s. Reason: %s',(select c.company_name from public.companies c where c.company_id=p_company_id),v_reason)
        else pg_catalog.format('Administrative access restrictions were lifted for %s. Reason: %s',(select c.company_name from public.companies c where c.company_id=p_company_id),v_reason) end
    from public.company_memberships m where m.company_id=p_company_id and m.membership_status='active' and m.member_role in ('owner','employer');
  return v_next;
end;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.set_company_restriction(uuid,text,text)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.set_company_restriction(uuid,text,text); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.update_job_moderation: narrow compatibility replacement.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.update_job_moderation(uuid,text,text)');
 expected text := $historical_body$
declare
  v_actor uuid:=auth.uid(); v_job public.job_postings%rowtype; v_previous text; v_next text;
  v_reason text:=nullif(pg_catalog.btrim(p_reason),''); v_exists boolean;
begin
  if v_actor is null or p_job_id is null or p_action not in ('flag','start_review','note','clear','restrict','restore') then
    raise exception 'Choose a valid Job Moderation action.';
  end if;
  if v_reason is null or pg_catalog.length(v_reason) not between 1 and 4000 then
    raise exception 'A reason or investigation note of 1 to 4000 characters is required.';
  end if;
  perform u.user_id from public.users u where u.user_id=v_actor and u.role='administrator'::public.user_role
    and u.status='active'::public.account_status for share;
  if not found then raise exception 'An active Admin account is required.'; end if;
  perform ap.user_id from public.administrator_profiles ap where ap.user_id=v_actor
    and ap.can_manage_job_moderation for share;
  if not found then raise exception 'Job Moderation permission is required.'; end if;
  select * into v_job from public.job_postings j where j.job_id=p_job_id for update;
  if not found then raise exception 'Job posting not found.'; end if;
  if private.job_moderation_conflicts(v_actor,p_job_id) then raise exception 'You cannot review a job you created or a Company you belong to.'; end if;
  select s.moderation_status into v_previous from public.job_moderation_state s where s.job_id=p_job_id for update;
  v_exists:=found;
  v_previous:=coalesce(v_previous,'unflagged');
  if p_action='flag' and v_previous in ('unflagged','cleared') then v_next:='flagged';
  elsif p_action='start_review' and v_previous='flagged' then v_next:='under_review';
  elsif p_action='note' and v_previous in ('flagged','under_review') then v_next:=v_previous;
  elsif p_action='clear' and v_previous in ('flagged','under_review') then v_next:='cleared';
  elsif p_action='restrict' and v_previous in ('flagged','under_review') then v_next:='restricted';
  elsif p_action='restore' and v_previous='restricted' then v_next:='cleared';
  else raise exception 'This moderation action is not allowed from status %.',v_previous; end if;

  if v_exists then
    update public.job_moderation_state set moderation_status=v_next,updated_by=v_actor,updated_at=pg_catalog.clock_timestamp()
      where job_id=p_job_id;
  else
    insert into public.job_moderation_state(job_id,moderation_status,updated_by) values(p_job_id,v_next,v_actor);
  end if;
  insert into public.job_moderation_history(job_id,actor_id,action,previous_status,new_status,reason)
    values(p_job_id,v_actor,p_action,v_previous,v_next,v_reason);

  -- No reporter or internal reason is disclosed to Employers.
  if p_action in ('flag','clear','restrict','restore') then
    insert into public.notifications(user_id,notification_type,title,message)
    select recipients.user_id,'job_moderation','Job posting moderation update',
      case v_next when 'flagged' then 'A concern about your job posting is being reviewed.'
        when 'cleared' then 'The moderation review for your job posting is complete.'
        when 'restricted' then 'A moderation restriction was recorded for your job posting. Availability across existing job feeds is still being integrated. Contact JobMate Support if you need help.'
        else 'The restriction on your job posting has been restored.' end
    from (select v_job.created_by as user_id
      union select m.user_id from public.company_memberships m where m.company_id=v_job.company_id and m.member_role in ('owner','employer')) recipients
    join public.users u on u.user_id=recipients.user_id and u.status='active'::public.account_status
    where recipients.user_id is not null;
  end if;
  return v_next;
end;
$historical_body$;
 replacement text := $historical_new$
declare
  v_actor uuid:=auth.uid(); v_job public.job_postings%rowtype; v_previous text; v_next text;
  v_reason text:=nullif(pg_catalog.btrim(p_reason),''); v_exists boolean;
begin
  if v_actor is null or p_job_id is null or p_action not in ('flag','start_review','note','clear','restrict','restore') then
    raise exception 'Choose a valid Job Moderation action.';
  end if;
  if v_reason is null or pg_catalog.length(v_reason) not between 1 and 4000 then
    raise exception 'A reason or investigation note of 1 to 4000 characters is required.';
  end if;
  perform u.user_id from public.users u where u.user_id=v_actor and u.role='administrator'::public.user_role
    and u.status='active'::public.account_status for share;
  if not found then raise exception 'An active Admin account is required.'; end if;
  perform ap.user_id from public.administrator_profiles ap where ap.user_id=v_actor
    and ap.can_manage_job_moderation for share;
  if not found then raise exception 'Job Moderation permission is required.'; end if;
  select * into v_job from public.job_postings j where j.job_id=p_job_id for update;
  if not found then raise exception 'Job posting not found.'; end if;
  if private.job_moderation_conflicts(v_actor,p_job_id) then raise exception 'You cannot review a job you created or a Company you belong to.'; end if;
  select s.moderation_status into v_previous from public.job_moderation_state s where s.job_id=p_job_id for update;
  v_exists:=found;
  v_previous:=coalesce(v_previous,'unflagged');
  if p_action='flag' and v_previous in ('unflagged','cleared') then v_next:='flagged';
  elsif p_action='start_review' and v_previous='flagged' then v_next:='under_review';
  elsif p_action='note' and v_previous in ('flagged','under_review') then v_next:=v_previous;
  elsif p_action='clear' and v_previous in ('flagged','under_review') then v_next:='cleared';
  elsif p_action='restrict' and v_previous in ('flagged','under_review') then v_next:='restricted';
  elsif p_action='restore' and v_previous='restricted' then v_next:='cleared';
  else raise exception 'This moderation action is not allowed from status %.',v_previous; end if;

  if v_exists then
    update public.job_moderation_state set moderation_status=v_next,updated_by=v_actor,updated_at=pg_catalog.clock_timestamp()
      where job_id=p_job_id;
  else
    insert into public.job_moderation_state(job_id,moderation_status,updated_by) values(p_job_id,v_next,v_actor);
  end if;
  insert into public.job_moderation_history(job_id,actor_id,action,previous_status,new_status,reason)
    values(p_job_id,v_actor,p_action,v_previous,v_next,v_reason);

  -- No reporter or internal reason is disclosed to Employers.
  if p_action in ('flag','clear','restrict','restore') then
    insert into public.notifications(user_id,notification_type,title,message)
    select recipients.user_id,'job_moderation','Job posting moderation update',
      case v_next when 'flagged' then 'A concern about your job posting is being reviewed.'
        when 'cleared' then 'The moderation review for your job posting is complete.'
        when 'restricted' then 'A moderation restriction was recorded for your job posting. Availability across existing job feeds is still being integrated. Contact JobMate Support if you need help.'
        else 'The restriction on your job posting has been restored.' end
    from (select v_job.created_by as user_id
      union select m.user_id from public.company_memberships m where m.company_id=v_job.company_id and m.membership_status='active' and m.member_role in ('owner','employer')) recipients
    join public.users u on u.user_id=recipients.user_id and u.status='active'::public.account_status
    where recipients.user_id is not null;
  end if;
  return v_next;
end;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.update_job_moderation(uuid,text,text)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.update_job_moderation(uuid,text,text); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.submit_dispute: narrow compatibility replacement.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.submit_dispute(text,uuid,text)');
 expected text := $historical_body$
declare v_uid uuid:=auth.uid(); v_worker uuid; v_company uuid; v_id uuid;
begin
  if p_category is null or p_category not in ('recruitment','work','payment') or p_related_id is null
    or p_description is null or p_description !~ '[^[:space:]]' or char_length(p_description)>4000 then
    raise exception 'Valid category, related record, and description are required.';
  end if;
  if not exists(select 1 from public.users u where u.user_id=v_uid and u.status='active' and u.role in ('job_seeker','employer')) then
    raise exception 'An active party account is required.';
  end if;
  if p_category='recruitment' then
    select a.applicant_id,j.company_id into v_worker,v_company from public.job_applications a
      join public.job_postings j on j.job_id=a.job_id where a.application_id=p_related_id;
  else
    select a.worker_id,a.company_id into v_worker,v_company from public.work_assignments a where a.assignment_id=p_related_id;
  end if;
  if v_worker is null or v_company is null or not exists(select 1 from public.users u where u.user_id=v_uid and
    ((u.role='job_seeker' and v_worker=v_uid) or (u.role='employer' and exists(select 1 from public.company_memberships m
       where m.company_id=v_company and m.user_id=v_uid and m.member_role in ('owner','employer'))))) then
    raise exception 'The related record is unavailable to this account.';
  end if;
  insert into public.disputes(category,application_id,assignment_id,company_id,worker_id,submitted_by,description)
  values(p_category,case when p_category='recruitment' then p_related_id end,
    case when p_category<>'recruitment' then p_related_id end,v_company,v_worker,v_uid,btrim(p_description))
  returning dispute_id into v_id;
  insert into public.dispute_status_history(dispute_id,actor_id,action,new_status,note)
    values(v_id,v_uid,'submitted','open',btrim(p_description));
  perform private.dispute_notify(v_id,'Dispute opened','A dispute involving your account or company has been opened.');
  return v_id;
end;
$historical_body$;
 replacement text := $historical_new$
declare v_uid uuid:=auth.uid(); v_worker uuid; v_company uuid; v_id uuid;
begin
  if p_category is null or p_category not in ('recruitment','work','payment') or p_related_id is null
    or p_description is null or p_description !~ '[^[:space:]]' or char_length(p_description)>4000 then
    raise exception 'Valid category, related record, and description are required.';
  end if;
  if not exists(select 1 from public.users u where u.user_id=v_uid and u.status='active' and u.role in ('job_seeker','employer')) then
    raise exception 'An active party account is required.';
  end if;
  if p_category='recruitment' then
    select a.applicant_id,j.company_id into v_worker,v_company from public.job_applications a
      join public.job_postings j on j.job_id=a.job_id where a.application_id=p_related_id;
  else
    select a.worker_id,a.company_id into v_worker,v_company from public.work_assignments a where a.assignment_id=p_related_id;
  end if;
  if v_worker is null or v_company is null or not exists(select 1 from public.users u where u.user_id=v_uid and
    ((u.role='job_seeker' and v_worker=v_uid) or (u.role='employer' and exists(select 1 from public.company_memberships m
       where m.company_id=v_company and m.user_id=v_uid and m.membership_status='active' and m.member_role in ('owner','employer'))))) then
    raise exception 'The related record is unavailable to this account.';
  end if;
  insert into public.disputes(category,application_id,assignment_id,company_id,worker_id,submitted_by,description)
  values(p_category,case when p_category='recruitment' then p_related_id end,
    case when p_category<>'recruitment' then p_related_id end,v_company,v_worker,v_uid,btrim(p_description))
  returning dispute_id into v_id;
  insert into public.dispute_status_history(dispute_id,actor_id,action,new_status,note)
    values(v_id,v_uid,'submitted','open',btrim(p_description));
  perform private.dispute_notify(v_id,'Dispute opened','A dispute involving your account or company has been opened.');
  return v_id;
end;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.submit_dispute(text,uuid,text)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.submit_dispute(text,uuid,text); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.can_read_dispute_evidence: compatibility source assertion; no replacement needed.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.can_read_dispute_evidence(text)');
 expected text := $historical_body$
  select exists (
    select 1 from public.dispute_evidence e
    where e.storage_path = p_storage_path and e.status = 'available'
      and (private.dispute_can_read(e.dispute_id, false)
        or private.dispute_can_read(e.dispute_id, true))
  );
$historical_body$;
 replacement text := $historical_new$
  select exists (
    select 1 from public.dispute_evidence e
    where e.storage_path = p_storage_path and e.status = 'available'
      and (private.dispute_can_read(e.dispute_id, false)
        or private.dispute_can_read(e.dispute_id, true))
  );
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.can_read_dispute_evidence(text)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.can_read_dispute_evidence(text); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- private.attach_jobmate_company_logo: compatibility source assertion; no replacement needed.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('private.attach_jobmate_company_logo()');
 expected text := $historical_body$
declare
  v_prefix text;
  v_count bigint;
  v_path text;
  v_metadata jsonb;
  v_size bigint;
  v_expected_mime text;
begin
  if new.status <> 'pending' then
    return new;
  end if;

  v_prefix :=
    new.submitted_by::text || '/' ||
    new.request_id::text || '/logo.';

  select count(*), min(o.name)
  into v_count, v_path
  from storage.objects as o
  where o.bucket_id = 'jobmate-company-logos'
    and o.name in (
      v_prefix || 'jpg',
      v_prefix || 'png',
      v_prefix || 'webp'
    );

  -- No new logo: retain the company's existing logo.
  if v_count = 0 then
    return new;
  end if;

  if v_count > 1 then
    raise exception 'Upload only one logo per submission.';
  end if;

  if not exists (
    select 1
    from public.company_memberships as m
    join public.companies as c
      on c.company_id = m.company_id
    where m.user_id = new.submitted_by
      and m.company_id = new.company_id
      and m.member_role = 'owner'
      and c.verification_status = 'pending'
  ) then
    raise exception 'Unable to attach this company logo.';
  end if;

  select o.metadata
  into v_metadata
  from storage.objects as o
  where o.bucket_id = 'jobmate-company-logos'
    and o.name = v_path;

  v_size := coalesce(
    (v_metadata ->> 'size')::bigint,
    0
  );

  if v_size not between 1 and 2097152 then
    raise exception 'Company logo must be at most 2 MiB.';
  end if;

  v_expected_mime := case
    when right(v_path, 4) = '.jpg' then 'image/jpeg'
    when right(v_path, 4) = '.png' then 'image/png'
    else 'image/webp'
  end;

  if (v_metadata ->> 'mimetype')
     is distinct from v_expected_mime then
    raise exception 'Unsupported company logo format.';
  end if;

  update public.companies
  set logo_storage_path = v_path
  where company_id = new.company_id;

  return new;
end;
$historical_body$;
 replacement text := $historical_new$
declare
  v_prefix text;
  v_count bigint;
  v_path text;
  v_metadata jsonb;
  v_size bigint;
  v_expected_mime text;
begin
  if new.status <> 'pending' then
    return new;
  end if;

  v_prefix :=
    new.submitted_by::text || '/' ||
    new.request_id::text || '/logo.';

  select count(*), min(o.name)
  into v_count, v_path
  from storage.objects as o
  where o.bucket_id = 'jobmate-company-logos'
    and o.name in (
      v_prefix || 'jpg',
      v_prefix || 'png',
      v_prefix || 'webp'
    );

  -- No new logo: retain the company's existing logo.
  if v_count = 0 then
    return new;
  end if;

  if v_count > 1 then
    raise exception 'Upload only one logo per submission.';
  end if;

  if not exists (
    select 1
    from public.company_memberships as m
    join public.companies as c
      on c.company_id = m.company_id
    where m.user_id = new.submitted_by
      and m.company_id = new.company_id
      and m.member_role = 'owner'
      and c.verification_status = 'pending'
  ) then
    raise exception 'Unable to attach this company logo.';
  end if;

  select o.metadata
  into v_metadata
  from storage.objects as o
  where o.bucket_id = 'jobmate-company-logos'
    and o.name = v_path;

  v_size := coalesce(
    (v_metadata ->> 'size')::bigint,
    0
  );

  if v_size not between 1 and 2097152 then
    raise exception 'Company logo must be at most 2 MiB.';
  end if;

  v_expected_mime := case
    when right(v_path, 4) = '.jpg' then 'image/jpeg'
    when right(v_path, 4) = '.png' then 'image/png'
    else 'image/webp'
  end;

  if (v_metadata ->> 'mimetype')
     is distinct from v_expected_mime then
    raise exception 'Unsupported company logo format.';
  end if;

  update public.companies
  set logo_storage_path = v_path
  where company_id = new.company_id;

  return new;
end;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: private.attach_jobmate_company_logo()'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: private.attach_jobmate_company_logo(); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- private.job_moderation_conflicts: compatibility source assertion; no replacement needed.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('private.job_moderation_conflicts(uuid,uuid)');
 expected text := $historical_body$
  select exists(select 1 from public.job_postings j join public.companies c on c.company_id=j.company_id
    where j.job_id=p_job_id and (j.created_by=p_actor or c.created_by=p_actor
      or exists(select 1 from public.company_memberships m where m.company_id=c.company_id and m.user_id=p_actor)))
$historical_body$;
 replacement text := $historical_new$
  select exists(select 1 from public.job_postings j join public.companies c on c.company_id=j.company_id
    where j.job_id=p_job_id and (j.created_by=p_actor or c.created_by=p_actor
      or exists(select 1 from public.company_memberships m where m.company_id=c.company_id and m.user_id=p_actor)))
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: private.job_moderation_conflicts(uuid,uuid)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: private.job_moderation_conflicts(uuid,uuid); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- private.user_report_conflicts: compatibility source assertion; no replacement needed.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('private.user_report_conflicts(uuid,uuid,uuid)');
 expected text := $historical_body$
  select coalesce(p_actor=p_target_user,false) or (p_target_company is not null and exists(
    select 1 from public.companies c where c.company_id=p_target_company and c.created_by=p_actor
  )) or (p_target_company is not null and exists(
    select 1 from public.company_memberships m where m.company_id=p_target_company and m.user_id=p_actor
  ))
$historical_body$;
 replacement text := $historical_new$
  select coalesce(p_actor=p_target_user,false) or (p_target_company is not null and exists(
    select 1 from public.companies c where c.company_id=p_target_company and c.created_by=p_actor
  )) or (p_target_company is not null and exists(
    select 1 from public.company_memberships m where m.company_id=p_target_company and m.user_id=p_actor
  ))
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: private.user_report_conflicts(uuid,uuid,uuid)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: private.user_report_conflicts(uuid,uuid,uuid); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.can_read_job_moderation_visibility: narrow compatibility replacement.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.can_read_job_moderation_visibility(uuid,uuid)');
 expected text := $historical_body$
  select not exists(select 1 from public.job_moderation_state s
      where s.job_id=p_job_id and s.moderation_status='restricted')
    or exists(select 1 from public.users u where u.user_id=auth.uid() and u.status='active'::public.account_status
      and ((u.role='administrator'::public.user_role and exists(select 1 from public.administrator_profiles ap
          where ap.user_id=u.user_id and ap.can_manage_job_moderation)
        and not private.job_moderation_conflicts(auth.uid(),p_job_id))
        or (u.role='employer'::public.user_role and exists(select 1 from public.company_memberships m
          where m.company_id=p_company_id and m.user_id=u.user_id and m.member_role in ('owner','employer')))))
$historical_body$;
 replacement text := $historical_new$
  select not exists(select 1 from public.job_moderation_state s
      where s.job_id=p_job_id and s.moderation_status='restricted')
    or exists(select 1 from public.users u where u.user_id=auth.uid() and u.status='active'::public.account_status
      and ((u.role='administrator'::public.user_role and exists(select 1 from public.administrator_profiles ap
          where ap.user_id=u.user_id and ap.can_manage_job_moderation)
        and not private.job_moderation_conflicts(auth.uid(),p_job_id))
        or (u.role='employer'::public.user_role and exists(select 1 from public.company_memberships m
          where m.company_id=p_company_id and m.user_id=u.user_id and m.membership_status='active' and m.member_role in ('owner','employer')))))
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.can_read_job_moderation_visibility(uuid,uuid)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.can_read_job_moderation_visibility(uuid,uuid); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.list_company_logo_review_requests: compatibility source assertion; no replacement needed.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.list_company_logo_review_requests(integer,integer)');
 expected text := $historical_body$
begin
  if not exists (select 1 from public.users u join public.administrator_profiles ap on ap.user_id = u.user_id
    where u.user_id = auth.uid() and u.role::text = 'administrator' and u.status::text = 'active'
      and ap.can_review_companies = true) then
    raise exception 'You do not have permission to review Companies.';
  end if;
  if p_limit is null or p_limit not between 1 and 101 or p_offset is null or p_offset < 0 then
    raise exception 'Invalid page size or offset.';
  end if;
  return query select r.request_id, r.company_id, c.company_name::text, r.previous_storage_path,
    r.storage_path, 'Company logo'::text, r.submitted_at
  from public.company_logo_change_requests r join public.companies c on c.company_id = r.company_id
  where r.status = 'pending' and c.created_by <> auth.uid() and not exists (
    select 1 from public.company_memberships m where m.company_id = r.company_id and m.user_id = auth.uid())
  order by r.submitted_at, r.request_id limit p_limit offset p_offset;
end;
$historical_body$;
 replacement text := $historical_new$
begin
  if not exists (select 1 from public.users u join public.administrator_profiles ap on ap.user_id = u.user_id
    where u.user_id = auth.uid() and u.role::text = 'administrator' and u.status::text = 'active'
      and ap.can_review_companies = true) then
    raise exception 'You do not have permission to review Companies.';
  end if;
  if p_limit is null or p_limit not between 1 and 101 or p_offset is null or p_offset < 0 then
    raise exception 'Invalid page size or offset.';
  end if;
  return query select r.request_id, r.company_id, c.company_name::text, r.previous_storage_path,
    r.storage_path, 'Company logo'::text, r.submitted_at
  from public.company_logo_change_requests r join public.companies c on c.company_id = r.company_id
  where r.status = 'pending' and c.created_by <> auth.uid() and not exists (
    select 1 from public.company_memberships m where m.company_id = r.company_id and m.user_id = auth.uid())
  order by r.submitted_at, r.request_id limit p_limit offset p_offset;
end;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.list_company_logo_review_requests(integer,integer)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.list_company_logo_review_requests(integer,integer); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.list_company_review_requests: compatibility source assertion; no replacement needed.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.list_company_review_requests(integer,integer)');
 expected text := $historical_body$
begin
  if not exists (
    select 1
    from public.users as u
    join public.administrator_profiles as ap on ap.user_id = u.user_id
    where u.user_id = auth.uid()
      and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_review_companies = true
  ) then
    raise exception 'You do not have permission to review Companies.';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 101 then
    raise exception 'Invalid page size.';
  end if;
  if p_offset is null or p_offset < 0 then
    raise exception 'Invalid page offset.';
  end if;

  return query
  select r.request_id,
         r.company_id,
         c.company_name::text,
         r.submitted_by,
         r.profile_snapshot,
         r.storage_path,
         r.original_name::text,
         r.mime_type,
         r.size_bytes,
         r.submitted_at
  from public.company_verification_requests as r
  join public.companies as c on c.company_id = r.company_id
  where r.status = 'pending'::public.verification_status
    and c.created_by is distinct from auth.uid()
    and not exists (
      select 1
      from public.company_memberships as m
      where m.company_id = r.company_id
        and m.user_id = auth.uid()
    )
  order by r.submitted_at, r.request_id
  limit p_limit
  offset p_offset;
end;
$historical_body$;
 replacement text := $historical_new$
begin
  if not exists (
    select 1
    from public.users as u
    join public.administrator_profiles as ap on ap.user_id = u.user_id
    where u.user_id = auth.uid()
      and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_review_companies = true
  ) then
    raise exception 'You do not have permission to review Companies.';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 101 then
    raise exception 'Invalid page size.';
  end if;
  if p_offset is null or p_offset < 0 then
    raise exception 'Invalid page offset.';
  end if;

  return query
  select r.request_id,
         r.company_id,
         c.company_name::text,
         r.submitted_by,
         r.profile_snapshot,
         r.storage_path,
         r.original_name::text,
         r.mime_type,
         r.size_bytes,
         r.submitted_at
  from public.company_verification_requests as r
  join public.companies as c on c.company_id = r.company_id
  where r.status = 'pending'::public.verification_status
    and c.created_by is distinct from auth.uid()
    and not exists (
      select 1
      from public.company_memberships as m
      where m.company_id = r.company_id
        and m.user_id = auth.uid()
    )
  order by r.submitted_at, r.request_id
  limit p_limit
  offset p_offset;
end;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.list_company_review_requests(integer,integer)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.list_company_review_requests(integer,integer); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.list_dispute_eligible_records: narrow compatibility replacement.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.list_dispute_eligible_records(text,integer,integer)');
 expected text := $historical_body$
begin
  if p_category is null or p_category not in ('recruitment', 'work', 'payment')
     or p_limit is null or p_limit not between 1 and 101
     or p_offset is null or p_offset < 0 then
    raise exception 'Invalid dispute record query.';
  end if;
  if not exists (
    select 1 from public.users u where u.user_id = auth.uid()
      and u.status = 'active'::public.account_status
      and u.role in ('job_seeker'::public.user_role, 'employer'::public.user_role)
  ) then
    raise exception 'An active party account is required.';
  end if;

  if p_category = 'recruitment' then
    return query
    select a.application_id, 'recruitment'::text, j.title::text,
           c.company_name::text, a.applied_at, a.status::text
    from public.job_applications a
    join public.job_postings j on j.job_id = a.job_id
    join public.companies c on c.company_id = j.company_id
    where a.applicant_id = auth.uid()
       or exists (
         select 1 from public.company_memberships m
         where m.company_id = j.company_id and m.user_id = auth.uid()
           and m.member_role in ('owner', 'employer')
       )
    order by a.applied_at desc, a.application_id desc
    limit p_limit offset p_offset;
  else
    return query
    select a.assignment_id, p_category, j.title::text, c.company_name::text,
           a.scheduled_start, a.status::text
    from public.work_assignments a
    join public.job_postings j on j.job_id = a.job_id
    join public.companies c on c.company_id = a.company_id
    where a.worker_id = auth.uid()
       or exists (
         select 1 from public.company_memberships m
         where m.company_id = a.company_id and m.user_id = auth.uid()
           and m.member_role in ('owner', 'employer')
       )
    order by a.scheduled_start desc, a.assignment_id desc
    limit p_limit offset p_offset;
  end if;
end;
$historical_body$;
 replacement text := $historical_new$
begin
  if p_category is null or p_category not in ('recruitment', 'work', 'payment')
     or p_limit is null or p_limit not between 1 and 101
     or p_offset is null or p_offset < 0 then
    raise exception 'Invalid dispute record query.';
  end if;
  if not exists (
    select 1 from public.users u where u.user_id = auth.uid()
      and u.status = 'active'::public.account_status
      and u.role in ('job_seeker'::public.user_role, 'employer'::public.user_role)
  ) then
    raise exception 'An active party account is required.';
  end if;

  if p_category = 'recruitment' then
    return query
    select a.application_id, 'recruitment'::text, j.title::text,
           c.company_name::text, a.applied_at, a.status::text
    from public.job_applications a
    join public.job_postings j on j.job_id = a.job_id
    join public.companies c on c.company_id = j.company_id
    where a.applicant_id = auth.uid()
       or exists (
         select 1 from public.company_memberships m
         where m.company_id = j.company_id and m.user_id = auth.uid()
           and m.membership_status='active' and m.member_role in ('owner','employer')
       )
    order by a.applied_at desc, a.application_id desc
    limit p_limit offset p_offset;
  else
    return query
    select a.assignment_id, p_category, j.title::text, c.company_name::text,
           a.scheduled_start, a.status::text
    from public.work_assignments a
    join public.job_postings j on j.job_id = a.job_id
    join public.companies c on c.company_id = a.company_id
    where a.worker_id = auth.uid()
       or exists (
         select 1 from public.company_memberships m
         where m.company_id = a.company_id and m.user_id = auth.uid()
           and m.membership_status='active' and m.member_role in ('owner','employer')
       )
    order by a.scheduled_start desc, a.assignment_id desc
    limit p_limit offset p_offset;
  end if;
end;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.list_dispute_eligible_records(text,integer,integer)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.list_dispute_eligible_records(text,integer,integer); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.review_company_logo_change: compatibility source assertion; no replacement needed.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.review_company_logo_change(uuid,text,text)');
 expected text := $historical_body$
declare
  v_uid uuid := auth.uid(); v_company_id uuid; v_company public.companies%rowtype;
  v_request public.company_logo_change_requests%rowtype;
  v_comment text := nullif(btrim(p_review_comment),'');
begin
  if p_request_id is null or p_decision is null or p_decision not in ('verified','rejected') then
    raise exception 'Choose a valid logo review decision.';
  end if;
  if (p_decision = 'rejected' and v_comment is null) or length(v_comment) > 2000 then
    raise exception 'Rejection needs a reason. Comments must be 2000 characters or fewer.';
  end if;
  perform 1 from public.users u where u.user_id = v_uid
    and u.status::text = 'active' and u.role::text = 'administrator' for share;
  if not found then raise exception 'An active administrator account is required.'; end if;
  perform 1 from public.administrator_profiles ap where ap.user_id = v_uid
    and ap.can_review_companies = true for share;
  if not found then raise exception 'Company Review permission is required.'; end if;
  select r.company_id into v_company_id from public.company_logo_change_requests r where r.request_id = p_request_id;
  if not found then raise exception 'Logo request not found.'; end if;
  select * into v_company from public.companies c where c.company_id = v_company_id for update;
  if v_company.created_by = v_uid or exists (select 1 from public.company_memberships m
    where m.user_id = v_uid and m.company_id = v_company_id) then
    raise exception 'You cannot review a Company you own or belong to.';
  end if;
  select * into v_request from public.company_logo_change_requests r where r.request_id = p_request_id for update;
  if v_request.status <> 'pending' then
    raise exception 'This logo request is no longer pending. Refresh the queue.';
  end if;
  -- A document resubmission may have changed the current logo after submission.
  if p_decision = 'verified' and v_company.logo_storage_path is distinct from v_request.previous_storage_path then
    raise exception 'The current logo changed. Reject this stale request and ask the Owner to resubmit.';
  end if;
  if p_decision = 'verified' and not exists (select 1 from storage.objects o
    where o.bucket_id = 'jobmate-company-logos' and o.name = v_request.storage_path
      and (o.metadata ->> 'mimetype') = v_request.mime_type
      and (o.metadata ->> 'size')::bigint = v_request.size_bytes) then
    raise exception 'The submitted image is missing or changed. Reject and request another upload.';
  end if;
  update public.company_logo_change_requests set status = p_decision, reviewed_by = v_uid,
    reviewed_at = clock_timestamp(), review_comment = v_comment where request_id = p_request_id;
  if p_decision = 'verified' then
    update public.companies set logo_storage_path = v_request.storage_path where company_id = v_company_id;
    -- Audit trigger records both paths and the reviewer in this same transaction.
  end if;
  insert into public.notifications(user_id, notification_type, title, message) values (
    v_request.submitted_by, 'company_logo_review',
    case when p_decision = 'verified' then 'Company logo approved' else 'Company logo rejected' end,
    case when p_decision = 'verified'
      then format('The new logo for %s has been approved.', v_company.company_name)
      else format('The new logo for %s was rejected. Reason: %s', v_company.company_name, v_comment) end
  );
  return p_decision;
end;
$historical_body$;
 replacement text := $historical_new$
declare
  v_uid uuid := auth.uid(); v_company_id uuid; v_company public.companies%rowtype;
  v_request public.company_logo_change_requests%rowtype;
  v_comment text := nullif(btrim(p_review_comment),'');
begin
  if p_request_id is null or p_decision is null or p_decision not in ('verified','rejected') then
    raise exception 'Choose a valid logo review decision.';
  end if;
  if (p_decision = 'rejected' and v_comment is null) or length(v_comment) > 2000 then
    raise exception 'Rejection needs a reason. Comments must be 2000 characters or fewer.';
  end if;
  perform 1 from public.users u where u.user_id = v_uid
    and u.status::text = 'active' and u.role::text = 'administrator' for share;
  if not found then raise exception 'An active administrator account is required.'; end if;
  perform 1 from public.administrator_profiles ap where ap.user_id = v_uid
    and ap.can_review_companies = true for share;
  if not found then raise exception 'Company Review permission is required.'; end if;
  select r.company_id into v_company_id from public.company_logo_change_requests r where r.request_id = p_request_id;
  if not found then raise exception 'Logo request not found.'; end if;
  select * into v_company from public.companies c where c.company_id = v_company_id for update;
  if v_company.created_by = v_uid or exists (select 1 from public.company_memberships m
    where m.user_id = v_uid and m.company_id = v_company_id) then
    raise exception 'You cannot review a Company you own or belong to.';
  end if;
  select * into v_request from public.company_logo_change_requests r where r.request_id = p_request_id for update;
  if v_request.status <> 'pending' then
    raise exception 'This logo request is no longer pending. Refresh the queue.';
  end if;
  -- A document resubmission may have changed the current logo after submission.
  if p_decision = 'verified' and v_company.logo_storage_path is distinct from v_request.previous_storage_path then
    raise exception 'The current logo changed. Reject this stale request and ask the Owner to resubmit.';
  end if;
  if p_decision = 'verified' and not exists (select 1 from storage.objects o
    where o.bucket_id = 'jobmate-company-logos' and o.name = v_request.storage_path
      and (o.metadata ->> 'mimetype') = v_request.mime_type
      and (o.metadata ->> 'size')::bigint = v_request.size_bytes) then
    raise exception 'The submitted image is missing or changed. Reject and request another upload.';
  end if;
  update public.company_logo_change_requests set status = p_decision, reviewed_by = v_uid,
    reviewed_at = clock_timestamp(), review_comment = v_comment where request_id = p_request_id;
  if p_decision = 'verified' then
    update public.companies set logo_storage_path = v_request.storage_path where company_id = v_company_id;
    -- Audit trigger records both paths and the reviewer in this same transaction.
  end if;
  insert into public.notifications(user_id, notification_type, title, message) values (
    v_request.submitted_by, 'company_logo_review',
    case when p_decision = 'verified' then 'Company logo approved' else 'Company logo rejected' end,
    case when p_decision = 'verified'
      then format('The new logo for %s has been approved.', v_company.company_name)
      else format('The new logo for %s was rejected. Reason: %s', v_company.company_name, v_comment) end
  );
  return p_decision;
end;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.review_company_logo_change(uuid,text,text)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.review_company_logo_change(uuid,text,text); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.review_company_request: compatibility source assertion; no replacement needed.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.review_company_request(uuid,text,text)');
 expected text := $historical_body$
declare
  v_actor_id uuid := auth.uid();
  v_company_id uuid;
  v_created_by uuid;
  v_submitted_by uuid;
  v_company_name text;
  v_comment text := nullif(pg_catalog.btrim(p_review_comment), '');
begin
  if v_actor_id is null then
    raise exception 'Please log in first.';
  end if;
  if p_request_id is null
     or p_decision is null
     or p_decision not in ('verified', 'rejected') then
    raise exception 'Choose a valid Company review decision.';
  end if;
  if p_decision = 'rejected' and v_comment is null then
    raise exception 'A rejection reason is required.';
  end if;
  if v_comment is not null and pg_catalog.length(v_comment) > 2000 then
    raise exception 'Review comments must be 2000 characters or fewer.';
  end if;
  if not exists (
    select 1
    from public.users as u
    join public.administrator_profiles as ap on ap.user_id = u.user_id
    where u.user_id = v_actor_id
      and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_review_companies = true
  ) then
    raise exception 'You do not have permission to review Companies.';
  end if;

  select r.company_id, r.submitted_by, c.company_name::text
  into v_company_id, v_submitted_by, v_company_name
  from public.company_verification_requests as r
  join public.companies as c on c.company_id = r.company_id
  where r.request_id = p_request_id
    and r.status = 'pending'::public.verification_status
  for update;

  if not found then
    raise exception 'This Company request is no longer pending.';
  end if;

  select c.created_by
  into v_created_by
  from public.companies as c
  where c.company_id = v_company_id
  for update;

  if not found then
    raise exception 'Company record was not found.';
  end if;

  if v_created_by = v_actor_id or exists (
    select 1
    from public.company_memberships as m
    where m.company_id = v_company_id
      and m.user_id = v_actor_id
  ) then
    raise exception 'You cannot review a Company you created or belong to.';
  end if;

  update public.company_verification_requests
  set status = p_decision::public.verification_status,
      reviewed_at = pg_catalog.now(),
      reviewed_by = v_actor_id,
      review_comment = v_comment
  where request_id = p_request_id;

  update public.companies
  set verification_status = p_decision::public.verification_status,
      updated_at = pg_catalog.now()
  where company_id = v_company_id;

  insert into public.notifications (
    user_id,
    notification_type,
    title,
    message
  ) values (
    v_submitted_by,
    'company_review',
    case when p_decision = 'verified'
      then 'Company application approved'
      else 'Company application rejected'
    end,
    case when p_decision = 'verified'
      then pg_catalog.format(
        'Your Company application for %s has been approved.',
        v_company_name
      )
      else pg_catalog.format(
        'Your Company application for %s was rejected. Reason: %s',
        v_company_name,
        v_comment
      )
    end
  );

  return p_decision;
end;
$historical_body$;
 replacement text := $historical_new$
declare
  v_actor_id uuid := auth.uid();
  v_company_id uuid;
  v_created_by uuid;
  v_submitted_by uuid;
  v_company_name text;
  v_comment text := nullif(pg_catalog.btrim(p_review_comment), '');
begin
  if v_actor_id is null then
    raise exception 'Please log in first.';
  end if;
  if p_request_id is null
     or p_decision is null
     or p_decision not in ('verified', 'rejected') then
    raise exception 'Choose a valid Company review decision.';
  end if;
  if p_decision = 'rejected' and v_comment is null then
    raise exception 'A rejection reason is required.';
  end if;
  if v_comment is not null and pg_catalog.length(v_comment) > 2000 then
    raise exception 'Review comments must be 2000 characters or fewer.';
  end if;
  if not exists (
    select 1
    from public.users as u
    join public.administrator_profiles as ap on ap.user_id = u.user_id
    where u.user_id = v_actor_id
      and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_review_companies = true
  ) then
    raise exception 'You do not have permission to review Companies.';
  end if;

  select r.company_id, r.submitted_by, c.company_name::text
  into v_company_id, v_submitted_by, v_company_name
  from public.company_verification_requests as r
  join public.companies as c on c.company_id = r.company_id
  where r.request_id = p_request_id
    and r.status = 'pending'::public.verification_status
  for update;

  if not found then
    raise exception 'This Company request is no longer pending.';
  end if;

  select c.created_by
  into v_created_by
  from public.companies as c
  where c.company_id = v_company_id
  for update;

  if not found then
    raise exception 'Company record was not found.';
  end if;

  if v_created_by = v_actor_id or exists (
    select 1
    from public.company_memberships as m
    where m.company_id = v_company_id
      and m.user_id = v_actor_id
  ) then
    raise exception 'You cannot review a Company you created or belong to.';
  end if;

  update public.company_verification_requests
  set status = p_decision::public.verification_status,
      reviewed_at = pg_catalog.now(),
      reviewed_by = v_actor_id,
      review_comment = v_comment
  where request_id = p_request_id;

  update public.companies
  set verification_status = p_decision::public.verification_status,
      updated_at = pg_catalog.now()
  where company_id = v_company_id;

  insert into public.notifications (
    user_id,
    notification_type,
    title,
    message
  ) values (
    v_submitted_by,
    'company_review',
    case when p_decision = 'verified'
      then 'Company application approved'
      else 'Company application rejected'
    end,
    case when p_decision = 'verified'
      then pg_catalog.format(
        'Your Company application for %s has been approved.',
        v_company_name
      )
      else pg_catalog.format(
        'Your Company application for %s was rejected. Reason: %s',
        v_company_name,
        v_comment
      )
    end
  );

  return p_decision;
end;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.review_company_request(uuid,text,text)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.review_company_request(uuid,text,text); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- public.submit_company_logo_change: narrow compatibility replacement.
DO $historical_compatibility$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.submit_company_logo_change(uuid,uuid,text,text)');
 expected text := $historical_body$
declare
  v_uid uuid := auth.uid(); v_current text; v_prefix text; v_mime text;
  v_metadata jsonb; v_size bigint; v_existing public.company_logo_change_requests%rowtype;
begin
  perform 1 from public.users u where u.user_id = v_uid
    and u.status::text = 'active' and u.role::text = 'employer' for update;
  if not found then raise exception 'An active Employer account is required.'; end if;
  if p_company_id is null or p_upload_id is null or p_storage_path is null then
    raise exception 'Company, upload ID and logo path are required.';
  end if;
  perform 1 from public.company_memberships m where m.user_id = v_uid
    and m.company_id = p_company_id and m.member_role = 'owner' for share;
  if not found then raise exception 'Only the Company Owner may change its logo.'; end if;
  select c.logo_storage_path into v_current from public.companies c
    where c.company_id = p_company_id for update;
  if not found then raise exception 'Company not found.'; end if;
  select * into v_existing from public.company_logo_change_requests r where r.request_id = p_upload_id;
  if found then
    if v_existing.company_id = p_company_id and v_existing.submitted_by = v_uid
      and v_existing.storage_path = p_storage_path
      and v_existing.previous_storage_path is not distinct from p_expected_logo_path then
      return v_existing.status; -- Same immutable request, including a lost response after review.
    end if;
    raise exception 'This logo request ID has already been used.';
  end if;
  if exists (select 1 from public.company_logo_change_requests r
    where r.company_id = p_company_id and r.status = 'pending') then
    raise exception 'A logo change is already waiting for review. Refresh to view its status.';
  end if;
  if v_current is distinct from p_expected_logo_path then
    raise exception 'The company logo changed elsewhere. Refresh the Company page first.';
  end if;
  v_prefix := v_uid::text || '/profile-' || p_upload_id::text || '/logo.';
  if p_storage_path not in (v_prefix || 'jpg', v_prefix || 'png', v_prefix || 'webp') then
    raise exception 'Invalid company logo path.';
  end if;
  select o.metadata into v_metadata from storage.objects o
    where o.bucket_id = 'jobmate-company-logos' and o.name = p_storage_path;
  if not found then raise exception 'Upload the logo before submitting.'; end if;
  v_size := coalesce((v_metadata ->> 'size')::bigint, 0);
  v_mime := case when right(p_storage_path,4) = '.jpg' then 'image/jpeg'
    when right(p_storage_path,4) = '.png' then 'image/png' else 'image/webp' end;
  if v_size not between 1 and 2097152 or (v_metadata ->> 'mimetype') is distinct from v_mime then
    raise exception 'The logo must be JPG, PNG or WebP of at most 2 MiB.';
  end if;
  insert into public.company_logo_change_requests(
    request_id, company_id, submitted_by, previous_storage_path, storage_path, mime_type, size_bytes
  ) values (p_upload_id, p_company_id, v_uid, v_current, p_storage_path, v_mime, v_size);
  -- Current logo, Company verification and job permissions stay unchanged.
  return 'pending';
end;
$historical_body$;
 replacement text := $historical_new$
declare
  v_uid uuid := auth.uid(); v_current text; v_prefix text; v_mime text;
  v_metadata jsonb; v_size bigint; v_existing public.company_logo_change_requests%rowtype;
begin
  perform 1 from public.users u where u.user_id = v_uid
    and u.status::text = 'active' and u.role::text = 'employer' for update;
  if not found then raise exception 'An active Employer account is required.'; end if;
  if p_company_id is null or p_upload_id is null or p_storage_path is null then
    raise exception 'Company, upload ID and logo path are required.';
  end if;
  perform 1 from public.company_memberships m where m.user_id = v_uid
    and m.company_id = p_company_id and m.membership_status = 'active' and m.member_role = 'owner' for share;
  if not found then raise exception 'Only the Company Owner may change its logo.'; end if;
  select c.logo_storage_path into v_current from public.companies c
    where c.company_id = p_company_id for update;
  if not found then raise exception 'Company not found.'; end if;
  select * into v_existing from public.company_logo_change_requests r where r.request_id = p_upload_id;
  if found then
    if v_existing.company_id = p_company_id and v_existing.submitted_by = v_uid
      and v_existing.storage_path = p_storage_path
      and v_existing.previous_storage_path is not distinct from p_expected_logo_path then
      return v_existing.status; -- Same immutable request, including a lost response after review.
    end if;
    raise exception 'This logo request ID has already been used.';
  end if;
  if exists (select 1 from public.company_logo_change_requests r
    where r.company_id = p_company_id and r.status = 'pending') then
    raise exception 'A logo change is already waiting for review. Refresh to view its status.';
  end if;
  if v_current is distinct from p_expected_logo_path then
    raise exception 'The company logo changed elsewhere. Refresh the Company page first.';
  end if;
  v_prefix := v_uid::text || '/profile-' || p_upload_id::text || '/logo.';
  if p_storage_path not in (v_prefix || 'jpg', v_prefix || 'png', v_prefix || 'webp') then
    raise exception 'Invalid company logo path.';
  end if;
  select o.metadata into v_metadata from storage.objects o
    where o.bucket_id = 'jobmate-company-logos' and o.name = p_storage_path;
  if not found then raise exception 'Upload the logo before submitting.'; end if;
  v_size := coalesce((v_metadata ->> 'size')::bigint, 0);
  v_mime := case when right(p_storage_path,4) = '.jpg' then 'image/jpeg'
    when right(p_storage_path,4) = '.png' then 'image/png' else 'image/webp' end;
  if v_size not between 1 and 2097152 or (v_metadata ->> 'mimetype') is distinct from v_mime then
    raise exception 'The logo must be JPG, PNG or WebP of at most 2 MiB.';
  end if;
  insert into public.company_logo_change_requests(
    request_id, company_id, submitted_by, previous_storage_path, storage_path, mime_type, size_bytes
  ) values (p_upload_id, p_company_id, v_uid, v_current, p_storage_path, v_mime, v_size);
  -- Current logo, Company verification and job permissions stay unchanged.
  return 'pending';
end;
$historical_new$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: public.submit_company_logo_change(uuid,uuid,text,text)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: public.submit_company_logo_change(uuid,uuid,text,text); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
$historical_compatibility$;
COMMIT;
