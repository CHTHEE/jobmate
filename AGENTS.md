# Mandatory development rules

These rules apply to coding-agent tasks throughout this repository.

1. Read root `README.md`, applicable instructions and relevant existing code before changes. Treat README.md and AGENTS.md as project guidance while following the user's latest explicit task and existing project requirements.
2. Follow the README's Web and Android UI/UX rules. Preserve working features and shared business logic, validation, authentication and backend behavior.
3. Inspect current routing before editing navigation: `lib/main.dart`, `lib/shared/navigation/app_routes.dart`, shared navigation widgets and affected screens. Reuse GoRouter and safe navigation patterns; check whether a route can pop and provide safe fallbacks for initial/direct routes.
4. On Web, sidebar destinations (including Personal Profile, Company Profile and My Job Postings) must not show redundant top-left AppBar back arrows. Disable inferred back arrows with `automaticallyImplyLeading: false` where appropriate; preserve sidebar/drawer access, titles and styling. Preserve browser Back, Forward, refresh and direct URLs; never make browser Back the only exit. Keep Android's appropriate AppBar/system Back behavior.
5. On Android, retain appropriate contextual AppBar and system Back behavior. Respect touch targets, keyboard usability, SafeArea and system insets.
6. Use `kIsWeb` only for platform differences; use responsive constraints/helpers for layout differences. Never infer platform from width. Keep consistent branding and accessible controls without overflow.
7. Protect unsaved user input when modifying forms or navigation. Inspect existing guards; busy-state locking alone is not dirty-form protection. Never remove the only practical exit.
8. Keep Gemini credentials and API calls server-side in Supabase Edge Functions. Never expose secrets in Flutter, bundled `.env`, logs or documentation. Only existing public Supabase client configuration belongs in `.env`.
9. Preserve Supabase authentication, authorization, RLS, company verification and employer membership checks. Use the existing Supabase project; never weaken checks to make functionality work.
10. Preserve employer draft/published/closed workflows. AI formatting must retain Original Description, keep generated sections editable and require employer review; never fabricate job facts.
11. Never modify unrelated teammates' work without approval. Prefer small, focused changes over large refactors.
12. Do not invent database columns, API contracts, environment variables, dependencies or commands. Inspect actual implementations; flag missing backend sources or uncertain deployment details.
13. Ask before destructive changes, major architectural changes or database migrations. Existing files do not authorize applying migrations or changing remote infrastructure.
14. Run `flutter analyze` and relevant tests when possible. Check affected Web and Android behavior as appropriate. Never claim something was tested unless it actually was; report blockers and untested behavior.
15. Report changed files, test results, warnings and any manual Supabase steps. Document necessary Dashboard changes separately without secret values.
16. Do not automatically commit or push unless explicitly requested. When requested, use focused, descriptive commits.
17. Update README.md when changes materially affect setup, architecture, features or UI conventions.
