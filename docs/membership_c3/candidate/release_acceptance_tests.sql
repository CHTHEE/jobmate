-- DRAFT / NOT APPROVED FOR DEPLOYMENT. UNEXECUTED psql test program.
-- ONLY on a disposable local database AFTER the exact candidate is separately
-- approved for isolated testing and installed there. Does not apply any candidate
-- or change/remove its approval guards. Requires synthetic empty test baseline.
\set ON_ERROR_STOP on
SELECT current_database() LIKE 'jobmate_c3_disposable%'
 AND inet_server_addr() IN ('127.0.0.1'::inet,'::1'::inet)
 AND current_user='postgres' AS disposable_local \gset
\if :disposable_local
\else
 \echo 'STOP: requires explicitly disposable loopback PostgreSQL database as postgres'
 \quit 3
\endif
BEGIN;
SET LOCAL statement_timeout='20s';
SET LOCAL lock_timeout='5s';
-- Existing executable fixtures/assertions: two companies, replay, real API role,
-- inactive/revoked conflicts, decline/withdraw, injected write failures, owners.
\ir ../local_tests/acceptance_cases.sql
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='00000000-0000-4000-8000-000000000101';
SELECT public.c3_assert(
 (public.get_my_hiring_membership(public.c3_uid(501))->>'membership_status')='revoked',
 'authoritative revoked read');
SELECT public.c3_assert(
 (public.get_my_hiring_membership(public.c3_uid(502))->>'membership_status')='active',
 'second company read isolated');
DO $$ BEGIN
 BEGIN
  PERFORM public.get_my_hiring_membership(public.c3_uid(505));
  RAISE EXCEPTION 'Expected foreign application denial';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO public.company_memberships(user_id,company_id,member_role)
  VALUES(public.c3_uid(101),public.c3_uid(399),'owner');
  RAISE EXCEPTION 'Expected direct membership write denial';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT public.c3_assert(NOT has_function_privilege('anon',
 'public.get_my_hiring_membership(uuid)','EXECUTE'),'anonymous membership RPC denied');
SELECT public.c3_assert(NOT has_function_privilege('service_role',
 'public.get_my_hiring_membership(uuid)','EXECUTE'),'new read RPC not exposed to service API');
SELECT public.c3_assert(NOT has_table_privilege('authenticated',
 'private.hiring_membership_acceptances','SELECT'),'receipt is server only');
SELECT public.c3_assert((SELECT prosecdef FROM pg_catalog.pg_proc
 WHERE oid='public.respond_to_job_application(uuid,text)'::regprocedure),
 'acceptance remains security definer');
ROLLBACK;
\echo 'Sequential assertions passed; fixtures rolled back. NOT concurrency, Storage, onboarding or full RLS certification.'
-- Multi-session tests cannot use these rolled-back fixtures. Existing
-- local_tests/run_disposable.ps1 and concurrent_assertions.sql define the separate
-- concurrency fixture, but currently test only the supported subset, not 002.
