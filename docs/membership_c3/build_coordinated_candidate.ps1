# DRAFT / NOT APPROVED FOR DEPLOYMENT. Text generation only. No database access.
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$candidate=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'candidate/001_hiring_membership_supported_candidate.sql'))
$stop=@'
-- Coordinated release remains incomplete. Agreement in principle is not artifact approval.
DO $coordinated_release_stop$
BEGIN
 RAISE EXCEPTION 'DRAFT: evaluation source, remaining authorization coverage, historical source match, policy approval and database tests outstanding';
END;
$coordinated_release_stop$;

'@
$candidate=$candidate.Replace('-- Source: 01_schema.sql',$stop+'-- Source: 01_schema.sql')
$patches=''
$targets=@(
 @('20261106000300_work_evidence_workflow.sql','can_review_work_evidence_company'),
 @('20261106000200_employer_attendance_gps.sql','read_employer_work_attendance_gps')
)
foreach ($target in $targets) {
 $source=[IO.File]::ReadAllText((Join-Path $repo ('supabase/migrations/'+$target[0])))
 $pattern='(?s)CREATE FUNCTION public\.'+[regex]::Escape($target[1])+'\(.*?AS \$function\$(.*?)\$function\$;'
 $match=[regex]::Match($source,$pattern)
 if (-not $match.Success) { throw ('Missing exact local source: '+$target[1]) }
 $original=$match.Groups[1].Value.Replace("`r`n","`n")
 $anchor="m.member_role IN ('owner', 'employer')"
 if ([regex]::Matches($original,[regex]::Escape($anchor)).Count -ne 1) { throw 'Ambiguous membership anchor' }
 $updated=$original.Replace($anchor,"m.membership_status = 'active' AND "+$anchor)
 $signature=if ($target[1] -eq 'can_review_work_evidence_company') {'uuid'} else {'uuid,uuid'}
 $patches+=@"

-- LOCAL SOURCE: supabase/migrations/$($target[0]). NOT a claimed live definition.
-- Apply ONLY when the actual body matches exactly (line endings normalized).
-- Existing OID, owner, ACL and SECURITY DEFINER configuration are preserved.
DO `$compatibility_patch`$
DECLARE
 f oid := pg_catalog.to_regprocedure('public.$($target[1])($signature)');
 old_body text := `$expected_body`$$original`$expected_body`$;
 new_body text := `$replacement_body`$$updated`$replacement_body`$;
 original_definition text; original_owner oid; original_acl aclitem[];
 original_config text[]; original_definer boolean;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required Module 4 function missing: $($target[1])'; END IF;
 SELECT p.proowner,p.proacl,p.proconfig,p.prosecdef,pg_catalog.pg_get_functiondef(p.oid)
 INTO original_owner,original_acl,original_config,original_definer,original_definition
 FROM pg_catalog.pg_proc p WHERE p.oid=f;
 IF NOT original_definer OR original_config IS DISTINCT FROM ARRAY['search_path=""']::text[]
 OR (SELECT replace(p.prosrc,E'\r\n',E'\n') FROM pg_catalog.pg_proc p WHERE p.oid=f) IS DISTINCT FROM old_body
 THEN RAISE EXCEPTION 'Source/security drift: $($target[1]); use the existing exact export, do not approximate'; END IF;
 -- Replace the body inside the server-rendered definition, preserving header/settings.
 EXECUTE replace(original_definition,(SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=f),new_body);
 IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=original_owner AND p.proacl IS NOT DISTINCT FROM original_acl
   AND p.proconfig IS NOT DISTINCT FROM original_config AND p.prosecdef=original_definer)
 THEN RAISE EXCEPTION 'Unexpected security boundary change'; END IF;
END;
`$compatibility_patch`$;
"@
}
$history=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'historical_function_evidence.json') -Raw | ConvertFrom-Json
foreach ($record in $history.functions) {
 $original=$record.body
 $updated=$original
 if ($record.name -eq 'public.submit_company_for_review') {
  $anchor='where m.user_id = v_user_id;'
  if ([regex]::Matches($original,[regex]::Escape($anchor)).Count -ne 1) { throw 'Ambiguous onboarding anchor' }
  $updated=$original.Replace($anchor,"where m.user_id = v_user_id and m.member_role = 'owner';")
 } elseif ($record.name -eq 'public.set_company_restriction') {
  $anchor='from public.company_memberships m where m.company_id=p_company_id;'
  if (-not $original.Contains($anchor)) { throw 'Restriction audience anchor missing' }
  $updated=$original.Replace($anchor,"from public.company_memberships m where m.company_id=p_company_id and m.membership_status='active' and m.member_role in ('owner','employer');")
 } elseif ($record.name -eq 'public.submit_company_logo_change') {
  $anchor="m.member_role = 'owner' for share;"
  if (-not $original.Contains($anchor)) { throw 'Owner logo anchor missing' }
  $updated=$original.Replace($anchor,"m.membership_status = 'active' and "+$anchor)
 } elseif ($record.name -in @('private.dispute_can_read','private.dispute_notify',
   'public.update_job_moderation','public.submit_dispute',
   'public.can_read_job_moderation_visibility','public.list_dispute_eligible_records')) {
  # Change ONLY explicit operational Owner/Employer predicates. Historical
  # Admin conflict NOT EXISTS affiliation predicates remain byte-for-byte intact.
  $rolePattern="m\.member_role in \('owner',\s*'employer'\)"
  if ([regex]::Matches($original,$rolePattern).Count -lt 1) { throw ('Missing operational role anchor: '+$record.name) }
  $updated=[regex]::Replace($original,$rolePattern,"m.membership_status='active' and m.member_role in ('owner','employer')")
 }
 $patches+=@"

-- HISTORICAL SOURCE: jobmate-before-module4-20261106.dump, schema text only.
-- NOT claimed deployed. Exact body match REQUIRED; header/ACL kept from server.
-- $($record.name): $(if ($original -eq $updated) {'compatibility source assertion; no replacement needed'} else {'narrow compatibility replacement'}).
DO `$historical_compatibility`$
DECLARE
 f oid := pg_catalog.to_regprocedure('$($record.identity)');
 expected text := `$historical_body`$$original`$historical_body`$;
 replacement text := `$historical_new`$$updated`$historical_new`$;
 before_row pg_catalog.pg_proc%ROWTYPE;
BEGIN
 IF f IS NULL THEN RAISE EXCEPTION 'Required historical function missing: $($record.identity)'; END IF;
 SELECT * INTO before_row FROM pg_catalog.pg_proc WHERE oid=f;
 IF replace(before_row.prosrc,E'\r\n',E'\n') IS DISTINCT FROM expected
   OR NOT before_row.prosecdef
   OR before_row.proowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='$($record.owner)')
   OR before_row.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
 THEN RAISE EXCEPTION 'Historical source/security mismatch: $($record.identity); do not approximate'; END IF;
 IF expected IS DISTINCT FROM replacement THEN
  EXECUTE replace(pg_catalog.pg_get_functiondef(f),before_row.prosrc,replacement);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=f
   AND p.proowner=before_row.proowner AND p.proacl IS NOT DISTINCT FROM before_row.proacl
   AND p.proconfig IS NOT DISTINCT FROM before_row.proconfig AND p.prosecdef=before_row.prosecdef
   AND p.prorettype=before_row.prorettype AND p.provolatile=before_row.provolatile)
 THEN RAISE EXCEPTION 'Historical compatibility changed security/signature'; END IF;
END;
`$historical_compatibility`$;
"@
}
if (-not $candidate.TrimEnd().EndsWith('COMMIT;')) { throw 'Expected final transaction boundary' }
$candidate=$candidate.TrimEnd().Substring(0,$candidate.TrimEnd().Length-7)+$patches+"`nCOMMIT;`n"
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'candidate/002_coordinated_release_candidate.sql'),$candidate)
Write-Output 'Generated blocked coordinated candidate. No SQL executed; original guards/files unchanged.'
