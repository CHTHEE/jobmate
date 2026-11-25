import { allowedBrowserOrigin, boundedBody, uuid } from '../_shared/chat_basic/protocol.mjs';

const revision = 'phase3b-request-diag-1';
const revisionHeader = 'X-JobMate-Recommendation-Revision';
const rejectionHeader = 'X-JobMate-Recommendation-Rejection';

const types = new Map([
  ['full_time', 'This posting lists full-time employment.'],
  ['part_time', 'This posting lists part-time employment.'],
  ['contract', 'This posting lists contract employment.'],
  ['internship', 'This posting lists an internship.'],
  ['temporary', 'This posting lists temporary employment.'],
]);
const arrangements = new Map([
  ['on_site', 'This posting lists on-site work.'],
  ['hybrid', 'This posting lists hybrid work.'],
  ['remote', 'This posting lists remote work.'],
]);
export const instructions = 'Return JSON with an explanations array containing exactly one item per job_id. Each item contains only job_id and explanation. Copy one approved_explanations sentence verbatim for that job.';
export const insightCatalog = {
  why: { s: 'Mention skills shared by posting and profile', b: 'Note background keyword overlap', p: 'Note preference alignment' },
  consider: { g: 'Review listed skills absent from the profile', r: 'Check remaining role requirements', l: 'Explain limited evidence' },
  next: { p: 'Highlight a relevant project or experience', u: 'Review and update the profile where applicable', r: 'Review the posting before applying' },
};
const whyIds = ['0', ...Object.keys(insightCatalog.why)];
const nextIds = ['0', ...Object.keys(insightCatalog.next)];
export const insightScenarios = {
  strong: { why: whyIds, consider: ['0', 'g', 'r'], next: nextIds },
  partial: { why: whyIds, consider: ['0', 'g', 'r'], next: nextIds },
  limited: { why: whyIds, consider: ['0', 'g', 'l'], next: nextIds },
};
const businessDate = new Intl.DateTimeFormat('sv-SE', {
  timeZone: 'Asia/Kuala_Lumpur', year: 'numeric', month: '2-digit', day: '2-digit',
});
const parseJson = bytes => JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
const json = async (response, limit) => parseJson(await boundedBody(response, limit));
const exactKeys = (value, keys) =>
  value !== null && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));

function openOn(deadline, today) {
  if (typeof deadline !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(deadline)) return false;
  const parsed = new Date(`${deadline}T00:00:00Z`);
  return Number.isFinite(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === deadline && deadline >= today;
}

function completeRows(rows, contentRange) {
  if (!Array.isArray(rows)) return false;
  if (rows.length === 0) return contentRange === '*/0';
  return contentRange === `0-${rows.length - 1}/${rows.length}`;
}

export function publicPostingFacts(employmentType, workArrangement) {
  return {
    employment_type: types.has(employmentType) ? employmentType : null,
    work_arrangement: arrangements.has(workArrangement) ? workArrangement : null,
    approved_explanations: [types.get(employmentType), arrangements.get(workArrangement)].filter(Boolean),
  };
}

function providerJobs(rows) {
  // Canonical order depends only on the allowlisted facts. It carries no
  // recommendation rank, and aliases are meaningful only within this batch.
  const facts = rows.map(row => ({
    id: row.job_id,
    ...publicPostingFacts(row.employment_type, row.work_arrangement),
  })).sort((a, b) =>
    (a.employment_type ?? '').localeCompare(b.employment_type ?? '') ||
    (a.work_arrangement ?? '').localeCompare(b.work_arrangement ?? ''),
  );
  return facts.map(({ id, ...fields }, index) => ({
    id,
    item: {
      job_id: `job-${index + 1}`,
      ...fields,
    },
  }));
}

function validateProvider(output, jobs) {
  if (!exactKeys(output, ['explanations']) || !Array.isArray(output.explanations) ||
      output.explanations.length !== jobs.length) throw Error('invalid_provider_output');
  const byAlias = new Map(jobs.map(job => [job.item.job_id, job]));
  return output.explanations.map(row => {
    if (!exactKeys(row, ['job_id', 'explanation'])) throw Error('invalid_provider_output');
    const job = byAlias.get(row.job_id);
    if (!job || !job.item.approved_explanations.includes(row.explanation)) {
      throw Error('invalid_provider_output');
    }
    byAlias.delete(row.job_id);
    return { job_id: job.id, explanation: row.explanation };
  });
}

function validateInsights(output, jobs) {
  if (!exactKeys(output, ['insights']) || !Array.isArray(output.insights) ||
      output.insights.length !== jobs.length) throw Error('invalid_provider_output');
  const scenarios = Object.keys(insightScenarios);
  const aliases = new Map(jobs.map(job => [job.item.job_id, job.id]));
  return output.insights.map(row => {
    if (!exactKeys(row, ['job_id', ...scenarios]) || !aliases.has(row.job_id)) {
      throw Error('invalid_provider_output');
    }
    for (const [scenario, sections] of Object.entries(insightScenarios)) {
      const choices = row[scenario];
      if (!exactKeys(choices, Object.keys(sections)) ||
          !Object.entries(sections).every(([section, ids]) => ids.includes(choices[section]))) {
        throw Error('invalid_provider_output');
      }
    }
    const id = aliases.get(row.job_id);
    aliases.delete(row.job_id);
    return { ...row, job_id: id };
  });
}

export function beforeTimeout(signal, work) {
  signal.throwIfAborted();
  let abort;
  const timeout = new Promise((_, reject) => {
    abort = () => reject(signal.reason);
    signal.addEventListener('abort', abort, { once: true });
  });
  return Promise.race([timeout, Promise.resolve().then(work)])
    .finally(() => signal.removeEventListener('abort', abort));
}

// Instance-local demo limits. A live deployment needs a reviewed shared budget.
function demoLimit(now) {
  const lastRequest = new Map();
  let recent = [];
  return id => {
    const time = now().getTime();
    recent = recent.filter(at => time - at < 60_000);
    for (const [user, at] of lastRequest) {
      if (time - at >= 30_000) lastRequest.delete(user);
    }
    if (lastRequest.has(id) || recent.length >= 10) return false;
    lastRequest.set(id, time);
    recent.push(time);
    return true;
  };
}

export function recommendationExplanationHandler({
  base, anon, origin, provider, demoUserId, request = fetch,
  now = () => new Date(), timeoutMs = 6500,
}) {
  const withinLimit = demoLimit(now);
  const restrictToDemoUser = demoUserId !== undefined;
  const invalidDemoUser = restrictToDemoUser && !uuid(demoUserId);
  return async incoming => {
    const browser = incoming.headers.get('origin');
    const allowed = browser !== null && allowedBrowserOrigin(browser, origin);
    const cors = {
      Vary: 'Origin',
      'Cache-Control': 'no-store',
      'Access-Control-Allow-Methods': 'POST,OPTIONS',
      'Access-Control-Allow-Headers': 'authorization,apikey,content-type,x-client-info',
      [revisionHeader]: revision,
      ...(allowed ? {
        'Access-Control-Allow-Origin': browser,
        'Access-Control-Expose-Headers': `${revisionHeader}, ${rejectionHeader}`,
      } : {}),
    };
    const reply = (status, body) => Response.json(body, { status, headers: cors });
    const fail = (status, error) => reply(status, { error });
    const invalidShortlist = category => Response.json({ error: 'invalid_shortlist' }, {
      status: 400, headers: { ...cors, [rejectionHeader]: category },
    });
    if (browser !== null && !allowed) return fail(403, 'forbidden');
    if (incoming.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (incoming.method !== 'POST') return fail(405, 'method_not_allowed');
    const token = /^Bearer ([^\s]+)$/i.exec(incoming.headers.get('authorization') ?? '')?.[1];
    if (!token) return fail(401, 'unauthenticated');
    if (!base || !anon || !provider || invalidDemoUser) return fail(503, 'unavailable');
    const signal = AbortSignal.timeout(timeoutMs);

    let bytes;
    try {
      bytes = await beforeTimeout(signal, () => boundedBody(incoming, 1024));
    } catch {
      return signal.aborted ? fail(504, 'timeout') : invalidShortlist('body_read');
    }
    let body;
    try {
      body = parseJson(bytes);
    } catch {
      return invalidShortlist('json_parse');
    }
    const insights = exactKeys(body, ['job_ids', 'insights_version']);
    if (!insights && !exactKeys(body, ['job_ids'])) return invalidShortlist('request_fields');
    if (insights && body.insights_version !== 1) return invalidShortlist('request_version');
    const ids = body.job_ids;
    if (!Array.isArray(ids) || ids.length < 1 || ids.length > 5) return invalidShortlist('shortlist_shape');
    if (!ids.every(uuid)) return invalidShortlist('job_uuid');
    if (new Set(ids).size !== ids.length) return invalidShortlist('duplicate_jobs');

    const headers = {
      apikey: anon, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
    };
    const get = (url, options = {}) =>
      request(url, { headers, signal, redirect: 'error', ...options });
    const readRpc = async (name, projection) => {
      const url = new URL(`${base}/rest/v1/rpc/${name}`);
      url.search = new URLSearchParams({ select: projection, job_id: `in.(${ids.join(',')})` });
      const response = await get(url, {
        method: 'POST',
        headers: { ...headers, Prefer: 'count=exact' },
        body: '{}',
      });
      if (!response.ok) throw Error('unavailable_rpc');
      const rows = await json(response, 16_384);
      if (!completeRows(rows, response.headers.get('content-range')) ||
          !rows.every(row => ids.includes(row?.job_id))) throw Error('incomplete_rpc');
      return rows;
    };

    try {
      return await beforeTimeout(signal, async () => {
        const auth = await get(`${base}/auth/v1/user`);
        if (auth.status === 401 || auth.status === 403) return fail(401, 'unauthenticated');
        if (!auth.ok) return fail(503, 'unavailable');
        const user = await json(auth, 16_384);
        if (!uuid(user?.id) || user.is_anonymous === true) return fail(401, 'unauthenticated');
        if (restrictToDemoUser && user.id !== demoUserId) return fail(403, 'forbidden');

        const profileUrl = new URL(`${base}/rest/v1/users`);
        profileUrl.search = new URLSearchParams({
          select: 'role,status', user_id: `eq.${user.id}`,
        });
        const profile = await get(profileUrl);
        if (!profile.ok) return fail(503, 'unavailable');
        const accounts = await json(profile, 1024);
        if (!Array.isArray(accounts) || accounts.length !== 1 ||
            accounts[0]?.role !== 'job_seeker' || accounts[0]?.status !== 'active') {
          return fail(403, 'forbidden');
        }
        if (!withinLimit(user.id)) return fail(429, 'rate_limited');
        const [rows, applications] = await Promise.all([
          readRpc('list_published_jobs', 'job_id,application_deadline,employment_type,work_arrangement'),
          readRpc('list_my_job_applications', 'job_id'),
        ]);
        const today = businessDate.format(now());
        if (rows.length !== ids.length || new Set(rows.map(row => row.job_id)).size !== ids.length ||
            rows.some(row => !openOn(row.application_deadline, today)) ||
            applications.length !== 0) return fail(422, 'ineligible_shortlist');
        const jobs = providerJobs(rows);
        if (jobs.some(job => job.item.approved_explanations.length === 0)) {
          return fail(422, 'ineligible_shortlist');
        }
        signal.throwIfAborted();
        try {
          const output = await provider({ instructions, ...(insights ? { insights_version: 1 } : {}), jobs: jobs.map(job => ({
            ...job.item, approved_explanations: [...job.item.approved_explanations],
          })) }, { signal });
          signal.throwIfAborted();
          return reply(200, insights
            ? { insights_version: 1, insights: validateInsights(output, jobs) }
            : { explanations: validateProvider(output, jobs) });
        } catch (error) {
          if (error?.status === 429) return fail(429, 'rate_limited');
          if (signal.aborted || error?.name === 'TimeoutError') return fail(504, 'timeout');
          return fail(502, 'provider_unavailable');
        }
      });
    } catch {
      return signal.aborted ? fail(504, 'timeout') : fail(503, 'unavailable');
    }
  };
}
