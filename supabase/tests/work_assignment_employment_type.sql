-- psql -X -v disposable_shift_type_fixture=true -d <empty-local-db> -f <this-file>
\set ON_ERROR_STOP on
\if :{?disposable_shift_type_fixture}
  SELECT :'disposable_shift_type_fixture' = 'true'
    AND (pg_catalog.inet_server_addr() IS NULL OR
         pg_catalog.inet_server_addr() IN ('127.0.0.1'::inet, '::1'::inet))
    AND pg_catalog.to_regnamespace('private') IS NULL
    AND pg_catalog.to_regclass('public.job_postings') IS NULL
    AND pg_catalog.to_regclass('public.work_assignments') IS NULL AS safe_fixture \gset
\else
  \set safe_fixture false
\endif
\if :safe_fixture
\else
DO $$ BEGIN RAISE EXCEPTION 'Use a dedicated empty local database'; END $$;
\endif

CREATE SCHEMA private;
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
END;
$$;
CREATE TABLE public.job_postings (
    job_id integer PRIMARY KEY, company_id integer NOT NULL, employment_type text
);
CREATE TABLE public.work_assignments (job_id integer, company_id integer, status text);
INSERT INTO public.job_postings VALUES
    (1, 1, 'part_time'), (2, 1, 'temporary'), (3, 1, 'full_time'),
    (4, 1, 'internship'), (5, 1, 'contract'), (6, 1, 'unknown'), (7, 1, NULL);
INSERT INTO public.work_assignments VALUES (3, 1, 'scheduled');

\ir ../migrations/20261120000300_require_shift_eligible_employment_types.sql

BEGIN;
DO $test$
DECLARE
    job integer;
BEGIN
    INSERT INTO public.work_assignments VALUES (1, 1, 'scheduled'), (2, 1, 'scheduled');
    FOR job IN 3..8 LOOP
        BEGIN
            INSERT INTO public.work_assignments VALUES (job, 1, 'scheduled');
            RAISE EXCEPTION 'Unexpectedly accepted job %', job;
        EXCEPTION WHEN check_violation THEN NULL;
        END;
    END LOOP;
    BEGIN
        INSERT INTO public.work_assignments VALUES (1, 2, 'scheduled');
        RAISE EXCEPTION 'Accepted a posting from a different company';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    UPDATE public.work_assignments SET status = 'completed' WHERE job_id = 3;
    ASSERT EXISTS (SELECT FROM public.work_assignments WHERE job_id = 3 AND status = 'completed');
END;
$test$;
ROLLBACK;
