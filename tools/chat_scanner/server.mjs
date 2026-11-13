import http from 'node:http';
import net from 'node:net';
import { createHash, timingSafeEqual } from 'node:crypto';
import { stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { validateFile, MAX } from './validate.mjs';

function command(bytes, configuration) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(configuration.socket);
    let response = Buffer.alloc(0);
    socket.setTimeout(45000, () => socket.destroy(Error('timeout')));
    socket.on('error', reject);
    socket.on('data', chunk => {
      response = Buffer.concat([response, chunk]);
      if (response.length > 4096) socket.destroy(Error('response'));
      if (response.includes(0) || response.includes(10)) { socket.destroy(); resolve(response.toString().replace(/[\0\r\n]+$/, '')); }
    });
    socket.on('end', () => reject(Error('incomplete')));
    socket.on('connect', async () => {
      try {
        if (bytes === null) { socket.write('zVERSION\0'); return; }
        socket.write('zINSTREAM\0');
        for (let i = 0; i < bytes.length; i += 65536) {
          const chunk = bytes.subarray(i, i + 65536), length = Buffer.alloc(4);
          length.writeUInt32BE(chunk.length);
          if (!socket.write(Buffer.concat([length, chunk]))) await new Promise(r => socket.once('drain', r));
        }
        socket.write(Buffer.alloc(4));
      } catch (error) { socket.destroy(); reject(error); }
    });
  });
}
export function clamScanner(configuration) {
  return async bytes => {
    // Fail closed on stale signatures, even if clamd would return OK.
    const db = await stat(configuration.database);
    if (Date.now() - db.mtimeMs > 48 * 3600000) throw Error('stale signatures');
    const engine = await command(null, configuration);
    if (!/^ClamAV [^/]+\/\d+\//.test(engine)) throw Error('version');
    const result = await command(bytes, configuration);
    if (result === 'stream: OK') return { verdict: 'approved', engine };
    if (/^stream: .+ FOUND$/.test(result)) return { verdict: 'rejected', engine };
    // Limits, parser errors, socket outages and unexpected responses are not clean.
    throw Error('scan incomplete');
  };
}
export function scannerServer({ secret, scan }) {
  let busy = false;
  return http.createServer(async (request, response) => {
    const reply = (status, value) => { response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); response.end(JSON.stringify(value)); };
    const digest = s => createHash('sha256').update(s).digest();
    if (!secret || request.method !== 'POST' || request.url !== '/scan' ||
        !timingSafeEqual(digest(request.headers.authorization ?? ''), digest(`Bearer ${secret}`))) { reply(401, { error: 'Unavailable' }); return; }
    if (busy) { reply(429, { error: 'Busy' }); return; }
    busy = true;
    try {
      const chunks = []; let size = 0;
      for await (const chunk of request) { size += chunk.length; if (size > MAX) throw Error('size'); chunks.push(chunk); }
      const bytes = Buffer.concat(chunks), hash = createHash('sha256').update(bytes).digest('hex');
      const name = decodeURIComponent(request.headers['x-file-name'] ?? '');
      const mime = request.headers['x-file-mime'];
      try { validateFile(bytes, name, mime); } catch (_) {
        reply(200, { verdict: 'rejected', sha256: hash, size_bytes: bytes.length, mime_type: mime, engine: 'jobmate-structure-v1' }); return;
      }
      const result = await scan(bytes);
      if (!['approved','rejected'].includes(result.verdict) || !result.engine) throw Error('scanner');
      reply(200, { ...result, engine: `jobmate-structure-v1; ${result.engine}`,
        sha256: hash, size_bytes: bytes.length, mime_type: mime });
    } catch (_) { reply(503, { error: 'Scan unavailable' }); }
    finally { busy = false; }
  });
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const server = scannerServer({ secret: process.env.CHAT_SCANNER_SECRET,
    scan: clamScanner({ socket: process.env.CLAMD_SOCKET ?? '/run/clamav/clamd.ctl',
      database: process.env.CLAMAV_DATABASE ?? '/var/lib/clamav/daily.cld' }) });
  // TLS/authenticated reverse proxy exposes /scan; never expose clamd's socket.
  server.requestTimeout = 60000; server.headersTimeout = 10000;
  server.listen(Number(process.env.PORT ?? 8788), '127.0.0.1');
}
