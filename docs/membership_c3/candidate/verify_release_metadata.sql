-- DRAFT / NOT APPROVED FOR DEPLOYMENT. READ ONLY; manual approved catalog review.
-- Does not execute the candidate or read application rows. Run only when authorized.
SELECT n.nspname,p.proname,pg_catalog.pg_get_function_identity_arguments(p.oid) AS arguments,
 pg_catalog.pg_get_userbyid(p.proowner) AS owner,p.prosecdef,p.proconfig,p.proacl,
 pg_catalog.md5(p.prosrc) AS body_md5
FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE (n.nspname='public' AND p.proname IN
 ('respond_to_job_application','get_my_hiring_membership','can_manage_company_jobs',
  'submit_company_for_review','submit_company_for_review_v2','get_user_account_details',
  'update_job_application_status','can_review_work_evidence_company',
  'read_employer_work_attendance_gps','submit_dispute','set_company_restriction','update_job_moderation'))
 OR (n.nspname='private' AND p.proname IN
 ('protect_jobmate_company_owner','c3_require_owner_employer_role','dispute_can_read','dispute_notify'))
ORDER BY n.nspname,p.proname,arguments;
SELECT conname,pg_catalog.pg_get_constraintdef(oid) AS definition
FROM pg_catalog.pg_constraint WHERE conrelid='public.company_memberships'::regclass
ORDER BY conname;
SELECT indexname,indexdef FROM pg_catalog.pg_indexes
WHERE schemaname='public' AND tablename='company_memberships' ORDER BY indexname;
SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check
FROM pg_catalog.pg_policies WHERE
 (schemaname='public' AND tablename IN ('company_memberships','companies','company_logo_change_requests'))
 OR (schemaname='storage' AND tablename='objects')
ORDER BY schemaname,tablename,policyname;
