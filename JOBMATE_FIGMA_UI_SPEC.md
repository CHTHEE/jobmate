# JobMate Figma Make UI Specification

> **Document purpose:** implementation handoff for the existing JobMate FYP prototype.
>
> **Evidence basis:** direct inspection of the React, TypeScript, and Tailwind source in this Figma Make project.
>
> **Important limitation:** the inspected prototype is a front-end simulation. It contains hard-coded sample data, local React state, and timed success transitions. No Supabase client, database access, storage integration, map provider, AI API, notification service, or real authentication implementation is present in this repository.

## Documentation conventions

| Label | Meaning |
|---|---|
| **Designed** | A complete visual state or interactive prototype path exists. |
| **Partially designed** | Some UI exists, but actions, validation, or edge states are missing. |
| **Placeholder** | The element is visible but has no meaningful action or uses simulated data. |
| **NOT DESIGNED** | No corresponding screen or state exists in the inspected prototype. |
| **NEEDS CONFIRMATION** | The prototype is ambiguous or conflicts with the stated Flutter/Supabase project context. |
| **Proposed entity** | An implementation-oriented data model inferred from visible UI. It is not a verified Supabase table. |

---

# 1. Project Overview

## 1.1 Product represented by the prototype

JobMate is represented as an AI-assisted recruitment and workforce platform for conventional jobs, part-time work, temporary work, freelance projects, gigs, and short-term assignments.

The prototype includes three role experiences:

| Role | Represented permissions |
|---|---|
| **Job Seeker** | Browse and filter jobs; view AI recommendations; inspect nearby jobs; apply; track applications; record attendance; upload work evidence; evaluate employers; chat with employers; view reputation; confirm or dispute externally recorded payments; edit profile and account settings. |
| **Employer** | View dashboard metrics; create/edit/preview/draft/publish job posts; manage applicants; move applicants through a pipeline; view workers; verify or flag attendance/evidence; record external payments; evaluate workers; chat; edit company profile; view company reputation and account settings. |
| **Administrator** | View platform metrics; search/filter users; restrict, suspend, or reactivate accounts; review/remove job posts; review disputes and related records; access dispute messages with an audit warning; request information; resolve or reject disputes; view reports and export controls. |

The prototype does **not** enforce these permissions through a backend. Role views are selected through local demo navigation.

## 1.2 Overall information architecture

```text
Demo Preview Switcher
├── Authentication
├── Job Seeker Application
│   ├── Home
│   ├── Jobs
│   │   ├── Browse Jobs
│   │   ├── For You
│   │   └── Nearby
│   ├── Applications
│   ├── Work
│   │   ├── Attendance
│   │   └── Evaluations
│   ├── Messages
│   └── Profile
│       ├── Edit Profile
│       ├── Reputation
│       ├── Payments
│       └── Settings
├── Employer Application
│   ├── Dashboard
│   ├── Job Posts
│   │   ├── Posting Dashboard
│   │   └── Job Location
│   ├── Applications
│   ├── Workers
│   │   ├── Workers
│   │   ├── Attendance
│   │   └── Payment Handling
│   ├── Messages
│   └── Company Profile
│       ├── Profile
│       ├── Evaluations
│       ├── Reputation
│       ├── Edit Company Profile
│       └── Settings
├── Administrator Application
│   ├── Dashboard
│   ├── Users
│   ├── Job Posts
│   ├── Disputes
│   └── Reports
└── Attendance & Work Completion Report
```

## 1.3 Main application shell

### Desktop and tablet shell

- Sidebar appears from the Tailwind `md` breakpoint, equivalent to **768 px**.
- Sidebar width: **240 px**.
- Fixed sidebar begins below the 36 px Figma Make preview bar.
- Sticky top bar height: **56 px**.
- Main content receives `240 px` left padding.
- Page padding: `24 px` horizontal and `32 px` vertical at `md`; `16 px` horizontal and `24 px` vertical below `md`.
- Job Seeker and Employer shells display six sidebar items.
- Administrator displays five sidebar items.

### Mobile shell

- Below `768 px`, the sidebar becomes a left drawer.
- The drawer width is **256 px** with a dark translucent backdrop.
- Job Seeker and Employer receive a fixed five-item bottom navigation using only the first five navigation entries.
- Their sixth destination, Profile or Company Profile, is therefore not shown in the mobile bottom navigation. It remains reachable only through other prototype controls if present. **NEEDS CONFIRMATION for Flutter navigation.**
- Administrator has no bottom navigation. Admin navigation uses the drawer.
- Mobile top bar shows the JobMate mark and notification/avatar controls.

### Prototype-only preview bar

The fixed 36 px dark “Preview” switcher in `src/App.tsx` is a Figma Make demonstration aid, not a product navigation element.

## 1.4 Design system

### Typography

| Usage | Font |
|---|---|
| Display headings | DM Serif Display |
| Body, labels, controls | Outfit |
| IDs, scores, monetary values, times, coordinates | DM Mono |

Imported weights:

- Outfit: 300, 400, 500, 600, 700
- DM Serif Display: regular and italic
- DM Mono: 400, 500

### Brand palette

| Token | HEX |
|---|---|
| Brand 50 | `#F0FDFA` |
| Brand 100 | `#CCFBF1` |
| Brand 200 | `#99F6E4` |
| Brand 300 | `#5EEAD4` |
| Brand 400 | `#2DD4BF` |
| Brand 500 | `#14B8A6` |
| Brand 600 | `#0D9488` |
| Brand 700 | `#0F766E` |
| Brand 800 | `#115E59` |
| Brand 900 | `#134E4A` |

Primary surface and text colors:

- Page background: Slate 50, `#F8FAFC`
- Main text: Slate 900, `#0F172A`
- Secondary text: Slate 500, `#64748B`
- Borders: Slate 200/300, `#E2E8F0` / `#CBD5E1`
- Success: green
- Warning/pending: amber or orange
- Error/destructive/dispute: red
- Information: blue

### Spacing and shape

- Base spacing follows Tailwind’s 4 px scale.
- Common card padding: 16–20 px.
- Common vertical section gap: 16–24 px.
- Cards and inputs usually use 12 px radii.
- Modals use 16 px radii on desktop and rounded top corners as mobile sheets.
- Pills and status badges are fully rounded.
- Standard shadow is subtle; modals use stronger `shadow-xl`/`shadow-2xl`.

### Buttons

Reusable variants:

- Primary: teal background, white text.
- Secondary: light teal background, dark teal text.
- Ghost: neutral text with light hover surface.
- Outline: neutral border.
- Danger: red background.

Buttons provide hover and disabled opacity states. Some primary form actions show simulated success text; many secondary actions are visual-only.

### Forms

- Labels: 12–14 px, medium weight.
- Inputs: white surface, 1 px neutral border, 8–12 px radius.
- Focus: teal 2 px ring.
- Error: red border and 12 px error copy.
- Required fields use a red asterisk.
- Password fields provide visibility toggles.
- Upload controls use dashed drop zones and hidden file inputs.

### Cards, dialogs, and lists

- Primary content is organized in white cards with neutral borders.
- Status information uses semantic tinted banners.
- Mobile dialogs become bottom sheets; desktop dialogs are centered.
- Modal backdrops use Slate 900 at approximately 50–60% opacity.
- Lists commonly include empty states but rarely include real error or retry states.

### Icons and visual assets

- Icons are from `lucide-react`.
- The JobMate logo is a custom SVG briefcase mark.
- No photographic assets are used.
- Maps are custom SVG illustrations labeled “© WorkMap”; no map provider is integrated.
- Avatars are initials-based colored circles.

## 1.5 Responsive breakpoints implemented

| Breakpoint | Approximate width | Behavior |
|---|---:|---|
| Base | `<640 px` | Single-column forms, mobile sheets, compact controls. |
| `sm` | `640 px` | Some two-column fields, centered modals, horizontal filter rows. |
| `md` | `768 px` | Permanent sidebar, desktop chat split view, multi-column statistics. |
| `lg` | `1024 px` | Authentication split panel and wider admin dispute layout. |

No `xl`-specific product layout was identified.

---

# 2. Complete Screen Inventory

## 2.1 Authentication and account screens

| ID | Screen | Module | Role | Platform | Entry and destination | Main UI and behavior | Status |
|---|---|---|---|---|---|---|---|
| AUTH-01 | Login | 1 | All | Both | Default auth state; success opens selected role shell | Email, password, visibility toggle, forgot link, Sign In; empty validation; simulated loading. Demo-only quick logins for three roles. | Designed, mock behavior |
| AUTH-02 | Registration | 1 | Job Seeker/Employer | Both | Login → Register; success opens selected role | Embedded account-type cards; name/contact name, email, phone, conditional company name, password, confirmation, strength meter, terms checkbox. | Designed, mock behavior |
| AUTH-03 | Forgot Password | 1 | All | Both | Login → Forgot password; success → AUTH-04 | Email field and Send Reset Link; disabled while empty; simulated loading. | Designed, mock behavior |
| AUTH-04 | Reset Link Sent | 1 | All | Both | AUTH-03 success; Back to login | Success icon, resend link, back link. Resend has no handler. | Partially designed |
| ACC-01 | Account Settings Home | 1 | Job Seeker/Employer | Both | Profile/Company Profile → Settings | Account summary; Personal Information, Change Password, Notification Settings; 2FA and visibility placeholders; terms/privacy; sign out/delete dialogs. | Designed with placeholders |
| ACC-02 | Personal Information | 1 | Job Seeker/Employer | Both | ACC-01 → Personal Information | Editable name, email, phone; email verification warning; Save Changes success state. | Designed, simulated |
| ACC-03 | Change Password | 1 | Job Seeker/Employer | Both | ACC-01 → Change Password | Current/new/confirm password, visibility toggles, strength meter, requirements, validation, success state. | Designed, simulated |
| ACC-04 | Notification Settings | 1 | Job Seeker/Employer | Both | ACC-01 → Notification Settings | Toggle groups for activity, email, and SMS notifications. | Designed, local state only |
| ACC-05 | Sign Out Confirmation | 1 | Job Seeker/Employer | Both | ACC-01 → Sign Out | Cancel and Sign Out. Parent logout callbacks are no-ops. | Designed, not wired |
| ACC-06 | Delete Account Confirmation | 1 | Job Seeker/Employer | Both | ACC-01 → Delete Account | Permanent deletion warning; Cancel/Delete. Delete only closes modal. | Designed, not wired |

**NOT DESIGNED:** email-verification screen, OTP screen, reset-password form, social login, admin self-registration, 2FA setup, profile-visibility configuration.

## 2.2 Job Seeker screens

| ID | Screen | Module | Entry | Main sections, data, and actions | Status |
|---|---|---|---|---|---|
| JS-01 | Home Dashboard | Cross-module | Home nav | Greeting, 75% profile completion checklist, application stats, AI match banner, recommended jobs, recent applications, trust score and skill bars. Navigation actions open Jobs or Applications. | Designed |
| JS-02 | Browse Jobs | 2 | Jobs → Browse Jobs | Search, collapsible filters, category/type/location chips, sorting, job cards, save toggles, empty state. Salary-range state exists but has no UI. | Designed with minor unused state |
| JS-03 | Job Details | 2/7 | Select job from JS-02 | Job metadata, description, requirements, skills, company verification, employer trust score, Apply actions. Share button is placeholder. | Designed |
| JS-04 | Apply to Job Modal | 2 | JS-03 → Apply Now | Optional application note; profile-sharing notice; Submit Application; simulated success. | Designed, mock |
| JS-05 | AI Recommendations | 3 | Jobs → For You | AI transparency notice, filters, sort, match rings, matched/gap skills, employer reputation, “why suggested,” save and apply. View Job is placeholder. | Designed |
| JS-06 | AI Recommendation Apply Modal | 3/2 | JS-05 → Apply Now | Match summary, optional note, disclaimer, simulated success. | Designed, mock |
| JS-07 | Nearby Jobs Map/List | 10 | Jobs → Nearby | Location text field, current-location placeholder, radius selector, type filters, map/list toggle, pins, radius circle, cards, empty states. | Designed with simulated map |
| JS-08 | Nearby Job Location Detail | 10/2 | JS-07 → View Job | Salary, distance, rating, mini map, address, navigation buttons, Apply button. Navigation and Apply are placeholders. | Partially designed |
| JS-09 | My Applications | 2 | Applications nav | Summary counts, search, All/Active/Completed tabs, status cards, offer buttons, detail and withdraw actions. | Designed |
| JS-10 | Application Detail Modal | 2 | JS-09 → View Details | Job summary, application timeline, status, ID, offer actions, withdraw action. Accept/Decline are placeholders. | Partially designed |
| JS-11 | Withdraw Confirmation | 2 | JS-09/10 → Withdraw | Irreversible warning; Keep Application or Withdraw. Local status becomes Withdrawn. | Designed, local state |
| JS-12 | Attendance Today | 4 | Work → Attendance → Today | Active assignment, live clock, simulated location verification, check-in/out states, elapsed time, status cards. | Designed, simulated |
| JS-13 | Check-In/Out Confirmation | 4 | JS-12 action | Time, location, consent notice, Cancel/Confirm. | Designed |
| JS-14 | Work Evidence Form | 4 | Work → Attendance → Evidence | Multi-file upload, preview/removal, required work description, disclaimer, loading and success. | Designed, local files only |
| JS-15 | Attendance History | 4 | Work → Attendance → History | All/Completed/Issues filters, attendance cards, evidence indicator, empty state. Details button is placeholder. | Partially designed |
| JS-16 | Pending Evaluations | 6 | Work → Evaluations | Bidirectional notice, pending/history tabs, pending evaluation cards, due dates. | Designed |
| JS-17 | Employer Evaluation Form | 6 | JS-16 → Start Evaluation | Six employer criteria, 1–5 ratings, progress, optional 300-character feedback, validation. | Designed |
| JS-18 | Evaluation Submitted | 6 | JS-17 success | Rating summary, visibility explanation, View Evaluation History. | Designed |
| JS-19 | Evaluation History | 6 | Evaluations → History | Given/received filters, average tiles, cards, details, report controls. | Designed |
| JS-20 | Evaluation Detail Modal | 6 | JS-19 → View Details | Metadata, criteria breakdown, feedback, report action for received evaluations. | Designed |
| JS-21 | Report Evaluation Modal | 6/8 | JS-19/20 → Report | Required preset reason, optional details, warning, success state. | Designed, mock |
| JS-22 | Messages List/Conversation | 5 | Messages nav | Search, conversation list, job context, online state, grouped messages, attachments, quick replies, send, sent/delivered/read simulation. | Designed, local state |
| JS-23 | Profile | 1/7/9 | Profile nav | Identity, verification, availability, skills, categories, resume, reputation, achievements; Edit/Reputation/Payments/Settings. | Designed |
| JS-24 | Edit Profile | 1 | JS-23 → Edit Profile | Photo placeholder, name, 250-character bio, location, availability, skills, up to five categories, resume upload/removal, save success. | Designed, local state |
| JS-25 | My Reputation | 7 | JS-23 → My Reputation | Trust score, score factors, soft skills, work history, attendance summary, evaluations, disclaimer. | Designed, read-only mock |
| JS-26 | Job Seeker Payments | 9 | JS-23 → Payment Handling | Pending/History tabs, confirmation, issue reporting, details, summaries and filters. | Designed, local state |

## 2.3 Employer screens

| ID | Screen | Module | Entry | Main sections, data, and actions | Status |
|---|---|---|---|---|---|
| EMP-01 | Employer Dashboard | Cross-module | Dashboard nav | Metrics, quick actions, active posts, recent applicants, worker performance. | Designed |
| EMP-02 | Job Posting Dashboard | 2 | Job Posts → Job Posts | Status summaries, search, filters, cards, applicant metrics, edit, publish, close. Draft Publish button is no-op; close confirmation does not persist status. | Partially designed |
| EMP-03 | Create Job Posting | 2/3/10 | EMP-02 → Post Job | Basic info, compensation, schedule/location, description, AI generation, requirements, skills, Save Draft, Preview, Publish. | Designed, simulated |
| EMP-04 | Edit Job Posting | 2/3 | EMP-02 → Edit | Same form as create; only some fields prepopulate from mock posting. | Designed, mock |
| EMP-05 | Job Preview Modal | 2 | EMP-03/04 → Preview | Public-facing job summary, description, requirements, skills, nonfunctional Apply Now. | Designed |
| EMP-06 | Job Location Picker | 10 | Job Posts → Job Location | Required address, local autocomplete, draggable marker, coordinate display, confirm/update state. | Designed, simulated geocoding |
| EMP-07 | Applicant Management | 2 | Job posting → Applicants or Applications nav | Job filter, pipeline counts, search, sort, applicant cards, stage actions, reject flow. | Designed |
| EMP-08 | Applicant Profile Modal | 2/7 | EMP-07 → View Profile | Trust score, rating history, skills, cover note, pipeline action. | Designed |
| EMP-09 | Applicant Rejection Confirmation | 2 | EMP-07 → Reject | Optional internal note, Cancel/Confirm Rejection. | Designed, local state |
| EMP-10 | Workers | 4/7 | Workers → Workers | Active/completed/rated stats, worker list, status, trust score, completed gigs, reputation modal. | Designed |
| EMP-11 | Worker Reputation Modal | 7 | EMP-10 → View Reputation | Job Seeker reputation in responsive modal. | Designed |
| EMP-12 | Attendance Review | 4 | Workers → Attendance | Stats, pending-review banner, search/job/status filters, worker attendance cards, verify/flag actions. | Designed |
| EMP-13 | Worker Attendance Detail | 4 | EMP-12 → View | Attendance details, trust, evidence, worker note, verify/flag actions, absent controls. Evidence View and absent message/actions are placeholders. | Partially designed |
| EMP-14 | Flag Work Record | 4/8 | EMP-12/13 → Flag | Required preset or custom reason; Submit Flag. | Designed, local state |
| EMP-15 | Record Payment | 9 | Workers → Payment Handling → Record | Completed job, auto-filled worker, required positive amount/date, method, optional reference/proof/note. | Designed |
| EMP-16 | Payment Recorded Success | 9 | EMP-15 success | Recorded payment summary; View History or Record Another. | Designed, mock |
| EMP-17 | Employer Payment History | 9 | Payment Handling → History | Summary tiles, search/status filter, payment list and details. | Designed |
| EMP-18 | Employer Messages | 5 | Messages nav | Same shared chat module with worker conversations. | Designed, local state |
| EMP-19 | Company Profile | 1/7 | Company Profile → Profile | Company identity, verification, stats, reputation summary, edit/settings. | Designed |
| EMP-20 | Edit Company Profile | 1 | EMP-19 → Edit Profile | Logo, company name/description, industry, size, website, location, contact name/email, verification status, save success. | Designed, local state |
| EMP-21 | Employer Evaluations | 6 | Company Profile → Evaluations | Pending/history evaluation flow using worker criteria. | Designed |
| EMP-22 | Company Reputation | 7 | Company Profile → Reputation | Trust factors, employer ratings, completed jobs and received evaluations. | Designed, read-only mock |

## 2.4 Administrator and report screens

| ID | Screen | Module | Entry | Main sections, data, and actions | Status |
|---|---|---|---|---|---|
| ADM-01 | Platform Dashboard | 8 | Dashboard nav | Platform metrics, user breakdown, system health, activity feed, open disputes. | Designed, mock |
| ADM-02 | User Management | 8/1 | Users nav | Search, role/status filters, CSV placeholder, user rows, profile and account actions, empty state. | Designed |
| ADM-03 | User Profile Modal | 8 | ADM-02 → View Profile | Identity, role/status, trust/completion/dispute metrics, restrict/suspend/reactivate. | Designed |
| ADM-04 | User Action Confirmation | 8 | ADM-02/03 account action | Role-specific impact copy; confirm/cancel; local status mutation. | Designed, local state |
| ADM-05 | Job Posting Management | 8/2 | Job Posts nav | Status tabs, search, cards, reports, approve placeholder, remove confirmation, empty state. | Partially designed |
| ADM-06 | Remove Posting Confirmation | 8/2 | ADM-05 → Remove Posting | Irreversible warning, Remove/Cancel; local status changes to Removed. | Designed, local state |
| ADM-07 | Dispute Management | 8 | Disputes nav | Status filters, parties, category, priority, related job, Review Case. | Designed |
| ADM-08 | Dispute Detail | 8 | ADM-07 → Review Case | Parties, description, evidence, attendance/payment/evaluation accordions, protected message thread, case summary, actions and remarks. | Designed |
| ADM-09 | Request Information Modal | 8 | ADM-08 → Request Additional Information | Party selector, required details, success state. Copy says status becomes Pending Info, but state is not updated. | Partially designed |
| ADM-10 | Resolve Dispute Modal | 8 | ADM-08 → Resolve | Outcome radio options, required explanation, success state, local status → Resolved. | Designed, local state |
| ADM-11 | Reject Dispute Modal | 8 | ADM-08 → Reject | Rejection reason, optional notes, success state, local status → Rejected. | Designed, local state |
| ADM-12 | Platform Reports | 8 | Reports nav | Statistics, registration chart, top employers, CSV and PDF controls. Export buttons are placeholders. | Designed, not wired |
| RPT-01 | Attendance & Work Completion Report | 4 | Prototype preview switcher | A4 report with job, schedule, attendance, locations, work verification, assignment, summary, disclaimer and print/PDF action. | Fully designed static document |

---

# 3. All 10 Modules

## Module 1 — Account and Identity Management

**Responsible developer:** UNKNOWN.

### Purpose and represented user stories

- A user can select Job Seeker or Employer during registration.
- A user can sign in, request a reset link, and edit personal information.
- Job Seekers can maintain profile, availability, skills, categories, and resume.
- Employers can maintain company and contact information.
- Employers can display SSM verification status.
- Users can change passwords and notification preferences.
- Administrators can view account status and restrict, suspend, or reactivate accounts.

### Relevant screens

AUTH-01–04, ACC-01–06, JS-23–24, EMP-19–20, ADM-02–04.

### Main journey

1. Open Login.
2. Register and select account type.
3. Enter identity/contact credentials and accept terms.
4. Prototype immediately opens the selected role shell.
5. User opens Profile or Company Profile.
6. User edits profile or opens Settings.
7. Admin may change account standing.

### Business rules and transitions represented

- Registration account types: Job Seeker and Employer only.
- Password minimum: 8 characters; strength also checks uppercase, number, and special character.
- Job Seeker category selection is limited to five.
- Employer verification is displayed as verified for 12 months, but no submission/review flow exists.
- Restricted accounts can still log in according to admin confirmation copy.
- Suspended accounts cannot log in according to admin confirmation copy.

### Validation

- Registration name required.
- Registration email must contain `@`.
- Optional phone must match a permissive phone pattern.
- Password and confirmation must match.
- Terms required.
- Profile/company edit forms have character limits but no required-field enforcement.
- Change Password validates current password presence, minimum length, and confirmation match.

### Proposed entities, not verified tables

`profiles`, `employer_profiles`, `company_verifications`, `user_roles`, `account_status_history`, `notification_preferences`, `resume_files`, `profile_skills`, `profile_job_categories`.

### Dependencies

- Supabase Auth: required in Flutter project, not present here.
- Supabase database: likely for profiles and roles; schema unverified.
- Supabase Storage: proposed for avatars, logos, resumes, and verification documents.
- Email service: verification and password recovery.

### Missing and unresolved

- Email verification UI: **NOT DESIGNED**.
- Reset-password form: **NOT DESIGNED**.
- Verification application/upload/rejection/expiry renewal: **NOT DESIGNED**.
- Terms and privacy destinations: **NOT DESIGNED**.
- 2FA and profile-visibility settings: placeholders.
- Logout and delete account are not wired.
- Employer registration Company Name input is visually present but non-editable in source.

### Recommendations, not existing design

- Define role creation transaction and profile creation rollback behavior.
- Define account deletion retention/anonymization policy.
- Add verification pending, rejected, expired, and resubmission states.
- Ensure role and account status are enforced server-side, not only hidden in UI.

## Module 2 — Job Posting and Application Management

**Responsible developer:** UNKNOWN.

### Purpose and represented user stories

- Employers create, edit, preview, draft, publish, and close job posts.
- Job Seekers search/filter jobs, view details, apply, save jobs, and track applications.
- Employers filter applicants and advance or reject them.
- Job Seekers can withdraw early-stage applications and respond to offers visually.

### Screens

JS-02–04, JS-09–11, EMP-02–05, EMP-07–09, ADM-05–06.

### Employer posting journey

1. Job Posts → Post Job.
2. Enter title, category, type, compensation, positions, schedule, deadline, and location.
3. Write description/requirements or use AI generation.
4. Add required skills.
5. Save Draft, Preview, or Publish.
6. Return to posting dashboard.
7. Edit, view applicants, publish draft, or close posting.

### Application journey

1. Job Seeker searches or filters jobs.
2. Opens Job Details.
3. Opens Apply modal.
4. Optionally enters a note.
5. Submits; UI shows success and marks the job applied.
6. My Applications shows status and timeline.
7. Early stages may be withdrawn.

### Applicant state transitions represented

```text
Applied → Reviewing → Interview → Offered
     └──────────────────────────→ Rejected
```

Job Seeker statuses additionally include Withdrawn. Offer accept/decline controls are visible but do not mutate state.

### Validation

- Create form marks title, category, job type, and description required but does not enforce them.
- Positions input has minimum 1.
- Skill additions reject blank and duplicate local entries.
- Application note is optional.
- Rejection note is optional and described as not visible to applicant.

### Proposed entities

`job_posts`, `job_post_schedules`, `job_post_skills`, `applications`, `application_status_history`, `application_notes`, `saved_jobs`, `job_offers`, `job_assignments`.

### Dependencies

- Supabase database and realtime subscriptions: proposed.
- Notifications for application and offer transitions.
- Storage for resumes.
- AI dependency overlaps Module 3.
- Map/location overlaps Module 10.

### Missing and unresolved

- Required-field validation is visually stated but not implemented.
- Draft Publish is a no-op.
- Close does not persist status.
- Offer scheduling details, interview date entry, accept/decline confirmation, and assignment creation are **NOT DESIGNED**.
- Admin View and Approve actions are placeholders.
- Saved jobs have no dedicated screen.
- Salary-range filter state exists without controls.

### Recommendations

- Agree status transition permissions and audit history before backend work.
- Make publishing transactional and prevent publishing incomplete posts.
- Define whether applicant rejection reasons are stored and disclosed.
- Define duplicate-application and closed-deadline behavior.

## Module 3 — AI-Assisted Job Recommendation

**Responsible developer:** UNKNOWN.

### Purpose and user stories

- Job Seekers see match percentages, matched skills, skill gaps, and explanation text.
- Job Seekers filter recommendations by location, category, type, salary, and score.
- Employers generate editable job descriptions and requirements.

### Screens

JS-01 AI banner, JS-05–06, EMP-03–04 AI Generate control.

### Rules represented

- Match labels: Excellent ≥90, Strong ≥75, Good ≥60, otherwise Fair.
- Match factors are described as skills, work history, availability, and location.
- Recommendations explicitly do not guarantee placement.
- Employer AI output remains editable.

### Proposed entities

`recommendation_runs`, `job_match_scores`, `match_explanations`, `skill_gaps`, `ai_generation_requests`.

### Dependencies

- AI model or Edge Function: required for real implementation, absent here.
- Profile skills/history, job skills, availability, and location.

### Missing and unresolved

- Model/provider, prompts, scoring formula, consent, retention, cost limits, and fallback behavior: **NEEDS CONFIRMATION**.
- No loading/error state for recommendation retrieval.
- Employer generation has only simulated loading and fixed text.
- “View Job” from recommendation is not wired.

### Recommendations

- Keep match explanations auditable and avoid protected-attribute inputs.
- Store model/version and input snapshot for reproducibility.
- Provide deterministic fallback ranking when AI is unavailable.

## Module 4 — Attendance and Work Verification

**Responsible developer:** UNKNOWN.

### Purpose and user stories

- Job Seekers check in/out with time and location.
- Job Seekers submit work evidence.
- Employers review attendance/evidence and verify or flag work.
- A printable attendance report summarizes system records.

### Screens

JS-12–15, EMP-12–14, RPT-01.

### State transitions represented

```text
Idle → Checking In → Checked In → Checking Out → Checked Out
Evidence: Empty → Submitting → Submitted
Employer decision: Pending → Verified or Flagged
```

### Rules represented

- Check-in is disabled until location is “verified.”
- Late threshold in prototype: after 08:15 for an 08:00 shift.
- Work evidence requires at least one file and a non-empty description.
- Employer cannot verify without evidence.
- Flag reason is required.
- Verification is presented as the employer’s decision.

### Proposed entities

`assignments`, `shift_schedules`, `attendance_records`, `attendance_locations`, `work_evidence`, `work_verifications`, `attendance_flags`, `attendance_reports`.

### Dependencies

- Device geolocation and permission handling.
- Supabase database.
- Supabase Storage for evidence.
- Optional server-side report/PDF generation.
- Notifications.

### Missing and unresolved

- Real geolocation, accuracy, spoofing protection, geofence radius, offline behavior, and permission-denied state: **NOT DESIGNED**.
- Evidence file-size/type validation is copy only.
- Evidence View and attendance history Details are placeholders.
- Employer absent controls are placeholders.
- Report is static and not linked from attendance records.

### Recommendations

- Record server timestamps alongside device timestamps.
- Store coordinates, accuracy, permission state, and source.
- Define correction/dispute workflows for location failure or missed check-in.

## Module 5 — Chat and Communication

**Responsible developer:** UNKNOWN.

### Purpose and user stories

- Role users communicate within job-specific conversations.
- Users send text and simulated image/document attachments.
- Users see online, unread, and sent/delivered/read states.
- Admin may inspect messages only in dispute context with an audit warning.

### Screens

JS-22, EMP-18, ADM-08 protected message thread.

### Rules represented

- Conversations are associated with a job.
- Enter sends; Shift+Enter creates a newline.
- Blank messages cannot be sent.
- New local messages simulate sent → delivered → read.
- Admin message access is warned as logged and only for dispute resolution.

### Proposed entities

`conversations`, `conversation_participants`, `messages`, `message_attachments`, `message_receipts`, `message_access_audit`.

### Dependencies

- Supabase Realtime or another realtime service.
- Storage for attachments.
- Push/email notifications.
- Presence service.

### Missing and unresolved

- New conversation creation, blocking, moderation, deletion, pagination, upload progress, retry, offline queue, and attachment viewer: **NOT DESIGNED**.
- Phone/more menu imports do not create visible implemented workflows.
- Quick-reply text is shared across roles and may be contextually inappropriate.

### Recommendations

- Enforce conversation membership with RLS.
- Audit admin access server-side.
- Add delivery failure and retry states.

## Module 6 — Bidirectional Soft Skill Evaluation

**Responsible developer:** UNKNOWN.

### Purpose and user stories

- Both sides evaluate each other after completed work.
- Six criteria use 1–5 ratings.
- Users can review history and report received evaluations.

### Job Seeker criteria for evaluating employers

Communication, Job Description Accuracy, Professionalism, Payment Reliability, Work Environment, Respect Towards Workers.

### Employer criteria for evaluating workers

Communication, Responsibility, Teamwork, Professionalism, Adaptability, Punctuality.

### Screens

JS-16–21 and EMP-21.

### Rules represented

- All six criteria are required.
- Written feedback is optional and limited to 300 characters.
- Feedback becomes visible after both sides submit.
- Pending evaluations include an availability deadline.
- Only received evaluations can be reported.
- Report reason is required; details are optional.

### Proposed entities

`evaluation_requests`, `evaluations`, `evaluation_ratings`, `evaluation_visibility`, `evaluation_reports`.

### Dependencies

- Completed assignment from Module 2/4.
- Trust aggregation in Module 7.
- Admin dispute/review in Module 8.
- Notifications.

### Missing and unresolved

- Evaluation editing, deadline expiry, anonymity, moderation outcome, duplicate protection, and score recalculation: **NOT DESIGNED**.
- Report success claims a three-working-day review without supporting admin SLA design.

### Recommendations

- Prevent evaluation submission until assignment completion is server-verified.
- Reveal feedback atomically after both submit or after a defined deadline.

## Module 7 — Trust Score and Reputation

**Responsible developer:** UNKNOWN.

### Purpose and user stories

- Job Seekers and Employers see trust scores and component factors.
- Opposite roles inspect reputation before hiring or applying.
- Profiles show ratings, history, attendance/payment reliability, and disputes.

### Screens

JS-25, EMP-11, EMP-22, reputation snippets in JS-03, JS-05, EMP-08, JS-01, JS-23, EMP-19.

### Rules represented

- Trust score is 0–100.
- Criteria ratings are 1–5.
- Job Seeker factors include completion, attendance, soft skills, standing, and disputes.
- Employer factors include payment, job accuracy, satisfaction, response, and disputes.
- Disclaimer states past performance does not guarantee future outcomes.

### Proposed entities

`trust_scores`, `trust_score_snapshots`, `trust_score_factors`, `reputation_metrics`, `achievements`.

### Dependencies

Modules 1, 2, 4, 6, 8, and 9.

### Missing and unresolved

- Formula, weighting, update cadence, appeals, score history, and handling of removed evaluations: **NEEDS CONFIRMATION**.
- All data is hard-coded.
- Reputation modal accepts a name but renders the same sample profile for every user.

### Recommendations

- Compute scores server-side from auditable facts.
- Version the scoring formula.
- Show factor explanations without exposing exploitable thresholds.

## Module 8 — Admin Management and Dispute Resolution

**Responsible developer:** UNKNOWN.

### Purpose and user stories

- Admin monitors platform status and activity.
- Admin manages user and job standing.
- Admin reviews disputes with evidence and cross-module records.
- Admin requests information, records remarks, resolves, or rejects.

### Screens

ADM-01–12; dispute creation is also depicted from payment/evaluation/attendance actions.

### Dispute states

```text
Open → Investigating → Pending Info → Resolved
                                └──→ Rejected
```

The list contains these states, but Request Information does not actually mutate the detail status.

### Permissions represented

- Admin can access dispute-related private messages after acknowledging an audit warning.
- Admin remarks are internal.
- Admin may restrict, suspend, reactivate, approve, or remove.

### Proposed entities

`admin_actions`, `disputes`, `dispute_parties`, `dispute_evidence`, `dispute_messages`, `dispute_related_records`, `dispute_resolutions`, `admin_remarks`, `audit_logs`, `job_reports`.

### Dependencies

All other modules, particularly attendance, payment, evaluation, chat, accounts, and jobs.

### Missing and unresolved

- Job Seeker/Employer dispute list and general dispute-creation screen are **NOT DESIGNED**.
- Payment report creates a case only in local UI.
- Admin approval buttons, exports, and evidence viewing are placeholders.
- No admin authentication/authorization implementation exists.
- No immutable audit log exists.
- No assignment of case owner, SLA, escalation, appeal, or notification history.

### Recommendations

- Use strict admin claims and server-side authorization.
- Log every private-message access and administrative state change.
- Make dispute resolution transactional with linked-module corrections.

## Module 9 — Payment Record Management

**Responsible developer:** UNKNOWN.

### Purpose and user stories

- Employer records a payment made outside JobMate.
- Job Seeker confirms receipt or reports an issue.
- Both sides review payment history and proof.

### Screens

JS-26, EMP-15–17, payment-related dispute records in ADM-08.

### Rules represented

- JobMate explicitly does not process bank transactions.
- Related job, positive amount, and payment date are required.
- Payment proof is recommended, not required.
- Reference and note are optional.
- Job Seeker confirmation changes Pending to Confirmed.
- Report Issue creates a depicted dispute case.

### Payment states

Pending, Confirmed, Disputed, Overdue. Overdue is defined but not represented in sample flows.

### Proposed entities

`payment_records`, `payment_proofs`, `payment_confirmations`, `payment_disputes`.

### Dependencies

- Completed assignments.
- Supabase Storage for proof.
- Notifications.
- Admin disputes.

### Missing and unresolved

- No transaction processing or payment gateway.
- No overdue transition, reminders, corrections, deletion, or duplicate detection.
- “View” proof actions are placeholders.
- Report Issue does not mutate payment state.

### Recommendations

- Label every record as employer-declared until confirmed.
- Use immutable amount/date changes or revision history.
- Restrict proof access to involved parties and admins with cause.

## Module 10 — Location-Aware Job Discovery

**Responsible developer:** UNKNOWN.

### Purpose and user stories

- Job Seekers browse nearby jobs by radius and job type.
- Employers set an address and marker position.
- Job details show workplace location and distance.

### Screens

JS-07–08, EMP-06, location elements in JS-03 and Module 4.

### Rules represented

- Radius choices: 2, 5, 10, 25, 50 km.
- Jobs are filtered by mock distance.
- Employer address is required before confirmation.
- Marker supports mouse and touch dragging.
- Coordinates shown are marker percentages mislabeled as latitude/longitude.

### Proposed entities

`job_locations`, `profile_locations`, `location_search_preferences`, `geocoding_cache`.

### Dependencies

- Maps/geocoding/directions provider: absent and **NEEDS CONFIRMATION**.
- Device location permission.
- Job posts and attendance.

### Missing and unresolved

- Address validation, real coordinates, privacy controls, map errors, permission denial, and remote-job behavior: **NOT DESIGNED**.
- Current location, zoom, navigation, and Apply buttons are placeholders.
- “WorkMap” is illustrative SVG only.

### Recommendations

- Store proper latitude/longitude and geocoding provider IDs.
- Calculate distance server-side or with a consistent geospatial function.
- Request precise location only when needed.

---

# 4. Important JobMate Flows

## 4.1 Registration, login, and role navigation

### Existing prototype

1. Login is the initial view.
2. Register opens an embedded Job Seeker/Employer selector.
3. Successful registration immediately opens the selected role shell.
4. Login infers demo role from whether the email contains `employer` or `admin`.
5. Demo quick-login bypasses credentials.
6. There is no session restoration or real route guard.

### Flutter/Supabase implication

Preserve existing Flutter Supabase Auth and replace the prototype-only role inference with verified role data. Exact email verification screens are **NOT DESIGNED**.

## 4.2 Employer and company profile

1. Employer opens Company Profile.
2. Profile displays verification, company details, stats, and trust.
3. Edit Profile allows logo, company information, and contact updates.
4. Verification is read-only and says documents require support contact.
5. Settings provides account-level controls.

## 4.3 Company verification and employer permissions

Existing design shows only successful verification:

- “Company Verified”
- “SSM Verified”
- Verified date and 12-month validity
- Verified badge on job posts

Submission, pending review, rejection, expiration, and permission blocking are **NOT DESIGNED**. Whether unverified employers may publish is **NEEDS CONFIRMATION**.

## 4.4 Job creation, editing, preview, draft, publish, and close

1. Employer selects Post Job.
2. Completes five grouped form sections.
3. May call AI Generate for description and requirements.
4. May Preview.
5. May Save Draft or Publish.
6. Posting dashboard shows status and metrics.
7. Active posting may be closed after inline confirmation.

Only success banners and return navigation are simulated. No persistent post is created.

## 4.5 AI-assisted description formatting

- Trigger: `AI Generate`.
- Loading copy: `Generating…`.
- Result: fixed type-specific description plus fixed requirements.
- Success note asks the employer to review and edit.
- Regeneration is available.
- No prompt input, error, cancellation, moderation, or quota state exists.

## 4.6 Job discovery and application

1. Job Seeker opens Browse, For You, or Nearby.
2. Uses search/filter/sort controls.
3. Opens a detail or apply modal.
4. Submits optional note.
5. UI marks the job applied.
6. Applications screen tracks status and allows withdrawal in early stages.

## 4.7 Applicant management

1. Employer opens Applications or a posting’s Applicants action.
2. Filters by job, status, name, and trust/date.
3. Opens profile or advances pipeline.
4. Can reject with optional internal note.
5. State changes exist only in local component state.

## 4.8 Attendance to payment flow

1. Assignment appears as active.
2. Job Seeker waits for simulated location verification.
3. Checks in and later checks out.
4. Uploads work evidence and description.
5. Employer verifies or flags.
6. Employer records external payment.
7. Job Seeker confirms receipt or reports an issue.
8. A dispute may be depicted for admin review.

This end-to-end flow is visually strong but not connected between modules in data.

## 4.9 Evaluation and reputation flow

1. Completed job creates a pending evaluation.
2. User rates all six criteria and may add feedback.
3. Submission moves the item to history.
4. Received evaluation may be reported.
5. Scores are described as contributing to trust, but trust data does not recalculate.

---

# 5. Web vs Android Requirements

## 5.1 Actual implemented prototype behavior

| Concern | Web/desktop prototype | Mobile-width prototype |
|---|---|---|
| Primary navigation | Permanent sidebar at ≥768 px | Drawer; Job Seeker/Employer also have five-item bottom nav |
| Contextual back | Internal subviews frequently show back arrows even inside desktop dashboard content | Same controls become useful for stacked mobile flows |
| Dialogs | Centered modal | Bottom sheet for many large dialogs |
| Chat | Conversation list and chat side by side | One pane at a time with chat back arrow |
| Forms | Some `sm` two-column grids | Single-column |
| Admin dispute | Three-column layout at ≥1024 px | Single-column |
| Tables/report | Static A4 report; not optimized as an app screen | No dedicated mobile report adaptation |

## 5.2 Required Flutter navigation interpretation

### Web

- Dashboard destinations should not add a redundant top-left AppBar back arrow.
- Back controls should appear only for nested detail/edit states.
- Browser history should be supported, but in-app sidebar/drawer navigation must remain complete.
- Nested screens should update the URL or a Router state where practical.

### Android

- Nested detail, edit, and modal routes should expose contextual Back.
- Android system Back must close, in order: open dialog/sheet, nested detail, drawer, then leave the app.
- Bottom navigation should preserve per-tab state where appropriate.

## 5.3 Recommended improvement versus existing behavior

The source uses local conditional rendering rather than routes, so browser/system Back is not represented. Implementing route-aware nested navigation is a **recommendation**, not an existing prototype fact.

The mobile bottom nav omits Profile/Company Profile. Flutter must either provide another explicit entry or use a More/Profile item. This needs product-owner confirmation.

---

# 6. UI-to-Backend Contract

The following table describes intended operations inferred from visible UI. It does not confirm existing Supabase implementation.

| Trigger | Input and validation | Intended operation | Required data/response | Success/error UI | Permission/integration | Prototype |
|---|---|---|---|---|---|---|
| Login → Sign In | Email/password; non-empty in prototype | Auth sign-in | Session, user, role, account status | Loading text; generic empty error | Supabase Auth; reject suspended users | Simulated |
| Register → Create Account | Role, identity, email, phone, password, terms | Create auth user and role profile | User ID, role, verification state | Loading then role shell | Supabase Auth + DB | Simulated |
| Forgot → Send Reset Link | Non-empty email | Password recovery request | Neutral success response | Check Email state | Supabase Auth/email | Simulated |
| Save Personal Information | Name/email/phone | Update profile; email change may require verification | Updated profile and verification state | Changes Saved/error needed | Auth + DB | Local only |
| Update Password | Current/new/confirm | Update credential | Success or auth error | Password Updated/error banner | Supabase Auth | Local only |
| Save Profile/Company | Profile fields/files | Update profile and upload files | Updated record and asset URLs | Saved state/error needed | DB + Storage | Local only |
| Publish Job | Required posting fields | Create/update published job | Job ID/status/timestamps | Success banner/error needed | Employer; verification rule TBD | Simulated |
| Save Draft | Partial posting | Create/update draft | Draft ID | Draft saved/error needed | Employer | Simulated |
| AI Generate | Job type and current context | Generate description/requirements | Text, model metadata | Generated state/error absent | Edge Function/AI | Fixed timer |
| Submit Application | Job ID, optional note, profile/resume reference | Create application | Application ID/status | Success; duplicate/error needed | Job Seeker | Local only |
| Withdraw Application | Application ID | Update to Withdrawn | Updated status/history | Card update | Applicant; only early states | Local only |
| Applicant stage action | Application ID/new stage | Update pipeline | Updated status/history | Immediate card update | Posting owner | Local only |
| Check In/Out | Assignment, timestamp, coordinates | Create/update attendance | Authoritative timestamps and location metadata | Recording/success/error needed | Assigned worker; geolocation | Simulated |
| Submit Evidence | Files + required description | Upload and create evidence | File URLs, evidence record | Spinner and success | Worker; Storage | Local object URLs |
| Verify Work | Attendance/evidence | Create verification/update assignment | Verification record | Verified status | Employer owner | Local only |
| Flag Work | Required reason | Create flag/dispute signal | Flag ID/status | Flagged state | Employer/admin notification | Local only |
| Send Message | Text or attachment | Create message/upload file | Message ID, receipt state | Sent/delivered/read; failure absent | Conversation member; Realtime/Storage | Local timers |
| Submit Evaluation | Six ratings + optional feedback | Create evaluation | Evaluation ID/visibility | Confirmation | Assignment participant | Local only |
| Report Evaluation | Required reason, optional details | Create evaluation report | Report/dispute ID | Success message | Recipient/admin | Local only |
| Record Payment | Job, positive amount, date; optional proof/reference/note | Create external payment record | Payment ID/pending status | Payment Recorded | Employer; DB/Storage/notification | Local only |
| Confirm Receipt | Payment ID | Update payment to Confirmed | Confirmation timestamp | Success then history | Assigned worker | Local only |
| Report Payment | Reason/details | Create dispute and mark payment disputed | Dispute ID | `D-0046` success | Worker/admin notification | Static success |
| Confirm Job Location | Required address + marker | Geocode and save location | Address, lat/lng, provider ID | Confirmed banner | Maps/geocoding | Random marker |
| Restrict/Suspend/Reactivate | User ID/action | Update account status and audit | New status | List update | Admin only | Local only |
| Remove Job | Job ID | Update moderation status | Removed status/audit | Local card status | Admin only | Local only |
| Request Dispute Info | Party + required details | Create request/update Pending Info | Request ID/status | Request Sent | Admin + notifications | Simulated; status not updated |
| Resolve/Reject Dispute | Outcome/reason and explanation | Finalize dispute | Resolution and audit | Success/status update | Admin only | Local only |
| Save Admin Remarks | Internal text | Update case notes | Saved timestamp/editor | Saved label | Admin only | Local only |
| Export/Print | Filters/report ID | Generate CSV/PDF or print | Download | Browser print only for RPT-01 | Server/report generator optional | Admin exports placeholder |

---

# 7. Gap Analysis

## 7.1 Fully represented visual flows

- Authentication login/register/forgot/reset-link confirmation.
- Job browsing, detail, and application submission.
- Application tracking and withdrawal.
- Job posting form, preview, draft/publish success.
- Applicant pipeline movement and rejection.
- Attendance check-in/out visual state machine.
- Evidence upload and employer verification/flagging.
- Bidirectional evaluation form, history, and reporting.
- Role-based chat visual behavior.
- Reputation profiles.
- External payment recording and confirmation.
- Admin dispute detail and final resolution.
- Static A4 attendance report and browser print.

## 7.2 Missing or incomplete flows

- Real authentication, verification, session, logout, and deletion.
- Employer verification submission and approval.
- Offer accept/decline and assignment creation.
- Interview scheduling form.
- Saved-jobs destination.
- General dispute creation/list for non-admin users.
- Real maps, geolocation, directions, and geocoding.
- Notification center.
- Admin export and job approval/view.
- Report generation from a selected attendance record.
- Error recovery for almost every async workflow.

## 7.3 Contradictory or inconsistent behavior

- Project context says Supabase, but inspected repository has no Supabase dependency or client.
- Registration Company Name is non-editable in the source.
- Request Information says dispute becomes Pending Info but does not update state.
- Closing a posting confirms visually but does not change its status.
- Draft Publish is a no-op.
- Recommendation “Good” threshold code and filter copy use slightly different wording.
- Location coordinates display percentages as geographic degrees.
- Mobile bottom nav omits Profile/Company Profile.
- Static report dates and identities differ from dashboard sample data.
- Admin system health claims services such as Payment Gateway and Document Verification that are not integrated.

## 7.4 Missing loading, empty, error, and confirmation states

Loading states exist for login, registration, password reset request, AI generation, attendance recording, evidence upload, and some admin actions.

Empty states exist in job search, applications, evaluations, attendance filters, payments, applicant filters, and maps.

Major missing states:

- Network/offline/retry.
- Supabase authorization/session expiry.
- Storage upload progress/failure.
- AI generation failure.
- Map/geolocation permission denial.
- Chat send failure.
- Export failure.
- Concurrent update/conflict.
- Deleted/closed content.

## 7.5 Potential security and permission issues

- Role navigation is local and not authorization.
- Admin actions have no verified admin claim.
- Message access audit is copy only.
- Sensitive evidence and payment proof access rules are undefined.
- Account restriction/suspension is not server-enforced.
- Location data retention and precision policy are undefined.
- Trust score calculation is client-visible mock data.

## 7.6 Recommendations

- Agree an RLS matrix before implementing mutations.
- Create immutable audit records for admin, payments, attendance, and disputes.
- Define file buckets and signed URL policies.
- Define route guards and status enforcement.
- Add common async loading/error/retry components.
- Separate declared records from verified records in labels and schema.

---

# 8. Implementation Handoff

## 8.1 Suggested Flutter organization

```text
lib/
├── app/
│   ├── router/
│   ├── theme/
│   └── shell/
├── core/
│   ├── auth/
│   ├── supabase/
│   ├── storage/
│   ├── permissions/
│   └── widgets/
├── features/
│   ├── account/
│   ├── jobs/
│   ├── recommendations/
│   ├── attendance/
│   ├── chat/
│   ├── evaluations/
│   ├── reputation/
│   ├── admin/
│   ├── payments/
│   └── location/
└── reports/
    └── attendance/
```

Each feature should separate:

- `data/`: repositories, Supabase DTOs, storage.
- `domain/`: entities, permissions, state transitions.
- `presentation/`: screens, controllers/providers, widgets.

## 8.2 Reusable UI components

- `JobMateAppShell`
- `ResponsiveSidebar`
- `MobileBottomNavigation`
- `JobMateWordmark`
- `SectionHeader`
- `PrimaryButton`, `SecondaryButton`, `DangerButton`
- `JobMateTextField`, `PasswordField`, `SearchField`
- `StatusBadge`
- `StatCard`
- `AvatarInitials`
- `TrustScoreRing`
- `EmptyState`, `ErrorState`, `LoadingSkeleton`
- `ConfirmDialog`
- `ResponsiveModalSheet`
- `FilterPills`
- `FileUploadField`
- `ScoreBar`, `RatingPicker`
- `JobCard`, `ApplicantCard`, `PaymentCard`

## 8.3 Suggested implementation order

1. Theme, typography, responsive shell, and reusable primitives.
2. Supabase Auth, role lookup, route guards, account status enforcement.
3. Profile/company data and storage contracts.
4. Job posts and applications with agreed state transitions.
5. Assignments and attendance.
6. Evidence storage and employer verification.
7. Payments and disputes.
8. Evaluations and trust calculation.
9. Chat/realtime and notifications.
10. AI and maps integrations.
11. Admin auditing, exports, and reports.

## 8.4 Suitable for initial mock-data UI implementation

- Dashboards and statistics.
- Reputation read-only screens.
- Job cards/search/filter UI.
- Reports and static charts.
- Account settings layout.
- Evaluation rating controls.
- Responsive navigation shell.

## 8.5 Requires backend contract first

- Role assignment and account status.
- Company verification.
- Job/application/offer state transitions.
- Attendance location integrity.
- Evidence access.
- Payment confirmation/disputes.
- Trust score calculation.
- Admin permissions and audit logs.
- Chat membership and retention.
- AI inputs/output retention.
- Geolocation privacy and provider choice.

## 8.6 External assets and services

- Google Fonts or bundled Flutter font assets for Outfit, DM Serif Display, and DM Mono.
- JobMate custom briefcase SVG.
- Lucide-equivalent Flutter icon package or mapped Material icons.
- Supabase Auth, Database, Realtime, and Storage.
- Email provider through Supabase Auth.
- Push notifications: provider **NEEDS CONFIRMATION**.
- AI provider/model: **NEEDS CONFIRMATION**.
- Maps/geocoding/directions provider: **NEEDS CONFIRMATION**.
- PDF generation approach: **NEEDS CONFIRMATION**.

## 8.7 Questions for project owners

- Which developer owns each of the ten modules?
- What are the actual Supabase tables, enums, and RLS policies?
- Where is role membership stored and how is admin status granted?
- Must employers be verified before publishing?
- What creates an assignment after an offer is accepted?
- What are the authoritative application and job state transitions?
- What attendance geofence, accuracy, and anti-spoofing rules apply?
- What files, limits, retention, and visibility rules apply to uploads?
- How is the trust score calculated and appealed?
- Are payments record-only, or will real payment processing be added?
- Where can Job Seekers and Employers view and create disputes?
- Which map and AI providers are approved?
- Which screens should be routes on Web and Android?
- How should the omitted mobile Profile/Company Profile destination be exposed?

---

# Inspection Coverage

## Screens and flows actually inspected

- Authentication: login, registration, forgot password, reset-link confirmation.
- Shared desktop/mobile shell, sidebar, drawer, bottom navigation, logo, and global styles.
- Job Seeker: dashboard, jobs, recommendations, nearby map, applications, attendance, evidence, evaluations, chat, profile, reputation, payments, settings.
- Employer: dashboard, postings, create/edit/preview, applicant management, workers, attendance review, payments, chat, company profile, evaluations, reputation, settings.
- Administrator: dashboard, users, job moderation, disputes, dispute detail/actions, reports.
- Static Attendance & Work Completion Report and print control.

## Could not be verified

- Any Flutter implementation.
- Supabase Auth, schema, RLS, Storage, Realtime, Edge Functions, or database behavior.
- Developer ownership of modules.
- Real AI, map, geolocation, payment, email, notification, or document-verification integrations.
- Real permissions, audit logs, exports, file access, or PDF generation.
- Screens explicitly marked **NOT DESIGNED** or placeholder actions listed above.

## Source files inspected

- `src/App.tsx`
- `src/index.css`
- `src/components/Layout.tsx`
- `src/components/UI.tsx`
- `src/views/AuthView.tsx`
- `src/views/AccountSettings.tsx`
- `src/views/JobSeekerView.tsx`
- `src/views/EmployerView.tsx`
- `src/views/AdminView.tsx`
- `src/views/jobseeker/JobsView.tsx`
- `src/views/jobseeker/AIRecommendationsView.tsx`
- `src/views/jobseeker/MyApplicationsView.tsx`
- `src/views/jobseeker/AttendanceView.tsx`
- `src/views/employer/JobPostings.tsx`
- `src/views/employer/AttendanceReview.tsx`
- `src/views/shared/ChatModule.tsx`
- `src/views/shared/EvaluationModule.tsx`
- `src/views/shared/ReputationProfile.tsx`
- `src/views/shared/PaymentModule.tsx`
- `src/views/shared/LocationModule.tsx`
- `src/views/reports/AttendanceReport.tsx`
