// Separate BASIC content-validation protocol. No malware-scan claim.
export const MAX_BYTES = 5242880;
export const CHUNK_BYTES = 262144;
export const BUCKET = 'jobmate-chat-basic-files';
export const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(value);
export async function sha256(bytes) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(x => x.toString(16).padStart(2, '0')).join('');
}
export function paths(row) {
  if (!uuid(row.attachment_id) || !uuid(row.conversation_id) || !uuid(row.sender_id)) throw Error('identity');
  return `${row.conversation_id}/${row.sender_id}/${row.attachment_id}/`;
}
export function chunkLength(size, index) {
  if (!Number.isSafeInteger(size) || size < 1 || size > MAX_BYTES ||
      !Number.isSafeInteger(index) || index < 0 || index >= Math.ceil(size / CHUNK_BYTES)) throw Error('chunk');
  return Math.min(CHUNK_BYTES, size - index * CHUNK_BYTES);
}
export async function boundedBody(request, limit) {
  if (Number(request.headers.get('content-length')) > limit) throw Error('size');
  const reader = request.body?.getReader();
  if (!reader) throw Error('body');
  const chunks = []; let length = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > limit) throw Error('size');
      chunks.push(value);
    }
  } finally { await reader.cancel().catch(() => {}); }
  const bytes = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return bytes;
}

// Dependencies are injectable for offline tests. Production supplies real auth,
// RPC, private Storage and validator adapters; there is no antivirus or mock scanner in this workflow.
export function allowedBrowserOrigin(origin, configuredOrigin) {
  if (typeof origin !== 'string') return false;
  // Match the literal browser host, not URL-normalized shorthand IPs or suffixes.
  const local = /^http:\/\/(?:localhost|127\.0\.0\.1)(?::([0-9]{1,5}))?$/.exec(origin);
  if (local) return local[1] === undefined || Number(local[1]) >= 1 && Number(local[1]) <= 65535;
  try {
    const parsed = new URL(origin);
    return ['http:', 'https:'].includes(parsed.protocol) && parsed.origin === origin &&
      origin === configuredOrigin;
  } catch { return false; }
}
export function attachmentHandler(deps) {
  return async request => {
    const origin = request.headers.get('origin');
    const allowed = origin !== null && allowedBrowserOrigin(origin, deps.origin);
    const allowedHeaders = 'authorization,apikey,content-type,x-client-info,x-attachment-id,x-chunk-index';
    const cors = { 'Vary': 'Origin',
      ...(allowed ? { 'Access-Control-Allow-Origin': origin } : {}),
      'Access-Control-Allow-Headers': allowedHeaders,
      'Access-Control-Allow-Methods': 'POST,OPTIONS', 'Cache-Control': 'no-store' };
    const reply = (value, status = 200) => Response.json(value, { status, headers: cors });
    if (origin !== null && !allowed) return reply({ error: 'Origin unavailable.' }, 403);
    if (request.method === 'OPTIONS') {
      if (!allowed) return reply({ error: 'Origin unavailable.' }, 403);
      const method = request.headers.get('access-control-request-method');
      const headers = request.headers.get('access-control-request-headers');
      if (method && method !== 'POST' || headers && headers.split(',').some(
        name => !allowedHeaders.split(',').includes(name.trim().toLowerCase()))) {
        return reply({ error: 'Preflight unavailable.' }, 403);
      }
      // Preflight never authenticates or touches RPCs/Storage, even with release off.
      return new Response(null, { status: 204, headers: cors });
    }
    if (!deps.enabled) {
      return reply({ error: 'Attachments unavailable.' }, 503);
    }
    if (request.method !== 'POST') return reply({ error: 'Method unavailable.' }, 405);
    try {
      const op = new URL(request.url).searchParams.get('op');
      if (op === 'cleanup') {
        await deps.authorizeCleanup(request);
        const rows = await deps.serviceRpc('claim_expired_chat_attachments_basic_v1', {});
        for (const row of rows) {
          if (!uuid(row.attachment_id) || typeof row.storage_path !== 'string' || !row.storage_path.endsWith('/file')) throw Error('cleanup');
          const prefix = row.storage_path.slice(0, -4);
          // Canonical paths came from service-only SQL; no client path is accepted.
          const objects = [...(row.chunks_only ? [] : [row.storage_path]), ...Array.from({ length: Math.ceil(row.size_bytes / CHUNK_BYTES) }, (_, i) => `${prefix}part.${i}`)];
          await deps.remove(objects);
          await deps.serviceRpc('complete_chat_attachment_cleanup_basic_v1', { p_attachment_id: row.attachment_id });
        }
        return reply({ cleaned: rows.length });
      }
      await deps.authenticate(request);
      const id = request.headers.get('x-attachment-id');
      if (!uuid(id)) return reply({ error: 'Invalid attachment.' }, 400);
      const row = await deps.userRpc(request, 'get_chat_attachment_basic_v1', { p_attachment_id: id });
      const prefix = paths(row);
      if (op === 'status') return reply(row);
      if (row.can_upload !== true || ['rejected', 'expired'].includes(row.state)) return reply({ error: 'Attachment unavailable or read-only.' }, 403);
      if (op === 'upload') {
        if (row.state !== 'pending') return reply({ error: 'Upload is locked. Check validation status.' }, 409);
        // SQL atomically rejects expired/collected reservations and leases the
        // upload against GC before any Storage HTTP write is started.
        await deps.userRpc(request, 'prepare_chat_attachment_upload_basic_v1', { p_attachment_id: id });
        const index = Number(request.headers.get('x-chunk-index'));
        const expected = chunkLength(row.size_bytes, index);
        const bytes = await boundedBody(request, expected);
        if (bytes.length !== expected) return reply({ error: 'Incomplete chunk.' }, 400);
        await deps.putImmutable(`${prefix}part.${index}`, bytes, 'application/octet-stream');
        return reply({ received: Math.min((index + 1) * CHUNK_BYTES, row.size_bytes) });
      }
      if (op !== 'validate') return reply({ error: 'Operation unavailable.' }, 400);
      if (['validated', 'committed'].includes(row.state)) return reply(row);
      const lease = await deps.userRpc(request, 'prepare_chat_attachment_validation_basic_v1', { p_attachment_id: id });
      if (!lease.validation_token) return reply(lease);
      const bytes = new Uint8Array(row.size_bytes);
      for (let i = 0, offset = 0; offset < bytes.length; i++) {
        const chunk = await deps.download(`${prefix}part.${i}`);
        if (chunk.length !== chunkLength(row.size_bytes, i)) throw Error('incomplete');
        bytes.set(chunk, offset); offset += chunk.length;
      }
      const hash = await sha256(bytes);
      const verdict = hash === row.expected_sha256 ? await deps.validate(bytes, row) : {
        verdict: 'rejected', sha256: hash, size_bytes: bytes.length,
        mime_type: row.mime_type, engine: 'jobmate-integrity-v1',
      };
      if (!['validated', 'rejected'].includes(verdict.verdict) || verdict.sha256 !== hash ||
          verdict.size_bytes !== bytes.length || typeof verdict.engine !== 'string' ||
          verdict.engine.length < 1 || verdict.engine.length > 200 ||
          verdict.verdict === 'validated' && verdict.mime_type !== row.mime_type) throw Error('validator');
      if (verdict.verdict === 'validated') await deps.putImmutable(`${prefix}file`, bytes, row.mime_type);
      await deps.serviceRpc('finish_chat_attachment_validation_basic_v1', { p_attachment_id: id, p_validation_token: lease.validation_token,
        p_verdict: verdict.verdict, p_sha256: hash, p_mime_type: row.mime_type,
        p_size_bytes: bytes.length, p_validator_version: verdict.engine });
      return reply(await deps.userRpc(request, 'get_chat_attachment_basic_v1', { p_attachment_id: id }));
    } catch (_) {
      // Includes auth, validator/network/lease failures: never approve or commit.
      // Do not log filenames, bytes, URLs, tokens or raw backend errors.
      return reply({ error: 'Attachment not confirmed. Check status and retry the same identity.' }, 503);
    }
  };
}
