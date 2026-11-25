import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';
import 'package:jobmate/shared/widgets/app_workspace.dart';
import 'package:jobmate/shared/widgets/design_primitives.dart';
import 'package:jobmate/features/jobs/job_postings_page.dart';
import 'package:jobmate/features/jobs/job_form_page.dart';
import 'package:jobmate/features/jobs/job_form_route.dart';
import 'package:jobmate/features/jobs/job_preview.dart';
import 'package:jobmate/features/home/dashboard_content.dart';

import 'job_postings_test.dart' as fixtures;

/// PNGs are rendered Flutter fixture previews, never authenticated backend evidence.
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
  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/phase51-review/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final width in [390.0, 768.0, 1440.0]) {
    for (final screen in ['jobs', 'create', 'seeker-home', 'employer-home']) {
      testWidgets('Rendered $screen at $width', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = fixtures.TestJobs()
          ..records = [
            for (var i = 0; i < 6; i++)
              {
                ...fixtures.completeJob(),
                'job_id': 'fixture-$i',
                'title': i == 0
                    ? 'Retail Operations Assistant'
                    : 'Fixture opportunity ${i + 1}',
                'status': i < 2
                    ? 'draft'
                    : i < 5
                    ? 'published'
                    : 'closed',
                'role_overview': 'Screenshot fixture: support a welcoming team and help deliver thoughtful customer service.',
              },
          ];
        final key = GlobalKey();
        final root = switch (screen) {
          'jobs' => JobPostingsPage(
            repository: repo,
            initialStatus: 'published',
          ),
          'create' => JobFormPage(repository: repo),
          _ => AppWorkspace(
            title: 'Dashboard',
            path: '/',
            role: screen == 'seeker-home' ? 'job_seeker' : 'employer',
            child: WorkspaceContent(
              maxWidth: screen == 'employer-home' ? 768 : 672,
              child: DashboardContent(
                profile: {
                  'role': screen == 'seeker-home' ? 'job_seeker' : 'employer',
                  'name': 'Review fixture',
                  'status': 'active',
                  'verification_status': 'pending',
                },
                email: 'fixture@example.com',
                company: screen == 'employer-home'
                    ? {
                        'company_name': 'Screenshot Fixture Company',
                        'verification_status': 'verified',
                        'industry': 'Retail',
                        'location': 'Shah Alam',
                      }
                    : null,
                memberRole: 'owner',
                jobPostings: screen == 'employer-home' ? repo.records : null,
                onProfile: () {},
                onCompany: () {},
                onVerification: () {},
              ),
            ),
          ),
        };
        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => root),
            if (screen == 'jobs')
              jobFormRoute('/job-postings/:jobId/edit', repository: repo),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: JobMateTheme.light(),
              routerConfig: router,
            ),
          ),
        );
        await capture(tester, key, '$screen-${width.toInt()}');
        expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 56);
        final content = tester.widget<WorkspaceContent>(
          find.byType(WorkspaceContent),
        );
        expect(content.maxWidth, switch (screen) {
          'jobs' => double.infinity,
          'create' => 880,
          'employer-home' => 768,
          _ => 672,
        });
        if (!kIsWeb || width >= 840) {
          expect(find.byType(Drawer), findsNothing);
        } else {
          expect(
            tester.widget<Scaffold>(find.byType(Scaffold)).drawer,
            isA<Drawer>(),
          );
        }
        if (screen == 'create') {
          for (final title in [
            'Basic Information',
            'Compensation',
            'Schedule & Location',
            'Job Description & AI Formatting',
            'Requirements & Benefits',
          ]) {
            expect(find.text(title), findsOneWidget);
          }
        }
        if (screen == 'jobs') {
          for (final (status, label, count) in [
            ('all', 'Total Jobs', repo.records.length),
            (
              'published',
              'Published',
              repo.records.where((j) => j['status'] == 'published').length,
            ),
          ]) {
            final tile = find.byKey(ValueKey('posting-stat-$status'));
            expect(
              find.descendant(of: tile, matching: find.text(label)),
              findsOneWidget,
            );
            expect(
              find.descendant(of: tile, matching: find.text('$count')),
              findsOneWidget,
            );
          }
        }
        if (screen == 'employer-home') {
          final tiles = tester.widgetList<StatTile>(find.byType(StatTile));
          expect(
            tiles.where((t) => t.label == 'Total Jobs').single.value,
            '${repo.records.length}',
          );
          expect(
            tiles.where((t) => t.label == 'Published').single.value,
            '${repo.records.where((j) => j['status'] == 'published').length}',
          );
        }
        if (screen == 'jobs') {
          final edit = find.widgetWithText(OutlinedButton, 'Edit').first;
          await tester.ensureVisible(edit);
          await tester.tap(edit);
          await tester.pumpAndSettle();
          final preview = find.text('Preview unsaved changes');
          await tester.ensureVisible(preview);
          await tester.tap(preview);
          await tester.pumpAndSettle();
          expect(find.byType(JobPreview), findsOneWidget);
          await capture(tester, key, 'preview-${width.toInt()}');
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
