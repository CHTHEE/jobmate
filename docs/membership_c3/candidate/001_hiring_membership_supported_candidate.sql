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
COMMIT;