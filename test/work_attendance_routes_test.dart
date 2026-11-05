import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/work_attendance/work_attendance_pages.dart';
import 'package:jobmate/features/work_attendance/work_attendance_routes.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:jobmate/shared/navigation/workspace_destinations.dart';
import 'package:jobmate/shared/widgets/app_workspace.dart';

import 'support/workspace_navigation_test_helper.dart';
import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, other;

void main() {
  test(
    'production destination is seeker-only and demo paths remain distinct',
    () {
      final seeker = workspaceDestinations('job_seeker').values
          .expand((v) => v);
      expect(
        seeker.where((v) => v.$1 == AppRoutes.workAttendance).single.$2,
        'My Work Shifts',
      );
      expect(
        seeker.where((v) => v.$1 == AppRoutes.attendance).single.$2,
        'Attendance (demo)',
      );
      for (final role in ['employer', 'administrator', 'guest']) {
        expect(
          workspaceDestinations(role).values
              .expand((v) => v)
              .where((v) => v.$1 == AppRoutes.workAttendance),
          isEmpty,
        );
      }
      expect(AppRoutes.workAttendance, '/work-attendance');
      expect(AppRoutes.attendanceHistory, '/attendance/history');
      expect(AppRoutes.workEvidence, '/attendance/evidence');
      expect(AppRoutes.attendanceReview, '/attendance-review');
      expect(isWorkspaceRootPath(AppRoutes.workAttendance), isTrue);
      expect(
        selectedWorkspacePath(AppRoutes.workAttendance, seeker),
        AppRoutes.workAttendance,
      );
    },
  );

  for (final allowed in [true, false]) {
    testWidgets('direct entry with access $allowed and safe Dashboard exit', (
      tester,
    ) async {
      final source = FakeSource();
      var checks = 0;
      final router = GoRouter(
        initialLocation: AppRoutes.workAttendance,
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: Text('Dashboard destination')),
          ),
          workAttendanceRoute(
            source: source,
            checkAccess: () async {
              checks++;
              return allowed;
            },
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(checks, 1);
      expect(source.calls, allowed ? 1 : 0);
      if (allowed) {
        expect(find.text('Server job'), findsOneWidget);
        expect(find.byType(WorkAttendancePage), findsOneWidget);
        final workspace = tester.widget<AppWorkspace>(
          find.byType(AppWorkspace),
        );
        expect(workspace.path, AppRoutes.workAttendance);
        expect(workspace.focused, isFalse);
        await openWorkspaceMenu(tester);
        await scrollWorkspaceMenuTo(tester, 'Dashboard');
        await tester.tap(find.widgetWithText(ListTile, 'Dashboard'));
      } else {
        expect(find.text('Page unavailable'), findsOneWidget);
        await tester.tap(find.text('Back to Dashboard'));
      }
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.text('Dashboard destination'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      expect(source.changes.hasListener, isFalse);
      await source.changes.close();
    });
  }

  testWidgets(
    'account switch rechecks access and suppresses pending old-account data',
    (tester) async {
      final source = FakeSource();
      var checks = 0;
      final pending = Completer<List<Map<String, dynamic>>>();
      source.workerRead = () => pending.future;
      final router = GoRouter(
        initialLocation: AppRoutes.workAttendance,
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Dashboard')),
          ),
          workAttendanceRoute(
            source: source,
            checkAccess: () async {
              checks++;
              return source.userId != other;
            },
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      await tester.pump();
      expect(source.calls, 1);
      source.switchAccount(other);
      await tester.pumpAndSettle();
      pending.complete([assignment()]);
      await tester.pumpAndSettle();
      expect(checks, 2);
      expect(find.text('Server job'), findsNothing);
      expect(find.text('Page unavailable'), findsOneWidget);
      source.switchAccount(null);
      await tester.pumpAndSettle();
      expect(checks, 2);
      expect(find.text('Page unavailable'), findsOneWidget);
      expect(source.calls, 1);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await source.changes.close();
    },
  );

  testWidgets(
    'fresh router reload, navigation to production and back are safe',
    (tester) async {
      final source = FakeSource();
      GoRouter createRouter(String initial) => GoRouter(
        initialLocation: initial,
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const AppWorkspace(
              title: 'Dashboard',
              path: '/',
              role: 'job_seeker',
              showAccountMenu: false,
              child: Text('Dashboard content'),
            ),
          ),
          workAttendanceRoute(source: source, checkAccess: () async => true),
        ],
      );
      var router = createRouter('/');
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await openWorkspaceMenu(tester);
      await scrollWorkspaceMenuTo(tester, 'My Work Shifts');
      await tester.tap(find.widgetWithText(ListTile, 'My Work Shifts'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutes.workAttendance,
      );
      expect(find.text('Server job'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      // Reconstruct from the URL, equivalent to a fresh app entry without route extras.
      router = createRouter(AppRoutes.workAttendance);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('Server job'), findsOneWidget);
      expect(source.calls, 2);
      router.push('/');
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Server job'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      expect(source.changes.hasListener, isFalse);
      await source.changes.close();
    },
  );

  testWidgets(
    'signed-out direct entry cannot invoke injected access check or RPC',
    (tester) async {
      final source = FakeSource()..userId = null;
      final router = GoRouter(
        initialLocation: AppRoutes.workAttendance,
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SizedBox()),
          workAttendanceRoute(
            source: source,
            checkAccess: () async => throw StateError('must not run'),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('Page unavailable'), findsOneWidget);
      expect(source.calls, 0);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await source.changes.close();
    },
  );
}
