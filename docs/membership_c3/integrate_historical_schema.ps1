# DRAFT / NOT APPROVED FOR DEPLOYMENT. Parses already-exported SCHEMA TEXT only.
# Never connects to a database. Historical definitions are NOT claimed current.
param([Parameter(Mandatory=$true)][string]$SchemaFile)
$ErrorActionPreference='Stop'
$schema=[IO.File]::ReadAllText($SchemaFile).Replace("`r`n","`n")
$names=@('public.submit_company_for_review','public.submit_company_for_review_v2',
 'public.get_user_account_details','public.update_job_application_status',
 'public.get_managed_company','public.list_managed_companies',
 'private.dispute_can_read','private.dispute_notify',
 'public.set_company_restriction','public.update_job_moderation',
 'public.submit_dispute','public.can_read_dispute_evidence',
 'private.attach_jobmate_company_logo','private.job_moderation_conflicts',
 'private.user_report_conflicts','public.can_read_job_moderation_visibility',
 'public.list_company_logo_review_requests','public.list_company_review_requests',
 'public.list_dispute_eligible_records','public.review_company_logo_change',
 'public.review_company_request','public.submit_company_logo_change')
$records=@()
foreach ($name in $names) {
 $pattern='(?ms)^CREATE FUNCTION '+[regex]::Escape($name)+'\((?<args>.*?)\) RETURNS .*?\bAS (?<tag>\$[a-zA-Z_0-9]*\$)(?<body>.*?)\k<tag>;'
 $matchesFound=[regex]::Matches($schema,$pattern)
 if ($matchesFound.Count -ne 1) { throw ('Missing/ambiguous historical definition: '+$name) }
 $match=$matchesFound[0]
 $alter=[regex]::Match($schema,'(?m)^ALTER FUNCTION '+[regex]::Escape($name)+'\((?<args>.*?)\) OWNER TO (?<owner>\w+);')
 if (-not $alter.Success) { throw 'Missing historical owner/signature' }
 $types=@($alter.Groups['args'].Value.Split(',') | ForEach-Object { $_.Trim() -replace '^\w+\s+','' })
 $acl=@([regex]::Matches($schema,'(?m)^(?:GRANT|REVOKE) .*? ON FUNCTION '+[regex]::Escape($name)+'\(.*?;') | ForEach-Object Value)
 $records+=@{name=$name;identity=$name+'('+($types -join ',')+')';owner=$alter.Groups['owner'].Value;
  definition=$match.Value;body=$match.Groups['body'].Value;acl_statements=$acl}
}
$evidence=@{status='DRAFT / NOT APPROVED FOR DEPLOYMENT';provenance='Historical jobmate-before-module4-20261106.dump, schema-only pg_restore; NOT current deployed evidence';schema_sha256=(Get-FileHash -LiteralPath $SchemaFile).Hash;functions=$records}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'historical_function_evidence.json'),($evidence | ConvertTo-Json -Depth 8))
Write-Output ('Recovered '+$records.Count+' complete historical definitions; existing 110-object snapshot unchanged.')
