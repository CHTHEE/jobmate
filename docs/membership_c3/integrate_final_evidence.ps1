# DRAFT / NOT APPROVED FOR DEPLOYMENT. Local CSV/JSON processing only.
param([Parameter(Mandatory=$true)][string]$EvidencePath)
$ErrorActionPreference='Stop'
$csv=@(Import-Csv -LiteralPath $EvidencePath)
if ($csv.Count -ne 1 -or -not $csv[0].evidence) { throw 'Expected one evidence CSV row' }
$final=$csv[0].evidence | ConvertFrom-Json
if (-not $final.history_found -or -not $final.notifications_found) { throw 'Missing side-effect table' }
$originalPath=Join-Path $PSScriptRoot 'evidence_snapshot.json'
$original=Get-Content -LiteralPath $originalPath -Raw | ConvertFrom-Json
if (@($original.evidence.items).Count -ne 91) { throw 'Original snapshot changed' }
$merged=@($original.evidence.items)+@($final.items)
if (@($merged | Group-Object { $_.kind+':'+$_.identity } | Where-Object Count -gt 1).Count) { throw 'Overlapping evidence needs explicit reconciliation' }
if (@($final.items | Where-Object { $_.kind -eq 'trigger' -and -not $_.details.internal }).Count) { throw 'Unreviewed custom side-effect trigger' }
foreach ($spec in @(
  @{name='application_status_history';written=@('application_id','previous_status','new_status','changed_by')},
  @{name='notifications';written=@('user_id','notification_type','title','message')}
)) {
  $r=@($final.items | Where-Object { $_.kind -eq 'relation' -and $_.identity -eq $spec.name })
  if ($r.Count -ne 1) { throw ('Missing relation '+$spec.name) }
  foreach ($name in $spec.written) {
    if (@($r[0].details.columns | Where-Object name -eq $name).Count -ne 1) { throw ('Missing INSERT column '+$name) }
  }
  foreach ($c in $r[0].details.columns) {
    if ($c.not_null -and $c.name -notin $spec.written -and -not $c.default -and -not $c.identity -and -not $c.generated) { throw ('Missing required INSERT value/default '+$c.name) }
  }
}
$side=[ordered]@{status='DRAFT / NOT APPROVED FOR DEPLOYMENT';source_file=(Split-Path $EvidencePath -Leaf);source_sha256=(Get-FileHash -LiteralPath $EvidencePath).Hash;evidence=$final}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'final_evidence_snapshot.json'),($side | ConvertTo-Json -Depth 32))
$combined=[ordered]@{status='DRAFT / NOT APPROVED FOR DEPLOYMENT';original_snapshot_sha256=(Get-FileHash -LiteralPath $originalPath).Hash;original_object_count=91;additional_object_count=@($final.items).Count;evidence=[ordered]@{items=$merged}}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'combined_evidence_snapshot.json'),($combined | ConvertTo-Json -Depth 32))
Write-Output ('PASS: original 91 preserved; '+@($final.items).Count+' additional objects; INSERT column/default coverage; no custom side-effect triggers')
