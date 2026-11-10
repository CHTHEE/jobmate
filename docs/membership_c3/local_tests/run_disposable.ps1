# DRAFT / NOT APPROVED FOR DEPLOYMENT. LOCAL DISPOSABLE POSTGRESQL ONLY.
# No connection string/remote host parameter. Review SQL files are never edited.
param([string]$PostgresBin='C:\Program Files\PostgreSQL\18\bin')
$ErrorActionPreference='Stop'
$package=Split-Path $PSScriptRoot -Parent
$root=Join-Path ([IO.Path]::GetTempPath()) ('jobmate_c3_disposable_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
$listener.Start(); $port=$listener.LocalEndpoint.Port; $listener.Stop()
$db='jobmate_c3_disposable'
$psql=Join-Path $PostgresBin 'psql.exe'
$pgctl=Join-Path $PostgresBin 'pg_ctl.exe'
$bootstrap=Join-Path (Split-Path $PostgresBin -Parent) 'share\postgres.bki'
if (-not (Test-Path -LiteralPath $bootstrap)) {
  throw ('Local PostgreSQL is incomplete: missing '+$bootstrap+'. No test SQL executed. Temp path: '+$root)
}
$argsLocal=@('-X','-h','127.0.0.1','-p',"$port",'-U','postgres','-d',$db,'-v','ON_ERROR_STOP=1')
function ExecSql([string]$file) {
  & $psql @argsLocal -f $file
  if ($LASTEXITCODE -ne 0) { throw ('Local SQL test failed: '+$file) }
}
$hashes=@{}
foreach ($name in @('01_schema.sql','02_acceptance.sql','03_authorization.sql')) {
  $hashes[$name]=(Get-FileHash -LiteralPath (Join-Path $package $name)).Hash
}
$started=$false
try {
  & (Join-Path $PostgresBin 'initdb.exe') -D (Join-Path $root 'data') -U postgres -A trust --no-locale -E UTF8
  if ($LASTEXITCODE) { throw 'Disposable initdb failed' }
  & $pgctl -D (Join-Path $root 'data') -l (Join-Path $root 'postgres.log') -o "-h 127.0.0.1 -p $port" -w start
  if ($LASTEXITCODE) { throw 'Disposable PostgreSQL start failed' }
  $started=$true
  & $psql -X -h 127.0.0.1 -p $port -U postgres -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE $db"
  if ($LASTEXITCODE) { throw 'Disposable database creation failed' }
  $snapshot=Get-Content -LiteralPath (Join-Path $package 'combined_evidence_snapshot.json') -Raw | ConvertFrom-Json
  $items=@($snapshot.evidence.items)
  # Explicitly synthetic adapters, not claimed deployed enum/Auth definitions.
  $baseline=@'
-- DRAFT / NOT APPROVED FOR DEPLOYMENT. DISPOSABLE FIXTURE ONLY.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
CREATE SCHEMA auth;
CREATE SCHEMA private;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE TABLE public.personal_resumes(resume_id uuid PRIMARY KEY);
CREATE TYPE public.user_role AS ENUM('job_seeker','employer','administrator');
CREATE TYPE public.account_status AS ENUM('active','suspended');
CREATE TYPE public.verification_status AS ENUM('not_submitted','verified','pending','rejected');
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
GRANT USAGE ON SCHEMA auth TO authenticated;

'@
  $rels=@($items | Where-Object kind -eq 'relation')
  foreach ($r in $rels) {
    $cols=@($r.details.columns | ForEach-Object {
      '"'+$_.name+'" '+$_.type+$(if ($_.default) {' DEFAULT '+$_.default})+$(if ($_.not_null) {' NOT NULL'})
    })
    $baseline+='CREATE TABLE public.'+$r.identity+" (`n"+($cols -join ",`n")+"`n);`n"
  }
  $constraints=@($items | Where-Object kind -eq 'constraint')
  # All 40 exported constraints, with PK/unique definitions before FK references.
  foreach ($k in @($constraints | Sort-Object @{Expression={if ($_.details.definition -match '^(PRIMARY KEY|UNIQUE)') {0} elseif ($_.details.definition -match '^FOREIGN KEY') {2} else {1}}})) {
    $parts=$k.identity.Split('.')
    $baseline+='ALTER TABLE public.'+$parts[0]+' ADD CONSTRAINT "'+$parts[1]+'" '+$k.details.definition+";`n"
  }
  foreach ($r in $rels) {
    if ($r.details.rls) { $baseline+='ALTER TABLE public.'+$r.identity+" ENABLE ROW LEVEL SECURITY;`n" }
    if ($r.details.force_rls) { $baseline+='ALTER TABLE public.'+$r.identity+" FORCE ROW LEVEL SECURITY;`n" }
    # Reproduce captured table/column ACL privileges for API roles.
    $map=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($pair in @('a=INSERT','r=SELECT','w=UPDATE','d=DELETE','D=TRUNCATE','x=REFERENCES','t=TRIGGER','m=MAINTAIN')) {
      $parts=$pair.Split('='); $map.Add($parts[0],$parts[1])
    }
    foreach ($entry in $r.details.acl.Trim('{}').Split(',')) {
      if ($entry -match '^(anon|authenticated|service_role)=([^/]+)/') {
        $role=$Matches[1];$privs=$Matches[2]
        $names=@($privs.ToCharArray() | ForEach-Object { $map[[string]$_] } | Where-Object { $_ })
        if ($names.Count) { $baseline+='GRANT '+($names -join ',')+' ON public.'+$r.identity+' TO '+$role+";`n" }
      }
    }
    foreach ($c in $r.details.columns) {
      if ($c.acl -eq '{authenticated=r/postgres}') { $baseline+='GRANT SELECT("'+$c.name+'") ON public.'+$r.identity+" TO authenticated;`n" }
    }
  }
  foreach ($i in @($items | Where-Object { $_.kind -eq 'index' -and $_.identity -in @('company_memberships_company_id_idx','jobmate_one_owner_per_company_idx') })) { $baseline+=$i.details.definition+";`n" }
  foreach ($name in @('private.protect_jobmate_company_owner()','public.can_manage_company_jobs(p_company_id uuid)','public.respond_to_job_application(p_application_id uuid, p_action text)')) {
    $f=($items | Where-Object { $_.kind -eq 'function' -and $_.identity -eq $name })
    $baseline+=$f.details.definition+";`n"
    $sig=if ($name -match '^private') {'private.protect_jobmate_company_owner()'} elseif ($name -match 'can_manage') {'public.can_manage_company_jobs(uuid)'} else {'public.respond_to_job_application(uuid,text)'}
    $baseline+='REVOKE ALL ON FUNCTION '+$sig+" FROM PUBLIC,anon,authenticated,service_role;`n"
    if ($name -notmatch '^private') { $baseline+='GRANT EXECUTE ON FUNCTION '+$sig+" TO authenticated,service_role;`n" }
  }
  $baseline+=($items | Where-Object { $_.kind -eq 'trigger' -and $_.identity -eq 'company_memberships.jobmate_protect_company_owner' }).details.definition+";`n"
  [IO.File]::WriteAllText((Join-Path $root 'baseline.sql'),$baseline)
  ExecSql (Join-Path $root 'baseline.sql')
  foreach ($name in @('01_schema.sql','02_acceptance.sql')) {
    $body=[IO.File]::ReadAllText((Join-Path $package $name))
    $pattern='(?s)DO \$c3_draft_guard\$.*?\$c3_draft_guard\$;'
    if ([regex]::Matches($body,$pattern).Count -ne 1) { throw 'Expected single review guard' }
    # Only disposable generated copies omit the guard. Original files untouched.
    $copy=Join-Path $root $name
    [IO.File]::WriteAllText($copy,[regex]::Replace($body,$pattern,'-- Guard omitted ONLY in disposable local test copy.'))
    ExecSql $copy
  }
  # Test the management helper from 03; Storage policies/full 03 are out of scope.
  $auth=[IO.File]::ReadAllText((Join-Path $package '03_authorization.sql'))
  $helper=[regex]::Match($auth,'(?s)CREATE OR REPLACE FUNCTION public\.can_manage_company_jobs.*?\$function\$;').Value
  if (-not $helper) { throw 'Management helper missing' }
  [IO.File]::WriteAllText((Join-Path $root 'management.sql'),$helper)
  ExecSql (Join-Path $root 'management.sql')
  ExecSql (Join-Path $PSScriptRoot 'acceptance_cases.sql')

  # Hold the first transaction after acceptance. Verify a second session waits
  # on the same application row before releasing the first to commit.
  $a=Join-Path $root 'concurrent_a.sql'
  $b=Join-Path $root 'concurrent_b.sql'
  [IO.File]::WriteAllText($a,@'
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='00000000-0000-4000-8000-000000000111';
SELECT public.respond_to_job_application(public.c3_uid(511),'accept_offer');
SELECT pg_sleep(4);
COMMIT;
'@)
  [IO.File]::WriteAllText($b,@'
SET application_name='c3_acceptance_contender';
SET lock_timeout='10s';
SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-4000-8000-000000000111';
SELECT public.respond_to_job_application(public.c3_uid(511),'accept_offer');
'@)
  $processA=Start-Process -FilePath $psql -ArgumentList ($argsLocal+@('-f',$a)) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'concurrent_a.out') -RedirectStandardError (Join-Path $root 'concurrent_a.err')
  $locked=$false
  for ($n=0;$n -lt 30;$n++) {
    $probe=& $psql @argsLocal -At -c "SELECT count(*) FROM pg_stat_activity WHERE datname='$db' AND query='SELECT pg_sleep(4);' AND state='active'"
    if ($probe -eq '1') { $locked=$true; break }
    Start-Sleep -Milliseconds 100
  }
  if (-not $locked) { throw 'First concurrent session did not reach held-commit barrier' }
  $processB=Start-Process -FilePath $psql -ArgumentList ($argsLocal+@('-f',$b)) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'concurrent_b.out') -RedirectStandardError (Join-Path $root 'concurrent_b.err')
  $waitObserved=$false
  for ($n=0;$n -lt 25;$n++) {
    $probe=& $psql @argsLocal -At -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='c3_acceptance_contender' AND wait_event_type='Lock'"
    if ($probe -eq '1') { $waitObserved=$true; break }
    Start-Sleep -Milliseconds 100
  }
  $processA.WaitForExit(); $processB.WaitForExit()
  if ($processA.ExitCode -ne 0 -or $processB.ExitCode -ne 0 -or -not $waitObserved) { throw 'Concurrent acceptance failed or no lock wait observed' }
  ExecSql (Join-Path $PSScriptRoot 'concurrent_assertions.sql')
  Write-Output ('PASS: concurrent requests in independent authenticated sessions; lock wait observed. Logs: '+$root)
  [IO.File]::WriteAllText((Join-Path $root 'PASS.txt'),'Sequential and concurrent isolated acceptance tests passed. See repository report for fixture limitations.')
} finally {
  if ($started) { & $pgctl -D (Join-Path $root 'data') -m fast -w stop }
  foreach ($name in $hashes.Keys) {
    if ((Get-FileHash -LiteralPath (Join-Path $package $name)).Hash -ne $hashes[$name]) { throw ('Review file changed: '+$name) }
  }
  Write-Output ('Disposable cluster started='+$started+'; any started cluster stopped; no files deleted. Artifacts: '+$root)
}
