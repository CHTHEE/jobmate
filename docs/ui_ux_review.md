# Platform UI review — November 4, 2026

This pass applies the supplied [Web + Android standards](flutter_ui_ux_standards.md)
to the existing shell and shared design system. It does not certify every screen
against every device or deployed backend. Older README Phase descriptions are
historical; the current navigation rules are below.

## Audit and implemented changes

| Finding | Correction |
| --- | --- |
| Navigation family depended on width, so narrow Web got native bottom tabs and wide native screens got a Web sidebar | `AppWorkspace` chooses by `kIsWeb` first, then constraints determine the Web sidebar/drawer presentation |
| Real Admin dashboard had a separate sidebar and compact navigation card | Reuses `AppWorkspace`, including native tabs/More, role grouping, theme and gutters |
| Admin permissions and company-review lists were standalone screens | Both now use the same workspace shell; their existing loading/errors, authorization and mutations are preserved |
| Extra native destinations needed a drawer or were missing for Admin | Four native destinations: three primary role tabs plus a grouped, scrollable More sheet |
| Root tab changes could repeatedly push root pages | Shared root navigation uses GoRouter `go`; explicit detail pushes and route-exit guards remain |
| A nested URL could fail to highlight its containing menu section | Longest matching path selects one destination and ignores query strings |
| Native roots inferred a Back arrow; some details repeated it in the content | Root arrows are disabled. Focused details retain one contextual native AppBar Back; Web retains text return links |
| Width conventions differed from the supplied requirements | Compact below 600, medium below 840, expanded from 840, wide threshold 1200; Web sidebar from 840 |
| Short landscape keyboard views could leave too little form space | Native primary tabs hide while the software keyboard is open and return with the same route selection after dismissal |
| Bright primary filled buttons had insufficient normal-text contrast | Shared filled actions now use dark teal/white; focus colors, 48 dp targets and native navigation styling share the existing theme |
| Replacing a Company form root could discard selected input | Company menu/native Back exits compare saved text, selected PDF/logo and uncertain submission state, then request discard confirmation |
| A signed-out Admin fixture could show an endless spinner | Missing-session dashboard state stops loading and provides a sign-in explanation |
| Job Seeker/Employer Home displayed an irrelevant Admin-access card | The card is restricted to the Administrator role; ordinary workspace UI remains role-specific |

## Platform behavior

Web has a 240 dp persistent left sidebar at 840 dp and wider. Below that, its
menu button opens the same grouped navigation in a left drawer. It never shows
native bottom navigation. No Web workspace AppBar back arrow is inferred, even
if a caller supplies native leading controls. Detail return links remain textual.

Native Job Seeker roots have Home, Jobs, Applications, More. Employer roots have
Home, Posts, Applications, More. Admin roots have Home, Users, Payments, More.
More includes the complete grouped role menu; privileged dashboard links are
included only after existing permission checks succeed. Permission/review pages
also include their current section in that menu. This is presentation: existing
server authorization remains authoritative. An active More tab means the route
belongs to an additional destination such as Profile or Settings.

The bottom bar is hidden for focused forms/details and while the keyboard is
open. Explicit native Back callbacks keep their existing guarded route/fallback.
Authentication, password verification, invitation acceptance and document-upload
flows retain their focused layouts and explicit return paths.

Root navigation uses the existing GoRouter. No second router, history API,
StatefulShellRoute or new dependency was introduced. Root switches do not keep
duplicate root pages. They can dispose local page state, so this does not promise
retention of every list's local filters/scroll position. Existing store-backed
drafts and explicit job/payment guards remain. Universal browser refresh/tab-close
protection and a persistent stateful tab architecture remain outside this pass.
Web pages and native workspace roots use `NoTransitionPage` so changing a tab
does not slide the entire navigation bar. Native details/focused forms retain
`MaterialPage` transitions.
`configureAppNavigation` enables the existing GoRouter package's Web
`optionURLReflectsImperativeAPIs` compatibility setting for pushed detail URLs.
Its package documentation cautions that pushed locations are not automatically
deep-linkable; checked-in routes retain their existing direct-route/error
fallbacks, while transient OTP/demo state still cannot be reconstructed from
the URL. This setting is not a replacement for live browser history testing.

## Code walkthrough

### Choose the platform, then the layout

```dart
final sidebar = kIsWeb &&
    ResponsiveLayout.usesSidebar(constraints.maxWidth);
```

`kIsWeb` answers “is this a browser build?” `constraints.maxWidth` answers “how
much room does this container have?” `&&` requires both conditions. A 390 dp
browser gets a drawer; a 1440 dp Android tablet still gets native tabs. Resizing
rebuilds this `LayoutBuilder`, so the presentation adapts without a different page.

### Root navigation and details serve different purposes

```dart
GoRouter.of(context).go(destination); // Switch a root destination.
context.push<void>(detailPath);      // Existing focused detail flow.
```

`go` updates the matched route instead of piling up Home → Jobs → Home → Jobs
as duplicate root pages. `push` places a detail above its origin so native Back
can return to that origin. Both use the existing router; job/payment exit checks
are kept. Browser Back/Forward still needs live acceptance testing.

### Let content determine card height

```dart
ResponsiveGrid(
  minItemWidth: 240,
  children: cards,
)
```

This existing helper chooses a column count from the available content width and
text scale, then uses `Wrap` with naturally growing card heights. A long Admin
tool description becomes taller rather than overflowing a fixed grid ratio.
Wide screens can fit multiple cards; small screens stack them.

### Protect Company form input

```dart
final leave = await confirmDiscardChanges(context, _hasUnsavedInput);
if (mounted && leave) setState(() => _leaving = true);
```

`await` waits for the user's choice. “Stay” keeps the fields/files. “Leave page”
allows the navigation. `mounted` checks that this State still has a widget before
calling `setState`. This does not submit or approve a Company or change its role.

## Files in this UI pass

- Shared: `lib/shared/widgets/app_workspace.dart`, `responsive_layout.dart`,
  `auth_style.dart`; `lib/shared/theme/jobmate_theme.dart`;
  `lib/shared/navigation/workspace_destinations.dart` and `app_page.dart`.
- Workspace screens: Admin dashboard, permissions and company review; Home;
  Company profile/onboarding; shared demo-page wrapper; Job and Application details;
  Sandbox payment page presentation/navigation.
- Tests: platform/width matrix, workspace/menu helpers and existing navigation,
  authentication, job-key, Admin Material and visual fixture expectations.
- Documentation: this review, supplied standards and root README conventions.

The working tree already contained the Payment Handling foundation. Its existing
backend/integration limitations are documented separately in `payment_handling.md`.
No migrations, RLS, gateway, authentication setup, teammate data models, commits
or pushes are part of this UI pass. No Supabase Dashboard steps are required.

## Verification and remaining acceptance checks

The new shared-shell matrix exercises all three roles at 320, 360, 390, 430,
599, 600, 768, 839, 840, 1024, 1280, 1440 and 1920 logical pixels with 1.0x and
1.5x text. It checks native navigation versus actual Web-build expectations,
menu access, selection, root route replacement, direct-detail fallback and mutation
locking. Another case uses 568×320, keyboard inset 180 and system inset 24 to
check form-action reachability. These are Flutter widget tests, not physical
Android or live-browser visual acceptance.

Existing screen fixtures additionally exercise portrait/landscape, text scaling
up to 1.6x, long content, empty/error states and guarded job/payment flows.
Static analysis, full-suite results and build results are reported in the task
reply. Logs and fixture PNGs stay under ignored `build/`.

Results for this pass:

- Full suite: 497 passed, one existing failure in the obsolete counter smoke
  test (`test/widget_test.dart` expects a counter in the routed JobMate app).
- Latest focused regressions: 121 platform/registration/Module 2/payment-preview
  cases and 42 Admin/workspace/responsive-navigation cases passed.
- `flutter analyze`: no errors; three existing diagnostics remain (two deprecated
  registration Radio properties and the unused password-verification `_user`).
  Dead Home menu/local declarations were removed while updating that screen.
- Normal Web production build succeeded with local CanvasKit resources.
- Final isolated preview debug APK build succeeded. An earlier build of the
  preview launched on the installed Android 17 emulator and exposed its Dart VM
  service, without a live-account sign-in or Billplz/Supabase call.
- Rendered native widget fixtures for Employer Home at 390 dp and Job Postings
  at 1440 dp were visually inspected. Their bottom navigation/content fit the
  captured viewport; these images are fixture renders, not browser/device captures.
- `git diff --check` passed. No remote setup, database changes or commits.

Headless Chrome tests stalled while loading and were stopped. Computer-use visual
inspection also stopped because the tool could not reliably determine the browser
URL; no further UI automation was attempted. Therefore actual Web Back/Forward,
refresh/deep-link hosting, 125%/150% browser zoom, hover/Tab/Enter and screenshots
from Chrome remain unverified. Native preview build/launch is a compile/runtime
check only; system Back, real software keyboard interaction, TalkBack and visual
device review are not established by that launch.

Manual acceptance still needs all affected screens with real authorized accounts,
slow/offline failures, actual file pickers, all roles, private data permissions
and browser/device interactions from the supplied standards. This pass does not
claim the full project definition of done is met.
