import 'fixtures/published_jobs_source.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';

import 'package:jobmate/features/applications/browse_jobs_page.dart';
import 'package:jobmate/features/applications/job_details_page.dart';
import 'package:jobmate/features/applications/applications_page.dart';
import 'package:jobmate/features/demo_work/phase3_store.dart';
import 'package:jobmate/features/recommendations/recommendations_page.dart';
import 'package:jobmate/features/attendance/attendance_pages.dart';
import 'package:jobmate/features/attendance/workers_page.dart';
import 'package:jobmate/features/chat/chat_page.dart';
import 'package:jobmate/features/location/location_pages.dart';
import 'package:jobmate/features/phase4/phase4_store.dart';
import 'package:jobmate/features/phase4/evaluation_pages.dart';
import 'package:jobmate/features/phase4/reputation_page.dart';
import 'package:jobmate/features/phase4/payment_pages.dart';
import 'package:jobmate/features/phase4/admin_preview_pages.dart';
import 'package:jobmate/features/phase4/account_settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Load the same bundled font families as the application.
    for (final entry in {
      'Outfit': 'Outfit-Variable.ttf',
      'DM Serif Display': 'DMSerifDisplay-Regular.ttf',
      'DM Mono': 'DMMono-Regular.ttf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(rootBundle.load('assets/fonts/${entry.value}'));
      await loader.load();
    }
    var directory = File(Platform.resolvedExecutable).parent;
    for (var depth = 0; depth < 9; depth++) {
      final font = File(
        '${directory.path}/artifacts/material_fonts/materialicons-regular.otf',
      );
      if (await font.exists()) {
        final loader = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          );
        await loader.load();
        break;
      }
      directory = directory.parent;
    }
  });

  for (final scenario in [
    (const Size(390, 1000), 1.0),
    (const Size(1440, 1000), 1.0),
    (const Size(320, 720), 1.6),
    (const Size(568, 320), 1.3),
  ]) {
    final width = scenario.$1.width;
    final scale = scenario.$2;
    for (final screen in [
      'browse',
      'job-detail',
      'apply',
      'applications',
      'application-detail',
      'applicants',
      'applicant-detail',
      'recommendations',
      'attendance',
      'evidence',
      'attendance-review',
      'workers',
      'report',
      'chat',
      'nearby',
      'location-picker',
      'evaluate',
      'reputation',
      'payments',
      'record-payment',
      'admin-jobs',
      'admin-disputes',
      'dispute-detail',
      'admin-reports',
      'settings',
    ]) {
      testWidgets('Phase 5.2 $screen at ${scenario.$1} / text $scale', (
        tester,
      ) async {
        tester.view.physicalSize = scenario.$1;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final jobs = fixtureModule2(),
            work = Phase3Store(),
            data = Phase4Store();
        addTearDown(jobs.dispose);
        addTearDown(work.dispose);
        addTearDown(data.dispose);
        final application = jobs.applications.firstWhere((a) => a.mine);
        final child = switch (screen) {
          'browse' => BrowseJobsPage(repository: jobs),
          'job-detail' => JobDetailsPage(jobId: 'demo-job-1', repository: jobs),
          'apply' => Scaffold(
            body: Center(
              child: Dialog(
                child: SizedBox(
                  width: 448,
                  child: ApplyDemoForm(
                    job: jobs.job('demo-job-1')!,
                    repository: jobs,
                  ),
                ),
              ),
            ),
          ),
          'applications' => ApplicationsPage(repository: jobs),
          'application-detail' => ApplicationDetailsPage(
            applicationId: application.id,
            repository: jobs,
          ),
          'applicants' => ApplicationsPage(employer: true, repository: jobs),
          'applicant-detail' => ApplicationDetailsPage(
            employer: true,
            applicationId: jobs.applications.last.id,
            repository: jobs,
          ),
          'recommendations' => RecommendationsPage(repository: jobs),
          'attendance' => AttendancePage(store: work),
          'evidence' => EvidencePage(store: work),
          'attendance-review' => AttendanceListPage(
            employer: true,
            store: work,
          ),
          'workers' => WorkersPage(store: work),
          'report' => AttendanceDetailPage(
            recordId: 'shift-1',
            report: true,
            store: work,
          ),
          'chat' => ChatPage(conversationId: 'chat-1', store: work),
          'nearby' => NearbyJobsPage(repository: jobs),
          'location-picker' => JobLocationDemoPage(store: work),
          'evaluate' => EvaluationFormPage(
            assignmentId: 'sample-assignment-1',
            store: data,
          ),
          'reputation' => ReputationPage(store: data),
          'payments' => PaymentHistoryPage(store: data),
          'record-payment' => PaymentRecordPage(store: data),
          'admin-jobs' => AdminPreviewPage(section: 'Jobs', store: data),
          'admin-disputes' => AdminPreviewPage(
            section: 'Disputes',
            store: data,
          ),
          'dispute-detail' => DisputeDetailPage(
            disputeId: 'demo-case-1',
            store: data,
          ),
          'admin-reports' => AdminPreviewPage(section: 'Reports', store: data),
          _ => AccountSettingsPage(
            store: data,
            loadAccount: () async => {
              'name': 'Review account',
              'email': 'fixture@example.com',
              'role': 'job_seeker',
              'status': 'active',
              'phone_num': '',
            },
          ),
        };
        final router = GoRouter(
          routes: [GoRoute(path: '/', builder: (_, _) => child)],
        );
        addTearDown(router.dispose);
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp.router(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              debugShowCheckedModeBanner: false,
              theme: JobMateTheme.light(),
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (![
          'settings',
          'apply',
          'browse',
          'job-detail',
          'applications',
          'application-detail',
          'applicants',
          'applicant-detail',
        ].contains(screen)) {
          expect(find.text('DEMO / PREVIEW'), findsOneWidget);
        }
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'build/phase52-review/$screen-${width.toInt()}-text-$scale.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        if (screen == 'workers') {
          await tester.ensureVisible(find.text('View Reputation').first);
          await tester.tap(find.text('View Reputation').first);
          await tester.pumpAndSettle();
          expect(find.text('Not enough reputation data'), findsOneWidget);
          await tester.ensureVisible(find.text('Close'));
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField).first,
            'no worker matches',
          );
          await tester.pumpAndSettle();
          expect(find.text('No workers found'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
