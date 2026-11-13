-- READ ONLY. CH runs manually from an independent SQL Editor connection.
-- No cancellation, termination, data access or business RPC. Does not dump query text.
-- If validation PID was recorded, inspect it explicitly as shown in the incident runbook.
WITH sessions AS (
 SELECT a.pid,a.usename,a.datname,a.backend_start,a.state,a.xact_start,a.query_start,a.state_change,
   a.application_name,a.wait_event_type,a.wait_event,
   (pg_catalog.strpos(COALESCE(a.query,''),'BASIC UNIVERSITY DEMO ONLY')>0
     AND pg_catalog.strpos(COALESCE(a.query,''),'a5d682393de3f9ffc66f01c5264ec7c1')>0) AS appears_to_match_failed_trial
 FROM pg_catalog.pg_stat_activity a
 WHERE a.datname=pg_catalog.current_database() AND a.backend_type='client backend'
   AND a.pid<>pg_catalog.pg_backend_pid()
)
SELECT pg_catalog.pg_backend_pid() AS observer_pid,current_user,pg_catalog.current_database() AS database_name,
 pg_catalog.clock_timestamp() AS observed_at,
 (SELECT setting FROM pg_catalog.pg_settings WHERE name='track_activity_query_size') AS activity_text_limit,
 COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(s) ORDER BY pid) FROM sessions s
   WHERE xact_start IS NOT NULL OR state LIKE 'idle in transaction%' OR state IS NULL),'[]'::jsonb)
   AS other_client_open_or_unknown_transactions,
 COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(s) ORDER BY pid) FROM sessions s
   WHERE appears_to_match_failed_trial),'[]'::jsonb) AS possible_failed_trial_backends;
