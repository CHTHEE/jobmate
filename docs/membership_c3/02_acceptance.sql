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

COMMIT;
