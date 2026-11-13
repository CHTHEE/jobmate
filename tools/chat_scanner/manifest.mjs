import { readFileSync,writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const root=new URL('../../',import.meta.url);
const files=[
 'supabase/candidates/chat_phase6b_attachment_foundation.sql',
 'supabase/candidates/chat_phase6b_rollback_validation_candidate.sql',
 'supabase/candidates/chat_phase6b_security_tests.sql',
 'supabase/candidates/chat_phase6b_empty_rollback_candidate.sql',
 'supabase/candidates/chat_phase6b_readonly_preflight.sql',
 'supabase/candidates/chat_phase6b_catalog_verification.sql',
 'supabase/functions/chat-attachments/index.ts',
 'supabase/functions/_shared/chat_attachments/protocol.mjs',
 'tools/chat_scanner/validate.mjs','tools/chat_scanner/server.mjs',
 'tools/chat_scanner/clamd.conf.example','tools/chat_scanner/jobmate-chat-scanner.service.example',
].sort();
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const entries=Object.fromEntries(files.map(path=>[path,sha(readFileSync(new URL(path,root)))]));
const result={backend_bundle_sha256:sha(JSON.stringify(entries)),files:entries};
writeFileSync(new URL('docs/chat_phase6b_artifact_hashes.json',root),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result));
