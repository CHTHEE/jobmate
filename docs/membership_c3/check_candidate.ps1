# DRAFT / NOT APPROVED FOR DEPLOYMENT. Local static contract assertions only.
$ErrorActionPreference='Stop'
function Assert([bool]$ok,[string]$message) {
  if (-not $ok) { throw $message }; Write-Output ('PASS: '+$message)
}
$path=Join-Path $PSScriptRoot 'candidate\001_hiring_membership_supported_candidate.sql'
$sql=[IO.File]::ReadAllText($path)
Assert ($sql.StartsWith('-- DRAFT / NOT APPROVED FOR DEPLOYMENT')) 'candidate draft label'
Assert ($sql.Contains("current_setting('jobmate.c3_candidate_approved',true)")) 'candidate fails closed without explicit review acknowledgement'
Assert (([regex]::Matches($sql,'(?m)^BEGIN;')).Count -eq 1 -and ([regex]::Matches($sql,'(?m)^COMMIT;')).Count -eq 1) 'one candidate outer transaction'
Assert ($sql.Contains('PRIMARY KEY(company_id,user_id)') -and $sql.Contains('ON CONFLICT(company_id,user_id) DO NOTHING')) 'schema/acceptance pair-key contract aligned'
Assert ($sql.Contains('c3_one_owned_company_per_user_idx')) 'explicit Owner-user uniqueness'
Assert ($sql.Contains("member_role IN ('owner','employer','member')")) 'ordinary role supported'
Assert (([regex]::Matches($sql,'INSERT INTO public.application_status_history')).Count -eq 1) 'one preserved history insertion'
Assert (([regex]::Matches($sql,'INSERT INTO public.notifications')).Count -eq 1) 'one preserved notification insertion'
$rpc=$sql.Substring($sql.IndexOf('CREATE FUNCTION public.get_my_hiring_membership'))
Assert ($rpc.Contains('a.applicant_id=v_actor') -and $rpc.Contains("a.status='hired'")) 'membership read limited to owned Hired application'
Assert ($rpc.Contains("u.role='job_seeker'::public.user_role") -and $rpc.Contains("u.status='active'::public.account_status")) 'membership read requires active worker'
Assert (-not ($rpc -match '(?im)^\s*(INSERT|UPDATE|DELETE)\s')) 'membership read does not write'
Assert ($rpc.Contains('FROM PUBLIC,anon,authenticated,service_role') -and $rpc.Contains('TO authenticated;')) 'new read RPC ACL restricts API execution'
foreach ($key in @('contract_version','application_id','company_id','user_id','member_role','membership_status','acceptance_recorded')) {
  Assert ($rpc.Contains("'$key'")) ('read projection field: '+$key)
}
& (Join-Path $PSScriptRoot 'check_evidence_drafts.ps1')
Write-Output 'No PostgreSQL execution, syntax parsing, RLS or concurrency test performed.'
