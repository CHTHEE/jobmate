// Self-contained Dashboard entrypoint for recommendation-insights.
export {};

const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(value);

class BodyTooLarge extends Error {}

async function boundedBody(request, limit) {
  if (Number(request.headers.get('content-length')) > limit) throw new BodyTooLarge();
  const reader = request.body?.getReader();
  if (!reader) throw Error('body');
  const chunks = []; let length = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > limit) throw new BodyTooLarge();
      chunks.push(value);
    }
  } finally { await reader.cancel().catch(() => {}); }
  const bytes = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return bytes;
}

function allowedBrowserOrigin(origin, configuredOrigin) {
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

const revision = 'recommendation-insights-v1-reliability';
const revisionHeader = 'X-JobMate-Recommendation-Revision';
const rejectionHeader = 'X-JobMate-Recommendation-Rejection';
const upstreamHeader = 'X-JobMate-Recommendation-Upstream-Status';

class ProviderFailure extends Error {
  readonly category: string;
  readonly upstreamStatus?: number;

  constructor(category: string, upstreamStatus?: number) {
    super(category);
    this.category = category;
    this.upstreamStatus = upstreamStatus;
  }
}

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
const instructions = 'Return JSON with an explanations array containing exactly one item per job_id. Each item contains only job_id and explanation. Copy one approved_explanations sentence verbatim for that job.';
const insightCatalog = {
  why: { s: 'Mention skills shared by posting and profile', b: 'Note background keyword overlap', p: 'Note preference alignment' },
  consider: { g: 'Review listed skills absent from the profile', r: 'Check remaining role requirements', l: 'Explain limited evidence' },
  next: { p: 'Highlight a relevant project or experience', u: 'Review and update the profile where applicable', r: 'Review the posting before applying' },
};
const whyIds = ['0', ...Object.keys(insightCatalog.why)];
const nextIds = ['0', ...Object.keys(insightCatalog.next)];
const insightScenarios = {
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

function publicPostingFacts(employmentType, workArrangement) {
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
      output.explanations.length !== jobs.length) throw new ProviderFailure('provider_output_shape');
  const byAlias = new Map(jobs.map(job => [job.item.job_id, job]));
  return output.explanations.map(row => {
    if (!exactKeys(row, ['job_id', 'explanation'])) throw new ProviderFailure('provider_output_shape');
    const job = byAlias.get(row.job_id);
    if (!job) throw new ProviderFailure('provider_alias_invalid');
    if (!job.item.approved_explanations.includes(row.explanation)) {
      throw new ProviderFailure('provider_template_invalid');
    }
    byAlias.delete(row.job_id);
    return { job_id: job.id, explanation: row.explanation };
  });
}

function validateInsights(output, jobs) {
  if (!exactKeys(output, ['insights']) || !Array.isArray(output.insights) ||
      output.insights.length !== jobs.length) throw new ProviderFailure('provider_output_shape');
  const scenarios = Object.keys(insightScenarios);
  const aliases = new Map(jobs.map(job => [job.item.job_id, job.id]));
  return output.insights.map(row => {
    if (!exactKeys(row, ['job_id', ...scenarios])) throw new ProviderFailure('provider_output_shape');
    if (!aliases.has(row.job_id)) throw new ProviderFailure('provider_alias_invalid');
    for (const [scenario, sections] of Object.entries(insightScenarios)) {
      const choices = row[scenario];
      if (!exactKeys(choices, Object.keys(sections))) throw new ProviderFailure('provider_output_shape');
      if (!Object.entries(sections).every(([section, ids]) => ids.includes(choices[section]))) {
        throw new ProviderFailure('provider_template_invalid');
      }
    }
    const id = aliases.get(row.job_id);
    aliases.delete(row.job_id);
    return { ...row, job_id: id };
  });
}

function beforeTimeout(signal, work) {
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

function recommendationExplanationHandler({
  base, anon, origin, provider, demoUserId, request = fetch,
  now = () => new Date(), timeoutMs = 16_000,
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
        'Access-Control-Expose-Headers': `${revisionHeader}, ${rejectionHeader}, ${upstreamHeader}`,
      } : {}),
    };
    const reply = (status, body, category?: string, upstreamStatus?: number) => Response.json(body, {
      status, headers: {
        ...cors,
        ...(category ? { [rejectionHeader]: category } : {}),
        ...(upstreamStatus !== undefined ? { [upstreamHeader]: String(upstreamStatus) } : {}),
      },
    });
    const fail = (status, error, category = error, upstreamStatus?: number) =>
      reply(status, { error }, category, upstreamStatus);
    const invalidShortlist = category => reply(400, { error: 'invalid_shortlist' }, category);
    if (browser !== null && !allowed) return fail(403, 'forbidden');
    if (incoming.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (incoming.method !== 'POST') return fail(405, 'method_not_allowed');
    const token = /^Bearer ([^\s]+)$/i.exec(incoming.headers.get('authorization') ?? '')?.[1];
    if (!token) return fail(401, 'unauthenticated');
    if (!base || !anon || !provider || invalidDemoUser) return fail(503, 'unavailable');
    const signal = AbortSignal.timeout(timeoutMs);
    const handlerTimeout = () => fail(504, 'timeout', 'handler_timeout');

    let bytes;
    try {
      bytes = await beforeTimeout(signal, () => boundedBody(incoming, 1024));
    } catch {
      return signal.aborted ? handlerTimeout() : invalidShortlist('body_read');
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
          if (signal.aborted) return handlerTimeout();
          if (!(error instanceof ProviderFailure)) return fail(502, 'provider_unavailable');
          const { category, upstreamStatus } = error;
          if (category === 'provider_timeout') return fail(504, 'timeout', category);
          if (upstreamStatus === 429) return fail(429, 'rate_limited', category, upstreamStatus);
          return fail(502, 'provider_unavailable', category, upstreamStatus);
        }
      });
    } catch {
      return signal.aborted ? handlerTimeout() : fail(503, 'unavailable');
    }
  };
}

const endpoint = 'https://generativelanguage.googleapis.com/v1/interactions';
const invalidProviderRequest = () => new ProviderFailure('provider_request_invalid');

function buildRequest(model, payload) {
  if (!Array.isArray(payload?.jobs) || payload.jobs.length < 1 || payload.jobs.length > 5) {
    throw invalidProviderRequest();
  }
  const aliases = new Set();
  const insights = payload.insights_version === 1;
  const jobs = payload.jobs.map(job => {
    const id = job?.job_id;
    if (typeof id !== 'string' || !/^job-[1-5]$/.test(id) || aliases.has(id)) {
      throw invalidProviderRequest();
    }
    aliases.add(id);
    // Rebuild the outbound facts and sentences. Never serialize caller text
    // or pass through unexpected properties at this boundary.
    const facts = publicPostingFacts(job.employment_type, job.work_arrangement);
    if (facts.approved_explanations.length === 0) throw invalidProviderRequest();
    const { approved_explanations: approved, ...publicFacts } = facts;
    return { job_id: id, ...publicFacts, ...(insights ? {} : { approved_explanations: approved }) };
  });
  if (insights) return buildInsightsRequest(model, jobs, [...aliases]);
  return {
    model,
    store: false,
    input: JSON.stringify({ instructions, jobs }),
    generation_config: { max_output_tokens: 512 },
    response_format: {
      type: 'text',
      mime_type: 'application/json',
      schema: {
        type: 'object',
        additionalProperties: false,
        required: ['explanations'],
        properties: {
          explanations: {
            type: 'array',
            minItems: jobs.length,
            maxItems: jobs.length,
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['job_id', 'explanation'],
              properties: {
                job_id: { type: 'string', enum: [...aliases] },
                explanation: { type: 'string' },
              },
            },
          },
        },
      },
    },
  };
}

function buildInsightsRequest(model, jobs, aliases) {
  const properties = {
    job_id: { type: 'string', enum: aliases },
    ...Object.fromEntries(Object.entries(insightScenarios).map(([scenario, sections]) => [
      scenario,
      {
        type: 'object', additionalProperties: false, required: Object.keys(sections),
        properties: Object.fromEntries(Object.entries(sections).map(([section, ids]) => [
          section, { type: 'string', enum: ids },
        ])),
      },
    ])),
  };
  return {
    model,
    store: false,
    input: JSON.stringify({
      catalog_version: 'insights-v1',
      instructions: 'Choose one approved ID per section and job for strong fit, partial fit and limited evidence. Use 0 to omit. Prefer practical guidance. Return only JSON.',
      jobs,
      catalog: insightCatalog,
    }),
    generation_config: {
      max_output_tokens: 1024,
      ...(model === 'gemini-3.5-flash-lite' ? { thinking_level: 'minimal' } : {}),
    },
    response_format: {
      type: 'text', mime_type: 'application/json',
      schema: {
        type: 'object', additionalProperties: false, required: ['insights'],
        properties: {
          insights: {
            type: 'array', minItems: jobs.length, maxItems: jobs.length,
            items: {
              type: 'object', additionalProperties: false,
              required: Object.keys(properties), properties,
            },
          },
        },
      },
    },
  };
}

function extractCompletedOutput(interaction) {
  if (interaction?.status === 'incomplete' || interaction?.status === 'requires_continuation') {
    throw new ProviderFailure('provider_incomplete');
  }
  if (interaction?.status !== 'completed' || !Array.isArray(interaction.steps)) {
    throw new ProviderFailure('provider_response_shape');
  }
  const content = interaction.steps.findLast(step => step?.type === 'model_output')?.content;
  if (!Array.isArray(content) || content.length === 0 ||
      !content.every(part => part?.type === 'text' && typeof part.text === 'string')) {
    throw new ProviderFailure('provider_response_shape');
  }
  try {
    return JSON.parse(content.map(part => part.text).join(''));
  } catch {
    throw new ProviderFailure('provider_output_json');
  }
}

function configuredGeminiProvider(getEnv, { request = fetch, timeoutMs = 12_000 } = {}) {
  if (getEnv('JOBMATE_RECOMMENDATION_GEMINI_ENABLED') !== 'true') return undefined;
  const model = getEnv('JOBMATE_RECOMMENDATION_GEMINI_MODEL')?.trim();
  if (!model || !/^gemini-[a-z0-9][a-z0-9.-]{0,79}$/.test(model)) return undefined;
  const key = getEnv('GEMINI_API_KEY')?.trim();
  if (!key || /\s/.test(key)) return undefined;

  return async (payload, { signal: parent } = {}) => {
    const deadline = AbortSignal.timeout(timeoutMs);
    const signal = parent ? AbortSignal.any([parent, deadline]) : deadline;
    try {
      return await beforeTimeout(signal, async () => {
        const response = await request(endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'x-goog-api-key': key },
          body: JSON.stringify(buildRequest(model, payload)),
          signal,
          redirect: 'error',
        });
        if (!response.ok) {
          void response.body?.cancel().catch(() => {});
          throw new ProviderFailure('provider_http', response.status);
        }
        const bytes = await boundedBody(response, 65_536);
        let interaction;
        try {
          interaction = parseJson(bytes);
        } catch {
          throw new ProviderFailure('provider_response_json');
        }
        return extractCompletedOutput(interaction);
      });
    } catch (error) {
      if (signal.aborted) throw new ProviderFailure('provider_timeout');
      if (error instanceof ProviderFailure) throw error;
      if (error instanceof BodyTooLarge) throw new ProviderFailure('provider_response_too_large');
      throw new ProviderFailure('provider_transport');
    }
  };
}

// No provider or credential lookup unless explicitly enabled server-side.
Deno.serve(recommendationExplanationHandler({
  base: Deno.env.get('SUPABASE_URL'),
  anon: Deno.env.get('SUPABASE_ANON_KEY'),
  origin: undefined,
  demoUserId: Deno.env.get('JOBMATE_RECOMMENDATION_GEMINI_DEMO_USER_ID'),
  provider: configuredGeminiProvider((name: string) => Deno.env.get(name)),
}));
