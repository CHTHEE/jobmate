# Offline artifact builder only. Reads the supplied CSV; NEVER executes SQL.
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$csvPath = Join-Path $taskRoot 'supabase/diagnostics/work_shift_schedule_catalog_export_20261110.csv'
$candidatePath = Join-Path $taskRoot 'supabase/migrations/20261110000100_work_shift_schedule_enforcement_candidate.sql'
$rollbackPath = Join-Path $taskRoot 'supabase/diagnostics/work_shift_schedule_enforcement_rollback_candidate.sql'
$manifestPath = Join-Path $taskRoot 'docs/work_shift_schedule_baseline_manifest.json'
$rows = @(Import-Csv -LiteralPath $csvPath)
if ($rows.Count -ne 3392 -or @($rows | Where-Object { [int]$_.total_row_count -ne $rows.Count }).Count) {
    throw 'Incomplete export: expected 3392 rows with matching total counts.'
}
foreach ($section in ($rows | Group-Object section)) {
    if (@($section.Group | Where-Object { [int]$_.section_row_count -ne $section.Count }).Count) {
        throw "Incomplete section $($section.Name)"
    }
}
foreach ($row in $rows | Where-Object { $_.section -in '01_required_function_presence','02_required_table_presence' }) {
    if (!(($row.details | ConvertFrom-Json).found)) { throw "Missing $($row.object_identity)" }
}
function Md5Text([string]$value) {
    $digest = [System.Security.Cryptography.MD5]::Create()
    try { return ([BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes($value)))).Replace('-', '').ToLowerInvariant() }
    finally { $digest.Dispose() }
}
function SqlLiteral([string]$value) { return "'" + $value.Replace("'", "''") + "'" }
function BodyHashLf([string]$definition) {
    $body = [regex]::Match($definition, '(?s)AS \$function\$(.*)\$function\$').Groups[1].Value
    if (!$body) { throw 'Missing function body for fingerprint' }
    return Md5Text ($body.Replace("`r`n", "`n").Replace("`r", "`n"))
}
$functions = @{}
foreach ($row in $rows | Where-Object { $_.section -eq '03_function_definition_security' }) {
    $d = $row.details | ConvertFrom-Json
    if ((Md5Text $d.definition) -ne $d.definition_md5) { throw "Definition hash mismatch: $($row.object_identity)" }
    $match = [regex]::Match($d.definition, 'CREATE OR REPLACE FUNCTION ([^(]+)\(')
    if (!$match.Success) { throw 'Unexpected function header' }
    $name = $match.Groups[1].Value
    if ($functions.ContainsKey($name)) { throw "Overload requires explicit builder review: $name" }
    $signature = $row.object_identity
    if (!$signature.StartsWith($d.schema + '.')) { $signature = $d.schema + '.' + $signature }
    $functions[$name] = [pscustomobject]@{name=$name; signature=$signature; metadata=$d; original=$d.definition; replacement=$d.definition}
}
function ReplaceOnce([string]$body, [string]$old, [string]$new) {
    if ([regex]::Matches($body, [regex]::Escape($old)).Count -ne 1) { throw "Ambiguous/missing edit anchor: $old" }
    return $body.Replace($old, $new)
}
$reserve = $functions['public.reserve_work_assignment_request']
$request = $functions['public.create_work_assignment_request']
$legacy = $functions['public.create_work_assignment']
$guard = $functions['public.guard_work_assignment_duplicate_shift']
$changed = @($reserve, $request, $legacy, $guard)
$approvedClosurePath = Join-Path $taskRoot 'supabase/diagnostics/closure_decline_authorization_patch_candidate.sql'
$approvedClosureSql = [IO.File]::ReadAllText($approvedClosurePath)
$approvedClosureMatch = [regex]::Match($approvedClosureSql, '(?s)CREATE OR REPLACE FUNCTION public.respond_job_engagement_closure_request\(.*?AS \$function\$(.*?)\$function\$')
if (!$approvedClosureMatch.Success) { throw 'Approved closure response definition missing' }
$approvedClosureHash = Md5Text ($approvedClosureMatch.Groups[1].Value.Replace("`r`n","`n").Replace("`r","`n"))
if ($approvedClosureHash -ne '8558e154e5eae1e8ea7b09c3fed41103') { throw 'Approved closure patch changed; explicit review/rebase required' }
$check = 'PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);'
# Make the application-first order explicit before the existing joined row locks.
# No changes to their authorization, payload matching or replay branches.
foreach ($f in @($reserve, $request)) {
    $f.replacement = ReplaceOnce $f.replacement ' SELECT a.status, j.company_id INTO v_app FROM public.job_applications a' @'
 PERFORM 1 FROM public.job_applications a WHERE a.application_id = p_application_id FOR UPDATE;
 SELECT a.status, j.company_id INTO v_app FROM public.job_applications a
'@
}
$reserve.replacement = ReplaceOnce $reserve.replacement ' INSERT INTO public.work_assignment_creation_requests(actor_id, application_id, company_id,' (" " + $check + "`n INSERT INTO public.work_assignment_creation_requests(actor_id, application_id, company_id,")
# Anchor only the final return after RETURNING; any later INSERT/FK waits are covered.
$reserve.replacement = ReplaceOnce $reserve.replacement ' RETURNING * INTO v_request;' (" RETURNING * INTO v_request;`n " + $check)
$request.replacement = ReplaceOnce $request.replacement ' v_assignment := public.create_work_assignment(' (" " + $check + "`n v_assignment := public.create_work_assignment(")
$request.replacement = ReplaceOnce $request.replacement ' RETURN v_assignment;' (" " + $check + "`n RETURN v_assignment;")
$legacy.replacement = ReplaceOnce $legacy.replacement '    SELECT' @'
    PERFORM 1 FROM public.job_applications a WHERE a.application_id = p_application_id FOR UPDATE;
    SELECT
'@
# The application lock is the deployed closure serialization point. Keep the
# original non-locking job read: adding a job lock to legacy creation would add
# a new lock edge with job-management writers, without improving closure safety.
$legacy.replacement = ReplaceOnce $legacy.replacement '    INSERT INTO public.work_assignments (' ("    " + $check + "`n    INSERT INTO public.work_assignments (")
$legacy.replacement = ReplaceOnce $legacy.replacement '    RETURN v_assignment_id;' ("    " + $check + "`n    RETURN v_assignment_id;")
# Preserve the COMPLETE deployed closure/cancellation/duplicate guard, adding
# validation after application and durable-claim waits, not replacing its logic.
# UPDATE already owns the assignment tuple before its row trigger runs. Never
# wait for an application held by cancellation, which can be waiting for that
# tuple. NOWAIT aborts the rescheduling statement with 55P03 instead of forming
# that cycle; the caller must roll back/retry the whole transaction. INSERT and
# the supported application-first cancellation RPC remain unchanged.
$guard.replacement = ReplaceOnce $guard.replacement 'order by a.application_id for update' @'
order by a.application_id for update nowait
'@
$guard.replacement = ReplaceOnce $guard.replacement '  return new;' @'
  if tg_op='INSERT' then
    perform private.validate_work_shift_schedule(new.scheduled_start,new.scheduled_end);
  elsif (new.application_id,new.scheduled_start,new.scheduled_end)
        is distinct from (old.application_id,old.scheduled_start,old.scheduled_end) then
    perform private.validate_work_shift_schedule(new.scheduled_start,new.scheduled_end);
  end if;
  return new;
'@

$newFunctions = @'
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
'@

# Pin unchanged lifecycle/authorization dependencies and all discovered assignment
# writers, not just the four edited routines. Metadata is exported, not assumed.
$pinned = @($functions.Values | Where-Object {
    $_.name -match '(work_assignment|engagement|^public.can_manage_company_jobs$)' -or
    $_.name -in @('public.check_in_work_assignment','public.check_out_work_assignment',
                 'public.request_more_work_evidence','public.submit_work_evidence','public.verify_work_assignment',
                 'private.protect_assignment_request_terminal_state','private.prevent_assignment_cancellation_mutation')
} | Sort-Object name)
function FunctionValues([bool]$post, [bool]$restored = $false) {
    $values = foreach ($f in $pinned) {
        $md = $f.metadata
        $hash = $md.definition_md5
        if ($f.name -eq 'public.respond_job_engagement_closure_request') { $hash = $approvedClosureHash }
        if (($post -or $restored) -and $changed.name -contains $f.name) {
            # Compare stored body on post-change, avoiding assumptions about
            # pg_get_functiondef's canonical header rendering.
            if ($post) { $hash = BodyHashLf $f.replacement }
            else { $hash = BodyHashLf $f.original }
        }
        '(' + ((@($f.signature, $hash, $md.owner, $md.raw_acl, (ConvertTo-Json -InputObject @($md.settings) -Compress), $md.volatility, $md.security_mode,
                  [string]$md.strict, [string]$md.leakproof, $md.parallel,
                  $md.identity_arguments, $md.arguments_with_defaults, $md.result, $md.kind, [string]$md.returns_set) | ForEach-Object { SqlLiteral $_ }) -join ',') + ')'
    }
    return $values -join ",`n"
}
function Assertions([bool]$post, [bool]$restored = $false) {
    $v = FunctionValues $post $restored
    $bodySignatures = @('public.respond_job_engagement_closure_request(uuid,text,text)')
    if ($post -or $restored) {
        $bodySignatures += @($changed | ForEach-Object { $_.signature })
    }
    $bodySignatureValues = ($bodySignatures | ForEach-Object { SqlLiteral $_ }) -join ','
    $sourceCompare = "CASE WHEN e.signature IN ($bodySignatureValues) THEN pg_catalog.md5(replace(replace(p.prosrc,chr(13)||chr(10),chr(10)),chr(13),chr(10))) ELSE pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) END"
    return @"
DO `$baseline`$
DECLARE e record; p pg_catalog.pg_proc;
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Candidate requires the exported postgres owner role.'; END IF;
  FOR e IN SELECT * FROM (VALUES
$v
  ) x(signature,expected_hash,owner_name,raw_acl,settings_json,volatility,security_mode,is_strict,is_leakproof,parallel_mode,identity_args,args_with_defaults,result_type,routine_kind,returns_set) LOOP
    SELECT * INTO p FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(e.signature);
    IF NOT FOUND THEN RAISE EXCEPTION 'Missing baseline routine: %',e.signature; END IF;
    IF ($sourceCompare) IS DISTINCT FROM e.expected_hash
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
`$baseline`$;
"@
}
$tableNames = @('public.work_assignments','public.work_assignment_creation_requests','public.work_assignment_shift_claims',
                'public.job_engagement_closures','public.job_engagement_closure_requests','public.work_assignment_cancellations')
$tableValues = foreach ($r in $rows | Where-Object { $_.section -eq '06_relation_security' -and $_.object_identity -in $tableNames }) {
    $d=$r.details|ConvertFrom-Json
    '(' + ((@($r.object_identity,$d.owner,$d.raw_acl) | ForEach-Object { SqlLiteral $_ }) -join ',') + ')'
}
$triggerValues = foreach($r in $rows | Where-Object { $_.section -eq '12_triggers' }) {
    $d=$r.details|ConvertFrom-Json
    $parts=$r.object_identity -split ' / ',2
    if ($parts[0] -in $tableNames -and $d.trigger_present -and !$d.internal) {
        '('+((@($parts[0],$parts[1],$d.definition.Replace('public.',''),$d.enabled_code) | ForEach-Object { SqlLiteral $_ }) -join ',')+')'
    }
}
$constraintValues = foreach($r in $rows | Where-Object { $_.section -eq '13_constraints' }) {
    $d=$r.details|ConvertFrom-Json
    $parts=$r.object_identity -split ' / ',2
    if ($parts[0] -in $tableNames -and $d.referencing_table.Replace('public.','') -eq $parts[0].Replace('public.','')) {
        '('+((@($parts[0],$parts[1],$d.definition.Replace('public.',''),[string]$d.validated,[string]$d.deferrable,[string]$d.initially_deferred) | ForEach-Object { SqlLiteral $_ }) -join ',')+')'
    }
}
$indexValues = foreach($r in $rows | Where-Object { $_.section -eq '14_indexes' }) {
    $d=$r.details|ConvertFrom-Json
    $parts=$r.object_identity -split ' / ',2
    if ($parts[0] -in $tableNames) {
        '('+((@($parts[0],$parts[1].Replace('public.',''),$d.definition.Replace('public.',''),[string]$d.unique,[string]$d.exclusion,[string]$d.immediate) | ForEach-Object { SqlLiteral $_ }) -join ',')+')'
    }
}
$triggerCountValues = foreach($table in $tableNames) {
    $count = @($rows | Where-Object {
        if ($_.section -ne '12_triggers' -or !($_.object_identity.StartsWith($table+' / '))) { return $false }
        $d=$_.details|ConvertFrom-Json
        return $d.trigger_present -and !$d.internal
    }).Count
    '('+(SqlLiteral $table)+','+$count+')'
}
$tableChecks = @"
DO `$tables`$
DECLARE e record; c pg_catalog.pg_class; v_trigger pg_catalog.pg_trigger; v_constraint pg_catalog.pg_constraint; v_index pg_catalog.pg_index;
BEGIN
  FOR e IN SELECT * FROM (VALUES
$($tableValues -join ",`n")
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
$($triggerCountValues -join ",`n")
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
$($constraintValues -join ",`n")
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
$($indexValues -join ",`n")
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
$($triggerValues -join ",`n")
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
`$tables`$;
"@
$prefix = @'
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
'@
$pre = Assertions $false
$post = Assertions $true
$restored = Assertions $false $true
$newNamesGuard = @'
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
'@
$newAclCheck = @'
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
'@
$helperValues = foreach ($match in [regex]::Matches($newFunctions, '(?s)CREATE FUNCTION (private\.[a-z_]+)\([^;]*?AS \$schedule\$(.*?)\$schedule\$;')) {
    $signature = $match.Groups[1].Value + '()'
    $definer = 'true'
    if ($match.Groups[1].Value -eq 'private.validate_work_shift_schedule') {
        $signature = $match.Groups[1].Value + '(timestamptz,timestamptz)'
        $definer = 'false'
    }
    '(' + (SqlLiteral $signature) + ',' + (SqlLiteral (Md5Text ($match.Groups[2].Value.Replace("`r`n", "`n").Replace("`r", "`n")))) + ',' + $definer + ')'
}
if (@($helperValues).Count -ne 2) { throw 'Expected exactly two new helper bodies' }
$helperChecks = @"
DO `$helpers`$
DECLARE e record; p pg_catalog.pg_proc;
BEGIN
  FOR e IN SELECT * FROM (VALUES
$($helperValues -join ",`n")
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
`$helpers`$;
"@
$candidate = @($prefix,$pre,$tableChecks,$newNamesGuard,$newFunctions) + @($changed | ForEach-Object { $_.replacement + ';' }) + @($post,$tableChecks,$newAclCheck,$helperChecks,'COMMIT;')
$rollback = @($prefix,$post,$tableChecks,$newAclCheck,$helperChecks,
    'DROP TRIGGER work_shift_schedule_after_write ON public.work_assignments;',
    'DROP TRIGGER work_shift_reservation_schedule_after_insert ON public.work_assignment_creation_requests;') +
    @($changed | ForEach-Object { $_.original + ';' }) + @(
    'DROP FUNCTION private.enforce_work_shift_schedule_after_write();',
    'DROP FUNCTION private.validate_work_shift_schedule(timestamptz,timestamptz);',
    $restored,$tableChecks,'COMMIT;')
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($candidatePath, ($candidate -join "`n`n") + "`n", $utf8)
[IO.File]::WriteAllText($rollbackPath, "-- ROLLBACK PROPOSAL ONLY: removes scheduling enforcement; separate approval required.`n" + ($rollback -join "`n`n") + "`n", $utf8)
$manifest = [ordered]@{status='NOT DEPLOYED / NOT DATABASE-TESTED; EXPECTED POST-SECURITY BASELINE';csv_sha256=(Get-FileHash -LiteralPath $csvPath -Algorithm SHA256).Hash;rows=$rows.Count;
    expected_security_dependency=[ordered]@{signature='public.respond_job_engagement_closure_request(uuid,text,text)';body_md5_lf=$approvedClosureHash;source='Approved local closure authorization patch; NOT independently verified deployed';artifact_sha256=(Get-FileHash -LiteralPath $approvedClosurePath -Algorithm SHA256).Hash};
    capture=(($rows|Where-Object section -eq '00_capture').details|ConvertFrom-Json);
    pinned_functions=@($pinned|ForEach-Object { [ordered]@{name=$_.name;signature=$_.signature;baseline=$_.metadata;modified=($changed.name -contains $_.name);
        baseline_body_md5_lf= $(if ($changed.name -contains $_.name) { BodyHashLf $_.original } else { $null });
        candidate_body_md5_lf= $(if ($changed.name -contains $_.name) { BodyHashLf $_.replacement } else { $null })} })}
[IO.File]::WriteAllText($manifestPath, ($manifest|ConvertTo-Json -Depth 16)+"`n", $utf8)
Write-Output 'Offline generation complete. No SQL executed.'
Write-Output $candidatePath
Write-Output $rollbackPath
Write-Output $manifestPath
