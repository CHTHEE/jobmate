-- READ ONLY: one SELECT, one result row even when no candidates exist.
-- Run separately as postgres. Name hints never certify QA ownership/permission.
-- Existing accepted verified/corrected work is excluded by active/not_submitted
-- and no-checkout discovery, and must never be selected as a mutation target.
-- Optional scope NULLs below accept independently verified company/worker UUIDs.
WITH scope AS (SELECT NULL::uuid AS company_id,NULL::uuid AS worker_id),
captured AS (SELECT statement_timestamp() AS server_as_of), candidates AS (
 SELECT a.*,j.title AS job_title,u.name AS worker_name,c.company_name,
   c.verification_status::text AS company_verification,ja.status AS application_status,
   (ja.applicant_id=a.worker_id AND ja.job_id=a.job_id AND j.company_id=a.company_id) AS relationships_match,
   (u.role::text='job_seeker' AND u.status::text='active') AS worker_active,
   att.check_in_at,att.check_out_at,att.check_in_location_status,
   md5(to_jsonb(att)::text) AS original_attendance_fingerprint,
   md5(jsonb_build_array(att.check_in_at,att.check_in_location_status,att.check_in_latitude,att.check_in_longitude)::text) AS original_checkin_fingerprint,
   captured.server_as_of,a.scheduled_end+interval '24 hours' AS cutoff
 FROM public.work_assignments a
 JOIN public.job_postings j ON j.job_id=a.job_id
 JOIN public.job_applications ja ON ja.application_id=a.application_id
 JOIN public.users u ON u.user_id=a.worker_id
 JOIN public.companies c ON c.company_id=a.company_id
 JOIN public.work_attendance att ON att.assignment_id=a.assignment_id
 CROSS JOIN scope CROSS JOIN captured
 WHERE (scope.company_id IS NULL OR scope.company_id=a.company_id)
   AND (scope.worker_id IS NULL OR scope.worker_id=a.worker_id)
   AND j.title ~* '(QA|TEST|SYNTHETIC|FIXTURE|Event Crew Assistant|Event Setup Assistant)'
   AND att.check_in_at IS NOT NULL AND att.check_out_at IS NULL
   AND a.scheduled_end<captured.server_as_of
   AND a.scheduled_end>captured.server_as_of-interval '120 days'
   AND a.status='active' AND a.verification_status='not_submitted' AND a.verified_at IS NULL
), inspected AS (
 SELECT a.*,
   EXISTS(SELECT 1 FROM public.work_attendance_resolutions r WHERE r.assignment_id=a.assignment_id) AS has_resolution,
   EXISTS(SELECT 1 FROM public.work_evidence e WHERE e.assignment_id=a.assignment_id) AS has_evidence,
   EXISTS(SELECT 1 FROM public.work_evidence_submissions e WHERE e.assignment_id=a.assignment_id) AS has_submission,
   EXISTS(SELECT 1 FROM public.work_evidence_submission_attempts e WHERE e.assignment_id=a.assignment_id) AS has_attempt,
   EXISTS(SELECT 1 FROM public.work_evidence_review_requests e WHERE e.assignment_id=a.assignment_id) AS has_review,
   EXISTS(SELECT 1 FROM public.job_engagement_closures c WHERE c.application_id=a.application_id) AS engagement_closed,
   EXISTS(SELECT 1 FROM public.job_engagement_closure_requests r WHERE r.application_id=a.application_id AND r.status='pending') AS pending_closure_request,
   EXISTS(SELECT 1 FROM public.disputes d WHERE d.status IN ('open','investigating','pending_information')
     AND (d.assignment_id=a.assignment_id OR d.application_id=a.application_id)) AS unresolved_dispute
 FROM candidates a
)

SELECT statement_timestamp() AS captured_at,
 (SELECT count(*) FROM inspected) AS matching_candidate_count,
 CASE WHEN EXISTS(SELECT 1 FROM inspected) THEN 'REVIEW_HINTS_AND_CONFIRM_QA_PROVENANCE'
      ELSE 'NO_MATCHING_CANDIDATES_WITH_CURRENT_HINTS' END AS discovery_result,
 coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.scenario,r.scheduled_end DESC,r.assignment_id) FROM (
   SELECT assignment_id,application_id,company_id,worker_id,job_title,worker_name,company_name,
     workplace_location,server_as_of,scheduled_start,scheduled_end,cutoff,
     CASE WHEN server_as_of<=cutoff THEN 'A_within_24h' ELSE 'B_after_24h' END AS scenario,
     cutoff-server_as_of AS time_until_cutoff,check_in_at,check_in_location_status,
     original_attendance_fingerprint,original_checkin_fingerprint,relationships_match,
     worker_active,company_verification,application_status,has_resolution,has_evidence,
     has_submission,has_attempt,has_review,engagement_closed,pending_closure_request,unresolved_dispute,
     (relationships_match AND worker_active AND company_verification='verified'
       AND application_status='hired' AND NOT(has_resolution OR has_evidence OR has_submission
         OR has_attempt OR has_review OR engagement_closed OR pending_closure_request OR unresolved_dispute)) AS structurally_suitable_only,
     false AS qa_provenance_confirmed,false AS write_permission_granted
   FROM inspected ORDER BY scheduled_end DESC,assignment_id LIMIT 50
 ) r),'[]'::jsonb) AS candidate_rows;
