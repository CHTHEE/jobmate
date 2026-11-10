-- NOT DEPLOYED. OFFLINE REVIEW / ISOLATED TEST CANDIDATE ONLY.
-- Derived from the complete 2026-11-10 catalog CSV, 3392 rows, PostgreSQL 17.11.
-- Do NOT apply through an automatic migration push. Review and isolated runtime,
-- real-role and multi-session checks are mandatory before separate live approval.
-- This file has NOT been executed. Read docs/work_shift_schedule_implementation_review.md.
-- REBASED EXPECTATION: the separately approved closure authorization patch must
-- already be installed and independently verified. Its body is EXPECTED from
-- the approved artifact, NOT claimed verified live by this offline generation.
-- Scheduling never replaces that security function; scheduling rollback keeps it.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SET LOCAL search_path = '';
-- Maintenance/quiescence required. Application-first mirrors the row protocol.
LOCK TABLE public.job_applications, public.job_postings,
 public.work_assignment_creation_requests, public.work_assignments,
 public.work_assignment_shift_claims, public.job_engagement_closures,
 public.job_engagement_closure_requests, public.work_assignment_cancellations
 IN SHARE ROW EXCLUSIVE MODE;

DO $baseline$
DECLARE e record; p pg_catalog.pg_proc;
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Candidate requires the exported postgres owner role.'; END IF;
  FOR e IN SELECT * FROM (VALUES
('private.guard_engagement_cancellation_audit()','4527eadc1a71b6dd00ce47ee277675a5','postgres','{postgres=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','','','trigger','f','False'),
('private.guard_engagement_request_insert()','5248a1f3e2be7bb7f8e50cc3e909b611','postgres','{postgres=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','','','trigger','f','False'),
('private.lock_engagement_dispute_application()','5870e584e0062e137ff60bea113b0601','postgres','{postgres=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','','','trigger','f','False'),
('private.prevent_assignment_cancellation_mutation()','234763bc15bfc7d41ef11bbc2dbfa9ba','postgres','{postgres=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','','','trigger','f','False'),
('private.prevent_engagement_closure_mutation()','5224132e0acb7b68999faa873cc1db9f','postgres','{postgres=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','','','trigger','f','False'),
('private.protect_assignment_request_terminal_state()','faf9f33e601877278698cd31226034a5','postgres','{postgres=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','','','trigger','f','False'),
('private.record_job_engagement_closure(uuid,uuid,text)','eecdf7e6d167363639b505a7dbc8a6a0','postgres','{postgres=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_application_id uuid, p_actor_id uuid, p_reason text','p_application_id uuid, p_actor_id uuid, p_reason text','timestamp with time zone','f','False'),
('public.can_manage_company_jobs(uuid)','7c41597c243580062e49efd25af2f9f0','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','s','DEFINER','False','False','u','p_company_id uuid','p_company_id uuid','boolean','f','False'),
('public.cancel_scheduled_work_assignment(uuid,text)','58b82b0e54db28c63d8c159acf65cfdf','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_assignment_id uuid, p_reason text','p_assignment_id uuid, p_reason text','timestamp with time zone','f','False'),
('public.cancel_work_assignment_request(uuid,text)','19c4f55ab01b41ece09932c5f09efa6b','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_request_id uuid, p_reason text','p_request_id uuid, p_reason text','void','f','False'),
('public.check_in_work_assignment(uuid,text,numeric,numeric)','da608f2b4ef94bbe4954d2f20d28971a','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_assignment_id uuid, p_location_status text, p_latitude numeric, p_longitude numeric','p_assignment_id uuid, p_location_status text, p_latitude numeric DEFAULT NULL::numeric, p_longitude numeric DEFAULT NULL::numeric','timestamp with time zone','f','False'),
('public.check_out_work_assignment(uuid,text,numeric,numeric)','cd78151fc05490eb8f98a428a85c3c70','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_assignment_id uuid, p_location_status text, p_latitude numeric, p_longitude numeric','p_assignment_id uuid, p_location_status text, p_latitude numeric DEFAULT NULL::numeric, p_longitude numeric DEFAULT NULL::numeric','timestamp with time zone','f','False'),
('public.close_job_engagement(uuid,text)','c71351b72abfbc7ca0f29fb348238cc0','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_application_id uuid, p_reason text','p_application_id uuid, p_reason text','timestamp with time zone','f','False'),
('public.create_work_assignment(uuid,timestamp with time zone,timestamp with time zone,text)','bb8d8bda205e02207b57541a185ca950','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text','p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text','uuid','f','False'),
('public.create_work_assignment_request(uuid,uuid,timestamp with time zone,timestamp with time zone,text)','12255c24979f6e24e79e83b0ecd252af','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_request_id uuid, p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text','p_request_id uuid, p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text','uuid','f','False'),
('public.get_my_job_engagement_closure_status(uuid)','509870d7889729e60d8a02575ff3588e','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','s','DEFINER','False','False','u','p_application_id uuid','p_application_id uuid','TABLE(closure_status text, eligible boolean, eligibility_reason text, request_id uuid, requested_at timestamp with time zone, request_reason text, response_reason text, closed_at timestamp with time zone)','f','True'),
('public.guard_work_assignment_duplicate_shift()','3de11b7ad06274924f25c49651767259','postgres','{postgres=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','','','trigger','f','False'),
('public.list_company_engagement_closure_requests()','5cbd56c7a4e5c98f840ec9cc46eea36b','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','s','DEFINER','False','False','u','','','TABLE(request_id uuid, application_id uuid, company_id uuid, job_title text, worker_name text, request_reason text, status text, requested_at timestamp with time zone, processed_by uuid, processed_at timestamp with time zone, response_reason text)','f','True'),
('public.list_company_work_assignments(uuid)','1107b445d7dfdba875b21e551c886ab9','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','s','DEFINER','False','False','u','p_company_id uuid','p_company_id uuid','TABLE(assignment_id uuid, application_id uuid, job_id uuid, job_title text, worker_id uuid, scheduled_start timestamp with time zone, scheduled_end timestamp with time zone, workplace_location text, assignment_status text, verification_status text, check_in_at timestamp with time zone, check_out_at timestamp with time zone, verified_at timestamp with time zone)','f','True'),
('public.list_my_work_assignments()','f9446e58502bc3f39435048c5ff7ef20','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','s','DEFINER','False','False','u','','','TABLE(assignment_id uuid, application_id uuid, job_id uuid, job_title text, company_id uuid, company_name text, scheduled_start timestamp with time zone, scheduled_end timestamp with time zone, workplace_location text, assignment_status text, verification_status text, check_in_at timestamp with time zone, check_out_at timestamp with time zone, verified_at timestamp with time zone)','f','True'),
('public.lookup_work_assignment_request(uuid)','d25d36d41b920c39381d4cb1799a5ef4','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_request_id uuid','p_request_id uuid','uuid','f','False'),
('public.request_job_engagement_closure(uuid,text)','61fe800ef16730ec6de1f0040cee163d','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_application_id uuid, p_reason text','p_application_id uuid, p_reason text','uuid','f','False'),
('public.request_more_work_evidence(uuid,text)','61fccb85590fbb4cb0a58d2a95f14320','postgres','{postgres=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_assignment_id uuid, p_reason text','p_assignment_id uuid, p_reason text','void','f','False'),
('public.reserve_work_assignment_request(uuid,timestamp with time zone,timestamp with time zone,text)','7a5fd48bd7bcd9779f4c9d39f6fd67a2','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text','p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text','uuid','f','False'),
('public.respond_job_engagement_closure_request(uuid,text,text)','8558e154e5eae1e8ea7b09c3fed41103','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_request_id uuid, p_decision text, p_reason text','p_request_id uuid, p_decision text, p_reason text','timestamp with time zone','f','False'),
('public.submit_work_evidence(uuid,text,text[])','5195aae515ef8e086e7425ec6dda22b2','postgres','{postgres=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_assignment_id uuid, p_description text, p_storage_paths text[]','p_assignment_id uuid, p_description text, p_storage_paths text[]','integer','f','False'),
('public.verify_work_assignment(uuid)','ec96a7903fc4862b0f5dd8ad278c41a3','postgres','{postgres=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_assignment_id uuid','p_assignment_id uuid','void','f','False')
  ) x(signature,expected_hash,owner_name,raw_acl,settings_json,volatility,security_mode,is_strict,is_leakproof,parallel_mode,identity_args,args_with_defaults,result_type,routine_kind,returns_set) LOOP
    SELECT * INTO p FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(e.signature);
    IF NOT FOUND THEN RAISE EXCEPTION 'Missing baseline routine: %',e.signature; END IF;
    IF (CASE WHEN e.signature IN ('public.respond_job_engagement_closure_request(uuid,text,text)') THEN pg_catalog.md5(replace(replace(p.prosrc,chr(13)||chr(10),chr(10)),chr(13),chr(10))) ELSE pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) END) IS DISTINCT FROM e.expected_hash
       OR pg_catalog.pg_get_userbyid(p.proowner)::text IS DISTINCT FROM e.owner_name
       OR p.proacl::text IS DISTINCT FROM e.raw_acl
       OR pg_catalog.to_jsonb(p.proconfig) IS DISTINCT FROM e.settings_json::jsonb
       OR p.provolatile::text IS DISTINCT FROM e.volatility
       OR p.prosecdef IS DISTINCT FROM (e.security_mode='DEFINER')
       OR p.proisstrict IS DISTINCT FROM e.is_strict::boolean
       OR p.proleakproof IS DISTINCT FROM e.is_leakproof::boolean
       OR p.proparallel::text IS DISTINCT FROM e.parallel_mode
       OR pg_catalog.pg_get_function_identity_arguments(p.oid) IS DISTINCT FROM e.identity_args
       OR pg_catalog.pg_get_function_arguments(p.oid) IS DISTINCT FROM e.args_with_defaults
       OR pg_catalog.pg_get_function_result(p.oid) IS DISTINCT FROM e.result_type
       OR p.prokind::text IS DISTINCT FROM e.routine_kind
       OR p.proretset IS DISTINCT FROM e.returns_set::boolean THEN
      RAISE EXCEPTION 'Baseline/security drift: %; stop and inspect, never restore historical grants.',e.signature;
    END IF;
  END LOOP;
END;
$baseline$;

DO $tables$
DECLARE e record; c pg_catalog.pg_class; v_trigger pg_catalog.pg_trigger; v_constraint pg_catalog.pg_constraint; v_index pg_catalog.pg_index;
BEGIN
  FOR e IN SELECT * FROM (VALUES
('public.job_engagement_closure_requests','postgres','{postgres=arwdDxtm/postgres}'),
('public.job_engagement_closures','postgres','{postgres=arwdDxtm/postgres}'),
('public.work_assignment_cancellations','postgres','{postgres=arwdDxtm/postgres}'),
('public.work_assignment_creation_requests','postgres','{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'),
('public.work_assignment_shift_claims','postgres','{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'),
('public.work_assignments','postgres','{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}')
  ) x(identity,owner_name,raw_acl) LOOP
    SELECT * INTO c FROM pg_catalog.pg_class WHERE oid=pg_catalog.to_regclass(e.identity);
    IF NOT FOUND THEN RAISE EXCEPTION 'Missing relation %',e.identity; END IF;
    IF c.relkind <> 'r' OR c.relispartition OR NOT c.relrowsecurity OR c.relforcerowsecurity
       OR pg_catalog.pg_get_userbyid(c.relowner)::text <> e.owner_name OR c.relacl::text IS DISTINCT FROM e.raw_acl THEN
      RAISE EXCEPTION 'Relation/security drift: %',e.identity;
    END IF;
    IF e.identity IN ('public.work_assignments','public.work_assignment_creation_requests','public.work_assignment_shift_claims')
       AND (EXISTS(SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid=c.oid)
         OR EXISTS(SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=c.oid AND attacl IS NOT NULL)) THEN
      RAISE EXCEPTION 'Unexpected policy/column grants on %',e.identity;
    END IF;
  END LOOP;
  FOR e IN SELECT * FROM (VALUES
('public.work_assignments',2),
('public.work_assignment_creation_requests',2),
('public.work_assignment_shift_claims',0),
('public.job_engagement_closures',1),
('public.job_engagement_closure_requests',0),
('public.work_assignment_cancellations',1)
  ) x(identity,expected_count) LOOP
    IF (SELECT count(*) FROM pg_catalog.pg_trigger t WHERE t.tgrelid=pg_catalog.to_regclass(e.identity)
        AND NOT t.tgisinternal AND NOT
          ((e.identity='public.work_assignments' AND t.tgname='work_shift_schedule_after_write') OR
           (e.identity='public.work_assignment_creation_requests' AND t.tgname='work_shift_reservation_schedule_after_insert')))
       <> e.expected_count THEN
      RAISE EXCEPTION 'Unexpected lifecycle trigger inventory on %',e.identity;
    END IF;
  END LOOP;
  FOR e IN SELECT * FROM (VALUES
('public.job_engagement_closure_requests','job_engagement_closure_requests_application_id_fkey','FOREIGN KEY (application_id) REFERENCES job_applications(application_id) ON DELETE RESTRICT','True','False','False'),
('public.job_engagement_closure_requests','job_engagement_closure_requests_check','CHECK (status = ''pending''::text AND processed_by IS NULL AND processed_at IS NULL AND response_reason IS NULL OR (status = ANY (ARRAY[''accepted''::text, ''declined''::text])) AND processed_by IS NOT NULL AND processed_at IS NOT NULL AND response_reason IS NOT NULL AND response_reason ~ ''[^[:space:]]''::text)','True','False','False'),
('public.job_engagement_closure_requests','job_engagement_closure_requests_pkey','PRIMARY KEY (request_id)','True','False','False'),
('public.job_engagement_closure_requests','job_engagement_closure_requests_processed_by_fkey','FOREIGN KEY (processed_by) REFERENCES users(user_id) ON DELETE RESTRICT','True','False','False'),
('public.job_engagement_closure_requests','job_engagement_closure_requests_request_reason_check','CHECK (request_reason ~ ''[^[:space:]]''::text AND char_length(request_reason) <= 2000)','True','False','False'),
('public.job_engagement_closure_requests','job_engagement_closure_requests_status_check','CHECK (status = ANY (ARRAY[''pending''::text, ''accepted''::text, ''declined''::text]))','True','False','False'),
('public.job_engagement_closure_requests','job_engagement_closure_requests_worker_id_fkey','FOREIGN KEY (worker_id) REFERENCES users(user_id) ON DELETE RESTRICT','True','False','False'),
('public.job_engagement_closures','job_engagement_closures_application_id_fkey','FOREIGN KEY (application_id) REFERENCES job_applications(application_id) ON DELETE RESTRICT','True','False','False'),
('public.job_engagement_closures','job_engagement_closures_closed_by_fkey','FOREIGN KEY (closed_by) REFERENCES users(user_id) ON DELETE RESTRICT','True','False','False'),
('public.job_engagement_closures','job_engagement_closures_closure_reason_check','CHECK (closure_reason ~ ''[^[:space:]]''::text AND char_length(closure_reason) <= 2000)','True','False','False'),
('public.job_engagement_closures','job_engagement_closures_pkey','PRIMARY KEY (application_id)','True','False','False'),
('public.work_assignment_cancellations','work_assignment_cancellations_assignment_id_fkey','FOREIGN KEY (assignment_id) REFERENCES work_assignments(assignment_id) ON DELETE RESTRICT','True','False','False'),
('public.work_assignment_cancellations','work_assignment_cancellations_cancellation_reason_check','CHECK (cancellation_reason ~ ''[^[:space:]]''::text AND char_length(cancellation_reason) <= 2000)','True','False','False'),
('public.work_assignment_cancellations','work_assignment_cancellations_cancelled_by_fkey','FOREIGN KEY (cancelled_by) REFERENCES users(user_id) ON DELETE RESTRICT','True','False','False'),
('public.work_assignment_cancellations','work_assignment_cancellations_pkey','PRIMARY KEY (assignment_id)','True','False','False'),
('public.work_assignment_creation_requests','assignment_request_cancellation_audit','CHECK (cancelled_by IS NULL AND cancelled_at IS NULL AND cancellation_reason IS NULL OR cancelled_by IS NOT NULL AND cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL AND cancellation_reason ~ ''[^[:space:]]''::text AND assignment_id IS NULL)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requ_actor_id_application_id_sched_key','UNIQUE (actor_id, application_id, scheduled_start, scheduled_end)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_actor_id_fkey','FOREIGN KEY (actor_id) REFERENCES users(user_id)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_application_id_fkey','FOREIGN KEY (application_id) REFERENCES job_applications(application_id)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_assignment_id_fkey','FOREIGN KEY (assignment_id) REFERENCES work_assignments(assignment_id)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_assignment_id_key','UNIQUE (assignment_id)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_cancelled_by_fkey','FOREIGN KEY (cancelled_by) REFERENCES users(user_id) ON DELETE RESTRICT','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_check','CHECK (scheduled_end > scheduled_start)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_company_id_fkey','FOREIGN KEY (company_id) REFERENCES companies(company_id)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_pkey','PRIMARY KEY (request_id)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_workplace_location_check','CHECK (length(workplace_location) >= 1 AND length(workplace_location) <= 500)','True','False','False'),
('public.work_assignment_shift_claims','work_assignment_shift_claims_application_id_fkey','FOREIGN KEY (application_id) REFERENCES job_applications(application_id)','True','False','False'),
('public.work_assignment_shift_claims','work_assignment_shift_claims_pkey','PRIMARY KEY (application_id, scheduled_start, scheduled_end)','True','False','False'),
('public.work_assignments','valid_assignment_schedule','CHECK (scheduled_end > scheduled_start)','True','False','False'),
('public.work_assignments','verified_assignment_consistency','CHECK (verification_status <> ''verified''::text OR status = ''completed''::text AND verified_at IS NOT NULL)','True','False','False'),
('public.work_assignments','work_assignments_application_id_fkey','FOREIGN KEY (application_id) REFERENCES job_applications(application_id)','True','False','False'),
('public.work_assignments','work_assignments_company_id_fkey','FOREIGN KEY (company_id) REFERENCES companies(company_id)','True','False','False'),
('public.work_assignments','work_assignments_created_by_fkey','FOREIGN KEY (created_by) REFERENCES users(user_id)','True','False','False'),
('public.work_assignments','work_assignments_job_id_fkey','FOREIGN KEY (job_id) REFERENCES job_postings(job_id)','True','False','False'),
('public.work_assignments','work_assignments_no_worker_overlap','EXCLUDE USING gist (worker_id WITH =, tstzrange(scheduled_start, scheduled_end, ''[)''::text) WITH &&) WHERE (status <> ''cancelled''::text)','True','False','False'),
('public.work_assignments','work_assignments_pkey','PRIMARY KEY (assignment_id)','True','False','False'),
('public.work_assignments','work_assignments_status_check','CHECK (status = ANY (ARRAY[''scheduled''::text, ''active''::text, ''awaiting_verification''::text, ''completed''::text, ''cancelled''::text, ''disputed''::text]))','True','False','False'),
('public.work_assignments','work_assignments_verification_status_check','CHECK (verification_status = ANY (ARRAY[''not_submitted''::text, ''pending_review''::text, ''more_evidence_required''::text, ''verified''::text, ''disputed''::text]))','True','False','False'),
('public.work_assignments','work_assignments_worker_id_fkey','FOREIGN KEY (worker_id) REFERENCES users(user_id)','True','False','False')
  ) x(identity,constraint_name,definition,validated,expected_deferrable,initially_deferred) LOOP
    SELECT * INTO v_constraint FROM pg_catalog.pg_constraint WHERE conrelid=pg_catalog.to_regclass(e.identity) AND conname=e.constraint_name;
    IF NOT FOUND THEN RAISE EXCEPTION 'Missing constraint %',e.constraint_name; END IF;
    IF replace(pg_catalog.pg_get_constraintdef(v_constraint.oid,true),'public.','') <> e.definition
       OR v_constraint.convalidated IS DISTINCT FROM e.validated::boolean OR v_constraint.condeferrable IS DISTINCT FROM e.expected_deferrable::boolean
       OR v_constraint.condeferred IS DISTINCT FROM e.initially_deferred::boolean THEN
      RAISE EXCEPTION 'Constraint drift: %',e.constraint_name;
    END IF;
  END LOOP;
  FOR e IN SELECT * FROM (VALUES
('public.job_engagement_closure_requests','job_engagement_closure_requests_pkey','CREATE UNIQUE INDEX job_engagement_closure_requests_pkey ON job_engagement_closure_requests USING btree (request_id)','True','False','True'),
('public.job_engagement_closure_requests','job_engagement_one_pending_closure_request','CREATE UNIQUE INDEX job_engagement_one_pending_closure_request ON job_engagement_closure_requests USING btree (application_id) WHERE (status = ''pending''::text)','True','False','True'),
('public.job_engagement_closures','job_engagement_closures_pkey','CREATE UNIQUE INDEX job_engagement_closures_pkey ON job_engagement_closures USING btree (application_id)','True','False','True'),
('public.work_assignment_cancellations','work_assignment_cancellations_pkey','CREATE UNIQUE INDEX work_assignment_cancellations_pkey ON work_assignment_cancellations USING btree (assignment_id)','True','False','True'),
('public.work_assignment_creation_requests','work_assignment_creation_requ_actor_id_application_id_sched_key','CREATE UNIQUE INDEX work_assignment_creation_requ_actor_id_application_id_sched_key ON work_assignment_creation_requests USING btree (actor_id, application_id, scheduled_start, scheduled_end)','True','False','True'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_assignment_id_key','CREATE UNIQUE INDEX work_assignment_creation_requests_assignment_id_key ON work_assignment_creation_requests USING btree (assignment_id)','True','False','True'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_pkey','CREATE UNIQUE INDEX work_assignment_creation_requests_pkey ON work_assignment_creation_requests USING btree (request_id)','True','False','True'),
('public.work_assignment_shift_claims','work_assignment_shift_claims_pkey','CREATE UNIQUE INDEX work_assignment_shift_claims_pkey ON work_assignment_shift_claims USING btree (application_id, scheduled_start, scheduled_end)','True','False','True'),
('public.work_assignments','idx_work_assignments_application','CREATE INDEX idx_work_assignments_application ON work_assignments USING btree (application_id)','False','False','True'),
('public.work_assignments','idx_work_assignments_company','CREATE INDEX idx_work_assignments_company ON work_assignments USING btree (company_id)','False','False','True'),
('public.work_assignments','idx_work_assignments_worker','CREATE INDEX idx_work_assignments_worker ON work_assignments USING btree (worker_id)','False','False','True'),
('public.work_assignments','work_assignments_no_worker_overlap','CREATE INDEX work_assignments_no_worker_overlap ON work_assignments USING gist (worker_id, tstzrange(scheduled_start, scheduled_end, ''[)''::text)) WHERE (status <> ''cancelled''::text)','False','True','True'),
('public.work_assignments','work_assignments_pkey','CREATE UNIQUE INDEX work_assignments_pkey ON work_assignments USING btree (assignment_id)','True','False','True')
  ) x(identity,index_name,definition,is_unique,is_exclusion,is_immediate) LOOP
    SELECT ix.* INTO v_index FROM pg_catalog.pg_index ix JOIN pg_catalog.pg_class ic ON ic.oid=ix.indexrelid
      WHERE ix.indrelid=pg_catalog.to_regclass(e.identity) AND ic.relname::text=e.index_name;
    IF NOT FOUND THEN RAISE EXCEPTION 'Missing index %',e.index_name; END IF;
    IF replace(pg_catalog.pg_get_indexdef(v_index.indexrelid),'public.','') <> e.definition
       OR NOT v_index.indisvalid OR NOT v_index.indisready OR NOT v_index.indislive
       OR v_index.indisunique IS DISTINCT FROM e.is_unique::boolean OR v_index.indisexclusion IS DISTINCT FROM e.is_exclusion::boolean
       OR v_index.indimmediate IS DISTINCT FROM e.is_immediate::boolean THEN
      RAISE EXCEPTION 'Index drift: %',e.index_name;
    END IF;
  END LOOP;
  FOR e IN SELECT * FROM (VALUES
('public.job_engagement_closures','job_engagement_closure_immutable','CREATE TRIGGER job_engagement_closure_immutable BEFORE DELETE OR UPDATE ON job_engagement_closures FOR EACH ROW EXECUTE FUNCTION private.prevent_engagement_closure_mutation()','O'),
('public.work_assignment_cancellations','work_assignment_cancellations_immutable','CREATE TRIGGER work_assignment_cancellations_immutable BEFORE DELETE OR UPDATE ON work_assignment_cancellations FOR EACH ROW EXECUTE FUNCTION private.prevent_assignment_cancellation_mutation()','O'),
('public.work_assignment_creation_requests','engagement_request_insert_guard','CREATE TRIGGER engagement_request_insert_guard BEFORE INSERT ON work_assignment_creation_requests FOR EACH ROW EXECUTE FUNCTION private.guard_engagement_request_insert()','O'),
('public.work_assignment_creation_requests','protect_assignment_request_terminal_state','CREATE TRIGGER protect_assignment_request_terminal_state BEFORE UPDATE ON work_assignment_creation_requests FOR EACH ROW EXECUTE FUNCTION private.protect_assignment_request_terminal_state()','O'),
('public.work_assignments','engagement_cancellation_audit_guard','CREATE TRIGGER engagement_cancellation_audit_guard BEFORE UPDATE OF status ON work_assignments FOR EACH ROW EXECUTE FUNCTION private.guard_engagement_cancellation_audit()','O'),
('public.work_assignments','work_assignment_duplicate_shift_guard','CREATE TRIGGER work_assignment_duplicate_shift_guard BEFORE INSERT OR UPDATE OF application_id, scheduled_start, scheduled_end ON work_assignments FOR EACH ROW EXECUTE FUNCTION guard_work_assignment_duplicate_shift()','O')
  ) x(identity,trigger_name,definition,enabled_code) LOOP
    SELECT * INTO v_trigger FROM pg_catalog.pg_trigger WHERE tgrelid=pg_catalog.to_regclass(e.identity) AND tgname=e.trigger_name;
    IF NOT FOUND THEN RAISE EXCEPTION 'Missing lifecycle trigger %',e.trigger_name; END IF;
    IF replace(pg_catalog.pg_get_triggerdef(v_trigger.oid,true),'public.','') <> e.definition OR v_trigger.tgenabled::text <> e.enabled_code THEN
      RAISE EXCEPTION 'Lifecycle trigger drift: %',e.trigger_name;
    END IF;
  END LOOP;
  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_constraint k JOIN pg_catalog.pg_index i ON i.indexrelid=k.conindid
    WHERE k.conrelid='public.work_assignments'::regclass AND k.conname='work_assignments_no_worker_overlap'
      AND k.contype='x' AND k.convalidated AND NOT k.condeferrable AND i.indisvalid AND i.indisready AND i.indimmediate
      AND pg_catalog.pg_get_constraintdef(k.oid,true) = 'EXCLUDE USING gist (worker_id WITH =, tstzrange(scheduled_start, scheduled_end, ''[)''::text) WITH &&) WHERE (status <> ''cancelled''::text)') THEN
    RAISE EXCEPTION 'Worker overlap constraint drift';
  END IF;
END;
$tables$;

DO $new_objects$
BEGIN
  IF pg_catalog.to_regprocedure('private.validate_work_shift_schedule(timestamptz,timestamptz)') IS NOT NULL
     OR pg_catalog.to_regprocedure('private.enforce_work_shift_schedule_after_write()') IS NOT NULL
     OR EXISTS(SELECT 1 FROM pg_catalog.pg_trigger WHERE
       (tgrelid='public.work_assignments'::regclass AND tgname='work_shift_schedule_after_write') OR
       (tgrelid='public.work_assignment_creation_requests'::regclass AND tgname='work_shift_reservation_schedule_after_insert')) THEN
    RAISE EXCEPTION 'Candidate already installed or new object name occupied; stop, do not overwrite.';
  END IF;
END;
$new_objects$;

-- New helpers are private and receive no client EXECUTE privileges.
CREATE FUNCTION private.validate_work_shift_schedule(p_start timestamptz, p_end timestamptz)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = ''
AS $schedule$
BEGIN
  -- The deployed closure protocol serializes on SELECT FOR UPDATE, without
  -- updating the application version. A stale REPEATABLE READ snapshot cannot
  -- safely re-read the separate closure table. Reject NEW scheduling there;
  -- existing request replay/lookup never invokes this helper.
  IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'New shift scheduling requires READ COMMITTED isolation.' USING ERRCODE='22023';
  END IF;
  IF p_start IS NULL OR p_end IS NULL
     OR NOT pg_catalog.isfinite(p_start) OR NOT pg_catalog.isfinite(p_end) THEN
    RAISE EXCEPTION 'Enter a valid shift schedule.' USING ERRCODE='22023';
  END IF;
  IF p_end <= p_start THEN
    RAISE EXCEPTION 'End must be after start.' USING ERRCODE='22023';
  END IF;
  IF (p_start AT TIME ZONE 'Asia/Kuala_Lumpur')::date
     <> (p_end AT TIME ZONE 'Asia/Kuala_Lumpur')::date THEN
    RAISE EXCEPTION 'A shift must start and end on the same Malaysia date. Use separate daily assignments for multi-day work.' USING ERRCODE='22023';
  END IF;
  IF p_start <= pg_catalog.clock_timestamp() THEN
    RAISE EXCEPTION 'Shift start must be in the future.' USING ERRCODE='22023';
  END IF;
END;
$schedule$;
REVOKE ALL ON FUNCTION private.validate_work_shift_schedule(timestamptz,timestamptz) FROM PUBLIC, anon, authenticated, service_role;

-- AFTER timing is essential: immediate exclusion/unique/FK checks may wait
-- after the existing BEFORE guard. A failure rolls back the complete statement.
CREATE FUNCTION private.enforce_work_shift_schedule_after_write()
RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $schedule$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM private.validate_work_shift_schedule(NEW.scheduled_start,NEW.scheduled_end);
  ELSIF (NEW.application_id,NEW.scheduled_start,NEW.scheduled_end)
        IS DISTINCT FROM (OLD.application_id,OLD.scheduled_start,OLD.scheduled_end) THEN
    PERFORM private.validate_work_shift_schedule(NEW.scheduled_start,NEW.scheduled_end);
  END IF;
  RETURN NEW;
END;
$schedule$;
REVOKE ALL ON FUNCTION private.enforce_work_shift_schedule_after_write() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER work_shift_schedule_after_write
AFTER INSERT OR UPDATE OF application_id, scheduled_start, scheduled_end ON public.work_assignments
FOR EACH ROW EXECUTE FUNCTION private.enforce_work_shift_schedule_after_write();
-- Reservation replay performs no INSERT, so historical requests remain usable.
-- Existing BEFORE request guard holds the application lock before this executes.
CREATE TRIGGER work_shift_reservation_schedule_after_insert
AFTER INSERT ON public.work_assignment_creation_requests
FOR EACH ROW EXECUTE FUNCTION private.enforce_work_shift_schedule_after_write();

CREATE OR REPLACE FUNCTION public.reserve_work_assignment_request(p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_app record; v_request public.work_assignment_creation_requests;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '28000'; END IF;
 PERFORM 1 FROM public.job_applications a WHERE a.application_id = p_application_id FOR UPDATE;
 SELECT a.status, j.company_id INTO v_app FROM public.job_applications a
 JOIN public.job_postings j ON j.job_id = a.job_id
 WHERE a.application_id = p_application_id FOR UPDATE OF a, j;
 IF NOT FOUND THEN RAISE EXCEPTION 'Application unavailable.'; END IF;
 IF v_app.status <> 'hired' OR public.can_manage_company_jobs(v_app.company_id) IS NOT TRUE THEN
  RAISE EXCEPTION 'Employer access or hired eligibility denied.' USING ERRCODE = '42501';
 END IF;
 IF p_scheduled_start IS NULL OR p_scheduled_end IS NULL OR p_scheduled_end <= p_scheduled_start
 OR NOT isfinite(p_scheduled_start) OR NOT isfinite(p_scheduled_end)
 OR p_workplace_location IS NULL OR length(trim(p_workplace_location)) NOT BETWEEN 1 AND 500 THEN
  RAISE EXCEPTION 'Invalid shift payload.' USING ERRCODE = '22023';
 END IF;
 SELECT * INTO v_request FROM public.work_assignment_creation_requests
 WHERE actor_id = auth.uid() AND application_id = p_application_id
 AND scheduled_start = p_scheduled_start AND scheduled_end = p_scheduled_end;
 IF FOUND THEN
  IF v_request.workplace_location <> trim(p_workplace_location) THEN
   RAISE EXCEPTION 'Request payload cannot change.' USING ERRCODE = '22023';
  END IF;
  RETURN v_request.request_id;
 END IF;
 PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
 INSERT INTO public.work_assignment_creation_requests(actor_id, application_id, company_id,
 scheduled_start, scheduled_end, workplace_location)
 VALUES(auth.uid(), p_application_id, v_app.company_id, p_scheduled_start, p_scheduled_end, trim(p_workplace_location))
 RETURNING * INTO v_request;
 PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
 RETURN v_request.request_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.create_work_assignment_request(p_request_id uuid, p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_request public.work_assignment_creation_requests; v_app record; v_assignment uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '28000'; END IF;
 -- Same lock order as reservation and the legacy insert trigger.
 PERFORM 1 FROM public.job_applications a WHERE a.application_id = p_application_id FOR UPDATE;
 SELECT a.status, j.company_id INTO v_app FROM public.job_applications a
 JOIN public.job_postings j ON j.job_id = a.job_id
 WHERE a.application_id = p_application_id FOR UPDATE OF a, j;
 IF NOT FOUND THEN RAISE EXCEPTION 'Application unavailable.'; END IF;
 IF public.can_manage_company_jobs(v_app.company_id) IS NOT TRUE THEN
  RAISE EXCEPTION 'Employer access denied.' USING ERRCODE = '42501';
 END IF;
 SELECT * INTO v_request FROM public.work_assignment_creation_requests WHERE request_id = p_request_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Request unavailable.' USING ERRCODE = '22023'; END IF;
 IF v_request.actor_id <> auth.uid() OR v_request.company_id <> v_app.company_id THEN
  RAISE EXCEPTION 'Request access denied.' USING ERRCODE = '42501';
 END IF;
 IF v_request.application_id IS DISTINCT FROM p_application_id
 OR v_request.scheduled_start IS DISTINCT FROM p_scheduled_start
 OR v_request.scheduled_end IS DISTINCT FROM p_scheduled_end
 OR v_request.workplace_location IS DISTINCT FROM trim(p_workplace_location) THEN
  RAISE EXCEPTION 'Request payload cannot change.' USING ERRCODE = '22023';
 END IF;
 IF v_request.assignment_id IS NOT NULL THEN RETURN v_request.assignment_id; END IF;
 IF v_app.status <> 'hired' THEN RAISE EXCEPTION 'Application no longer hired.'; END IF;
 PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
 v_assignment := public.create_work_assignment(p_application_id, p_scheduled_start, p_scheduled_end, p_workplace_location);
 UPDATE public.work_assignment_creation_requests SET assignment_id = v_assignment WHERE request_id = p_request_id;
 PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
 RETURN v_assignment;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.create_work_assignment(p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_application record;
    v_company_id uuid;
    v_assignment_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'You must be signed in.';
    END IF;

    PERFORM 1 FROM public.job_applications a WHERE a.application_id = p_application_id FOR UPDATE;
    SELECT
        a.application_id,
        a.job_id,
        a.applicant_id,
        a.status,
        j.company_id
    INTO v_application
    FROM public.job_applications a
    JOIN public.job_postings j
      ON j.job_id = a.job_id
    WHERE a.application_id = p_application_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job application not found.';
    END IF;

    IF v_application.status <> 'hired' THEN
        RAISE EXCEPTION
            'Work assignments can only be created for Hired applications.';
    END IF;

    v_company_id := v_application.company_id;

    IF NOT public.can_manage_company_jobs(v_company_id) THEN
        RAISE EXCEPTION
            'You are not authorized to create assignments for this company.';
    END IF;

    IF p_scheduled_start IS NULL
       OR p_scheduled_end IS NULL
       OR p_scheduled_end <= p_scheduled_start THEN
        RAISE EXCEPTION 'Invalid shift schedule.';
    END IF;

    IF p_workplace_location IS NULL
       OR length(trim(p_workplace_location)) = 0
       OR length(p_workplace_location) > 500 THEN
        RAISE EXCEPTION
            'Enter a workplace location of up to 500 characters.';
    END IF;

    PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
    INSERT INTO public.work_assignments (
        application_id,
        job_id,
        worker_id,
        company_id,
        scheduled_start,
        scheduled_end,
        workplace_location,
        created_by
    )
    VALUES (
        v_application.application_id,
        v_application.job_id,
        v_application.applicant_id,
        v_company_id,
        p_scheduled_start,
        p_scheduled_end,
        trim(p_workplace_location),
        auth.uid()
    )
    RETURNING assignment_id INTO v_assignment_id;

    PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
    RETURN v_assignment_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.guard_work_assignment_duplicate_shift()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_claim uuid; v_app_status text; v_locked_app uuid;
begin
  -- Existing trigger also fires for schedule/application relinks. Lock both
  -- application rows in UUID order and reject edits involving a finalized
  -- engagement, including attempts to move a shift out of a closed application.
  if tg_op='UPDATE' then
    for v_locked_app in
      select a.application_id from public.job_applications a
      where a.application_id in (old.application_id,new.application_id)
      order by a.application_id for update nowait
    loop
      if exists(select 1 from public.job_engagement_closures c where c.application_id=v_locked_app) then
        raise exception 'This Job Engagement is closed; its Shifts cannot be changed.';
      end if;
    end loop;
  end if;
  select a.status into v_app_status from public.job_applications a
    where a.application_id=new.application_id for update;
  if not found then raise exception 'Job Application not found.'; end if;
  if v_app_status is distinct from 'hired' then raise exception 'Assignments require a hired Application.'; end if;
  if exists(select 1 from public.job_engagement_closures c where c.application_id=new.application_id) then
    raise exception 'This Job Engagement is closed; no new Shift may be added.';
  end if;
  if exists(select 1 from public.work_assignment_creation_requests r
      where r.application_id=new.application_id and r.actor_id=new.created_by
        and r.scheduled_start=new.scheduled_start and r.scheduled_end=new.scheduled_end
        and r.cancelled_at is not null) then
    raise exception 'This Assignment Request was cancelled and cannot create a Shift.';
  end if;
  if exists (select 1 from public.work_assignments a
    where a.application_id=new.application_id and a.scheduled_start=new.scheduled_start
      and a.scheduled_end=new.scheduled_end and a.assignment_id<>new.assignment_id) then
    raise exception 'This application shift already exists.' using errcode='23505';
  end if;
  insert into public.work_assignment_shift_claims(application_id,scheduled_start,scheduled_end,assignment_id)
    values(new.application_id,new.scheduled_start,new.scheduled_end,new.assignment_id)
    on conflict do nothing;
  select assignment_id into v_claim from public.work_assignment_shift_claims
    where application_id=new.application_id and scheduled_start=new.scheduled_start and scheduled_end=new.scheduled_end;
  if v_claim is distinct from new.assignment_id then
    raise exception 'This application shift is already claimed.' using errcode='23505';
  end if;
  if tg_op='INSERT' then
    perform private.validate_work_shift_schedule(new.scheduled_start,new.scheduled_end);
  elsif (new.application_id,new.scheduled_start,new.scheduled_end)
        is distinct from (old.application_id,old.scheduled_start,old.scheduled_end) then
    perform private.validate_work_shift_schedule(new.scheduled_start,new.scheduled_end);
  end if;
  return new;
end
$function$
;

DO $baseline$
DECLARE e record; p pg_catalog.pg_proc;
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Candidate requires the exported postgres owner role.'; END IF;
  FOR e IN SELECT * FROM (VALUES
('private.guard_engagement_cancellation_audit()','4527eadc1a71b6dd00ce47ee277675a5','postgres','{postgres=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','','','trigger','f','False'),
('private.guard_engagement_request_insert()','5248a1f3e2be7bb7f8e50cc3e909b611','postgres','{postgres=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','','','trigger','f','False'),
('private.lock_engagement_dispute_application()','5870e584e0062e137ff60bea113b0601','postgres','{postgres=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','','','trigger','f','False'),
('private.prevent_assignment_cancellation_mutation()','234763bc15bfc7d41ef11bbc2dbfa9ba','postgres','{postgres=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','','','trigger','f','False'),
('private.prevent_engagement_closure_mutation()','5224132e0acb7b68999faa873cc1db9f','postgres','{postgres=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','','','trigger','f','False'),
('private.protect_assignment_request_terminal_state()','faf9f33e601877278698cd31226034a5','postgres','{postgres=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','','','trigger','f','False'),
('private.record_job_engagement_closure(uuid,uuid,text)','eecdf7e6d167363639b505a7dbc8a6a0','postgres','{postgres=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_application_id uuid, p_actor_id uuid, p_reason text','p_application_id uuid, p_actor_id uuid, p_reason text','timestamp with time zone','f','False'),
('public.can_manage_company_jobs(uuid)','7c41597c243580062e49efd25af2f9f0','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','s','DEFINER','False','False','u','p_company_id uuid','p_company_id uuid','boolean','f','False'),
('public.cancel_scheduled_work_assignment(uuid,text)','58b82b0e54db28c63d8c159acf65cfdf','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_assignment_id uuid, p_reason text','p_assignment_id uuid, p_reason text','timestamp with time zone','f','False'),
('public.cancel_work_assignment_request(uuid,text)','19c4f55ab01b41ece09932c5f09efa6b','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_request_id uuid, p_reason text','p_request_id uuid, p_reason text','void','f','False'),
('public.check_in_work_assignment(uuid,text,numeric,numeric)','da608f2b4ef94bbe4954d2f20d28971a','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_assignment_id uuid, p_location_status text, p_latitude numeric, p_longitude numeric','p_assignment_id uuid, p_location_status text, p_latitude numeric DEFAULT NULL::numeric, p_longitude numeric DEFAULT NULL::numeric','timestamp with time zone','f','False'),
('public.check_out_work_assignment(uuid,text,numeric,numeric)','cd78151fc05490eb8f98a428a85c3c70','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_assignment_id uuid, p_location_status text, p_latitude numeric, p_longitude numeric','p_assignment_id uuid, p_location_status text, p_latitude numeric DEFAULT NULL::numeric, p_longitude numeric DEFAULT NULL::numeric','timestamp with time zone','f','False'),
('public.close_job_engagement(uuid,text)','c71351b72abfbc7ca0f29fb348238cc0','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_application_id uuid, p_reason text','p_application_id uuid, p_reason text','timestamp with time zone','f','False'),
('public.create_work_assignment(uuid,timestamp with time zone,timestamp with time zone,text)','d0fb79b54f06fb3f71072a9975661fa6','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text','p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text','uuid','f','False'),
('public.create_work_assignment_request(uuid,uuid,timestamp with time zone,timestamp with time zone,text)','1a0aafb16fa9fa92c89ad49ffb1d9b73','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_request_id uuid, p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text','p_request_id uuid, p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text','uuid','f','False'),
('public.get_my_job_engagement_closure_status(uuid)','509870d7889729e60d8a02575ff3588e','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','s','DEFINER','False','False','u','p_application_id uuid','p_application_id uuid','TABLE(closure_status text, eligible boolean, eligibility_reason text, request_id uuid, requested_at timestamp with time zone, request_reason text, response_reason text, closed_at timestamp with time zone)','f','True'),
('public.guard_work_assignment_duplicate_shift()','f31c8ce2ade136ac0d0ab016dd450b46','postgres','{postgres=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','','','trigger','f','False'),
('public.list_company_engagement_closure_requests()','5cbd56c7a4e5c98f840ec9cc46eea36b','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','s','DEFINER','False','False','u','','','TABLE(request_id uuid, application_id uuid, company_id uuid, job_title text, worker_name text, request_reason text, status text, requested_at timestamp with time zone, processed_by uuid, processed_at timestamp with time zone, response_reason text)','f','True'),
('public.list_company_work_assignments(uuid)','1107b445d7dfdba875b21e551c886ab9','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','s','DEFINER','False','False','u','p_company_id uuid','p_company_id uuid','TABLE(assignment_id uuid, application_id uuid, job_id uuid, job_title text, worker_id uuid, scheduled_start timestamp with time zone, scheduled_end timestamp with time zone, workplace_location text, assignment_status text, verification_status text, check_in_at timestamp with time zone, check_out_at timestamp with time zone, verified_at timestamp with time zone)','f','True'),
('public.list_my_work_assignments()','f9446e58502bc3f39435048c5ff7ef20','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','s','DEFINER','False','False','u','','','TABLE(assignment_id uuid, application_id uuid, job_id uuid, job_title text, company_id uuid, company_name text, scheduled_start timestamp with time zone, scheduled_end timestamp with time zone, workplace_location text, assignment_status text, verification_status text, check_in_at timestamp with time zone, check_out_at timestamp with time zone, verified_at timestamp with time zone)','f','True'),
('public.lookup_work_assignment_request(uuid)','d25d36d41b920c39381d4cb1799a5ef4','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_request_id uuid','p_request_id uuid','uuid','f','False'),
('public.request_job_engagement_closure(uuid,text)','61fe800ef16730ec6de1f0040cee163d','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_application_id uuid, p_reason text','p_application_id uuid, p_reason text','uuid','f','False'),
('public.request_more_work_evidence(uuid,text)','61fccb85590fbb4cb0a58d2a95f14320','postgres','{postgres=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_assignment_id uuid, p_reason text','p_assignment_id uuid, p_reason text','void','f','False'),
('public.reserve_work_assignment_request(uuid,timestamp with time zone,timestamp with time zone,text)','8c86c365d7adaf558379f5850d78d093','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text','p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text','uuid','f','False'),
('public.respond_job_engagement_closure_request(uuid,text,text)','8558e154e5eae1e8ea7b09c3fed41103','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_request_id uuid, p_decision text, p_reason text','p_request_id uuid, p_decision text, p_reason text','timestamp with time zone','f','False'),
('public.submit_work_evidence(uuid,text,text[])','5195aae515ef8e086e7425ec6dda22b2','postgres','{postgres=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_assignment_id uuid, p_description text, p_storage_paths text[]','p_assignment_id uuid, p_description text, p_storage_paths text[]','integer','f','False'),
('public.verify_work_assignment(uuid)','ec96a7903fc4862b0f5dd8ad278c41a3','postgres','{postgres=X/postgres,service_role=X/postgres}','["search_path=\"\""]','v','DEFINER','False','False','u','p_assignment_id uuid','p_assignment_id uuid','void','f','False')
  ) x(signature,expected_hash,owner_name,raw_acl,settings_json,volatility,security_mode,is_strict,is_leakproof,parallel_mode,identity_args,args_with_defaults,result_type,routine_kind,returns_set) LOOP
    SELECT * INTO p FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(e.signature);
    IF NOT FOUND THEN RAISE EXCEPTION 'Missing baseline routine: %',e.signature; END IF;
    IF (CASE WHEN e.signature IN ('public.respond_job_engagement_closure_request(uuid,text,text)','public.reserve_work_assignment_request(uuid,timestamp with time zone,timestamp with time zone,text)','public.create_work_assignment_request(uuid,uuid,timestamp with time zone,timestamp with time zone,text)','public.create_work_assignment(uuid,timestamp with time zone,timestamp with time zone,text)','public.guard_work_assignment_duplicate_shift()') THEN pg_catalog.md5(replace(replace(p.prosrc,chr(13)||chr(10),chr(10)),chr(13),chr(10))) ELSE pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) END) IS DISTINCT FROM e.expected_hash
       OR pg_catalog.pg_get_userbyid(p.proowner)::text IS DISTINCT FROM e.owner_name
       OR p.proacl::text IS DISTINCT FROM e.raw_acl
       OR pg_catalog.to_jsonb(p.proconfig) IS DISTINCT FROM e.settings_json::jsonb
       OR p.provolatile::text IS DISTINCT FROM e.volatility
       OR p.prosecdef IS DISTINCT FROM (e.security_mode='DEFINER')
       OR p.proisstrict IS DISTINCT FROM e.is_strict::boolean
       OR p.proleakproof IS DISTINCT FROM e.is_leakproof::boolean
       OR p.proparallel::text IS DISTINCT FROM e.parallel_mode
       OR pg_catalog.pg_get_function_identity_arguments(p.oid) IS DISTINCT FROM e.identity_args
       OR pg_catalog.pg_get_function_arguments(p.oid) IS DISTINCT FROM e.args_with_defaults
       OR pg_catalog.pg_get_function_result(p.oid) IS DISTINCT FROM e.result_type
       OR p.prokind::text IS DISTINCT FROM e.routine_kind
       OR p.proretset IS DISTINCT FROM e.returns_set::boolean THEN
      RAISE EXCEPTION 'Baseline/security drift: %; stop and inspect, never restore historical grants.',e.signature;
    END IF;
  END LOOP;
END;
$baseline$;

DO $tables$
DECLARE e record; c pg_catalog.pg_class; v_trigger pg_catalog.pg_trigger; v_constraint pg_catalog.pg_constraint; v_index pg_catalog.pg_index;
BEGIN
  FOR e IN SELECT * FROM (VALUES
('public.job_engagement_closure_requests','postgres','{postgres=arwdDxtm/postgres}'),
('public.job_engagement_closures','postgres','{postgres=arwdDxtm/postgres}'),
('public.work_assignment_cancellations','postgres','{postgres=arwdDxtm/postgres}'),
('public.work_assignment_creation_requests','postgres','{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'),
('public.work_assignment_shift_claims','postgres','{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'),
('public.work_assignments','postgres','{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}')
  ) x(identity,owner_name,raw_acl) LOOP
    SELECT * INTO c FROM pg_catalog.pg_class WHERE oid=pg_catalog.to_regclass(e.identity);
    IF NOT FOUND THEN RAISE EXCEPTION 'Missing relation %',e.identity; END IF;
    IF c.relkind <> 'r' OR c.relispartition OR NOT c.relrowsecurity OR c.relforcerowsecurity
       OR pg_catalog.pg_get_userbyid(c.relowner)::text <> e.owner_name OR c.relacl::text IS DISTINCT FROM e.raw_acl THEN
      RAISE EXCEPTION 'Relation/security drift: %',e.identity;
    END IF;
    IF e.identity IN ('public.work_assignments','public.work_assignment_creation_requests','public.work_assignment_shift_claims')
       AND (EXISTS(SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid=c.oid)
         OR EXISTS(SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=c.oid AND attacl IS NOT NULL)) THEN
      RAISE EXCEPTION 'Unexpected policy/column grants on %',e.identity;
    END IF;
  END LOOP;
  FOR e IN SELECT * FROM (VALUES
('public.work_assignments',2),
('public.work_assignment_creation_requests',2),
('public.work_assignment_shift_claims',0),
('public.job_engagement_closures',1),
('public.job_engagement_closure_requests',0),
('public.work_assignment_cancellations',1)
  ) x(identity,expected_count) LOOP
    IF (SELECT count(*) FROM pg_catalog.pg_trigger t WHERE t.tgrelid=pg_catalog.to_regclass(e.identity)
        AND NOT t.tgisinternal AND NOT
          ((e.identity='public.work_assignments' AND t.tgname='work_shift_schedule_after_write') OR
           (e.identity='public.work_assignment_creation_requests' AND t.tgname='work_shift_reservation_schedule_after_insert')))
       <> e.expected_count THEN
      RAISE EXCEPTION 'Unexpected lifecycle trigger inventory on %',e.identity;
    END IF;
  END LOOP;
  FOR e IN SELECT * FROM (VALUES
('public.job_engagement_closure_requests','job_engagement_closure_requests_application_id_fkey','FOREIGN KEY (application_id) REFERENCES job_applications(application_id) ON DELETE RESTRICT','True','False','False'),
('public.job_engagement_closure_requests','job_engagement_closure_requests_check','CHECK (status = ''pending''::text AND processed_by IS NULL AND processed_at IS NULL AND response_reason IS NULL OR (status = ANY (ARRAY[''accepted''::text, ''declined''::text])) AND processed_by IS NOT NULL AND processed_at IS NOT NULL AND response_reason IS NOT NULL AND response_reason ~ ''[^[:space:]]''::text)','True','False','False'),
('public.job_engagement_closure_requests','job_engagement_closure_requests_pkey','PRIMARY KEY (request_id)','True','False','False'),
('public.job_engagement_closure_requests','job_engagement_closure_requests_processed_by_fkey','FOREIGN KEY (processed_by) REFERENCES users(user_id) ON DELETE RESTRICT','True','False','False'),
('public.job_engagement_closure_requests','job_engagement_closure_requests_request_reason_check','CHECK (request_reason ~ ''[^[:space:]]''::text AND char_length(request_reason) <= 2000)','True','False','False'),
('public.job_engagement_closure_requests','job_engagement_closure_requests_status_check','CHECK (status = ANY (ARRAY[''pending''::text, ''accepted''::text, ''declined''::text]))','True','False','False'),
('public.job_engagement_closure_requests','job_engagement_closure_requests_worker_id_fkey','FOREIGN KEY (worker_id) REFERENCES users(user_id) ON DELETE RESTRICT','True','False','False'),
('public.job_engagement_closures','job_engagement_closures_application_id_fkey','FOREIGN KEY (application_id) REFERENCES job_applications(application_id) ON DELETE RESTRICT','True','False','False'),
('public.job_engagement_closures','job_engagement_closures_closed_by_fkey','FOREIGN KEY (closed_by) REFERENCES users(user_id) ON DELETE RESTRICT','True','False','False'),
('public.job_engagement_closures','job_engagement_closures_closure_reason_check','CHECK (closure_reason ~ ''[^[:space:]]''::text AND char_length(closure_reason) <= 2000)','True','False','False'),
('public.job_engagement_closures','job_engagement_closures_pkey','PRIMARY KEY (application_id)','True','False','False'),
('public.work_assignment_cancellations','work_assignment_cancellations_assignment_id_fkey','FOREIGN KEY (assignment_id) REFERENCES work_assignments(assignment_id) ON DELETE RESTRICT','True','False','False'),
('public.work_assignment_cancellations','work_assignment_cancellations_cancellation_reason_check','CHECK (cancellation_reason ~ ''[^[:space:]]''::text AND char_length(cancellation_reason) <= 2000)','True','False','False'),
('public.work_assignment_cancellations','work_assignment_cancellations_cancelled_by_fkey','FOREIGN KEY (cancelled_by) REFERENCES users(user_id) ON DELETE RESTRICT','True','False','False'),
('public.work_assignment_cancellations','work_assignment_cancellations_pkey','PRIMARY KEY (assignment_id)','True','False','False'),
('public.work_assignment_creation_requests','assignment_request_cancellation_audit','CHECK (cancelled_by IS NULL AND cancelled_at IS NULL AND cancellation_reason IS NULL OR cancelled_by IS NOT NULL AND cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL AND cancellation_reason ~ ''[^[:space:]]''::text AND assignment_id IS NULL)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requ_actor_id_application_id_sched_key','UNIQUE (actor_id, application_id, scheduled_start, scheduled_end)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_actor_id_fkey','FOREIGN KEY (actor_id) REFERENCES users(user_id)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_application_id_fkey','FOREIGN KEY (application_id) REFERENCES job_applications(application_id)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_assignment_id_fkey','FOREIGN KEY (assignment_id) REFERENCES work_assignments(assignment_id)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_assignment_id_key','UNIQUE (assignment_id)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_cancelled_by_fkey','FOREIGN KEY (cancelled_by) REFERENCES users(user_id) ON DELETE RESTRICT','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_check','CHECK (scheduled_end > scheduled_start)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_company_id_fkey','FOREIGN KEY (company_id) REFERENCES companies(company_id)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_pkey','PRIMARY KEY (request_id)','True','False','False'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_workplace_location_check','CHECK (length(workplace_location) >= 1 AND length(workplace_location) <= 500)','True','False','False'),
('public.work_assignment_shift_claims','work_assignment_shift_claims_application_id_fkey','FOREIGN KEY (application_id) REFERENCES job_applications(application_id)','True','False','False'),
('public.work_assignment_shift_claims','work_assignment_shift_claims_pkey','PRIMARY KEY (application_id, scheduled_start, scheduled_end)','True','False','False'),
('public.work_assignments','valid_assignment_schedule','CHECK (scheduled_end > scheduled_start)','True','False','False'),
('public.work_assignments','verified_assignment_consistency','CHECK (verification_status <> ''verified''::text OR status = ''completed''::text AND verified_at IS NOT NULL)','True','False','False'),
('public.work_assignments','work_assignments_application_id_fkey','FOREIGN KEY (application_id) REFERENCES job_applications(application_id)','True','False','False'),
('public.work_assignments','work_assignments_company_id_fkey','FOREIGN KEY (company_id) REFERENCES companies(company_id)','True','False','False'),
('public.work_assignments','work_assignments_created_by_fkey','FOREIGN KEY (created_by) REFERENCES users(user_id)','True','False','False'),
('public.work_assignments','work_assignments_job_id_fkey','FOREIGN KEY (job_id) REFERENCES job_postings(job_id)','True','False','False'),
('public.work_assignments','work_assignments_no_worker_overlap','EXCLUDE USING gist (worker_id WITH =, tstzrange(scheduled_start, scheduled_end, ''[)''::text) WITH &&) WHERE (status <> ''cancelled''::text)','True','False','False'),
('public.work_assignments','work_assignments_pkey','PRIMARY KEY (assignment_id)','True','False','False'),
('public.work_assignments','work_assignments_status_check','CHECK (status = ANY (ARRAY[''scheduled''::text, ''active''::text, ''awaiting_verification''::text, ''completed''::text, ''cancelled''::text, ''disputed''::text]))','True','False','False'),
('public.work_assignments','work_assignments_verification_status_check','CHECK (verification_status = ANY (ARRAY[''not_submitted''::text, ''pending_review''::text, ''more_evidence_required''::text, ''verified''::text, ''disputed''::text]))','True','False','False'),
('public.work_assignments','work_assignments_worker_id_fkey','FOREIGN KEY (worker_id) REFERENCES users(user_id)','True','False','False')
  ) x(identity,constraint_name,definition,validated,expected_deferrable,initially_deferred) LOOP
    SELECT * INTO v_constraint FROM pg_catalog.pg_constraint WHERE conrelid=pg_catalog.to_regclass(e.identity) AND conname=e.constraint_name;
    IF NOT FOUND THEN RAISE EXCEPTION 'Missing constraint %',e.constraint_name; END IF;
    IF replace(pg_catalog.pg_get_constraintdef(v_constraint.oid,true),'public.','') <> e.definition
       OR v_constraint.convalidated IS DISTINCT FROM e.validated::boolean OR v_constraint.condeferrable IS DISTINCT FROM e.expected_deferrable::boolean
       OR v_constraint.condeferred IS DISTINCT FROM e.initially_deferred::boolean THEN
      RAISE EXCEPTION 'Constraint drift: %',e.constraint_name;
    END IF;
  END LOOP;
  FOR e IN SELECT * FROM (VALUES
('public.job_engagement_closure_requests','job_engagement_closure_requests_pkey','CREATE UNIQUE INDEX job_engagement_closure_requests_pkey ON job_engagement_closure_requests USING btree (request_id)','True','False','True'),
('public.job_engagement_closure_requests','job_engagement_one_pending_closure_request','CREATE UNIQUE INDEX job_engagement_one_pending_closure_request ON job_engagement_closure_requests USING btree (application_id) WHERE (status = ''pending''::text)','True','False','True'),
('public.job_engagement_closures','job_engagement_closures_pkey','CREATE UNIQUE INDEX job_engagement_closures_pkey ON job_engagement_closures USING btree (application_id)','True','False','True'),
('public.work_assignment_cancellations','work_assignment_cancellations_pkey','CREATE UNIQUE INDEX work_assignment_cancellations_pkey ON work_assignment_cancellations USING btree (assignment_id)','True','False','True'),
('public.work_assignment_creation_requests','work_assignment_creation_requ_actor_id_application_id_sched_key','CREATE UNIQUE INDEX work_assignment_creation_requ_actor_id_application_id_sched_key ON work_assignment_creation_requests USING btree (actor_id, application_id, scheduled_start, scheduled_end)','True','False','True'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_assignment_id_key','CREATE UNIQUE INDEX work_assignment_creation_requests_assignment_id_key ON work_assignment_creation_requests USING btree (assignment_id)','True','False','True'),
('public.work_assignment_creation_requests','work_assignment_creation_requests_pkey','CREATE UNIQUE INDEX work_assignment_creation_requests_pkey ON work_assignment_creation_requests USING btree (request_id)','True','False','True'),
('public.work_assignment_shift_claims','work_assignment_shift_claims_pkey','CREATE UNIQUE INDEX work_assignment_shift_claims_pkey ON work_assignment_shift_claims USING btree (application_id, scheduled_start, scheduled_end)','True','False','True'),
('public.work_assignments','idx_work_assignments_application','CREATE INDEX idx_work_assignments_application ON work_assignments USING btree (application_id)','False','False','True'),
('public.work_assignments','idx_work_assignments_company','CREATE INDEX idx_work_assignments_company ON work_assignments USING btree (company_id)','False','False','True'),
('public.work_assignments','idx_work_assignments_worker','CREATE INDEX idx_work_assignments_worker ON work_assignments USING btree (worker_id)','False','False','True'),
('public.work_assignments','work_assignments_no_worker_overlap','CREATE INDEX work_assignments_no_worker_overlap ON work_assignments USING gist (worker_id, tstzrange(scheduled_start, scheduled_end, ''[)''::text)) WHERE (status <> ''cancelled''::text)','False','True','True'),
('public.work_assignments','work_assignments_pkey','CREATE UNIQUE INDEX work_assignments_pkey ON work_assignments USING btree (assignment_id)','True','False','True')
  ) x(identity,index_name,definition,is_unique,is_exclusion,is_immediate) LOOP
    SELECT ix.* INTO v_index FROM pg_catalog.pg_index ix JOIN pg_catalog.pg_class ic ON ic.oid=ix.indexrelid
      WHERE ix.indrelid=pg_catalog.to_regclass(e.identity) AND ic.relname::text=e.index_name;
    IF NOT FOUND THEN RAISE EXCEPTION 'Missing index %',e.index_name; END IF;
    IF replace(pg_catalog.pg_get_indexdef(v_index.indexrelid),'public.','') <> e.definition
       OR NOT v_index.indisvalid OR NOT v_index.indisready OR NOT v_index.indislive
       OR v_index.indisunique IS DISTINCT FROM e.is_unique::boolean OR v_index.indisexclusion IS DISTINCT FROM e.is_exclusion::boolean
       OR v_index.indimmediate IS DISTINCT FROM e.is_immediate::boolean THEN
      RAISE EXCEPTION 'Index drift: %',e.index_name;
    END IF;
  END LOOP;
  FOR e IN SELECT * FROM (VALUES
('public.job_engagement_closures','job_engagement_closure_immutable','CREATE TRIGGER job_engagement_closure_immutable BEFORE DELETE OR UPDATE ON job_engagement_closures FOR EACH ROW EXECUTE FUNCTION private.prevent_engagement_closure_mutation()','O'),
('public.work_assignment_cancellations','work_assignment_cancellations_immutable','CREATE TRIGGER work_assignment_cancellations_immutable BEFORE DELETE OR UPDATE ON work_assignment_cancellations FOR EACH ROW EXECUTE FUNCTION private.prevent_assignment_cancellation_mutation()','O'),
('public.work_assignment_creation_requests','engagement_request_insert_guard','CREATE TRIGGER engagement_request_insert_guard BEFORE INSERT ON work_assignment_creation_requests FOR EACH ROW EXECUTE FUNCTION private.guard_engagement_request_insert()','O'),
('public.work_assignment_creation_requests','protect_assignment_request_terminal_state','CREATE TRIGGER protect_assignment_request_terminal_state BEFORE UPDATE ON work_assignment_creation_requests FOR EACH ROW EXECUTE FUNCTION private.protect_assignment_request_terminal_state()','O'),
('public.work_assignments','engagement_cancellation_audit_guard','CREATE TRIGGER engagement_cancellation_audit_guard BEFORE UPDATE OF status ON work_assignments FOR EACH ROW EXECUTE FUNCTION private.guard_engagement_cancellation_audit()','O'),
('public.work_assignments','work_assignment_duplicate_shift_guard','CREATE TRIGGER work_assignment_duplicate_shift_guard BEFORE INSERT OR UPDATE OF application_id, scheduled_start, scheduled_end ON work_assignments FOR EACH ROW EXECUTE FUNCTION guard_work_assignment_duplicate_shift()','O')
  ) x(identity,trigger_name,definition,enabled_code) LOOP
    SELECT * INTO v_trigger FROM pg_catalog.pg_trigger WHERE tgrelid=pg_catalog.to_regclass(e.identity) AND tgname=e.trigger_name;
    IF NOT FOUND THEN RAISE EXCEPTION 'Missing lifecycle trigger %',e.trigger_name; END IF;
    IF replace(pg_catalog.pg_get_triggerdef(v_trigger.oid,true),'public.','') <> e.definition OR v_trigger.tgenabled::text <> e.enabled_code THEN
      RAISE EXCEPTION 'Lifecycle trigger drift: %',e.trigger_name;
    END IF;
  END LOOP;
  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_constraint k JOIN pg_catalog.pg_index i ON i.indexrelid=k.conindid
    WHERE k.conrelid='public.work_assignments'::regclass AND k.conname='work_assignments_no_worker_overlap'
      AND k.contype='x' AND k.convalidated AND NOT k.condeferrable AND i.indisvalid AND i.indisready AND i.indimmediate
      AND pg_catalog.pg_get_constraintdef(k.oid,true) = 'EXCLUDE USING gist (worker_id WITH =, tstzrange(scheduled_start, scheduled_end, ''[)''::text) WITH &&) WHERE (status <> ''cancelled''::text)') THEN
    RAISE EXCEPTION 'Worker overlap constraint drift';
  END IF;
END;
$tables$;

DO $new_acl$
DECLARE p pg_catalog.pg_proc;
BEGIN
  FOR p IN SELECT * FROM pg_catalog.pg_proc WHERE oid IN (
    'private.validate_work_shift_schedule(timestamptz,timestamptz)'::regprocedure,
    'private.enforce_work_shift_schedule_after_write()'::regprocedure) LOOP
    IF pg_catalog.pg_get_userbyid(p.proowner) <> 'postgres' OR EXISTS(
      SELECT 1 FROM pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
      WHERE a.grantee <> p.proowner) THEN
      RAISE EXCEPTION 'Unexpected default EXECUTE grants on new private helper; stop, inspect defaults.';
    END IF;
  END LOOP;
END;
$new_acl$;

DO $helpers$
DECLARE e record; p pg_catalog.pg_proc;
BEGIN
  FOR e IN SELECT * FROM (VALUES
('private.validate_work_shift_schedule(timestamptz,timestamptz)','469a1ec1a273a631c3019bbf38a7b51a',false),
('private.enforce_work_shift_schedule_after_write()','113fbadb940f4675106fbd248fc2a714',true)
  ) x(signature,expected_body_hash,definer) LOOP
    SELECT * INTO p FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(e.signature);
    IF NOT FOUND THEN RAISE EXCEPTION 'Missing candidate helper %',e.signature; END IF;
    IF pg_catalog.md5(replace(replace(p.prosrc,chr(13)||chr(10),chr(10)),chr(13),chr(10))) <> e.expected_body_hash OR p.prosecdef IS DISTINCT FROM e.definer
       OR pg_catalog.pg_get_userbyid(p.proowner) <> 'postgres' OR p.provolatile <> 'v'
       OR p.prokind <> 'f' OR p.proretset OR p.proisstrict OR p.proleakproof OR p.proparallel <> 'u'
       OR p.prorettype <> (CASE WHEN e.definer THEN 'pg_catalog.trigger'::regtype ELSE 'pg_catalog.void'::regtype END)
       OR pg_catalog.pg_get_function_identity_arguments(p.oid) <> (CASE WHEN e.definer THEN '' ELSE 'p_start timestamp with time zone, p_end timestamp with time zone' END)
       OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[] THEN
      RAISE EXCEPTION 'Candidate helper drift: %',e.signature;
    END IF;
  END LOOP;
  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.work_assignments'::regclass
      AND t.tgname='work_shift_schedule_after_write' AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgtype=21
      AND t.tgqual IS NULL AND t.tgnargs=0 AND NOT t.tgdeferrable
      AND t.tgfoid='private.enforce_work_shift_schedule_after_write()'::regprocedure
      AND ARRAY(SELECT a.attname::text FROM unnest(t.tgattr::smallint[]) WITH ORDINALITY k(attnum,pos)
          JOIN pg_catalog.pg_attribute a ON a.attrelid=t.tgrelid AND a.attnum=k.attnum ORDER BY k.pos)
          = ARRAY['application_id','scheduled_start','scheduled_end']::text[]) THEN
    RAISE EXCEPTION 'Candidate assignment AFTER trigger drift';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_trigger WHERE tgrelid='public.work_assignment_creation_requests'::regclass
    AND tgname='work_shift_reservation_schedule_after_insert' AND tgenabled='O' AND NOT tgisinternal AND tgtype=5
    AND tgqual IS NULL AND tgnargs=0 AND NOT tgdeferrable
    AND tgfoid='private.enforce_work_shift_schedule_after_write()'::regprocedure) THEN
    RAISE EXCEPTION 'Candidate reservation AFTER trigger drift';
  END IF;
END;
$helpers$;

COMMIT;
