import { recommendationExplanationHandler } from './handler.mjs';
import { configuredGeminiProvider } from './gemini_provider.mjs';

// No provider or credential lookup unless explicitly enabled server-side.
Deno.serve(recommendationExplanationHandler({
  base: Deno.env.get('SUPABASE_URL'),
  anon: Deno.env.get('SUPABASE_ANON_KEY'),
  origin: undefined,
  demoUserId: Deno.env.get('JOBMATE_RECOMMENDATION_GEMINI_DEMO_USER_ID'),
  provider: configuredGeminiProvider((name: string) => Deno.env.get(name)),
}));
