-- DRAFT / NOT APPROVED FOR DEPLOYMENT. DISPOSABLE LOCAL TEST DATABASE ONLY.
-- Executed only by run_disposable.ps1 with explicit loopback host/port/db.
CREATE FUNCTION public.c3_uid(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE
AS $$ SELECT ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
CREATE FUNCTION public.c3_assert(ok boolean,label text) RETURNS void LANGUAGE plpgsql
AS $$ BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF;
RAISE NOTICE 'PASS: %',label; END $$;
CREATE FUNCTION public.c3_seed(n integer,w integer DEFAULT NULL,c integer DEFAULT NULL,o integer DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE worker integer:=coalesce(w,100+n); company integer:=coalesce(c,300+n); owner_id integer:=coalesce(o,200+n);
BEGIN
  INSERT INTO auth.users(id) VALUES(c3_uid(worker)),(c3_uid(owner_id)) ON CONFLICT DO NOTHING;
  INSERT INTO public.users(user_id,name,role,status,created_at)
    VALUES(c3_uid(worker),'Synthetic worker','job_seeker','active',now()),
          (c3_uid(owner_id),'Synthetic owner','employer','active',now()) ON CONFLICT DO NOTHING;
  INSERT INTO public.companies(company_id,company_name,created_by,verification_status)
    VALUES(c3_uid(company),'Synthetic company',c3_uid(owner_id),'verified') ON CONFLICT DO NOTHING;
  INSERT INTO public.company_memberships(user_id,company_id,member_role)
    VALUES(c3_uid(owner_id),c3_uid(company),'owner') ON CONFLICT DO NOTHING;
  INSERT INTO public.job_postings(job_id,company_id,created_by,title,employment_type,work_arrangement)
    VALUES(c3_uid(400+n),c3_uid(company),c3_uid(owner_id),'Synthetic offer','part_time','on_site');
  INSERT INTO public.job_applications(application_id,job_id,applicant_id,status)
    VALUES(c3_uid(500+n),c3_uid(400+n),c3_uid(worker),'offered');
END $$;

SELECT c3_seed(1);
SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-4000-8000-000000000101';
SELECT c3_assert(respond_to_job_application(c3_uid(501),'accept_offer')='hired','fresh authenticated offer acceptance');
SELECT c3_assert(respond_to_job_application(c3_uid(501),'accept_offer')='hired','authenticated replay');
SELECT c3_assert(NOT can_manage_company_jobs(c3_uid(301)),'ordinary Job Seeker has no management authority');
RESET ROLE;
SELECT c3_assert((SELECT count(*)=1 FROM company_memberships WHERE user_id=c3_uid(101) AND company_id=c3_uid(301) AND member_role='member'),'exactly one ordinary membership');
SELECT c3_assert((SELECT role='job_seeker' FROM users WHERE user_id=c3_uid(101)),'account role unchanged');
SELECT c3_assert((SELECT count(*)=1 FROM application_status_history WHERE application_id=c3_uid(501) AND previous_status='offered' AND new_status='hired'),'one history event on replay');
SELECT c3_assert((SELECT count(*)=1 FROM notifications WHERE user_id=c3_uid(201) AND notification_type='application_hired' AND message='An applicant for Synthetic offer has accepted the job offer.'),'one original employer notification');
SELECT c3_seed(2,101);
SET request.jwt.claim.sub='00000000-0000-4000-8000-000000000101';
SELECT respond_to_job_application(c3_uid(502),'accept_offer');
SELECT c3_assert((SELECT count(*)=2 FROM company_memberships WHERE user_id=c3_uid(101)),'same worker hired into two companies');

SELECT c3_seed(3);
INSERT INTO company_memberships(user_id,company_id,member_role,membership_status) VALUES(c3_uid(103),c3_uid(303),'member','inactive');
SELECT c3_seed(4);
INSERT INTO company_memberships(user_id,company_id,member_role,membership_status) VALUES(c3_uid(104),c3_uid(304),'member','revoked');
DO $$ DECLARE n integer; state text; BEGIN
  FOREACH n IN ARRAY ARRAY[3,4] LOOP
    PERFORM set_config('request.jwt.claim.sub',c3_uid(100+n)::text,false);
    BEGIN
      PERFORM respond_to_job_application(c3_uid(500+n),'accept_offer');
      RAISE EXCEPTION 'Expected lifecycle conflict';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM<>'Inactive or revoked membership requires separate review.' THEN RAISE; END IF;
    END;
    SELECT membership_status INTO state FROM company_memberships WHERE user_id=c3_uid(100+n);
    PERFORM c3_assert(state=CASE WHEN n=3 THEN 'inactive' ELSE 'revoked' END,'lifecycle never reactivated');
    PERFORM c3_assert((SELECT status='offered' FROM job_applications WHERE application_id=c3_uid(500+n)),'lifecycle conflict preserves Offered');
    PERFORM c3_assert((SELECT count(*)=0 FROM application_status_history WHERE application_id=c3_uid(500+n)),'lifecycle conflict has no history');
  END LOOP;
END $$;

SELECT c3_seed(5); SELECT c3_seed(6);
SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-4000-8000-000000000105';
SELECT c3_assert(respond_to_job_application(c3_uid(505),'decline_offer')='declined','decline retained');
SET request.jwt.claim.sub='00000000-0000-4000-8000-000000000106';
SELECT c3_assert(respond_to_job_application(c3_uid(506),'withdraw')='withdrawn','withdraw retained');
RESET ROLE;
SELECT c3_assert((SELECT count(*)=0 FROM company_memberships WHERE user_id IN (c3_uid(105),c3_uid(106))),'decline/withdraw do not enroll');
SELECT c3_assert((SELECT withdrawn_at IS NOT NULL FROM job_applications WHERE application_id=c3_uid(506)),'withdrawal timestamp retained');
SELECT c3_assert((SELECT count(*)=2 FROM notifications WHERE user_id IN (c3_uid(205),c3_uid(206))),'decline/withdraw notify original employers');

-- Inject failures at all three write stages; assertions run after subtransaction rollback.
SELECT c3_seed(7); SELECT c3_seed(8); SELECT c3_seed(9);
CREATE FUNCTION public.c3_forced_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'C3 forced failure'; END $$;
CREATE TRIGGER c3_fail_member BEFORE INSERT ON company_memberships FOR EACH ROW WHEN(NEW.user_id='00000000-0000-4000-8000-000000000107') EXECUTE FUNCTION c3_forced_failure();
CREATE TRIGGER c3_fail_history BEFORE INSERT ON application_status_history FOR EACH ROW WHEN(NEW.application_id='00000000-0000-4000-8000-000000000508') EXECUTE FUNCTION c3_forced_failure();
CREATE TRIGGER c3_fail_notification BEFORE INSERT ON notifications FOR EACH ROW WHEN(NEW.user_id='00000000-0000-4000-8000-000000000209') EXECUTE FUNCTION c3_forced_failure();
DO $$ DECLARE n integer; BEGIN
  FOREACH n IN ARRAY ARRAY[7,8,9] LOOP
    PERFORM set_config('request.jwt.claim.sub',c3_uid(100+n)::text,false);
    BEGIN
      PERFORM respond_to_job_application(c3_uid(500+n),'accept_offer');
      RAISE EXCEPTION 'Expected injected failure';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM<>'C3 forced failure' THEN RAISE; END IF;
    END;
    PERFORM c3_assert((SELECT status='offered' FROM job_applications WHERE application_id=c3_uid(500+n)),'forced failure rolls back application');
    PERFORM c3_assert((SELECT count(*)=0 FROM company_memberships WHERE user_id=c3_uid(100+n)),'forced failure rolls back membership');
    PERFORM c3_assert((SELECT count(*)=0 FROM private.hiring_membership_acceptances WHERE application_id=c3_uid(500+n)),'forced failure rolls back receipt');
    PERFORM c3_assert((SELECT count(*)=0 FROM application_status_history WHERE application_id=c3_uid(500+n)),'forced failure rolls back history');
    PERFORM c3_assert((SELECT count(*)=0 FROM notifications WHERE user_id=c3_uid(200+n)),'forced failure rolls back notification');
  END LOOP;
END $$;

SELECT c3_seed(10);
INSERT INTO auth.users(id) VALUES(c3_uid(220));
INSERT INTO users(user_id,name,role,status,created_at)
  VALUES(c3_uid(220),'Synthetic unassociated Employer','employer','active',now());
INSERT INTO companies(company_id,company_name,created_by,verification_status)
  VALUES(c3_uid(399),'Synthetic unowned company',c3_uid(201),'verified');
DO $$ BEGIN
  BEGIN
    INSERT INTO company_memberships(user_id,company_id,member_role) VALUES(c3_uid(220),c3_uid(301),'owner');
    RAISE EXCEPTION 'Expected unique owner failure';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  BEGIN
    INSERT INTO company_memberships(user_id,company_id,member_role) VALUES(c3_uid(201),c3_uid(399),'owner');
    RAISE EXCEPTION 'Expected unique owned-company failure';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  PERFORM c3_assert(true,'one Owner per company and one owned company per user');
  BEGIN
    UPDATE users SET role='job_seeker' WHERE user_id=c3_uid(201);
    RAISE EXCEPTION 'Expected owner account-role failure';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'A Company Owner must keep the Employer role.' THEN RAISE; END IF; END;
  PERFORM c3_assert(true,'Owner account role protected');
END $$;

-- Historical replay after later revocation must remain revoked.
UPDATE company_memberships SET membership_status='revoked' WHERE user_id=c3_uid(101) AND company_id=c3_uid(301);
SET request.jwt.claim.sub='00000000-0000-4000-8000-000000000101';
SELECT c3_assert(respond_to_job_application(c3_uid(501),'accept_offer')='hired','replay after revocation reconciles only');
SELECT c3_assert((SELECT membership_status='revoked' FROM company_memberships WHERE user_id=c3_uid(101) AND company_id=c3_uid(301)),'replay does not reactivate');
SELECT c3_assert((SELECT count(*)=1 FROM application_status_history WHERE application_id=c3_uid(501)),'revoked replay adds no history');

SELECT c3_seed(11); -- Prepared for independent-session concurrency test.
