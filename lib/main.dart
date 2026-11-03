import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'features/admin/admin_permissions_page.dart';
import 'features/admin/admin_users_page.dart';
import 'features/admin/company_review_page.dart';
import 'features/admin/invite_admin_page.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/sign_up_page.dart';
import 'features/auth/terms_privacy_page.dart';
import 'features/auth/verify_email_page.dart';
import 'features/company/create_company_page.dart';
import 'features/jobs/job_form_route.dart';
import 'features/applications/module2_repository.dart';
import 'features/applications/module2_widgets.dart';
import 'features/applications/browse_jobs_page.dart';
import 'features/applications/job_details_page.dart';
import 'features/applications/applications_page.dart';
import 'features/demo_work/phase3_store.dart';
import 'features/recommendations/recommendations_page.dart';
import 'features/attendance/attendance_pages.dart';
import 'features/attendance/workers_page.dart';
import 'features/chat/chat_page.dart';
import 'features/location/location_pages.dart';
import 'features/phase4/phase4_store.dart';
import 'features/phase4/evaluation_pages.dart';
import 'features/phase4/reputation_page.dart';
import 'features/phase4/payment_pages.dart';
import 'features/phase4/admin_preview_pages.dart';
import 'features/phase4/account_settings_page.dart';
import 'features/jobs/job_postings_page.dart';
import 'features/profile/change_password_page.dart';
import 'features/profile/document_submission_page.dart';
import 'features/profile/profile_page.dart';
import 'features/profile/verify_password_page.dart';
import 'features/notifications/notifications_page.dart';
import 'shared/navigation/app_routes.dart';
import 'shared/navigation/app_page.dart';
import 'shared/theme/jobmate_theme.dart';
import 'shared/widgets/jobmate_scroll_behavior.dart';
import 'shared/widgets/app_startup.dart';

late final _AuthRouterRefresh _authRouterRefresh;
late final GoRouter _appRouter;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AppStartup(initialize: _initializeApp, builder: (_) => const MyApp()));
}

Future<void> _initializeApp() async {
  try {
    await dotenv.load(fileName: '.env');
  } on FileNotFoundError {
    throw const AppStartupException(
      'The local .env configuration file could not be loaded. Restore it and restart the app.',
    );
  } on EmptyEnvFileError {
    throw const AppStartupException(
      'The local .env configuration file is empty. Restore the configuration and retry.',
    );
  }

  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseKey = dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ?? '';

  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    throw const AppStartupException(
      'Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY in .env. Check the configuration and retry.',
    );
  }

  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);

  _authRouterRefresh = _AuthRouterRefresh();
  _appRouter = _createRouter();
}

GoRouter _createRouter() {
  return GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: _authRouterRefresh,
    redirect: (context, state) {
      final isSignedIn = Supabase.instance.client.auth.currentSession != null;
      final path = state.uri.path;
      final publicPaths = {
        AppRoutes.home,
        AppRoutes.signUp,
        AppRoutes.verifyEmail,
        AppRoutes.forgotPassword,
        AppRoutes.terms,
        AppRoutes.privacy,
      };
      final guestOnlyPaths = {AppRoutes.signUp, AppRoutes.verifyEmail};

      if (!isSignedIn && !publicPaths.contains(path)) return AppRoutes.home;
      if (isSignedIn && guestOnlyPaths.contains(path)) {
        return AppRoutes.home;
      }
      return null;
    },
    routes: [
      _appRoute(
        AppRoutes.settings,
        (_, _) =>
            const Module2Gate(role: 'job_seeker', child: AccountSettingsPage()),
      ),
      _appRoute(
        AppRoutes.employerSettings,
        (_, _) => const Module2Gate(
          role: 'employer',
          child: AccountSettingsPage(role: 'employer'),
        ),
      ),
      _appRoute(
        AppRoutes.adminSettings,
        (_, _) => const AdminPreviewGate(
          child: AccountSettingsPage(role: 'administrator'),
        ),
      ),
      _appRoute(
        AppRoutes.profilePreview,
        (_, _) =>
            const Module2Gate(role: 'job_seeker', child: ExtendedProfilePage()),
      ),
      _appRoute(
        AppRoutes.companyPreview,
        (_, _) => const Module2Gate(
          role: 'employer',
          child: ExtendedProfilePage(employer: true),
        ),
      ),
      _appRoute(
        AppRoutes.evaluations,
        (_, _) =>
            const Module2Gate(role: 'job_seeker', child: EvaluationsPage()),
      ),
      _appRoute(
        '${AppRoutes.evaluations}/:assignmentId/rate',
        (_, state) => Module2Gate(
          role: 'job_seeker',
          child: EvaluationFormPage(
            assignmentId: state.pathParameters['assignmentId']!,
          ),
        ),
      ),
      _appRoute(
        '${AppRoutes.evaluations}/:assignmentId',
        (_, state) => Module2Gate(
          role: 'job_seeker',
          child: EvaluationDetailPage(
            assignmentId: state.pathParameters['assignmentId']!,
          ),
        ),
      ),
      _appRoute(
        AppRoutes.employerEvaluations,
        (_, _) => const Module2Gate(
          role: 'employer',
          child: EvaluationsPage(employer: true),
        ),
      ),
      _appRoute(
        '${AppRoutes.employerEvaluations}/:assignmentId/rate',
        (_, state) => Module2Gate(
          role: 'employer',
          child: EvaluationFormPage(
            employer: true,
            assignmentId: state.pathParameters['assignmentId']!,
          ),
        ),
      ),
      _appRoute(
        '${AppRoutes.employerEvaluations}/:assignmentId',
        (_, state) => Module2Gate(
          role: 'employer',
          child: EvaluationDetailPage(
            employer: true,
            assignmentId: state.pathParameters['assignmentId']!,
          ),
        ),
      ),
      _appRoute(
        AppRoutes.reputation,
        (_, _) =>
            const Module2Gate(role: 'job_seeker', child: ReputationPage()),
      ),
      _appRoute(
        AppRoutes.employerReputation,
        (_, _) => const Module2Gate(
          role: 'employer',
          child: ReputationPage(employer: true),
        ),
      ),
      _appRoute(
        AppRoutes.recordPayment,
        (_, _) =>
            const Module2Gate(role: 'employer', child: PaymentRecordPage()),
      ),
      _appRoute(
        AppRoutes.payments,
        (_, _) =>
            const Module2Gate(role: 'job_seeker', child: PaymentHistoryPage()),
      ),
      _appRoute(
        '${AppRoutes.payments}/:paymentId',
        (_, state) => Module2Gate(
          role: 'job_seeker',
          child: PaymentDetailPage(
            paymentId: state.pathParameters['paymentId']!,
          ),
        ),
      ),
      _appRoute(
        AppRoutes.employerPayments,
        (_, _) => const Module2Gate(
          role: 'employer',
          child: PaymentHistoryPage(employer: true),
        ),
      ),
      _appRoute(
        '${AppRoutes.employerPayments}/:paymentId',
        (_, state) => Module2Gate(
          role: 'employer',
          child: PaymentDetailPage(
            employer: true,
            paymentId: state.pathParameters['paymentId']!,
          ),
        ),
      ),
      _appRoute(
        AppRoutes.adminPreview,
        (_, _) => const AdminPreviewGate(child: AdminPreviewPage()),
      ),
      _appRoute(
        AppRoutes.adminDemoAccounts,
        (_, _) => const AdminPreviewGate(
          child: AdminPreviewPage(section: 'Accounts'),
        ),
      ),
      _appRoute(
        AppRoutes.adminDemoJobs,
        (_, _) =>
            const AdminPreviewGate(child: AdminPreviewPage(section: 'Jobs')),
      ),
      _appRoute(
        AppRoutes.adminDemoDisputes,
        (_, _) => const AdminPreviewGate(
          child: AdminPreviewPage(section: 'Disputes'),
        ),
      ),
      _appRoute(
        '${AppRoutes.adminDemoDisputes}/:disputeId',
        (_, state) => AdminPreviewGate(
          child: DisputeDetailPage(
            disputeId: state.pathParameters['disputeId']!,
          ),
        ),
      ),
      _appRoute(
        AppRoutes.adminDemoReports,
        (_, _) =>
            const AdminPreviewGate(child: AdminPreviewPage(section: 'Reports')),
      ),
      _appRoute(
        AppRoutes.recommendations,
        (_, _) =>
            const Module2Gate(role: 'job_seeker', child: RecommendationsPage()),
      ),
      _appRoute(
        AppRoutes.attendanceHistory,
        (_, _) =>
            const Module2Gate(role: 'job_seeker', child: AttendanceListPage()),
      ),
      _appRoute(
        AppRoutes.workEvidence,
        (_, _) => const Module2Gate(role: 'job_seeker', child: EvidencePage()),
      ),
      _appRoute(
        AppRoutes.attendance,
        (_, _) =>
            const Module2Gate(role: 'job_seeker', child: AttendancePage()),
      ),
      _appRoute(
        '${AppRoutes.attendance}/:recordId/report',
        (_, state) => Module2Gate(
          role: 'job_seeker',
          child: AttendanceDetailPage(
            recordId: state.pathParameters['recordId']!,
            report: true,
          ),
        ),
      ),
      _appRoute(
        '${AppRoutes.attendance}/:recordId',
        (_, state) => Module2Gate(
          role: 'job_seeker',
          child: AttendanceDetailPage(
            recordId: state.pathParameters['recordId']!,
          ),
        ),
      ),
      _appRoute(
        AppRoutes.attendanceReview,
        (_, _) => const Module2Gate(
          role: 'employer',
          child: AttendanceListPage(employer: true),
        ),
      ),
      _appRoute(
        AppRoutes.workers,
        (_, _) => const Module2Gate(role: 'employer', child: WorkersPage()),
      ),
      _appRoute(
        '${AppRoutes.attendanceReview}/:recordId/report',
        (_, state) => Module2Gate(
          role: 'employer',
          child: AttendanceDetailPage(
            recordId: state.pathParameters['recordId']!,
            employer: true,
            report: true,
          ),
        ),
      ),
      _appRoute(
        '${AppRoutes.attendanceReview}/:recordId',
        (_, state) => Module2Gate(
          role: 'employer',
          child: AttendanceDetailPage(
            recordId: state.pathParameters['recordId']!,
            employer: true,
          ),
        ),
      ),
      _appRoute(
        AppRoutes.messages,
        (_, _) => const Module2Gate(role: 'job_seeker', child: ChatPage()),
      ),
      _appRoute(
        '${AppRoutes.messages}/:conversationId',
        (_, state) => Module2Gate(
          role: 'job_seeker',
          child: ChatPage(
            conversationId: state.pathParameters['conversationId'],
          ),
        ),
      ),
      _appRoute(
        AppRoutes.employerMessages,
        (_, _) => const Module2Gate(
          role: 'employer',
          child: ChatPage(employer: true),
        ),
      ),
      _appRoute(
        '${AppRoutes.employerMessages}/:conversationId',
        (_, state) => Module2Gate(
          role: 'employer',
          child: ChatPage(
            employer: true,
            conversationId: state.pathParameters['conversationId'],
          ),
        ),
      ),
      _appRoute(
        AppRoutes.nearbyJobs,
        (_, _) =>
            const Module2Gate(role: 'job_seeker', child: NearbyJobsPage()),
      ),
      _appRoute(
        '${AppRoutes.nearbyJobs}/:jobId',
        (_, state) => Module2Gate(
          role: 'job_seeker',
          child: NearbyDetailPage(jobId: state.pathParameters['jobId']!),
        ),
      ),
      _appRoute(
        AppRoutes.jobLocationDemo,
        (_, _) =>
            const Module2Gate(role: 'employer', child: JobLocationDemoPage()),
      ),
      _appRoute(
        AppRoutes.browseJobs,
        (_, _) =>
            const Module2Gate(role: 'job_seeker', child: BrowseJobsPage()),
      ),
      _appRoute(
        '${AppRoutes.browseJobs}/:jobId',
        (_, state) => Module2Gate(
          role: 'job_seeker',
          child: JobDetailsPage(jobId: state.pathParameters['jobId']!),
        ),
      ),
      _appRoute(
        AppRoutes.applications,
        (_, _) =>
            const Module2Gate(role: 'job_seeker', child: ApplicationsPage()),
      ),
      _appRoute(
        '${AppRoutes.applications}/:applicationId',
        (_, state) => Module2Gate(
          role: 'job_seeker',
          child: ApplicationDetailsPage(
            applicationId: state.pathParameters['applicationId']!,
          ),
        ),
      ),
      _appRoute(
        AppRoutes.applicants,
        (_, state) => Module2Gate(
          role: 'employer',
          child: ApplicationsPage(
            employer: true,
            postingId: state.uri.queryParameters['posting'],
          ),
        ),
      ),
      _appRoute(
        '${AppRoutes.applicants}/:applicationId',
        (_, state) => Module2Gate(
          role: 'employer',
          child: ApplicationDetailsPage(
            employer: true,
            applicationId: state.pathParameters['applicationId']!,
          ),
        ),
      ),
      _appRoute(AppRoutes.home, (context, state) => const AuthGate()),
      _appRoute(AppRoutes.signUp, (context, state) => const SignUpPage()),
      _appRoute(
        AppRoutes.verifyEmail,
        (context, state) => VerifyEmailPage(
          email: AppRoutes.pendingAuthEmail,
          startWithCooldown: AppRoutes.pendingEmailCooldown,
        ),
      ),
      _appRoute(
        AppRoutes.forgotPassword,
        (context, state) => VerifyPasswordPage(
          isForgorPassword: true,
          initialEmail: AppRoutes.pendingAuthEmail,
        ),
      ),
      _appRoute(
        AppRoutes.verifyPassword,
        (context, state) => const VerifyPasswordPage(),
      ),
      _appRoute(
        AppRoutes.changePassword,
        (context, state) => ChangePasswordPage(
          expectedUserId: Supabase.instance.client.auth.currentUser?.id ?? '',
        ),
      ),
      _appRoute(
        AppRoutes.terms,
        (context, state) =>
            const TermsAndPrivacyPage(initialSection: PolicySection.terms),
      ),
      _appRoute(
        AppRoutes.privacy,
        (context, state) =>
            const TermsAndPrivacyPage(initialSection: PolicySection.privacy),
      ),
      _appRoute(
        AppRoutes.jobPostings,
        (context, state) => JobPostingsPage(
          initialStatus: state.uri.queryParameters['status'] ?? 'draft',
        ),
      ),
      jobFormRoute(AppRoutes.createJob),
      jobFormRoute('${AppRoutes.jobPostings}/:jobId/edit'),
      _appRoute(AppRoutes.profile, (context, state) => const ProfilePage()),
      _appRoute(
        AppRoutes.company,
        (context, state) => const CreateCompanyPage(),
      ),
      _appRoute(
        AppRoutes.documentSubmission,
        (context, state) => const DocumentSubmissionPage(),
      ),
      _appRoute(
        AppRoutes.inviteAdmin,
        (context, state) => const InviteAdminPage(),
      ),
      _appRoute(
        AppRoutes.adminPermissions,
        (context, state) => const AdminPermissionsPage(),
      ),
      _appRoute(
        AppRoutes.adminUsers,
        (context, state) => const AdminUsersPage(),
      ),
      _appRoute(
        AppRoutes.companyReviews,
        (context, state) => const CompanyReviewPage(),
      ),
      _appRoute(
        AppRoutes.notifications,
        (context, state) => const NotificationsPage(),
      ),
    ],
  );
}

GoRoute _appRoute(
  String path,
  Widget Function(BuildContext, GoRouterState) buildPage, {
  ExitCallback? onExit,
}) {
  return GoRoute(
    path: path,
    onExit: onExit,
    pageBuilder: (context, state) => appPage(state, buildPage(context, state)),
  );
}

class _AuthRouterRefresh extends ChangeNotifier {
  String? _demoUserId = Supabase.instance.client.auth.currentUser?.id;
  late final StreamSubscription<AuthState> _subscription;

  _AuthRouterRefresh() {
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != _demoUserId) {
        Module2Repository.session.reset();
        Phase3Store.session.reset();
        Phase4Store.session.reset();
        _demoUserId = userId;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'JobMate',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const JobMateScrollBehavior(),
      theme: JobMateTheme.light(),
      routerConfig: _appRouter,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: .center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
