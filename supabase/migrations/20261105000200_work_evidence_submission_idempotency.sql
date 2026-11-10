-- DRAFT ONLY: Step 101G. Not applied or tested against a database.
-- Additive to 20261105000100_work_attendance_verification.sql.
-- See docs/work_evidence_idempotency_test_plan.md before any deployment.
BEGIN;

ALTER TABLE public.work_evidence_submissions
    ADD COLUMN request_id uuid,
    ADD COLUMN request_storage_paths text[],
    ADD CONSTRAINT work_evidence_submission_request_unique
        UNIQUE (submitted_by, assignment_id, request_id),
    ADD CONSTRAINT work_evidence_submission_request_consistency
        CHECK (
            (request_id IS NULL AND request_storage_paths IS NULL)
            OR (request_id IS NOT NULL AND request_storage_paths IS NOT NULL)
        );

-- Default UNIQUE semantics permit legacy NULL request IDs. No historical rows
-- are backfilled, reclassified or associated with invented request identities.
-- Direct table privileges and RLS remain exactly as in the prerequisite.

CREATE FUNCTION public.submit_work_evidence_idempotent(
    p_assignment_id uuid,
    p_request_id uuid,
    p_description text,
    p_storage_paths text[]
)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_assignment_id uuid;
    v_existing public.work_evidence_submissions%ROWTYPE;
    v_description text;
    v_round integer;
    v_updated integer;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '28000', MESSAGE = 'Authentication required';
    END IF;

    -- Lock the same row as the legacy submit/review/verify functions. The lock
    -- lasts until the surrounding transaction ends. Filter by current ownership
    -- to give missing and unauthorized assignments the same safe response.
    SELECT a.assignment_id
    INTO v_assignment_id
    FROM public.work_assignments AS a
    WHERE a.assignment_id = p_assignment_id
      AND a.worker_id = v_actor
    FOR UPDATE OF a;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501', MESSAGE = 'Work assignment access denied';
    END IF;

    -- Check after any lock wait, and before returning a historical result.
    IF NOT EXISTS (
        SELECT 1
        FROM public.users AS u
        WHERE u.user_id = v_actor
          AND u.role = 'job_seeker'::public.user_role
          AND u.status = 'active'::public.account_status
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501', MESSAGE = 'Active worker access required';
    END IF;

    IF p_request_id IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023', MESSAGE = 'A submission request ID is required';
    END IF;

    v_description := pg_catalog.btrim(p_description);

    -- These separate statements run after acquiring the assignment lock.
    -- Under READ COMMITTED the next lookup sees a preceding caller's commit.
    -- At stricter isolation levels a serialization error must be retried with
    -- the SAME request key/payload, never interpreted as permission to rekey.
    SELECT s.*
    INTO v_existing
    FROM public.work_evidence_submissions AS s
    WHERE s.submitted_by = v_actor
      AND s.assignment_id = v_assignment_id
      AND s.request_id = p_request_id;

    IF FOUND THEN
        -- Array equality includes ordering and dimensions. Normalization is
        -- precisely PostgreSQL btrim, matching the existing submission RPC.
        IF v_existing.description IS DISTINCT FROM v_description
           OR v_existing.request_storage_paths IS DISTINCT FROM p_storage_paths
        THEN
            RAISE EXCEPTION USING
                ERRCODE = 'P0001',
                MESSAGE = 'Submission request conflicts with its original payload';
        END IF;

        -- Do not recheck NEW-submission status, attendance or Storage here.
        -- Replay after review/verification returns only the recorded round;
        -- it creates no history, evidence, submission or status changes.
        RETURN v_existing.submission_round;
    END IF;

    -- Reject unusual SQL array shapes, not just ordinary JSON arrays. Ordered
    -- paths must be one-dimensional, 1-based, non-null and contain 1-5 files.
    IF p_storage_paths IS NULL
       OR pg_catalog.array_ndims(p_storage_paths) IS DISTINCT FROM 1
       OR pg_catalog.array_lower(p_storage_paths, 1) IS DISTINCT FROM 1
       OR pg_catalog.cardinality(p_storage_paths) NOT BETWEEN 1 AND 5
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023', MESSAGE = 'Submit between 1 and 5 evidence files';
    END IF;

    IF pg_catalog.array_position(p_storage_paths, NULL::text) IS NOT NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023', MESSAGE = 'Invalid evidence file selection';
    END IF;

    -- Nested call retains auth.uid() from the request, not the definer's ID.
    -- It reacquires our own assignment lock without blocking and enforces ALL
    -- legacy description/eligibility/attendance/path/owner/MIME/size/reuse rules.
    -- Its writes are part of THIS transaction; there is no independent commit.
    v_round := public.submit_work_evidence(
        v_assignment_id, v_description, p_storage_paths
    );

    -- Round allocation is server-owned. Use the exact returned round together
    -- with assignment AND worker; never attach a key to max(round) or a client
    -- timestamp. Require an untouched row and verify the returned payload.
    UPDATE public.work_evidence_submissions AS s
    SET request_id = p_request_id,
        request_storage_paths = p_storage_paths
    WHERE s.assignment_id = v_assignment_id
      AND s.submitted_by = v_actor
      AND s.submission_round = v_round
      AND s.request_id IS NULL
      AND s.request_storage_paths IS NULL
      AND s.description = v_description
      AND s.file_count = pg_catalog.cardinality(p_storage_paths);

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    IF v_updated <> 1 THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001', MESSAGE = 'Unable to confirm submission request';
    END IF;

    -- No exception handler swallows failures: an association/constraint failure
    -- rolls back the nested RPC's evidence, submission, history and status too.
    RETURN v_round;
END;
$function$;

REVOKE ALL ON FUNCTION public.submit_work_evidence_idempotent(
    uuid, uuid, text, text[]
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.submit_work_evidence_idempotent(
    uuid, uuid, text, text[]
) TO authenticated;

CREATE FUNCTION public.get_my_work_evidence_request(
    p_assignment_id uuid,
    p_request_id uuid
)
RETURNS TABLE (
    request_id uuid,
    submission_round integer,
    submitted_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor uuid := auth.uid();
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '28000', MESSAGE = 'Authentication required';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.work_assignments AS a
        JOIN public.users AS u ON u.user_id = a.worker_id
        WHERE a.assignment_id = p_assignment_id
          AND a.worker_id = v_actor
          AND u.role = 'job_seeker'::public.user_role
          AND u.status = 'active'::public.account_status
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501', MESSAGE = 'Work assignment access denied';
    END IF;

    IF p_request_id IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023', MESSAGE = 'A submission request ID is required';
    END IF;

    RETURN QUERY
    SELECT s.request_id, s.submission_round, s.submitted_at
    FROM public.work_evidence_submissions AS s
    WHERE s.assignment_id = p_assignment_id
      AND s.submitted_by = v_actor
      AND s.request_id = p_request_id;
    -- No row means NOT OBSERVED COMMITTED, never proof of failure. This read
    -- cannot observe uncommitted or not-yet-arrived requests and does not unlock
    -- retries with a different key. No paths/descriptions are returned.
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_work_evidence_request(uuid, uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_my_work_evidence_request(uuid, uuid)
TO authenticated;

-- The existing three-argument RPC and its grants are intentionally unchanged.
-- Only callers of the new RPC receive keyed replay guarantees. Losing a key
-- across app restart is still unresolved; do not enable the production UI.
COMMIT;
