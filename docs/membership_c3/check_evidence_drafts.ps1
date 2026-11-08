# DRAFT / NOT APPROVED FOR DEPLOYMENT. Static local assertions, NOT SQL execution.
$ErrorActionPreference='Stop'
$snapshot=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'evidence_snapshot.json') -Raw | ConvertFrom-Json
$items=@($snapshot.evidence.items)
function Assert([bool]$condition,[string]$message) {
  if (-not $condition) { throw $message }
  Write-Output ('PASS: '+$message)
}
Assert ($items.Count -eq 91) '91 evidence objects retained'
$finalPath=Join-Path $PSScriptRoot 'final_evidence_snapshot.json'
if (Test-Path -LiteralPath $finalPath) {
  $final=Get-Content -LiteralPath $finalPath -Raw | ConvertFrom-Json
  $combined=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'combined_evidence_snapshot.json') -Raw | ConvertFrom-Json
  Assert ($final.evidence.history_found -and $final.evidence.notifications_found) 'side-effect table found flags true'
  Assert (@($final.evidence.items).Count -eq 19 -and @($combined.evidence.items).Count -eq 110) '19 final objects appended, combined evidence has 110'
  Assert (@($final.evidence.items | Where-Object { $_.kind -eq 'trigger' -and -not $_.details.internal }).Count -eq 0) 'no custom history/notification triggers in final export'
  Assert ($combined.original_snapshot_sha256 -eq (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'evidence_snapshot.json')).Hash) 'original 91-object snapshot hash unchanged'
}
Assert (@($items | Group-Object { $_.kind+':'+$_.identity } | Where-Object Count -gt 1).Count -eq 0) 'unique original identities'
$original=($items | Where-Object identity -eq 'public.respond_to_job_application(p_application_id uuid, p_action text)').details.definition.Replace("`r`n","`n")
$acceptance=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '02_acceptance.sql')).Replace("`r`n","`n")
$schema=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '01_schema.sql'))
$auth=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '03_authorization.sql'))
foreach ($name in @('01_schema.sql','02_acceptance.sql','03_authorization.sql')) {
  $body=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $name))
  Assert ($body.StartsWith('-- DRAFT / NOT APPROVED FOR DEPLOYMENT')) ($name+' draft label')
  Assert ($body.Contains("RAISE EXCEPTION 'DRAFT / NOT APPROVED FOR DEPLOYMENT")) ($name+' unconditional execution stop')
  Assert (-not ($body -match '(?m)^GRANT\s')) ($name+' no added positive privilege grants')
  $tags=[regex]::Matches($body,'\$[A-Za-z_][A-Za-z_0-9]*\$') | ForEach-Object Value | Group-Object
  Assert (@($tags | Where-Object { $_.Count % 2 -ne 0 }).Count -eq 0) ($name+' paired dollar delimiters')
}
$tail=$original.Substring($original.IndexOf('    -- Update application.')).TrimEnd()
Assert ($acceptance.Contains($tail)) 'original update/history/notification tail retained exactly'
$start=$original.IndexOf('    -- Only the applicant may respond.')
$end=$original.IndexOf('    -- Validate the requested action and current status.')
Assert ($acceptance.Contains($original.Substring($start,$end-$start).TrimEnd())) 'original applicant authorization retained exactly'
$start=$original.IndexOf("    ELSIF p_action = 'decline_offer'")
$end=$original.IndexOf('    -- Retrieve job details for the notification.')
Assert ($acceptance.Contains($original.Substring($start,$end-$start).TrimEnd())) 'original decline/withdraw branches retained exactly'
Assert (([regex]::Matches($acceptance,'INSERT INTO public.application_status_history')).Count -eq 1) 'one original history insertion'
Assert (([regex]::Matches($acceptance,'INSERT INTO public.notifications')).Count -eq 1) 'one original notification insertion'
Assert (-not ($acceptance -match '(?im)^\s*UPDATE\s+public\.(users|company_memberships)')) 'no role/status update-upsert on acceptance'
Assert ($acceptance.Contains('ON CONFLICT(company_id,user_id) DO NOTHING')) 'pair creation never overwrites existing lifecycle'
Assert ($acceptance.Contains("v_membership.membership_status IS DISTINCT FROM 'active'")) 'inactive/revoked enrollment conflict denied'
Assert ($acceptance.IndexOf('RETURN ''hired''') -lt $acceptance.IndexOf('INSERT INTO public.company_memberships')) 'receipt-backed replay precedes all enrollment writes'
Assert ($schema.Contains("tg_op = 'DELETE'") -and $schema.Contains("tg_op = 'UPDATE'") -and -not $schema.Contains("tg_op = 'delete'")) 'Owner TG_OP comparisons corrected'
Assert ($schema.Contains("NEW.role::text IS DISTINCT FROM 'employer'")) 'new explicit Owner account-role safeguard'
Assert ($schema.Contains('PRIMARY KEY(company_id,user_id)') -and $schema.Contains('c3_one_owned_company_per_user_idx')) 'pair uniqueness and explicit owner-user index'
Assert (([regex]::Matches($auth,'(?m)^ALTER POLICY ')).Count -eq 6) 'six supplied policies patched without replacement'
Assert (-not ($auth -match '(?m)^(DROP|CREATE) POLICY ')) 'policy composition preserved by ALTER only'
Assert (([regex]::Matches($auth,"AND \(u.role = 'employer'::user_role\)")).Count -eq 2) 'initial logo/document onboarding requires Employer'
Write-Output 'Static assertions complete. PostgreSQL parsing, RLS, transaction and concurrency testing NOT performed.'
