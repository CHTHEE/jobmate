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
COMMIT;