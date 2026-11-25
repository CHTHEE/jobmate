import { boundedBody } from './protocol.mjs';
import { beforeTimeout, insightCatalog, insightScenarios, instructions, publicPostingFacts } from './handler.mjs';

const endpoint = 'https://generativelanguage.googleapis.com/v1/interactions';
const providerFailure = () => Error('gemini_unavailable');

function buildRequest(model, payload) {
  if (!Array.isArray(payload?.jobs) || payload.jobs.length < 1 || payload.jobs.length > 5) {
    throw providerFailure();
  }
  const aliases = new Set();
  const insights = payload.insights_version === 1;
  const jobs = payload.jobs.map(job => {
    const id = job?.job_id;
    if (typeof id !== 'string' || !/^job-[1-5]$/.test(id) || aliases.has(id)) {
      throw providerFailure();
    }
    aliases.add(id);
    // Rebuild the outbound facts and sentences. Never serialize caller text
    // or pass through unexpected properties at this boundary.
    const facts = publicPostingFacts(job.employment_type, job.work_arrangement);
    if (facts.approved_explanations.length === 0) throw providerFailure();
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
      instructions: 'For every job alias, choose approved template IDs for all three hypothetical scenarios: strong fit, partial fit, and limited evidence. Choose one ID per section; use 0 to omit. Prioritize practical job-review guidance. Return only the requested structured JSON.',
      jobs,
      scenarios: insightScenarios,
      catalog: insightCatalog,
    }),
    generation_config: { max_output_tokens: 1024 },
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
  if (interaction?.status !== 'completed' || !Array.isArray(interaction.steps)) {
    throw providerFailure();
  }
  const content = interaction.steps.findLast(step => step?.type === 'model_output')?.content;
  if (!Array.isArray(content) || content.length === 0 ||
      !content.every(part => part?.type === 'text' && typeof part.text === 'string')) {
    throw providerFailure();
  }
  return JSON.parse(content.map(part => part.text).join(''));
}

export function configuredGeminiProvider(getEnv, { request = fetch, timeoutMs = 4000 } = {}) {
  if (getEnv('JOBMATE_RECOMMENDATION_GEMINI_ENABLED') !== 'true') return undefined;
  const model = getEnv('JOBMATE_RECOMMENDATION_GEMINI_MODEL')?.trim();
  if (!model || !/^gemini-[a-z0-9][a-z0-9.-]{0,79}$/.test(model)) return undefined;
  const key = getEnv('GEMINI_API_KEY')?.trim();
  if (!key || /\s/.test(key)) return undefined;

  return async (payload, { signal: parent } = {}) => {
    const deadline = AbortSignal.timeout(timeoutMs);
    const signal = parent ? AbortSignal.any([parent, deadline]) : deadline;
    let quota = false;
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
          quota = response.status === 429;
          void response.body?.cancel().catch(() => {});
          throw providerFailure();
        }
        const bytes = await boundedBody(response, 65_536);
        const interaction = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
        return extractCompletedOutput(interaction);
      });
    } catch {
      if (signal.aborted) throw new DOMException('Gemini request timed out.', 'TimeoutError');
      if (quota) throw Object.assign(providerFailure(), { status: 429 });
      throw providerFailure();
    }
  };
}
