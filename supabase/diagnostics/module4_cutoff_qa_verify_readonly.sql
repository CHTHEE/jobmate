-- READ ONLY. Run before QA to save hashes/server time, then after each action.
-- Fill only the independently approved A/B shift UUIDs; never the accepted shifts.
-- Copy baseline hashes and A's pre-checkout server time into the NULL inputs.
BEGIN READ ONLY;
SET LOCAL statement_timeout='15s';
WITH inputs(scenario,assignment_id,baseline_attendance_hash,baseline_checkin_hash,checkout_observed_after) AS (VALUES
 ('A',NULL::uuid,NULL::text,NULL::text,NULL::timestamptz),
 ('B',NULL::uuid,NULL::text,NULL::text,NULL::timestamptz)
), observed AS (
 SELECT i.*,statement_timestamp() AS server_as_of,a.application_id,a.worker_id,a.company_id,
   a.status,a.verification_status,a.verified_at,a.scheduled_start,a.scheduled_end,
   att.check_in_at,att.check_out_at,att.check_out_location_status,
   (att.check_out_latitude IS NOT NULL AND att.check_out_longitude IS NOT NULL) AS checkout_coordinates_present,
   CASE WHEN att.check_out_location_status='granted'
     THEN att.check_out_latitude BETWEEN -90 AND 90 AND att.check_out_longitude BETWEEN -180 AND 180
     WHEN att.check_out_location_status IN ('denied','unavailable')
     THEN att.check_out_latitude IS NULL AND att.check_out_longitude IS NULL ELSE false END AS checkout_gps_shape_valid,
   md5(to_jsonb(att)::text) AS current_attendance_hash,
   md5(jsonb_build_array(att.check_in_at,att.check_in_location_status,att.check_in_latitude,att.check_in_longitude)::text) AS current_checkin_hash,
   r.decision,r.reason AS resolution_reason,r.resolved_at,r.corrected_check_in_at,r.corrected_check_out_at,
   md5(r.original_attendance::text) AS audit_original_hash,
   e.check_in_at AS effective_check_in_at,e.check_out_at AS effective_check_out_at,
   (SELECT count(*) FROM public.work_evidence_submissions s WHERE s.assignment_id=a.assignment_id) AS submission_count,
   (SELECT count(*) FROM public.work_evidence_submission_attempts t WHERE t.assignment_id=a.assignment_id) AS attempt_count
 FROM inputs i LEFT JOIN public.work_assignments a ON a.assignment_id=i.assignment_id
 LEFT JOIN public.work_attendance att ON att.assignment_id=a.assignment_id
 LEFT JOIN public.work_attendance_resolutions r ON r.assignment_id=a.assignment_id
 LEFT JOIN private.effective_work_attendance e ON e.assignment_id=a.assignment_id
)
SELECT *,scheduled_end+interval '24 hours' AS cutoff,
 CASE WHEN assignment_id IS NULL THEN 'FILL_APPROVED_FIXTURE_ID'
      WHEN application_id IS NULL THEN 'ASSIGNMENT_NOT_FOUND'
      ELSE 'COMPARE_WITH_EXPECTED_STAGE_IN_PLAN' END AS inspection_status,
 CASE WHEN baseline_attendance_hash IS NOT NULL THEN current_attendance_hash=baseline_attendance_hash END AS raw_attendance_unchanged,
 CASE WHEN baseline_checkin_hash IS NOT NULL THEN current_checkin_hash=baseline_checkin_hash END AS original_checkin_gps_unchanged,
 CASE WHEN baseline_attendance_hash IS NOT NULL AND decision IS NOT NULL THEN audit_original_hash=baseline_attendance_hash END AS resolution_preserved_original_snapshot,
 CASE WHEN checkout_observed_after IS NOT NULL AND check_out_at IS NOT NULL
      THEN check_out_at BETWEEN checkout_observed_after AND server_as_of END AS checkout_in_observed_server_window,
 (check_out_at>scheduled_end AND check_out_at<=scheduled_end+interval '24 hours') AS raw_late_checkout_within_cutoff,
 (effective_check_in_at IS NOT NULL AND effective_check_out_at>=effective_check_in_at) AS effective_attendance_complete,
 (status='awaiting_verification' AND verification_status='not_submitted' AND verified_at IS NULL) AS awaiting_evidence_not_auto_verified
FROM observed ORDER BY scenario;
ROLLBACK;
