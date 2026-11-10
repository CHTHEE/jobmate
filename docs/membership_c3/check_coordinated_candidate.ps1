# Local static assertions only. Does not parse/execute SQL or connect to PostgreSQL.
$ErrorActionPreference='Stop'
$file=Join-Path $PSScriptRoot 'candidate/002_coordinated_release_candidate.sql'
$before=(Get-FileHash -LiteralPath $file).Hash
& (Join-Path $PSScriptRoot 'build_coordinated_candidate.ps1')
if ($before -ne (Get-FileHash -LiteralPath $file).Hash) { throw 'Non-deterministic candidate' }
$sql=[IO.File]::ReadAllText($file)
if ([regex]::Matches($sql,'(?m)^BEGIN;').Count -ne 1 -or
 [regex]::Matches($sql,'(?m)^COMMIT;').Count -ne 1) { throw 'Outer transaction mismatch' }
if ($sql -notmatch '(?s)DO \$coordinated_release_stop\$.*?RAISE EXCEPTION.*?\$coordinated_release_stop\$;') { throw 'Missing release stop' }
if ([regex]::Matches($sql,'Source/security drift:').Count -ne 2 -or
 [regex]::Matches($sql,'p.proacl IS NOT DISTINCT FROM original_acl').Count -ne 2 -or
 [regex]::Matches($sql,"m.membership_status = 'active' AND m.member_role IN").Count -ne 2) { throw 'Expected two security-preserving lifecycle patches' }
$test=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'candidate/release_acceptance_tests.sql'))
if ([regex]::Matches($sql,'DO \$historical_compatibility\$').Count -ne 22 -or
 -not $sql.Contains("where m.user_id = v_user_id and m.member_role = 'owner';") -or
 -not $sql.Contains('p.proacl IS NOT DISTINCT FROM before_row.proacl')) { throw 'Historical source patches/security checks missing' }
foreach ($token in @('inet_server_addr()', 'jobmate_c3_disposable%', '\quit 3', 'ROLLBACK;', '\ir ../local_tests/acceptance_cases.sql')) {
 if (-not $test.Contains($token)) { throw ('Missing test boundary: '+$token) }
}
Write-Output 'PASS: deterministic assembly; both execution guards; one transaction; two lifecycle/security checks; disposable test boundaries.'
Write-Output 'NOT tested: SQL parsing/runtime, actual deployed equivalence, JWT/RLS/Storage or concurrency.'
