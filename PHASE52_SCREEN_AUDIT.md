# Phase 5.2 screen audit

All 71 Figma IDs are mapped below. This is an implementation/visual audit, not a
claim of pixel-perfect reproduction or live-backend acceptance. The uncommitted
Phase 5.1 working tree was preserved. Source: exact handoff + original inventory,
existing routes and actual widget/data implementations.

## Review legend

- **Present/adapted**: an existing Flutter screen or modal/state provides the flow;
  source prototype local views may remain real Flutter routes for direct URLs/Back.
- All rows use the shared bundled fonts, teal/slate controls, bordered cards and
  responsive constraints. Existing guards/loading/error/empty states are retained.
- `test/phase52_visual_test.dart` renders 25 representative screens at 390/1440px,
  including representative states from all ten modules except authenticated real
  account/dashboard data (covered by existing injected tests/manual acceptance later).
- Existing module tests also cover 320/768/1440px and confirmations/status behavior.
  This does not prove every conditional row/state has been manually inspected.
- Every data/action note is explicit. Demo actions mutate session stores only;
  unavailable operations explain why. No route alone is treated as completed UI.

| ID / Figma screen | Flutter implementation | Role navigation / entry | Actual data, action and fidelity assessment |
| --- | --- | --- | --- |
| AUTH-01 Login | LoginPage | Login / signed-out entry | Present/adapted. Real authentication; shared typography refined |
| AUTH-02 Registration | SignUpPage | Login -> Sign up | Present/adapted. Real registration; existing rules retained |
| AUTH-03 Forgot Password | VerifyPasswordPage | Login -> Forgot Password | Present/adapted. Real recovery request |
| AUTH-04 Reset Link Sent | VerifyPasswordPage._codeSent | Recovery success state | Present/adapted. Real request response; conditional email wording |
| ACC-01 Account Settings Home | AccountSettingsPage | Role Settings | Present/adapted. Real account read; preferences explicitly local |
| ACC-02 Personal Information | ProfilePage / ExtendedProfilePage | Settings -> Profile / explicit demo preview | Present/adapted. Real limited profile; extended fields demo |
| ACC-03 Change Password | VerifyPasswordPage / ChangePasswordPage | Profile -> Change password | Present/adapted. Real OTP/security workflow |
| ACC-04 Notification Settings | AccountSettingsPage preferences | Settings preferences | Present/adapted. Session demo; no notification service |
| ACC-05 Sign Out Confirmation | AccountSettingsPage.logout | Settings -> Sign out | Present/adapted. Real Supabase sign-out confirmation |
| ACC-06 Delete Account Confirmation | AccountSettingsPage deletion information | Settings -> deletion information | Present/adapted. Unavailable; information only, no deletion |
| JS-01 Home Dashboard | DashboardContent | Home | Present/adapted. Real account completion; separate demo activity |
| JS-02 Browse Jobs | BrowseJobsPage | Jobs -> Browse | Present/adapted. Demo catalogue only; polished identity cards/filters |
| JS-03 Job Details | JobDetailsPage | Browse -> View Details | Present/adapted. Demo; compact Apply/Save, actual field semantics |
| JS-04 Apply to Job Modal | ApplyDemoForm | Job Details -> Apply | Present/adapted. Demo submission; note guards/retry/duplicates |
| JS-05 AI Recommendations | RecommendationsPage | For You | Present/adapted. Deterministic demo; disclosure and match ring |
| JS-06 AI Recommendation Apply Modal | ApplyDemoForm | For You -> Apply | Present/adapted. Same coherent demo submission flow |
| JS-07 Nearby Jobs Map/List | NearbyJobsPage | Nearby | Present/adapted. Demo map/list; 768px, 360px illustrative map |
| JS-08 Nearby Job Location Detail | NearbyDetailPage | Nearby -> detail | Present/adapted. Demo address/distance; mini map |
| JS-09 My Applications | ApplicationsPage | My Applications | Present/adapted. Demo counts/status/search; polished summaries |
| JS-10 Application Detail Modal | ApplicationDetailsPage | Application -> View | Present/adapted. Demo route retained; 448px detail/timeline |
| JS-11 Withdraw Confirmation | TransitionForm | Application -> Withdraw | Present/adapted. Demo guarded destructive confirmation |
| JS-12 Attendance Today | AttendancePage | Attendance | Present/adapted. Demo assignment/check-in/out; local timestamps |
| JS-13 Check-In/Out Confirmation | demoConfirm | Today -> Check in/out | Present/adapted. Demo confirmation, no GPS claim |
| JS-14 Work Evidence Form | EvidencePage | Attendance -> Evidence | Present/adapted. Local picker/preview/required note; no uploads |
| JS-15 Attendance History | AttendanceListPage | Attendance -> History | Present/adapted. Demo filters/cards/details |
| JS-16 Pending Evaluations | EvaluationsPage | Evaluations | Present/adapted. Demo pending/history with visibility warning |
| JS-17 Employer Evaluation Form | EvaluationFormPage | Pending -> Start Evaluation | Present/adapted. Six exact criteria; colored 1-5 choices |
| JS-18 Evaluation Submitted | EvaluationFormPage existing/success branch | After demo submit | Present/adapted. Local success; no server assertion |
| JS-19 Evaluation History | EvaluationsPage History tab | Evaluations -> History | Present/adapted. Given/received local state |
| JS-20 Evaluation Detail Modal | EvaluationDetailPage | History -> Details | Present/adapted. Demo criteria/feedback; visibility maintained |
| JS-21 Report Evaluation Modal | EvaluationReportForm | Received -> Report | Present/adapted. Demo linked case; no real moderation |
| JS-22 Messages List/Conversation | ChatPage | Messages | Present/adapted. Local conversation/send/attachments; refined split surface |
| JS-23 Profile | ProfilePage | Personal profile | Present/adapted. Real profile/photo; existing limited fields |
| JS-24 Edit Profile | ProfilePage inline editor / ExtendedProfilePage | Profile edit / labeled preview | Present/adapted. Real name/phone editor; extended fields demo |
| JS-25 My Reputation | ReputationPage | Reputation | Present/adapted. Demo score ring/breakdown; insufficient-data switch |
| JS-26 Job Seeker Payments | PaymentHistoryPage / PaymentDetailPage | Payments | Present/adapted. External-payment records demo; no transfer |
| EMP-01 Employer Dashboard | DashboardContent | Dashboard | Present/adapted. Existing improved baseline preserved; real counts + separate demos |
| EMP-02 Job Posting Dashboard | JobPostingsPage | My Job Postings | Present/adapted. Real employer-scoped data; Phase 5.1 layout retained |
| EMP-03 Create Job Posting | JobFormPage | Post Job | Present/adapted. Real five-section form; validation/AI preserved |
| EMP-04 Edit Job Posting | JobFormPage | Posting -> Edit | Present/adapted. Same real form/lifecycle/dirty guard |
| EMP-05 Job Preview Modal | JobPreview | Form / posting -> Preview | Present/adapted. Real actual form/saved values; 512px dialog |
| EMP-06 Job Location Picker | JobLocationDemoPage | Location Picker | Present/adapted. Demo marker/placeholder coordinates; real posting values untouched |
| EMP-07 Applicant Management | ApplicationsPage(employer) | Applications | Present/adapted. Demo pipeline; 768px; real posting entry separated |
| EMP-08 Applicant Profile Modal | ApplicationDetailsPage(employer) | View Applicant | Present/adapted. Demo profile/actions; 512px route adaptation |
| EMP-09 Applicant Rejection Confirmation | TransitionForm | Applicant -> Reject | Present/adapted. Demo private-note presentation + confirmation |
| EMP-10 Workers | WorkersPage | Workers | Present/adapted. Added; derived from attendance demo store |
| EMP-11 Worker Reputation Modal | WorkersPage reputation modal | Workers -> View Reputation | Present/adapted. Added; worker context and truthful insufficient-data state, no score invented |
| EMP-12 Attendance Review | AttendanceListPage(employer) | Attendance Review | Present/adapted. Demo review counts/filters; no persistent verification |
| EMP-13 Worker Attendance Detail | AttendanceDetailPage(employer) | Review -> Details | Present/adapted. Demo evidence/review/actions |
| EMP-14 Flag Work Record | FlagWorkForm | Details -> Flag | Present/adapted. Required demo reason + confirmation |
| EMP-15 Record Payment | PaymentRecordPage | Payments -> Record | Present/adapted. Demo completed assignment/external payment form |
| EMP-16 Payment Recorded Success | PaymentRecordPage success branch | After Record | Present/adapted. Local success only, no bank action |
| EMP-17 Employer Payment History | PaymentHistoryPage(employer) | Payment History | Present/adapted. Demo status/search/cards |
| EMP-18 Employer Messages | ChatPage(employer) | Messages | Present/adapted. Fictional employer conversations; local receipts |
| EMP-19 Company Profile | CreateCompanyPage | Company Profile | Present/adapted. Real company/logo/verification; baseline retained |
| EMP-20 Edit Company Profile | CreateCompanyPage / ExtendedProfilePage(employer) | Company permitted form / labeled demo editor | Present/adapted. Existing registration/resubmission rules retained; extended company fields demo, no newly authorized verified-company editing |
| EMP-21 Employer Evaluations | EvaluationsPage(employer) | Evaluations | Present/adapted. Six exact worker criteria; local history/submission |
| EMP-22 Company Reputation | ReputationPage(employer) | Company Reputation | Present/adapted. Illustrative score, not a verified company result |
| ADM-01 Platform Dashboard | AdminDashboardPage | Admin Home | Present/adapted. Real permissions/overview + explicitly separate demo summaries |
| ADM-02 User Management | AdminUsersPage / AdminPreviewPage Accounts | Real User Directory / UI Sandbox | Present/adapted. Real directory now uses shared shell; moderation sandbox separate |
| ADM-03 User Profile Modal | AdminPreview account details | Sandbox -> Account Details | Present/adapted. Fictional account/profile detail; no added protected-user reads |
| ADM-04 User Action Confirmation | AdminPreview account action modal | Sandbox -> Restrict/Suspend/Reactivate | Present/adapted. Demo confirmations only |
| ADM-05 Job Posting Management | AdminPreviewPage Jobs | Job Moderation | Present/adapted. Fictional jobs; search/filter/detail/removal |
| ADM-06 Remove Posting Confirmation | AdminPreview removal modal | Job -> Remove | Present/adapted. Demo destructive confirmation |
| ADM-07 Dispute Management | AdminPreviewPage Disputes | Disputes | Present/adapted. Local linked cases, statuses and search |
| ADM-08 Dispute Detail | DisputeDetailPage | Dispute -> Review | Present/adapted. 1024px; local evidence/timeline/remarks; protected messages unavailable |
| ADM-09 Request Information Modal | DisputeActionForm pendingInfo | Case -> Request More Information | Present/adapted. Demo party/request + state change |
| ADM-10 Resolve Dispute Modal | DisputeActionForm resolved | Case -> Resolve | Present/adapted. Demo outcome/explanation |
| ADM-11 Reject Dispute Modal | DisputeActionForm rejected | Case -> Reject | Present/adapted. Demo rejection/explanation |
| ADM-12 Platform Reports | AdminPreviewPage Reports | Reports | Present/adapted. 768px; derived demo summaries/progress, printable report; no fictional real analytics |
| RPT-01 Attendance & Work Completion Report | AttendanceDetailPage(report) / attendanceReportHtml | Attendance detail -> View Demo Report | Present/adapted. 794px Flutter report; styled A4 HTML, demo only |

## Remaining visual/acceptance differences

The existing improved employer dashboard/posting/forms/profiles are preserved.
Some prototype-only profile/trust/analytics content cannot truthfully be filled
from real records; extended previews remain labeled. Module 2 detail routes are
width-adapted pages rather than replacing router history with only modals. Admin
dispute detail now uses a responsive case/action-and-remarks rail, stacking on
narrow screens; the rail is not sticky; protected conversation access stays unavailable.
Admin analytics uses derived demo case/account summaries instead of invented
registration time series/top-employer rankings. Material icons and accessible
Android controls remain. The account footer shows role/account context without
fabricating a signed-in name. Exact Figma screenshots are unavailable; no
pixel-by-pixel match is asserted. Full live role/permission/browser-history,
keyboard, picker and Android hardware acceptance remains outstanding.
