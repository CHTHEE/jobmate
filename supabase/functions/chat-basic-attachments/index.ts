// Basic content validation only; never marks a file malware-free.
import { validateFile } from '../_shared/chat_basic/validate.mjs';
import { attachmentHandler, BUCKET, boundedBody, MAX_BYTES, sha256 } from '../_shared/chat_basic/protocol.mjs';

const env = (name: string) => Deno.env.get(name) ?? '';
const base = env('SUPABASE_URL');
const anon = env('SUPABASE_ANON_KEY');
const service = env('SUPABASE_SERVICE_ROLE_KEY');
const cleanupKey = env('CHAT_BASIC_CLEANUP_SECRET');
const enabled = env('CHAT_BASIC_ATTACHMENTS_ENABLED') === 'true' && !!service &&
  cleanupKey.length >= 32;
async function checked(response: Response) {
  if (!response.ok) throw Error('request');
  return response;
}
function headers(token: string) {
  return { apikey: token === service ? service : anon, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}
function bearer(request: Request) {
  const value = request.headers.get('authorization') ?? '';
  if (!value.startsWith('Bearer ') || value.length < 20) throw Error('auth');
  return value.slice(7);
}
async function rpc(token: string, name: string, args: unknown) {
  const response = await checked(await fetch(`${base}/rest/v1/rpc/${name}`, {
    method: 'POST', headers: headers(token), body: JSON.stringify(args), signal: AbortSignal.timeout(20000),
  }));
  const returnsVoid = name === 'finish_chat_attachment_validation_basic_v1' ||
    name === 'complete_chat_attachment_cleanup_basic_v1';
  if (returnsVoid && response.status === 204) return null;
  const text = await response.text();
  if (returnsVoid && text.trim() === '') return null;
  // JSON-returning RPCs must still reject empty/malformed responses. Failed HTTP
  // requests were rejected above; an empty error response is never success.
  return JSON.parse(text);
}
function objectUrl(path: string) { return `${base}/storage/v1/object/${BUCKET}/${path}`; }
async function download(path: string) {
  const response = await checked(await fetch(objectUrl(path), { headers: headers(service), signal: AbortSignal.timeout(20000) }));
  return boundedBody(response, MAX_BYTES);
}
const handler = attachmentHandler({
  enabled, origin: env('CHAT_BASIC_ALLOWED_ORIGIN'),
  async authenticate(request: Request) {
    const token = bearer(request);
    await checked(await fetch(`${base}/auth/v1/user`, { headers: headers(token), signal: AbortSignal.timeout(10000) }));
  },
  async authorizeCleanup(request: Request) {
    // Constant-time digest comparison avoids leaking the scheduler secret.
    // Scheduler uses a server-side service JWT for the normal Supabase gateway
    // plus a separate cleanup secret. Do not disable gateway JWT verification.
    const supplied = await sha256(new TextEncoder().encode(request.headers.get('x-cleanup-secret') ?? ''));
    const expected = await sha256(new TextEncoder().encode(cleanupKey));
    let mismatch = 0; for (let i = 0; i < supplied.length; i++) mismatch |= supplied.charCodeAt(i) ^ expected.charCodeAt(i);
    const suppliedService = await sha256(new TextEncoder().encode(bearer(request)));
    const expectedService = await sha256(new TextEncoder().encode(service));
    for (let i = 0; i < suppliedService.length; i++) mismatch |= suppliedService.charCodeAt(i) ^ expectedService.charCodeAt(i);
    if (mismatch || !cleanupKey) throw Error('auth');
  },
  userRpc: (request: Request, name: string, args: unknown) => rpc(bearer(request), name, args),
  serviceRpc: (name: string, args: unknown) => rpc(service, name, args),
  download,
  async putImmutable(path: string, bytes: Uint8Array, mime: string) {
    const response = await fetch(objectUrl(path), { method: 'POST', headers: {
      ...headers(service), 'Content-Type': mime, 'x-upsert': 'false',
    }, body: bytes.slice().buffer, signal: AbortSignal.timeout(20000) });
    if (response.ok) return;
    // Supabase versions return 400/409 for duplicate paths; content equality,
    // not the status code, is the authoritative retry condition.
    if (await sha256(await download(path)) !== await sha256(bytes)) throw Error('conflict');
  },
  async remove(paths: string[]) {
    await checked(await fetch(`${base}/storage/v1/object/${BUCKET}`, { method: 'DELETE', headers: headers(service),
      body: JSON.stringify({ prefixes: paths }), signal: AbortSignal.timeout(20000) }));
  },
  async validate(bytes: Uint8Array, row: { original_name: string; mime_type: string }) {
    const receipt = { sha256: await sha256(bytes), size_bytes: bytes.length,
      mime_type: row.mime_type, engine: 'basic-type-validation-no-antivirus-v1' };
    try { validateFile(bytes, row.original_name, row.mime_type); return { ...receipt, verdict: 'validated' }; }
    catch (_) { return { ...receipt, verdict: 'rejected' }; }
  },
});
Deno.serve(handler);
