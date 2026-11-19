import { jobDiscoverySearchHandler } from './handler.mjs';

Deno.serve(jobDiscoverySearchHandler({
  base: Deno.env.get('SUPABASE_URL'),
  anon: Deno.env.get('SUPABASE_ANON_KEY'),
  service: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
  key: Deno.env.get('GEOAPIFY_API_KEY'),
  origin: Deno.env.get('JOB_DISCOVERY_SEARCH_ALLOWED_ORIGIN'),
}));
