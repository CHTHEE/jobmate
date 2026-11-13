-- READ ONLY. Not executed by the agent. CH may inspect before any separate
-- validation approval; no event-trigger/handler/business RPC is invoked.
-- Export full definitions privately. Follow helper/external calls manually;
-- pg_depend and source strings cannot establish all dynamic/external effects.
SELECT current_user AS inspection_role, pg_catalog.current_database() AS database_name,
  pg_catalog.current_setting('server_version') AS server_version,
  pg_catalog.current_setting('session_replication_role') AS replication_role,
  pg_catalog.count(*) AS event_trigger_count,
  pg_catalog.count(*) FILTER (WHERE evtenabled <> 'D') AS enabled_event_trigger_count
FROM pg_catalog.pg_event_trigger;
SELECT e.evtname,e.evtevent,e.evtenabled,e.evttags,
  pg_catalog.pg_get_userbyid(e.evtowner) AS trigger_owner,
  pg_catalog.format('%I.%I(%s)',n.nspname,p.proname,
    pg_catalog.pg_get_function_identity_arguments(p.oid)) AS handler,
  pg_catalog.pg_get_userbyid(p.proowner) AS handler_owner,
  l.lanname,p.prosecdef,p.proconfig,p.prokind,p.pronargs,p.proretset,
  pg_catalog.pg_get_function_result(p.oid) AS result,p.proacl,
  (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_array(g.grantee,g.privilege,g.grantable)
      ORDER BY g.grantee COLLATE "C",g.privilege COLLATE "C")
   FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(a.grantee)::text END AS grantee,
       a.privilege_type AS privilege,pg_catalog.bool_or(a.is_grantable) AS grantable
     FROM pg_catalog.aclexplode(
       CASE WHEN pg_catalog.cardinality(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) > 0
         THEN COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner)) ELSE NULL::aclitem[] END
     ) a
     GROUP BY a.grantee,a.privilege_type) g) AS normalized_grant_set,
  pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) AS handler_fingerprint,
  pg_catalog.pg_get_functiondef(p.oid) AS handler_definition
FROM pg_catalog.pg_event_trigger e JOIN pg_catalog.pg_proc p ON p.oid = e.evtfoid
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
JOIN pg_catalog.pg_language l ON l.oid = p.prolang ORDER BY e.evtname;
-- Installed extensions are discovery leads, not proof of effects or safety.
SELECT extname,extversion FROM pg_catalog.pg_extension ORDER BY extname;
