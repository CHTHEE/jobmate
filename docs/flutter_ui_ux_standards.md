JobMate — Flutter Web + Android UI/UX Standards for Codex
Purpose: Make JobMate consistent, responsive, accessible, and platform-appropriate across Flutter Web and Android. Treat these rules as implementation and review acceptance criteria, not optional style suggestions.

IMPORTANT: Audit the existing codebase before changing anything. Reuse the project's existing design system, router, and shared widgets where appropriate. If this document conflicts with approved requirements or a documented design decision, identify the conflict rather than silently changing product functionality.

1. Non-negotiable requirements
- No RenderFlex overflow, clipping, overlapping content, unreachable buttons, or accidental full-page horizontal scroll on supported widths.
- Mandatory navigation by platform: Flutter Web uses a left sidebar for all top-level navigation; Flutter Android uses a bottom NavigationBar for primary top-level navigation. Never show Android bottom navigation on Web or the Web sidebar as Android primary navigation.
- No platform-inappropriate navigation: do not blindly reuse Android AppBar back arrows throughout desktop web pages.
- Do not duplicate top navigation, side navigation, and bottom navigation in the same layout unless there is a deliberate, documented reason.
- All pages use the same design tokens, typography hierarchy, paddings, colors, border radii, buttons, input styles, and status treatments.
- Every visible action must work, be explicitly disabled with a reason, or be removed. No placeholder controls disguised as working features.
- Preserve real backend and business behavior. A UI correction must not casually rewrite data models, security policies, payments, or workflows.
- Responsive behavior must be based primarily on available layout constraints; platform-specific interaction differences should be handled separately.
- Before claiming a screen is finished, test it on both Web and Android and report what was actually verified.
2. Platform-specific behavior: Web vs Android
Flutter Web — desktop or wide browser
- MANDATORY: Use a left-side sidebar as the primary navigation on Flutter Web. On desktop/wide browsers, keep it visible and highlight the current section. A top header may contain search, notifications, or account actions, but must not replace the sidebar with a top navbar.
- On narrow Web windows, keep the sidebar pattern: collapse to a compact left rail when it fits, or provide a button that opens an off-canvas left-side sidebar/drawer. Do not switch Web to Android bottom navigation.
- Use the same sidebar component and routing rules for Job Seeker, Employer, and Administrator; show only destinations authorized for each role.
- Do not automatically render an Android-style leading Back arrow on root pages (Dashboard, Jobs, Applications, Messages, Profile, Settings).
- For nested/detail pages, use breadcrumbs, a contextual Back to Jobs link, or a page-level back action only where it adds value. Do not interpret the rule as banning every back affordance.
- Browser Back and Forward buttons must work. Keep URL and current page synchronized. Support direct/deep links and page refresh where hosting supports route fallback.
- Prefer an existing project router; go_router is appropriate for applications with deep links and web browser history. Avoid ad hoc navigation that breaks URL state.
- Support mouse hover, pointer cursor, scroll wheel, visible keyboard focus, keyboard Tab traversal, Enter/Space activation where applicable, and sensible shortcuts.
- Avoid mobile-only UI patterns (oversized full-width buttons, bottom nav on wide web, stacked one-card layouts across the whole desktop width) unless intentional.
- A narrow mobile-browser window must use a compact content layout, but Web navigation must remain a left sidebar / collapsible left drawer, not a bottom NavigationBar.
Flutter Android
- MANDATORY: Use a bottom NavigationBar / Bottom Navigation for the primary top-level destinations on Flutter Android, including typical phone layouts. Do not copy the Web left sidebar as Android primary navigation.
- Keep bottom navigation to approximately 3–5 high-priority destinations with icons and text labels. If a role needs more destinations (e.g. Admin), include a More destination opening a clearly structured menu or screen; do not cram 8–10 tabs into the bottom bar.
- Preserve bottom navigation and the selected tab across top-level tab switches, without pushing duplicate copies of root pages onto the back stack. For full-screen details, authentication, or focused flows, bottom navigation may be hidden deliberately, with a clear Android back path.
- The bottom bar must respect system navigation insets and not cover form buttons or scrollable content.
- A detail page may show an AppBar back arrow; top-level pages generally should not show a back arrow that exits unexpectedly.
- Android system Back must navigate correctly through nested pages, dismiss dialogs/sheets first when appropriate, and never trap the user or exit unexpectedly.
- Respect SafeArea, status bar/navigation bar insets, keyboard insets, and cutouts.
- Use touch-friendly controls and appropriate interaction feedback; do not rely on hover.
- Forms must remain scrollable when the soft keyboard is visible; focused inputs and Submit actions must remain reachable.
- Use dialogs/bottom sheets/full-screen views based on complexity and available space, not one fixed pattern everywhere.
3. Responsive/adaptive sizing
Use these project starting breakpoints in Flutter logical pixels (dp), then adapt components according to their actual constraints:
Available width	Layout intent	Typical navigation	Typical content
< 600	Compact	Web: collapsible left sidebar/drawer; Android: bottom NavigationBar	One column; stacked form fields/cards
600–839	Medium	Web: left sidebar or left rail; Android: bottom NavigationBar	One/two columns, responsive details
840–1199	Expanded	Web: visible left sidebar; Android: bottom NavigationBar	Two/three columns if cards fit
>= 1200	Wide desktop	Web: persistent left sidebar; Android: bottom NavigationBar	Centered max-width main content; multi-column


- Use LayoutBuilder for component/container constraints and MediaQuery.sizeOf(context) for window-level adaptation.
- Choose the navigation family by platform (Web = left sidebar, Android = bottom NavigationBar), then choose the sidebar presentation and content density by available width. Do not use kIsWeb as a substitute for responsive sizing; do not use width alone to swap Web into Android navigation.
- A phone-sized web browser should still fit; a wide Android tablet should not be forced into a narrow phone layout.
- Use Expanded, Flexible, Wrap, ConstrainedBox, FractionallySizedBox, SliverGrid, and scrollable widgets appropriately, rather than arbitrary fixed widths.
- Use maxWidth constraints for wide content: e.g., general main content ~1200–1280dp and forms ~480–640dp, adjustable to existing design requirements.
- For cards, calculate column count based on minimum usable card width, not on screen width alone. Reduce columns when content would be cramped.
- Tables that are too wide for mobile should become item cards/stacked rows. Where a true table is required, allow table-contained horizontal scrolling, not accidental whole-page scrolling.
- Important actions must not fall outside the viewport. Never solve overflow by hiding or clipping content needed by the user.
- Support browser resizing, browser zoom, Android font scaling, orientation changes, and smaller-height viewports.
4. Alignment, spacing, and layout rhythm
- Define shared spacing tokens, preferably an 8dp rhythm with optional 4dp increments: 4, 8, 12, 16, 24, 32, 48.
- Use consistent page margins and card padding at each width class; do not generate random EdgeInsets across screens.
- Page title, descriptions, filters, content sections, and cards should align to shared left/right content guides.
- Repeated card rows should align their images, titles, metadata, and actions consistently; avoid irregular padding and arbitrary card heights.
- Use consistent gaps between labels and fields, between cards, and between sections.
- Prefer left alignment for body content and form labels. Center only deliberate hero/empty-state content.
- Avoid stretching text fields/forms to the full width of a large monitor.
- For groups of buttons, maintain consistent ordering, sizing, baseline, and spacing across screens.
- Avoid using Spacer/`Expanded` in unbounded scroll directions incorrectly; resolve layout constraints instead of adding arbitrary padding.
5. Visual design system
- Define/reuse ThemeData, ColorScheme, TextTheme, consistent component themes, and shared widgets.
- Use a limited palette: primary/action, background/surface, neutral text, success, warning, error. Color meaning must be consistent across all roles and pages.
- Consistent type hierarchy: page heading, section heading, card title, body, label/helper/caption. Do not randomize font sizes or weights per screen.
- Maintain readable contrast; aim for >= 4.5:1 for normal text and >= 3:1 for large text (per WCAG guidance).
- Consistent border radius, border colors, elevation/shadows, icon size, and button height.
- Use one icon family consistently, and always pair unfamiliar icons with a clear label/tooltip.
- Status chips must use the same label/color throughout JobMate, e.g. Pending, Accepted, Completed, Paid, Failed. Never rely on color alone to communicate status.
- Never redesign one screen in a different visual style from other role-based screens without an approved reason.
6. Forms, data, and interactions
- Each input needs a visible label. Use appropriate keyboard types, validation, hints, helper text, and field-level error messages.
- Distinguish required vs optional fields and show validation near the relevant field.
- Preserve input when a request fails; do not silently clear forms or reset state.
- Disable duplicate submits while an async action is processing, show a loading state, and restore interactivity on failure.
- Use confirmation dialogs for destructive/high-impact actions (delete, cancel assignment, payment submission, dispute resolution).
- Buttons and links must have clear, action-oriented labels. Use a visually primary action and subordinate secondary/tertiary actions.
- Feedback must be appropriate: loading, success, warning, error. Avoid silent failures and generic errors when a useful explanation is available.
- Handle long names, large currency values, long job titles, missing avatars/images, and empty optional fields without breaking alignment.
- Use correct date, time, and currency formatting in Malaysian context as appropriate; never hardcode sample values into live UI.
7. States every important page must support
Every data-driven screen should intentionally handle:
1. Initial loading/skeleton or progress.
2. Normal/populated data.
3. Empty state with helpful next action.
4. Error state with retry/recovery.
5. Permission denied/unauthorized state where relevant.
6. Slow network/offline or failed request where relevant.
7. In-progress/success/failed mutation feedback.
No blank white pages, endless spinner without recovery, fake “Success” statuses, or disabled UI without explanation.
8. Accessibility and interaction quality
- Make touch targets at least about 48×48 logical pixels on Android where applicable; use adequate spacing between interactive controls.
- Support keyboard Tab order and visible focus indicators on Web.
- Add meaningful Semantics/tooltip labels for icon-only buttons and important images.
- Preserve usability under larger text scaling; do not disable text scaling to avoid layout bugs.
- Ensure color contrast and do not encode success/error exclusively in red/green.
- Test TalkBack/keyboard access for critical flows such as login, job application, attendance, and payment.
9. JobMate page-specific patterns
- Job Seeker Jobs: desktop may show multi-column cards plus filters; compact screens use stacked job cards and collapsible filters. Every card should consistently expose title, employer, location, pay, type, and Apply/View action where available.
- Job Details: web uses breadcrumb/contextual navigation; Android detail page can use AppBar back. Key Apply action remains visible/reachable without overlapping content.
- Employer Dashboard: use responsive KPI cards; avoid squeezing four narrow dashboard tiles onto a phone. Place high-priority tasks first.
- Applications: mobile lists/cards; wider layouts may use a table. Status chips and actions must remain legible.
- Attendance / Work Verification: time, action, evidence, and confirmation states must be unambiguous. Do not hide important actions under clipped content.
- Chat: adaptive conversation list/detail; ensure the message input remains usable with the Android keyboard.
- Payment Handling (existing approved scope): show assignment, verified work status, amount, payment status, and payment history clearly. Employer Pay Now is available only when business rules allow. Do not label a Sandbox employer payment as actual receipt by the Job Seeker; do not invent wallet, escrow, or automatic payout UI.
- Admin: wider screens can use data tables and filters; mobile needs card or horizontally-scrollable table region with accessible actions.
- Role-based navigation: Job Seeker, Employer, Administrator have consistent but appropriately different menu items. Hiding buttons in UI is not access control: preserve backend authorization/RLS.
10. Navigation and page structure rules
- Create a reusable platform-aware app shell rather than coding independent navigation systems for every page. It must have a Web left sidebar and an Android bottom NavigationBar driven by the same route and role-specific navigation configuration.
- On Web, keep one sidebar at the left of the main content (persistent on desktop; collapsible/off-canvas on compact widths). The header must not introduce a second full navigation menu. Never show bottom navigation on Web.
- On Android, keep bottom navigation for primary root destinations. Use a More tab or secondary screens for extra destinations, and never show a persistent Web-style left sidebar as primary navigation.
- Sidebar width, collapsed rail width, bottom bar height, and content gutters must be consistent across every screen; navigation must not overlap content at any tested width.
- Exactly one current/active menu item should be highlighted where applicable.
- Keep page headings, breadcrumbs, toolbars, and primary actions in consistent positions.
- Do not use automatic leading arrows indiscriminately (AppBar.automaticallyImplyLeading requires careful configuration).
- Distinguish root destinations, nested detail routes, modal routes, and external links.
- All main pages should be reachable from the appropriate navigation structure and via documented routes.
- Preserve browser URL/history on web, and Android back stack semantics on mobile.
- Maintain scroll position or provide predictable restoration when returning to filtered lists where feasible.
11. Code quality and component architecture
- Inspect existing widgets, themes, route configuration, and screen components first; do not create duplicate components or a second design system.
- Split large screen widgets into meaningful shared pieces: AdaptiveScaffold/AppShell, PageContainer, SectionHeader, JobCard, StatusBadge, EmptyState, LoadingState, ErrorState, ResponsiveForm, etc., only when genuinely reused.
- Separate data/business state from presentation layout. Keep role permissions and Supabase rules intact.
- Avoid nested Scaffolds, multiple global scroll views, arbitrary Positioned widgets to fix alignment, and SingleChildScrollView used to hide broken constraints.
- Don't solve visual problems by globally decreasing font size, clipping all text, hiding important elements, or forcing fixed heights.
- Preserve existing routing and theme conventions unless there's a demonstrated bug; make changes incrementally.
- Do not change unrelated features, database schema, payment logic, authentication, or RLS as part of a UI cleanup.
12. Mandatory testing matrix
At minimum test EACH affected page at these available widths (logical pixels):
- 320, 360, 390, 430 (small Android phones / narrow browser)
- 600, 768, 840 (medium/tablet/breakpoint boundaries)
- 1024, 1280, 1440, 1920 (desktop web)
Also test:
- Browser resizing across a breakpoint (e.g. 599 → 600 and 839 → 840).
- Typical portrait and landscape heights, including short-height windows.
- Browser zoom at 100%, 125%, and 150%; Android increased font size/text scaling.
- Android soft keyboard visible during forms/chat.
- Web browser Back/Forward, direct URL visit, refresh on nested route, hover, keyboard Tab/Enter.
- Android hardware/system Back, nested navigation, dialog dismiss, selected bottom tab persistence, and More navigation.
- Web sidebar expanded/collapsed behavior, compact left drawer open/close, and absence of bottom navigation on Web.
- Android presence of bottom navigation on root destinations and absence of persistent Web sidebar.
- Long strings, empty data, loading, network failure, permission failure, and many results.
- Role-specific screens for Job Seeker, Employer, and Administrator.
Run relevant static analysis and widget/integration tests. Use screenshot/golden comparisons for critical layouts if available. Verify visually on web AND an Android target; do not claim checks were completed if not executed.
13. Acceptance criteria (definition of done)
For every changed screen, all of the following must be true:
- [ ] Web: left sidebar visible on wide screens and collapsible/off-canvas from the left on narrow screens; no Android bottom navigation; no unwanted back arrows on Web root pages.
- [ ] Android: bottom NavigationBar is used for primary root destinations, with no persistent Web sidebar; active tab and system Back work correctly.
- [ ] Extra role-specific destinations are accessible via a structured menu/`More` flow rather than overcrowding the Android bottom bar.
- [ ] Browser Back/Forward and Android system Back behave correctly.
- [ ] No overflow, clipping, unintended overlap, or whole-page horizontal scrolling at tested widths.
- [ ] Components align to consistent gutters and spacing; layout adapts without cramped content.
- [ ] Content stays usable with large text and keyboard open.
- [ ] Consistent theme, text hierarchy, buttons, cards, fields, and status colors.
- [ ] Loading, empty, error, permission, and completion states are handled where applicable.
- [ ] All visible buttons and actions are functional or explicitly disabled with reasons.
- [ ] No accidental change to backend rules, Supabase permissions, or payment flows.
- [ ] flutter analyze and applicable tests run; failures are reported honestly.
- [ ] Web/Android screenshots or a precise visual verification report are provided for affected screens.
14. Required workflow for Codex
When asked to improve JobMate UI:
1. Audit: Inspect current app shell, route setup, theme, affected widgets, and all target form factors. Identify which defects are platform navigation, responsive constraints, spacing, or interaction problems.
2. Plan: Give a compact affected-files plan and define expected behavior for Compact / Medium / Wide and for Web left sidebar / Android bottom NavigationBar.
3. Implement narrowly: Fix the affected flow/screens, reuse shared components, avoid unnecessary redesign, and do not alter business logic without explicit need.
4. Validate: Run flutter analyze, relevant tests, inspect at listed widths, and test web history + Android back.
5. Report: Provide files changed, exact issues fixed, tested widths/platforms, evidence/screenshots when possible, remaining issues, and checks that could not be run.
Suggested Codex task prompt
Read JobMate_Flutter_UI_Standards_for_Codex.md and treat every relevant rule as an acceptance criterion. MANDATORY: Flutter Web uses a left sidebar for navigation (persistent on desktop, collapsible/off-canvas left drawer on compact Web). Flutter Android uses a bottom NavigationBar for its primary 3–5 root destinations, with More for additional role-specific pages. Never interchange these patterns. First audit the existing JobMate Flutter Web + Android UI, navigation, theme, and responsive behavior. Fix platform-inappropriate back arrows, overflow, inconsistent alignment, and broken responsive components. Use current project design tokens and preserve Supabase/business behavior. Work screen-by-screen; do not combine unrelated modules or invent features. Test relevant pages at compact, medium, and wide widths, check browser history and Android back navigation, run flutter analyze and applicable tests, then report fixes and anything unverified.

Reference documentation
- Flutter: Adaptive and responsive design — https://docs.flutter.dev/ui/adaptive-responsive
- Flutter: General approach / LayoutBuilder — https://docs.flutter.dev/ui/adaptive-responsive/general
- Flutter: Adaptive best practices — https://docs.flutter.dev/ui/adaptive-responsive/best-practices
- Flutter: Navigation and routing — https://docs.flutter.dev/ui/navigation
- Flutter: User input and accessibility — https://docs.flutter.dev/ui/adaptive-responsive/input
- Flutter: Accessibility guidance — https://docs.flutter.dev/ui/accessibility/ui-design-and-styling
