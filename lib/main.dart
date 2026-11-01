import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'features/profile/change_password_page.dart';
import 'features/profile/document_submission_page.dart';
import 'features/profile/profile_page.dart';
import 'features/profile/verify_password_page.dart';
import 'features/notifications/notifications_page.dart';
import 'shared/navigation/app_routes.dart';
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
      final isSignedIn =
          Supabase.instance.client.auth.currentSession != null;
      final path = state.uri.path;
      final publicPaths = {
        AppRoutes.home,
        AppRoutes.signUp,
        AppRoutes.verifyEmail,
        AppRoutes.forgotPassword,
        AppRoutes.terms,
        AppRoutes.privacy,
      };
      final guestOnlyPaths = {
        AppRoutes.signUp,
        AppRoutes.verifyEmail,
      };

      if (!isSignedIn && !publicPaths.contains(path)) return AppRoutes.home;
      if (isSignedIn && guestOnlyPaths.contains(path)) {
        return AppRoutes.home;
      }
      return null;
    },
    routes: [
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
          expectedUserId:
              Supabase.instance.client.auth.currentUser?.id ?? '',
        ),
      ),
      _appRoute(
        AppRoutes.terms,
        (context, state) => const TermsAndPrivacyPage(
          initialSection: PolicySection.terms,
        ),
      ),
      _appRoute(
        AppRoutes.privacy,
        (context, state) => const TermsAndPrivacyPage(
          initialSection: PolicySection.privacy,
        ),
      ),
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
  Widget Function(BuildContext, GoRouterState) buildPage,
) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) => _appPage(
      state,
      buildPage(context, state),
    ),
  );
}

Page<void> _appPage(GoRouterState state, Widget child) {
  if (!kIsWeb) {
    return MaterialPage<void>(key: state.pageKey, child: child);
  }

  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class _AuthRouterRefresh extends ChangeNotifier {
  late final StreamSubscription<AuthState> _subscription;

  _AuthRouterRefresh() {
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
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
      title: 'Home Page',
      scrollBehavior: const JobMateScrollBehavior(),
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          surface: const Color(0xFFF5F8FA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F8FA),
        cardColor: Colors.white,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF172B3A),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
      ),
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
