import { allowedBrowserOrigin, boundedBody } from '../_shared/chat_basic/protocol.mjs';

const responseLimit = 65536;
const validAxis = (value, max) => Number.isFinite(value) && Math.abs(value) <= max;
const label = (value) => typeof value === 'string' ? value.trim().slice(0, 500) : '';
const json = async (message, limit) =>
  JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(await boundedBody(message, limit)));

export function jobDiscoverySearchHandler({
  base, anon, service, key, origin, request = fetch,
}) {
  const headers = (apiKey, token) => ({
    apikey: apiKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
  });
  return async (incoming) => {
    const browser = incoming.headers.get('origin');
    const allowed = browser !== null && allowedBrowserOrigin(browser, origin);
    const cors = {
      Vary: 'Origin',
      'Cache-Control': 'no-store',
      'Access-Control-Allow-Methods': 'POST,OPTIONS',
      'Access-Control-Allow-Headers': 'authorization,apikey,content-type,x-client-info',
      ...(allowed ? { 'Access-Control-Allow-Origin': browser } : {}),
    };
    const reply = (status, body) => Response.json(body, { status, headers: cors });
    const fail = (status, error) => reply(status, { error });
    if (browser !== null && !allowed) return fail(403, 'forbidden');
    if (incoming.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (incoming.method !== 'POST') return fail(405, 'method_not_allowed');
    const token = /^Bearer ([^\s]+)$/i.exec(incoming.headers.get('authorization') ?? '')?.[1];
    if (!token) return fail(401, 'unauthenticated');
    if (!base || !anon || !service || !key) return fail(503, 'unavailable');

    let query;
    try {
      const body = await json(incoming, 2048);
      query = typeof body?.query === 'string' ? body.query.trim() : '';
      if (Object.keys(body ?? {}).length !== 1 || query.length < 2 ||
          query.length > 120 || /[\x00-\x1f\x7f]/.test(query)) {
        return fail(400, 'invalid_query');
      }
    } catch {
      return fail(400, 'invalid_query');
    }

    try {
      const userHeaders = headers(anon, token);
      const auth = await request(`${base}/auth/v1/user`, {
        headers: userHeaders, signal: AbortSignal.timeout(5000),
      });
      if (auth.status === 401 || auth.status === 403) return fail(401, 'unauthenticated');
      if (!auth.ok) return fail(503, 'unavailable');
      const { id, is_anonymous: anonymous } = await json(auth, responseLimit);
      if (anonymous === true || typeof id !== 'string' ||
          !/^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i.test(id)) {
        return fail(401, 'unauthenticated');
      }

      const profileUrl = new URL(`${base}/rest/v1/users`);
      profileUrl.search = new URLSearchParams({ select: 'role,status', user_id: `eq.${id}` });
      const profile = await request(profileUrl, {
        headers: userHeaders, signal: AbortSignal.timeout(5000),
      });
      if (!profile.ok) return fail(503, 'unavailable');
      const rows = await json(profile, responseLimit);
      if (!Array.isArray(rows)) return fail(503, 'unavailable');
      if (rows.length !== 1 || rows[0]?.role !== 'job_seeker' || rows[0]?.status !== 'active') {
        return fail(403, 'forbidden');
      }

      const quota = await request(`${base}/rest/v1/rpc/reserve_job_discovery_place_search`, {
        method: 'POST', headers: headers(service, service),
        body: JSON.stringify({ p_job_seeker_id: id }), signal: AbortSignal.timeout(5000),
      });
      if (!quota.ok) return fail(503, 'unavailable');
      const reservation = await json(quota, 1024);
      if (reservation === 'forbidden') return fail(403, 'forbidden');
      if (reservation === 'rate_limited') return fail(429, 'rate_limited');
      if (reservation !== 'reserved') return fail(503, 'unavailable');
    } catch {
      return fail(503, 'unavailable');
    }

    const url = new URL('https://api.geoapify.com/v1/geocode/search');
    url.search = new URLSearchParams({
      text: query, filter: 'countrycode:my', limit: '5', format: 'json', apiKey: key,
    });
    const signal = AbortSignal.timeout(5000);
    try {
      const upstream = await request(url, { signal, redirect: 'error' });
      if (upstream.status === 429) return fail(429, 'rate_limited');
      if (!upstream.ok) return fail(503, 'unavailable');
      const { results } = await json(upstream, responseLimit);
      if (!Array.isArray(results)) return fail(503, 'unavailable');
      const places = [];
      for (const result of results) {
        if (result?.country_code?.toString().toLowerCase() !== 'my' ||
            !validAxis(result.lat, 90) || !validAxis(result.lon, 180)) continue;
        const address = label(result.formatted);
        const name = label(result.name) || label(result.address_line1) || address;
        if (!name) continue;
        places.push({ name, address, latitude: result.lat, longitude: result.lon });
        if (places.length === 5) break;
      }
      if (results.length && !places.length) return fail(503, 'unavailable');
      return reply(200, { places });
    } catch (error) {
      return signal.aborted || error?.name === 'TimeoutError'
        ? fail(504, 'timeout') : fail(503, 'unavailable');
    }
  };
}
