import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const root=new URL('../../',import.meta.url);
const read=p=>readFileSync(new URL(p,root),'utf8').replaceAll('\r\n','\n');
const sql=read('supabase/candidates/chat_phase6b_attachment_foundation.sql');
const validation=read('supabase/candidates/chat_phase6b_rollback_validation_candidate.sql');
const hashes={
 'supabase/migrations/20261112000100_chat_backend_foundation_candidate.sql':'8704715e62de895324a651c41bfd55cc2a756d2c739fded85b624fb4ab5fa0e7',
 'supabase/diagnostics/chat_phase2_rollback_validation_candidate.sql':'84ddf9ab9f30b2fc1930c3f68cfe7371b730c0ae1adfeceba859d070368ec099',
};
for(const [path,hash] of Object.entries(hashes)) assert.equal(createHash('sha256').update(readFileSync(new URL(path,root))).digest('hex'),hash,`Protected source changed: ${path}`);
const body=sql.replace(/COMMIT;\s*$/,'');
assert.ok(validation.includes(body),'exact migration body and guard equality');
assert.ok(validation.trimEnd().endsWith('ROLLBACK;'));
assert.ok(sql.includes("RAISE EXCEPTION 'CHAT ATTACHMENTS BLOCKED:"));
assert.equal((sql.match(/CREATE FUNCTION public\./g)??[]).length,10);
assert.equal((sql.match(/SECURITY DEFINER SET search_path = ''/g)??[]).length,11);
assert.equal((sql.match(/RESTRICTIVE/g)??[]).length,5);
assert.ok(!sql.includes('CREATE OR REPLACE'));
for(const name of ['finish_chat_attachment_scan_v2','claim_expired_chat_attachments_v2','complete_chat_attachment_cleanup_v2']) {
  assert.ok(sql.slice(sql.lastIndexOf('GRANT EXECUTE')).includes(name));
}
for(const value of ['expected_sha256','scan_token','scan_lease_until','upload_lease_until',"INTERVAL '10 minutes'",'FOR UPDATE SKIP LOCKED',"state='committed'",'public.send_chat_message(a.conversation_id,a.client_request_id,']) assert.ok(sql.includes(value),value);
for(const label of ['lock_timeout','statement_timeout','idle_in_transaction_session_timeout','transaction_timeout']) assert.ok(sql.includes(label));
const original=read('supabase/diagnostics/chat_phase2_rollback_validation_candidate.sql');
const hooks=original.slice(original.indexOf('  -- User-supplied reviewed PostgreSQL'),original.indexOf('\nEND;\n$chat_validation_safety$;'));
assert.ok(sql.includes(hooks),'exact six-hook definition/ACL baseline equality');
assert.ok(validation.includes('MAINTAIN'));
assert.ok(sql.includes('enabled boolean NOT NULL DEFAULT false'));
assert.ok(sql.includes('auth.uid()=ANY(s.participant_ids)'));
const diagnostic=read('supabase/candidates/chat_phase6b_readonly_preflight.sql');
assert.ok(sql.includes(diagnostic.slice(diagnostic.indexOf('WITH routines AS ('),diagnostic.indexOf('\nSELECT current_user'))),'shared read-only routine fingerprint CTE equality');
console.log('PASS: protected hashes, exact migration/guard copy, exact six-hook baseline, 10 secured RPCs, Storage boundaries, leases, quotas, idempotency structure and rollback assertions. Static inspection only; PostgreSQL execution UNVERIFIED.');
