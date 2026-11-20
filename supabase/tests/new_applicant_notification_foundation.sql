-- psql -X -v disposable_applicant_fixture=true -d <empty-local-db> -f <this-file>
-- Use a dedicated disposable PostgreSQL cluster. Setup commits fixture DDL.
\set ON_ERROR_STOP on
\if :{?disposable_applicant_fixture}
\else
  \set disposable_applicant_fixture false
\endif
SELECT :'disposable_applicant_fixture' = 'true'
  AND (pg_catalog.inet_server_addr() IS NULL
    OR pg_catalog.inet_server_addr() IN ('127.0.0.1'::inet, '::1'::inet))
  AND pg_catalog.to_regnamespace('auth') IS NULL
  AND pg_catalog.to_regnamespace('applicant_notifications_private') IS NULL
  AND pg_catalog.to_regclass('public.users') IS NULL
  AND pg_catalog.to_regclass('public.job_applications') IS NULL
  AND pg_catalog.to_regclass('public.job_postings') IS NULL
  AS safe_fixture \gset
\if :safe_fixture
\else
DO $$ BEGIN RAISE EXCEPTION 'Use a dedicated, empty local PostgreSQL cluster with explicit fixture opt-in'; END $$;
\endif

BEGIN;
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role BYPASSRLS; END IF;
END;
$$;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE SET search_path = ''
AS $$ SELECT nullif(pg_catalog.current_setting('request.jwt.claim.sub', true), '')::uuid $$;

CREATE TABLE public.users (user_id uuid PRIMARY KEY, role text NOT NULL, status text NOT NULL);
CREATE TABLE public.companies (company_id uuid PRIMARY KEY, verification_status text NOT NULL);
CREATE TABLE public.company_memberships (user_id uuid NOT NULL, company_id uuid NOT NULL, member_role text NOT NULL);
CREATE TABLE public.job_postings (job_id uuid PRIMARY KEY, company_id uuid NOT NULL, status text NOT NULL);
-- Omit the applicant FK in this fixture to test the required visibility join.
CREATE TABLE public.job_applications (
  application_id uuid PRIMARY KEY, job_id uuid NOT NULL,
  applicant_id uuid NOT NULL, applied_at timestamptz NOT NULL
);
CREATE FUNCTION public.can_manage_company_jobs(p_company_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users AS u
    JOIN public.company_memberships AS m ON m.user_id = u.user_id
    JOIN public.companies AS c ON c.company_id = m.company_id
    WHERE u.user_id = auth.uid() AND u.role = 'employer' AND u.status = 'active'
      AND m.company_id = p_company_id AND m.member_role IN ('owner', 'employer')
      AND c.verification_status = 'verified'
  )
$$;
COMMIT;

\ir ../migrations/20261120000200_new_applicant_notification_foundation.sql

BEGIN;
SET LOCAL plpgsql.check_asserts = on;
INSERT INTO public.users VALUES
  ('00000000-0000-4000-8000-000000000001', 'employer', 'active'),
  ('00000000-0000-4000-8000-000000000002', 'employer', 'active'),
  ('00000000-0000-4000-8000-000000000003', 'employer', 'inactive'),
  ('00000000-0000-4000-8000-000000000004', 'job_seeker', 'active');
INSERT INTO public.companies VALUES
  ('00000000-0000-4000-8000-000000000011', 'verified'),
  ('00000000-0000-4000-8000-000000000012', 'verified');
INSERT INTO public.company_memberships VALUES
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000011', 'owner'),
  ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000011', 'employer'),
  ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000012', 'employer'),
  ('00000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000011', 'employer');
INSERT INTO public.job_postings VALUES
  ('00000000-0000-4000-8000-000000000021', '00000000-0000-4000-8000-000000000011', 'closed'),
  ('00000000-0000-4000-8000-000000000022', '00000000-0000-4000-8000-000000000011', 'published'),
  ('00000000-0000-4000-8000-000000000023', '00000000-0000-4000-8000-000000000012', 'draft');
INSERT INTO public.job_applications VALUES
  ('00000000-0000-4000-8000-000000000031', '00000000-0000-4000-8000-000000000021', '00000000-0000-4000-8000-000000000004', '2026-01-01T00:00:00Z'),
  ('00000000-0000-4000-8000-000000000032', '00000000-0000-4000-8000-000000000021', '00000000-0000-4000-8000-000000000004', '2026-01-02T00:00:00Z'),
  ('00000000-0000-4000-8000-000000000033', '00000000-0000-4000-8000-000000000021', '00000000-0000-4000-8000-000000000004', '2026-01-03T00:00:00Z'),
  ('00000000-0000-4000-8000-000000000034', '00000000-0000-4000-8000-000000000021', '00000000-0000-4000-8000-000000000099', '2026-01-03T00:00:00Z'),
  ('00000000-0000-4000-8000-000000000035', '00000000-0000-4000-8000-000000000022', '00000000-0000-4000-8000-000000000004', '2026-01-03T00:00:00Z'),
  ('00000000-0000-4000-8000-000000000036', '00000000-0000-4000-8000-000000000023', '00000000-0000-4000-8000-000000000004', '2026-01-03T00:00:00Z');

DO $$
DECLARE role_name text;
BEGIN
  ASSERT (SELECT activated_at IS NULL FROM applicant_notifications_private.activation);
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    ASSERT NOT has_schema_privilege(role_name, 'applicant_notifications_private', 'USAGE, CREATE');
    ASSERT NOT has_table_privilege(role_name, 'applicant_notifications_private.activation',
      'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER');
    ASSERT NOT has_table_privilege(role_name, 'applicant_notifications_private.receipts',
      'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER');
    ASSERT NOT has_function_privilege(role_name, 'applicant_notifications_private.guard_activation()', 'EXECUTE');
    ASSERT has_function_privilege(role_name, 'public.list_unseen_applicant_counts()', 'EXECUTE') = (role_name = 'authenticated');
    ASSERT has_function_privilege(role_name, 'public.acknowledge_applicants_seen(uuid,uuid[])', 'EXECUTE') = (role_name = 'authenticated');
    ASSERT NOT has_function_privilege(role_name, 'public.list_unseen_applicant_counts()', 'EXECUTE WITH GRANT OPTION');
    ASSERT NOT has_function_privilege(role_name, 'public.acknowledge_applicants_seen(uuid,uuid[])', 'EXECUTE WITH GRANT OPTION');
  END LOOP;
END;
$$;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000001';
DO $$
BEGIN
  ASSERT (SELECT count(*) FROM public.list_unseen_applicant_counts()) = 0;
  ASSERT public.acknowledge_applicants_seen(
    '00000000-0000-4000-8000-000000000021', ARRAY['00000000-0000-4000-8000-000000000033']::uuid[]
  ) = 0;
END;
$$;
RESET ROLE;
DO $$ BEGIN
  ASSERT NOT EXISTS (SELECT 1 FROM applicant_notifications_private.receipts);
END $$;
DO $$
DECLARE
  before_activation timestamptz := clock_timestamp();
  cutoff timestamptz;
  affected integer;
BEGIN
  BEGIN
    UPDATE applicant_notifications_private.activation SET activated_at = NULL WHERE singleton;
    RAISE EXCEPTION 'A disabled activation row accepted a NULL-to-NULL update';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  ASSERT (SELECT activated_at IS NULL FROM applicant_notifications_private.activation);

  -- An input timestamp is only an activation request. The trigger supplies the cutoff.
  UPDATE applicant_notifications_private.activation
  SET activated_at = '2000-01-01T00:00:00Z'
  WHERE singleton AND activated_at IS NULL
  RETURNING activated_at INTO STRICT cutoff;
  ASSERT cutoff >= before_activation AND cutoff <= clock_timestamp();

  UPDATE applicant_notifications_private.activation
  SET activated_at = clock_timestamp() WHERE singleton AND activated_at IS NULL;
  GET DIAGNOSTICS affected = ROW_COUNT;
  ASSERT affected = 0;

  BEGIN
    UPDATE applicant_notifications_private.activation SET activated_at = NULL WHERE singleton;
    RAISE EXCEPTION 'Activation reset was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  BEGIN
    UPDATE applicant_notifications_private.activation
    SET activated_at = cutoff + interval '1 day' WHERE singleton;
    RAISE EXCEPTION 'Activation timestamp modification was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  BEGIN
    DELETE FROM applicant_notifications_private.activation WHERE singleton;
    RAISE EXCEPTION 'Activation row deletion was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  BEGIN
    TRUNCATE applicant_notifications_private.activation;
    RAISE EXCEPTION 'Activation truncation was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  ASSERT (SELECT activated_at FROM applicant_notifications_private.activation) = cutoff;

  UPDATE public.job_applications AS a
  SET applied_at = cutoff + (a.applied_at - '2026-01-02T00:00:00Z'::timestamptz);
END;
$$;
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  job uuid := '00000000-0000-4000-8000-000000000021';
  fresh uuid := '00000000-0000-4000-8000-000000000033';
  bad uuid;
BEGIN
  ASSERT (SELECT count(*) FROM public.list_unseen_applicant_counts()) = 2;
  ASSERT (SELECT unseen_count FROM public.list_unseen_applicant_counts() WHERE job_id = job) = 1;
  ASSERT (SELECT sum(unseen_count) FROM public.list_unseen_applicant_counts()) = 2;
  FOREACH bad IN ARRAY ARRAY[
    '00000000-0000-4000-8000-000000000034',
    '00000000-0000-4000-8000-000000000035',
    '00000000-0000-4000-8000-000000000099'
  ]::uuid[] LOOP
    BEGIN
      PERFORM public.acknowledge_applicants_seen(job, ARRAY[fresh, bad]);
      RAISE EXCEPTION 'Invisible, mixed-job or unknown application was accepted';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;
  END LOOP;
  BEGIN
    PERFORM public.acknowledge_applicants_seen(job, ARRAY[fresh, NULL::uuid]);
    RAISE EXCEPTION 'Null application ID was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.acknowledge_applicants_seen(job, array_fill(fresh, ARRAY[101]));
    RAISE EXCEPTION 'Oversized batch was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.acknowledge_applicants_seen(job, ARRAY[ARRAY[fresh, fresh]]);
    RAISE EXCEPTION 'Multidimensional batch was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.acknowledge_applicants_seen(
      '00000000-0000-4000-8000-000000000023', ARRAY['00000000-0000-4000-8000-000000000036']::uuid[]
    );
    RAISE EXCEPTION 'Cross-company access was accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  ASSERT (SELECT unseen_count FROM public.list_unseen_applicant_counts() WHERE job_id = job) = 1;
  ASSERT public.acknowledge_applicants_seen(job, ARRAY[
    '00000000-0000-4000-8000-000000000031'::uuid,
    '00000000-0000-4000-8000-000000000032'::uuid,
    fresh, fresh
  ]) = 1;
  ASSERT public.acknowledge_applicants_seen(job, ARRAY[fresh]) = 0;
  ASSERT NOT EXISTS (SELECT 1 FROM public.list_unseen_applicant_counts() WHERE job_id = job);
END;
$$;

-- A second employer still sees those applications and their other company.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000002';
DO $$ BEGIN
  ASSERT (SELECT sum(unseen_count) FROM public.list_unseen_applicant_counts()) = 3;
END $$;

-- Simulate a submission arriving after the list was fetched. Acknowledging
-- the original ID must leave the arrival unread.
RESET ROLE;
INSERT INTO public.job_applications
SELECT '00000000-0000-4000-8000-000000000037'::uuid,
  '00000000-0000-4000-8000-000000000021'::uuid,
  '00000000-0000-4000-8000-000000000004'::uuid,
  activated_at + interval '2 days'
FROM applicant_notifications_private.activation;
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  ASSERT public.acknowledge_applicants_seen(
    '00000000-0000-4000-8000-000000000021', ARRAY['00000000-0000-4000-8000-000000000033']::uuid[]
  ) = 1;
  ASSERT (SELECT unseen_count FROM public.list_unseen_applicant_counts()
    WHERE job_id = '00000000-0000-4000-8000-000000000021') = 1;
END;
$$;

DO $$
DECLARE actor text;
BEGIN
  FOREACH actor IN ARRAY ARRAY['', '00000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000004'] LOOP
    PERFORM set_config('request.jwt.claim.sub', actor, true);
    BEGIN
      PERFORM public.list_unseen_applicant_counts();
      RAISE EXCEPTION 'Unauthorized count was accepted';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
      PERFORM public.acknowledge_applicants_seen(
        '00000000-0000-4000-8000-000000000021', ARRAY['00000000-0000-4000-8000-000000000037']::uuid[]
      );
      RAISE EXCEPTION 'Unauthorized acknowledgment was accepted';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
END;
$$;
RESET ROLE;
DELETE FROM public.company_memberships
WHERE user_id = '00000000-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-8000-000000000002';
DO $$ BEGIN
  ASSERT NOT EXISTS (SELECT 1 FROM public.list_unseen_applicant_counts());
  BEGIN
    PERFORM public.acknowledge_applicants_seen(
      '00000000-0000-4000-8000-000000000021', ARRAY['00000000-0000-4000-8000-000000000037']::uuid[]
    );
    RAISE EXCEPTION 'Revoked membership was accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM applicant_notifications_private.receipts) = 2;
END $$;
ROLLBACK;
