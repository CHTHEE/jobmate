-- DANGER: DISPOSABLE, ISOLATED TEST DATABASE ONLY. NEVER shared/production Supabase.
-- Manual psql test, not a migration or production verification script.
-- Requires 20261105000300 and 20261106000300 over the base Module 4 schema.
-- Supply psql vars: assignment_id, worker_id, employer_id, outsider_id,
-- pdf_round1_path, pdf_round2_path. Use a disposable checked-out assignment
-- with NO previous evidence/history. Upload two different valid PDFs through
-- private Storage as that worker first. Never use cafe or verified QA records.
-- Worker/employer must be active and authorized for this synthetic assignment;
-- employer membership/company verification must qualify. Outsider has no access.
-- Keep populated fixture/protection manifests and expanded psql output private.
-- Also REQUIRED: protected_assignment_ids, a non-empty JSON array of UUID strings
-- from a private, reviewed manifest covering ALL protected real/QA assignments.
-- No IDs are embedded here. Never use dummy IDs; completeness is operator-verified.
-- Missing/empty/null/malformed inputs abort before RPCs; no default or bypass.
-- Missing psql variables cause SQL errors under ON_ERROR_STOP. Keep it enabled.
-- Operator must be able to SET ROLE authenticated and set the local JWT subject;
-- never grant these administrative test capabilities to application users.
-- RPCs INSERT/UPDATE attempts, evidence, submissions, reviews, assignments and
-- audit history. Full execution ends in ROLLBACK. On error, ON_ERROR_STOP may
-- stop before ROLLBACK: roll back or disconnect, never COMMIT. RPC row locks can
-- block other sessions until transaction end; no explicit lock/statement timeout.
-- Rollback does NOT undo fixture creation, prior private Storage HTTP uploads,
-- or external trigger effects. Provision/upload only after isolated fixture
-- approval and protection checks. Do not fabricate storage.objects records.
-- Dispose of the isolated database AND its test Storage objects separately after
-- testing, using an approved isolated-environment cleanup. Never delete shared
-- Storage objects/assignments or assume SQL rollback removes uploaded PDFs.
-- This script cannot establish connection isolation or protection-list completeness.
\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('test.protected_assignments', :'protected_assignment_ids', true);
SELECT set_config('test.assignment', :'assignment_id', true);
SELECT set_config('test.worker', :'worker_id', true);
SELECT set_config('test.employer', :'employer_id', true);
SELECT set_config('test.outsider', :'outsider_id', true);
SELECT set_config('test.pdf1', :'pdf_round1_path', true);
SELECT set_config('test.pdf2', :'pdf_round2_path', true);
SELECT set_config('request.jwt.claim.sub', :'worker_id', true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE a uuid := current_setting('test.assignment')::uuid;
    protected_json jsonb := current_setting('test.protected_assignments')::jsonb;
    protected_item jsonb; protected_ids uuid[] := ARRAY[]::uuid[];
    worker uuid := current_setting('test.worker')::uuid;
    employer uuid := current_setting('test.employer')::uuid;
    pdf1 text := current_setting('test.pdf1'); pdf2 text := current_setting('test.pdf2');
    s jsonb; attempt jsonb; replay jsonb; review jsonb; old_request uuid;
BEGIN
    IF jsonb_typeof(protected_json) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'Non-empty protected_assignment_ids JSON UUID array required';
    END IF;
    IF jsonb_array_length(protected_json) = 0 THEN
        RAISE EXCEPTION 'protected_assignment_ids must not be empty';
    END IF;
    FOR protected_item IN SELECT value FROM jsonb_array_elements(protected_json) LOOP
        IF jsonb_typeof(protected_item) IS DISTINCT FROM 'string'
           OR btrim(protected_item #>> '{}') = '' THEN
            RAISE EXCEPTION 'Every protected assignment must be a UUID string';
        END IF;
        protected_ids := array_append(protected_ids, (protected_item #>> '{}')::uuid);
    END LOOP;
    IF a = ANY(protected_ids) OR pdf1 = pdf2 THEN
        RAISE EXCEPTION 'Unsafe test fixture';
    END IF;
    s := public.work_evidence_workflow_context(a);
    IF (s->>'latest_round')::integer <> 0 OR jsonb_array_length(s->'history') <> 0
        OR s->>'attendance_complete' <> 'true' THEN RAISE EXCEPTION 'Fresh checked-out fixture required'; END IF;
    BEGIN
        PERFORM public.prepare_my_work_evidence_submission(a, 0, 'Six files', ARRAY[pdf1,pdf1,pdf1,pdf1,pdf1,pdf1]);
        RAISE EXCEPTION 'File count limit bypass';
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
    attempt := public.prepare_my_work_evidence_submission(a, 0, 'Initial PDF report', ARRAY[pdf1]);
    replay := public.prepare_my_work_evidence_submission(a, 0, 'Initial PDF report', ARRAY[pdf1]);
    IF attempt->>'request_id' IS DISTINCT FROM replay->>'request_id' THEN RAISE EXCEPTION 'Prepare replay changed request'; END IF;
    BEGIN
        PERFORM public.prepare_my_work_evidence_submission(a, 0, 'Changed payload', ARRAY[pdf1]);
        RAISE EXCEPTION 'Changed preparation accepted';
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
    attempt := public.submit_work_evidence_idempotent(a, (attempt->>'request_id')::uuid);
    replay := public.submit_work_evidence_idempotent(a, (attempt->>'request_id')::uuid);
    IF attempt IS DISTINCT FROM replay OR attempt->>'state' <> 'committed' THEN RAISE EXCEPTION 'Submit replay failed'; END IF;
    PERFORM set_config('request.jwt.claim.sub', employer::text, true);
    IF public.can_read_work_evidence_file(pdf1) IS NOT TRUE OR public.can_read_work_evidence_file(pdf2) IS TRUE THEN
        RAISE EXCEPTION 'Employer submitted-file scope failed'; END IF;
    review := public.prepare_work_evidence_review(a, 1, 'more_evidence_requested', 'Add closing task details');
    old_request := (review->>'request_id')::uuid;
    BEGIN
        PERFORM public.prepare_work_evidence_review(a, 1, 'verified', NULL);
        RAISE EXCEPTION 'Conflicting review accepted';
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
    review := public.commit_work_evidence_review(a, old_request);
    replay := public.commit_work_evidence_review(a, old_request);
    IF review IS DISTINCT FROM replay THEN RAISE EXCEPTION 'Review replay changed result'; END IF;
    PERFORM set_config('request.jwt.claim.sub', worker::text, true);
    s := public.work_evidence_workflow_context(a);
    IF s->'history'->1->>'note' <> 'Add closing task details' OR jsonb_array_length(s->'history') <> 2 THEN
        RAISE EXCEPTION 'Worker did not see request reason/history'; END IF;
    attempt := public.prepare_my_work_evidence_submission(a, 1, 'Updated PDF report', ARRAY[pdf2]);
    attempt := public.submit_work_evidence_idempotent(a, (attempt->>'request_id')::uuid);
    IF (attempt->>'target_round')::integer <> 2 THEN RAISE EXCEPTION 'Resubmission round incorrect'; END IF;
    PERFORM set_config('request.jwt.claim.sub', employer::text, true);
    PERFORM public.commit_work_evidence_review(a, old_request);
    s := public.work_evidence_workflow_context(a);
    IF s->>'verification_status' <> 'pending_review' OR jsonb_array_length(s->'history') <> 3 THEN
        RAISE EXCEPTION 'Old review changed later round'; END IF;
    IF public.can_read_work_evidence_file(pdf2) IS NOT TRUE THEN RAISE EXCEPTION 'New submitted PDF not authorized'; END IF;
    review := public.prepare_work_evidence_review(a, 2, 'verified', NULL);
    PERFORM public.commit_work_evidence_review(a, (review->>'request_id')::uuid);
    s := public.work_evidence_workflow_context(a);
    IF s->>'verification_status' <> 'verified' OR jsonb_array_length(s->'history') <> 4 THEN
        RAISE EXCEPTION 'Final verification/history failed'; END IF;
    PERFORM set_config('request.jwt.claim.sub', current_setting('test.outsider'), true);
    BEGIN
        PERFORM public.work_evidence_workflow_context(a);
        RAISE EXCEPTION 'Unauthorized history exposed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    IF public.can_read_work_evidence_file(pdf1) IS TRUE THEN RAISE EXCEPTION 'Unauthorized PDF exposed'; END IF;
    IF has_function_privilege('authenticated','public.submit_work_evidence(uuid,text,text[])','EXECUTE')
        OR has_function_privilege('authenticated','public.verify_work_assignment(uuid)','EXECUTE')
        OR has_function_privilege('authenticated','public.request_more_work_evidence(uuid,text)','EXECUTE') THEN
        RAISE EXCEPTION 'Legacy write bypass still executable';
    END IF;
END;
$test$;
ROLLBACK;
-- Separate required multi-session checks: race prepare/commit for one round,
-- competing employers/decisions, delayed old requests across a new round,
-- rollback, serialization/deadlock handling, revoked membership and account
-- status, blocked-attempt immutability, invalid ownership/MIME/size/path reuse,
-- and Storage INSERT/SELECT/UPDATE/DELETE policies through real Storage APIs.
