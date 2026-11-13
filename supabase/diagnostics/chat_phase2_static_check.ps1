# Offline security/scope checks only. Does not compile or execute PostgreSQL.
# No external packages, database connection, fixture or Git operation.
$ErrorActionPreference = 'Stop'
$chatRepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$chatCandidatePath = Join-Path $chatRepoRoot 'supabase/migrations/20261112000100_chat_backend_foundation_candidate.sql'
$chatDiagnosticPath = Join-Path $chatRepoRoot 'supabase/diagnostics/chat_phase2_catalog_verification.sql'
$chatSql = Get-Content -LiteralPath $chatCandidatePath -Raw
$chatDiagnostic = Get-Content -LiteralPath $chatDiagnosticPath -Raw
$chatCheckCount = 0
function Assert-ChatCheck([bool] $Condition, [string] $Description) {
    if (-not $Condition) { throw "Chat static check failed: $Description" }
    $script:chatCheckCount++
}

# Structural scope checks catch accidental changes to teammate-owned objects.
$chatWithoutComments = [regex]::Replace($chatSql, '(?m)--[^\r\n]*', '')
Assert-ChatCheck ($chatWithoutComments -match '(?s)^\s*BEGIN;\s*DO \$chat_release_guard\$.*?RAISE EXCEPTION.*?\$chat_release_guard\$;') 'unconditional release stop precedes DDL'
Assert-ChatCheck ($chatWithoutComments -match '(?s)DO \$chat_release_guard\$\s+BEGIN\s+RAISE EXCEPTION ''CHAT CANDIDATE BLOCKED: review deletion compatibility, current mutation paths, SQL compilation and security tests before approval'';\s+END;\s+\$chat_release_guard\$;') 'original unconditional guard block is intact'
Assert-ChatCheck ($chatWithoutComments -notmatch '(?im)^\s*(DROP|TRUNCATE|DELETE|CREATE\s+OR\s+REPLACE)\b') 'no destructive or replacing statements'
$chatTableNames = @('chat_conversations', 'chat_messages', 'chat_read_states')
$chatCreates = [regex]::Matches($chatWithoutComments, '(?i)CREATE TABLE public\.(\w+)')
Assert-ChatCheck ($chatCreates.Count -eq 3) 'exactly three new tables'
foreach ($chatMatch in $chatCreates) {
    Assert-ChatCheck ($chatTableNames -contains $chatMatch.Groups[1].Value) 'table create confined to chat'
}
foreach ($chatMatch in [regex]::Matches($chatWithoutComments, '(?i)ALTER TABLE public\.(\w+)')) {
    Assert-ChatCheck ($chatTableNames -contains $chatMatch.Groups[1].Value) 'table alteration confined to chat'
}
foreach ($chatMatch in [regex]::Matches($chatWithoutComments, '(?i)\b(?:INSERT INTO|UPDATE) public\.(\w+)')) {
    Assert-ChatCheck (($chatTableNames + @('notifications')) -contains $chatMatch.Groups[1].Value) 'DML targets only chat and atomic notifications'
}
Assert-ChatCheck ($chatWithoutComments -notmatch '(?i)\bUPDATE public\.notifications') 'existing inbox rows are not rewritten'
Assert-ChatCheck ($chatWithoutComments -notmatch '(?i)ON DELETE\s+(CASCADE|SET)') 'no history-erasing foreign key actions'
Assert-ChatCheck ($chatWithoutComments -notmatch '(?i)membership_status|is_active|revoked_at') 'no invented membership state columns'
Assert-ChatCheck ($chatWithoutComments -notmatch '(?i)\bUSING\s*\(\s*true\s*\)') 'no unrestricted read policy'
Assert-ChatCheck ($chatWithoutComments -notmatch '(?i)GRANT\s+(INSERT|UPDATE|DELETE|TRUNCATE|ALL)\b') 'no ordinary write grants'
Assert-ChatCheck ($chatWithoutComments -notmatch '(?i)pg_catalog\.(coalesce|greatest|least)\s*\(') 'SQL special expressions are not treated as functions'
foreach ($chatTable in $chatTableNames) {
    Assert-ChatCheck ($chatWithoutComments -match "ALTER TABLE public\.$chatTable ENABLE ROW LEVEL SECURITY;") "RLS enabled: $chatTable"
}
$chatPolicies = [regex]::Matches($chatWithoutComments, '(?is)CREATE POLICY\s+\w+\s+ON\s+public\.(\w+)\s+FOR\s+(\w+)\s+TO\s+(\w+)')
Assert-ChatCheck ($chatPolicies.Count -eq 2) 'exactly two Realtime table policies'
foreach ($chatPolicy in $chatPolicies) {
    Assert-ChatCheck (($chatTableNames -contains $chatPolicy.Groups[1].Value) -and
        $chatPolicy.Groups[1].Value -ne 'chat_read_states' -and
        $chatPolicy.Groups[2].Value -eq 'SELECT' -and
        $chatPolicy.Groups[3].Value -eq 'authenticated') 'participant SELECT policy scope'
}

# Every dollar quote is paired; examine each CREATE FUNCTION header separately.
$chatTags = [regex]::Matches($chatWithoutComments, '\$[A-Za-z_][A-Za-z_0-9]*\$') |
    Group-Object Value
foreach ($chatTag in $chatTags) {
    Assert-ChatCheck ($chatTag.Count -eq 2) "paired SQL dollar quote: $($chatTag.Name)"
}
$chatFunctionHeaders = [regex]::Matches($chatWithoutComments,
    '(?is)CREATE FUNCTION\s+((?:public|jobmate_chat_private)\.\w+)\s*\(.*?\)\s*RETURNS\b.*?\bAS\s+\$[A-Za-z_][A-Za-z_0-9]*\$')
Assert-ChatCheck ($chatFunctionHeaders.Count -eq 10) 'five RPCs and five internal helpers'
$chatExpectedPublicNames = @('public.get_or_create_chat_conversation',
    'public.list_my_chat_conversations', 'public.list_chat_messages',
    'public.send_chat_message', 'public.mark_chat_conversation_read')
$chatExpectedArguments = @{
    'public.get_or_create_chat_conversation' = 'p_application_id uuid'
    'public.list_my_chat_conversations' = 'p_limit integer DEFAULT 50, p_before_activity_at timestamptz DEFAULT NULL, p_before_conversation_id uuid DEFAULT NULL, p_conversation_id uuid DEFAULT NULL'
    'public.list_chat_messages' = 'p_conversation_id uuid, p_limit integer DEFAULT 50, p_before_sequence bigint DEFAULT NULL'
    'public.send_chat_message' = 'p_conversation_id uuid, p_client_request_id uuid, p_body text'
    'public.mark_chat_conversation_read' = 'p_conversation_id uuid, p_message_id uuid'
}
foreach ($chatHeader in $chatFunctionHeaders) {
    if ($chatHeader.Groups[1].Value.StartsWith('public.')) {
        Assert-ChatCheck ($chatExpectedPublicNames -contains $chatHeader.Groups[1].Value) 'public RPC names unchanged'
        $chatInputs = [regex]::Match($chatHeader.Value, '(?s)CREATE FUNCTION[^\(]+\((.*?)\)').Groups[1].Value
        Assert-ChatCheck (($chatInputs -replace '\s', '') -eq
            ($chatExpectedArguments[$chatHeader.Groups[1].Value] -replace '\s', '')) 'public RPC parameters, types and defaults unchanged'
    }
    Assert-ChatCheck ($chatHeader.Value -match "SET search_path = ''") "fixed search_path: $($chatHeader.Groups[1].Value)"
    if ($chatHeader.Groups[1].Value -ne 'jobmate_chat_private.valid_body') {
        Assert-ChatCheck ($chatHeader.Value -match 'SECURITY DEFINER') "trusted authorization path: $($chatHeader.Groups[1].Value)"
    }
}
$chatPublication = [regex]::Matches($chatWithoutComments, '(?im)^ALTER PUBLICATION[^;]+;')
Assert-ChatCheck ($chatPublication.Count -eq 1 -and
    $chatPublication[0].Value -eq 'ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_conversations, public.chat_messages;') 'only intended Realtime additions'

# Phase 2B privacy/concurrency boundaries, not a proof of runtime race handling.
Assert-ChatCheck ($chatWithoutComments -notmatch '(?i)LOCK TABLE public\.company_memberships') 'no global membership lock'
Assert-ChatCheck ($chatWithoutComments -match '(?s)GRANT SELECT ON public\.chat_conversations, public\.chat_messages\s+TO authenticated;') 'direct SELECT confined to published tables'
Assert-ChatCheck ($chatWithoutComments -notmatch '(?is)GRANT SELECT[^;]*chat_read_states') 'read-state access is RPC-only'
Assert-ChatCheck ($chatWithoutComments -notmatch '(?i)LOCK TABLE public\.job_moderation_state') 'no global moderation lock'
Assert-ChatCheck ($chatWithoutComments -notmatch '(?im)^\s*LOCK\b') 'no explicit global table lock of any spelling'
$chatParticipantBody = [regex]::Match($chatWithoutComments, '(?s)AS \$participant_lock\$(.*?)\$participant_lock\$;').Groups[1].Value
Assert-ChatCheck ($chatParticipantBody -notmatch '(?i)LOCK TABLE|company_restrictions|FOR UPDATE|FOR NO KEY UPDATE') 'participant locking excludes mutation/recipient locks'
Assert-ChatCheck ($chatParticipantBody -match '(?s)PERFORM j\.job_id FROM public\.job_postings j\s+WHERE j\.job_id = v_job_id FOR SHARE NOWAIT;') 'existing relevant job-row SHARE NOWAIT protection retained'
Assert-ChatCheck ($chatParticipantBody -match '(?s)PERFORM a\.application_id FROM public\.job_applications a\s+WHERE a\.application_id = p_application_id FOR SHARE NOWAIT;') 'application status and identity updates conflict with shared application protection'
Assert-ChatCheck ($chatWithoutComments -match "WHEN a.status <> 'hired' AND \(cr.restriction_status = 'restricted'") 'hired Option B exception preserved'
$chatWriteLockBody = [regex]::Match($chatWithoutComments, '(?s)AS \$lock\$(.*?)\$lock\$;').Groups[1].Value
Assert-ChatCheck ($chatParticipantBody -match "current_setting\('transaction_isolation'\) <> 'read committed'" -and
    $chatParticipantBody -match "ERRCODE = '25001'") 'all locked operations use READ COMMITTED'
Assert-ChatCheck ([regex]::Matches($chatWithoutComments,"current_setting\('transaction_isolation'\)").Count -eq 1) 'single shared isolation check'
foreach ($chatLockBody in @($chatParticipantBody, $chatWriteLockBody)) {
    foreach ($chatLockStatement in [regex]::Matches($chatLockBody, '(?s)(?:SELECT|PERFORM)[^;]+FOR (?:SHARE|NO KEY UPDATE) NOWAIT;')) {
        $chatAfterLock = $chatLockBody.Substring($chatLockStatement.Index + $chatLockStatement.Length)
        Assert-ChatCheck ($chatAfterLock -match '^\s*IF NOT FOUND THEN\s+RAISE EXCEPTION') 'required row lock immediately checks FOUND'
    }
}
Assert-ChatCheck ($chatWriteLockBody -match 'PERFORM jobmate_chat_private.lock_participant\(p_application_id\);' -and
    $chatWriteLockBody -notmatch 'FROM public\.job_postings') 'write helper reuses existing targeted job lock without duplicate job acquisition'
Assert-ChatCheck ($chatWriteLockBody -match '(?s)IF p_creation THEN\s+PERFORM jobmate_chat_private.lock_participant\(p_application_id\);') 'only first creation acquires participant locks inside write helper'
$chatCreateBody = [regex]::Match($chatWithoutComments, '(?s)AS \$create\$(.*?)\$create\$;').Groups[1].Value
Assert-ChatCheck ($chatCreateBody -match '(?s)SELECT c\.conversation_id.*?application_access.*?IF FOUND THEN RETURN v_id; END IF;\s+PERFORM jobmate_chat_private.lock_application') 'authorized existing-thread fast path precedes mutation locks'
Assert-ChatCheck ($chatCreateBody -match '(?s)PERFORM jobmate_chat_private.lock_application\(p_application_id, true\);.*?SELECT ac\.read_only_reason.*?application_access') 'first creation eligibility follows targeted locks in a separate statement'
$chatSendBody = [regex]::Match($chatWithoutComments, '(?s)AS \$send\$(.*?)\$send\$;').Groups[1].Value
Assert-ChatCheck ($chatSendBody -match '(?s)PERFORM jobmate_chat_private.lock_participant\(v_application_id\);.*?PERFORM jobmate_chat_private.lock_application\(v_application_id\);') 'send retains participant locks before write helper reuse'
Assert-ChatCheck ($chatSendBody -match '(?s)PERFORM jobmate_chat_private.lock_application\(v_application_id\);\s+SELECT ac\.\* INTO v_context FROM jobmate_chat_private.application_access') 'fresh send eligibility follows targeted locks in a separate statement'
$chatMarkBody = [regex]::Match($chatWithoutComments, '(?s)AS \$mark\$(.*?)\$mark\$;').Groups[1].Value
Assert-ChatCheck ($chatMarkBody -match 'lock_participant' -and $chatMarkBody -notmatch 'lock_application|FOR UPDATE|FOR NO KEY UPDATE|LOCK TABLE') 'mark-read uses only authorization and own-cursor locking'
Assert-ChatCheck ($chatMarkBody -match 'GREATEST\(rs.last_read_sequence,EXCLUDED.last_read_sequence\)') 'read cursor cannot decrease'
Assert-ChatCheck ($chatWithoutComments -match 'FROM pg_catalog.unnest\(v_recipient_ids\)') 'notification insert consumes fixed recipient IDs'
Assert-ChatCheck ($chatWithoutComments -match 'FOR SHARE OF recipient, cm NOWAIT') 'snapshot employer accounts and memberships are locked'
Assert-ChatCheck ($chatWithoutComments -match 'You have a new message from a job applicant\.') 'employer notifications use generic applicant wording'
Assert-ChatCheck ($chatWithoutComments -match 'BETWEEN 1 AND 4000') 'body limit remains 4000 code points'

# Diagnostics must consist of catalogue SELECT/CTE statements, not runtime calls.
$chatDiagWithoutComments = [regex]::Replace($chatDiagnostic, '(?m)--[^\r\n]*', '')
# Mask string contents first: a catalogue regex may legitimately contain ';'.
$chatDiagStatementShape = [regex]::Replace($chatDiagWithoutComments, "'(?:''|[^'])*'", "''")
foreach ($chatStatement in ($chatDiagStatementShape -split ';')) {
    if ($chatStatement.Trim()) {
        Assert-ChatCheck ($chatStatement.Trim() -match '^(?i:SELECT|WITH)\b') 'diagnostics are SELECT/CTE only'
    }
}
Assert-ChatCheck ($chatDiagWithoutComments -notmatch '(?i)FROM\s+(?:public\.)?(chat_messages|chat_conversations|chat_read_states|notifications)\b') 'diagnostics read metadata, not private business rows'
$chatValidation = Get-Content -LiteralPath (Join-Path $chatRepoRoot 'supabase/diagnostics/chat_phase2_rollback_validation_candidate.sql') -Raw
$chatPost = Get-Content -LiteralPath (Join-Path $chatRepoRoot 'supabase/diagnostics/chat_phase2_post_rollback_verification.sql') -Raw
$chatDdlSafety = Get-Content -LiteralPath (Join-Path $chatRepoRoot 'supabase/diagnostics/chat_phase2_ddl_safety_inspection.sql') -Raw
foreach ($chatAclSource in @($chatDiagnostic,$chatPost,$chatValidation,$chatDdlSafety)) {
    $chatAclCode = [regex]::Replace($chatAclSource,'(?m)--[^\r\n]*','')
    $chatAclCalls = [regex]::Matches($chatAclCode,'(?i)pg_catalog\.aclexplode\(')
    Assert-ChatCheck ($chatAclCalls.Count -eq 1) 'one reviewed ACL expansion in each Chat SQL file'
    foreach ($chatAclCall in $chatAclCalls) {
        $chatAclTail = $chatAclCode.Substring($chatAclCall.Index)
        Assert-ChatCheck ($chatAclTail -match '(?s)^pg_catalog\.aclexplode\(\s*CASE WHEN pg_catalog\.cardinality\(.*?\) > 0\s*THEN .*? ELSE NULL::aclitem\[\] END\s*\) a') 'empty ACL protection is inside each aclexplode argument'
    }
}
function Normalize-ChatSql([string] $Sql) { return $Sql.Replace("`r`n", "`n").Trim() }
$chatExpectedDdl = [regex]::Match($chatSql, '(?s)(DO \$chat_preflight\$.*)\s*COMMIT;\s*$').Groups[1].Value
$chatCopiedDdl = [regex]::Match($chatValidation, '(?s)-- BEGIN EXACT MIGRATION BODY\r?\n(.*?)\r?\n-- END EXACT MIGRATION BODY').Groups[1].Value
Assert-ChatCheck ($chatExpectedDdl.Length -gt 0 -and (Normalize-ChatSql $chatExpectedDdl) -ceq (Normalize-ChatSql $chatCopiedDdl)) 'rollback DDL body exactly equals final migration, excluding wrapper/guard/COMMIT'
$chatExpectedSummary = [regex]::Match($chatDiagnostic, '(?s)(WITH\s+tables\(name\).*?);\s*-- 1\. Expected relation').Groups[1].Value
$chatCopiedSummary = [regex]::Match($chatValidation, '(?s)-- BEGIN EXACT CATALOG SUMMARY\r?\n(.*?)\r?\n-- END EXACT CATALOG SUMMARY').Groups[1].Value
Assert-ChatCheck ($chatExpectedSummary.Length -gt 0 -and (Normalize-ChatSql $chatExpectedSummary) -ceq (Normalize-ChatSql $chatCopiedSummary)) 'validation assertions use exact current catalogue summary'
$chatExpectedFingerprint = [regex]::Match($chatDiagnostic, '(?s)(-- 5\. Consolidated baseline:.*?)(?=-- 6\. WRITER BASELINE)').Groups[1].Value
$chatCopiedFingerprint = [regex]::Match($chatPost, '(?s)-- BEGIN EXACT EXISTING OBJECT FINGERPRINTS\r?\n(.*?)\r?\n-- END EXACT EXISTING OBJECT FINGERPRINTS').Groups[1].Value
Assert-ChatCheck ($chatExpectedFingerprint.Length -gt 0 -and (Normalize-ChatSql $chatExpectedFingerprint) -ceq (Normalize-ChatSql $chatCopiedFingerprint)) 'post-rollback baseline uses exact existing-object fingerprints'
$chatValidationShape = [regex]::Replace($chatValidation,'(?m)--[^\r\n]*','')
Assert-ChatCheck ($chatValidationShape -match '(?s)^\s*BEGIN ISOLATION LEVEL READ COMMITTED;.*DO \$chat_validation_approval_guard\$\s+BEGIN\s+RAISE EXCEPTION') 'separate unconditional validation approval guard'
Assert-ChatCheck ($chatValidationShape -notmatch '(?im)^\s*COMMIT\b' -and $chatValidationShape -match 'ROLLBACK;\s*$') 'validation ends in ROLLBACK and never COMMIT'
Assert-ChatCheck ($chatValidationShape -match "SET LOCAL lock_timeout = '1s';" -and $chatValidationShape -match "SET LOCAL statement_timeout = '15s';") 'conservative transaction-local timeouts'
Assert-ChatCheck ($chatValidationShape -match "SET LOCAL transaction_timeout = '90s';" -and
    $chatValidationShape -match "SET LOCAL idle_in_transaction_session_timeout = '60s';") 'PostgreSQL 17 total and idle transaction bounds'
Assert-ChatCheck ($chatValidationShape -match '(?s)DO \$chat_validation_approval_guard\$\s+BEGIN\s+RAISE EXCEPTION ''CHAT ROLLBACK VALIDATION NOT APPROVED: CH/KZ must review DDL hooks, baseline and execution session before authorizing this separate candidate'';\s+END;\s+\$chat_validation_approval_guard\$;') 'original separate approval guard unchanged'
Assert-ChatCheck ($chatValidationShape -match "session_replication_role'\) <> 'origin'" -and
    $chatValidationShape -match "server_version_num'\)::integer <> 170011") 'reviewed PostgreSQL 17.11 origin environment pinned'
Assert-ChatCheck ($chatValidationShape -match 'FULL JOIN actual a ON a.hook = x.hook' -and
    $chatValidationShape -match 'x.hook IS NULL OR a.hook IS NULL') 'missing and extra hooks fail closed'
Assert-ChatCheck ($chatValidationShape -match 'count\(\*\) FROM pg_catalog.pg_event_trigger\) <> 6') 'complete six-trigger set checked before joining handlers'
foreach ($chatHookField in @('event_name','enabled','tags','trigger_owner','handler_owner','handler',
    'lanname','prosecdef','proconfig','definition_md5','acl')) {
    Assert-ChatCheck ($chatValidationShape -match ('a\.' + $chatHookField + ' IS DISTINCT FROM')) 'all reviewed hook metadata fields compared'
}
$chatHookHashes = @('8da9dff6b2ae47498209d341acaeb60b','53a44336da0ac1dd62d89dbd988e6d1d',
    '4e6d7efe4aed1b3b92063b648aa7a0cf','1d06ef4fb47bb0ab6e6f8818a62013bb',
    'afaad7193dcf8f81e728d2bedb85e43e','4357772baf5cfcd5c6d7049585b3a537')
foreach ($chatHash in $chatHookHashes) {
    Assert-ChatCheck ($chatValidationShape.Contains($chatHash)) 'reviewed handler fingerprint pinned'
}
$chatCorrectedAclExpectations = @{
    'issue_pg_graphql_access' = '[["PUBLIC","EXECUTE",false],["postgres","EXECUTE",true],["supabase_admin","EXECUTE",false]]'
    'issue_pg_net_access' = '[["PUBLIC","EXECUTE",false],["dashboard_user","EXECUTE",false],["supabase_admin","EXECUTE",true]]'
}
foreach ($chatHookName in $chatCorrectedAclExpectations.Keys) {
    $chatAclMatch = [regex]::Match($chatValidationShape,
        ('(?s)\(''' + $chatHookName + ''',''ddl_command_end'',''O'',ARRAY\[''CREATE EXTENSION''\],\s*''[^'']+'',''[a-f0-9]{32}'',\s*''([^'']+)''::jsonb\)'))
    Assert-ChatCheck ($chatAclMatch.Success -and
        $chatAclMatch.Groups[1].Value -ceq $chatCorrectedAclExpectations[$chatHookName]) 'corrected live-reviewed hook ACL pinned exactly'
}
Assert-ChatCheck ($chatValidationShape -match 'bool_or\(a.is_grantable\)' -and
    $chatValidationShape -match 'a.acl IS DISTINCT FROM x.acl') 'normalized handler grant sets compared without ACL order'
Assert-ChatCheck ($chatValidationShape -match "report.status <> 'PASS'" -and
    $chatValidationShape -match '(?s)\$chat_validation_assertions\$;\s+SELECT ''CHAT_DDL_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING''.*?ROLLBACK;\s*$') 'success marker only follows catalogue assertions and precedes final rollback'
Assert-ChatCheck ($chatDiagnostic -match "\('TRIGGER'\),\('MAINTAIN'\)") 'PostgreSQL 17 MAINTAIN included in table privilege assertions'
Assert-ChatCheck ($chatPost -match "CASE WHEN t.tgisinternal THEN 'internal_trigger'" -and
    $chatPost -notmatch 'AND NOT t.tgisinternal') 'internal FK triggers included in consolidated baseline'
Assert-ChatCheck ($chatPost -match 'pubviaroot' -and $chatPost -match 'p.attnames' -and
    $chatPost -match 'p.rowfilter' -and $chatPost -match 'p.pubowner') 'full publication semantics exported'
Assert-ChatCheck ($chatPost -match "'definition',pg_catalog.pg_get_functiondef" -and
    $chatPost -match "'acl_with_grantors'") 'event handler bodies and full ACL provenance exported'
Assert-ChatCheck ($chatPost -match 'count\(\*\) AS record_count' -and
    $chatPost -match 'jsonb_agg' -and $chatPost -match 'object_identity') 'one complete JSON baseline export'
$chatDigest = Get-Content -LiteralPath (Join-Path $chatRepoRoot 'supabase/diagnostics/chat_phase2_deployment_fingerprint_digest.sql') -Raw
$chatBaselineCte = [regex]::Match($chatPost,'(?s)(WITH relations AS \(.*)\r?\nSELECT pg_catalog.count\(\*\) AS record_count,').Groups[1].Value
$chatDigestCte = [regex]::Match($chatDigest,'(?s)-- BEGIN EXACT SHARED BASELINE CTE\r?\n(.*?)\r?\n-- END EXACT SHARED BASELINE CTE').Groups[1].Value
Assert-ChatCheck ($chatBaselineCte.Length -gt 0 -and (Normalize-ChatSql $chatBaselineCte) -ceq (Normalize-ChatSql $chatDigestCte)) 'deployment digest derives from exact existing baseline record definitions'
Assert-ChatCheck ($chatDigest -match 'pg_catalog.sha256\(pg_catalog.convert_to' -and
    $chatDigest -match 'ORDER BY category COLLATE "C",object_identity COLLATE "C"') 'digest uses built-in SHA256 and deterministic record order'
Assert-ChatCheck ($chatDigest -match 'duplicate_key_count' -and $chatDigest -match 'compared_record_count' -and
    $chatDigest -match 'category_digests') 'digest exposes counts, duplicate keys and category hashes'
Assert-ChatCheck ($chatDigest -match 't.tgrelid = k.confrelid' -and $chatDigest -match 'k.contype = ''f''' -and
    $chatDigest -match 'keys.child_cols = ARRAY\[''sender_id''\]') 'parent-trigger additions identified by actual FK relationships and exact columns'
Assert-ChatCheck ($chatDigest -match "p.pubname = 'supabase_realtime'" -and
    $chatDigest -match "p.tablename IN \('chat_conversations','chat_messages'\)") 'publication delta limited to the intended two Chat members'
Assert-ChatCheck ($chatDigest -match 'planned_additions_for_review' -and
    $chatDigest -match 'p.category = b.category AND p.object_identity = b.object_identity') 'planned deltas are separately reported and excluded by exact identity only'
foreach ($chatReadOnlySql in @($chatPost,$chatDdlSafety,$chatDigest)) {
    $chatReadOnlyShape = [regex]::Replace($chatReadOnlySql,'(?m)--[^\r\n]*','')
    $chatReadOnlyShape = [regex]::Replace($chatReadOnlyShape,"'(?:''|[^'])*'","''")
    $chatReadOnlyStatements = @($chatReadOnlyShape -split ';' | Where-Object { $_.Trim() })
    if ($chatReadOnlySql -ceq $chatPost -or $chatReadOnlySql -ceq $chatDigest) {
        Assert-ChatCheck ($chatReadOnlyStatements.Count -eq 1) 'baseline/digest export has exactly one read-only query'
    }
    foreach ($chatReadOnlyStatement in $chatReadOnlyStatements) {
        if ($chatReadOnlyStatement.Trim()) {
            Assert-ChatCheck ($chatReadOnlyStatement.Trim() -match '^(?i:SELECT|WITH)\b') 'additional verification files are read-only SELECT/CTE'
        }
    }
}
foreach ($chatSource in @($chatWithoutComments, $chatDiagWithoutComments,
    ([regex]::Replace($chatValidation,'(?m)--[^\r\n]*','')),
    ([regex]::Replace($chatPost,'(?m)--[^\r\n]*','')),
    ([regex]::Replace($chatDdlSafety,'(?m)--[^\r\n]*','')),
    ([regex]::Replace($chatDigest,'(?m)--[^\r\n]*','')))) {
    $chatOutsideStrings = [regex]::Replace($chatSource, "'(?:''|[^'])*'", "''")
    Assert-ChatCheck ($chatOutsideStrings.Replace("''", '') -notmatch "'") 'SQL single-quoted strings are paired'
    $chatDepth = 0
    foreach ($chatParen in [regex]::Matches($chatOutsideStrings, '[()]')) {
        if ($chatParen.Value -eq '(') { $chatDepth++ } else { $chatDepth-- }
        if ($chatDepth -lt 0) { throw 'Chat SQL has an unmatched closing parenthesis.' }
    }
    Assert-ChatCheck ($chatDepth -eq 0) 'SQL parentheses balanced outside strings/comments'
}
Write-Output "PASS: $chatCheckCount offline structural/scope checks. SQL compilation and runtime behavior remain unverified."
