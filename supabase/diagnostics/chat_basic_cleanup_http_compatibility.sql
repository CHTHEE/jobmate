-- READ ONLY. CH runs manually as postgres. No HTTP requests or option setters.
-- Metadata only: no Vault decrypted values, queue rows/headers or raw job commands.
-- A 1.6 catalog version does NOT attest the hosted C binary's redirect behavior.
SELECT pg_catalog.jsonb_build_object(
 'current_user',current_user,'database',pg_catalog.current_database(),
 'extensions',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
   'name',e.extname,'version',e.extversion,'schema',n.nspname) ORDER BY e.extname)
   FROM pg_catalog.pg_extension e JOIN pg_catalog.pg_namespace n ON n.oid=e.extnamespace
   WHERE e.extname IN ('http','pg_cron','pg_net','supabase_vault')),
 'available_http_versions',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
   'version',v.version,'installed',v.installed) ORDER BY v.version)
   FROM pg_catalog.pg_available_extension_versions v WHERE v.name='http'),
 'http_routines',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
   'signature',p.oid::regprocedure::text,
   'return_type',pg_catalog.pg_get_function_result(p.oid),
   'language',l.lanname,'library',p.probin,'entry_point',p.prosrc,
   'postgres_execute',pg_catalog.has_function_privilege('postgres',p.oid,'EXECUTE'))
   ORDER BY p.proname)
   FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
   JOIN pg_catalog.pg_language l ON l.oid=p.prolang
   WHERE n.nspname='extensions' AND l.lanname='c'
     AND p.proname IN ('http','http_set_curlopt','http_reset_curlopt','http_list_curlopt')),
 'http_composite_fields',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
   'type',t.typname,'field',a.attname,'field_type',pg_catalog.format_type(a.atttypid,a.atttypmod))
   ORDER BY t.typname,a.attnum)
   FROM pg_catalog.pg_type t JOIN pg_catalog.pg_namespace n ON n.oid=t.typnamespace
   JOIN pg_catalog.pg_attribute a ON a.attrelid=t.typrelid AND a.attnum>0 AND NOT a.attisdropped
   WHERE n.nspname='extensions' AND t.typname IN ('http_request','http_response','http_header')),
 'logging_settings',pg_catalog.jsonb_build_object(
   'log_min_messages',pg_catalog.current_setting('log_min_messages'),
   'client_min_messages',pg_catalog.current_setting('client_min_messages'),
   'log_parameter_max_length_on_error',pg_catalog.current_setting('log_parameter_max_length_on_error'),
   'pgaudit.log_parameter',pg_catalog.current_setting('pgaudit.log_parameter',true),
   'auto_explain.log_min_duration',pg_catalog.current_setting('auto_explain.log_min_duration',true),
   'auto_explain.log_verbose',pg_catalog.current_setting('auto_explain.log_verbose',true)),
 'vault_names',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name',s.name,'count',s.n)
   ORDER BY s.name) FROM (SELECT name,pg_catalog.count(*) n FROM vault.secrets
   WHERE name IN ('jobmate_chat_project_url','jobmate_chat_service_role_jwt','jobmate_chat_cleanup_secret')
   GROUP BY name) s),
 'vault_api_access',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
   'role',r,'schema_usage',pg_catalog.has_schema_privilege(r,'vault','USAGE'),
   'decrypted_value_select',pg_catalog.has_column_privilege(r,'vault.decrypted_secrets','decrypted_secret','SELECT')))
   FROM pg_catalog.unnest(ARRAY['anon','authenticated']) r),
 'cleanup_jobs',COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
   'jobid',j.jobid,'jobname',j.jobname,'schedule',j.schedule,'active',j.active,'username',j.username))
   FROM cron.job j WHERE j.jobname='jobmate-chat-basic-cleanup-hourly'),'[]'::jsonb),
 'redirect_safety','UNCONFIRMED: catalog/API presence does not prove no-follow behavior; no registration approved by this query'
) AS cleanup_http_compatibility;
