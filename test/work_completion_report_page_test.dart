import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_routes.dart';
import 'package:jobmate/features/work_attendance/work_completion_report_data.dart';
import 'package:jobmate/features/work_attendance/work_completion_report_document.dart';
import 'package:jobmate/features/work_attendance/work_completion_report_export.dart';
import 'package:jobmate/features/work_attendance/work_completion_report_page.dart';
import 'package:jobmate/features/work_attendance/work_completion_report_repository.dart';
import 'package:jobmate/features/work_attendance/work_verification_routes.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';

import 'work_attendance_repository_test.dart' as attendance;
import 'work_attendance_resolution_test.dart' show auditFor, resolutionContext;
import 'work_completion_report_repository_test.dart' as report;

class _Loader extends WorkCompletionReportRepository {
  _Loader(super.source);
  final requests = <(String, Completer<WorkCompletionReportResult>)>[];

  @override
  Future<WorkCompletionReportResult> load(String assignmentId) {
    final response = Completer<WorkCompletionReportResult>();
    requests.add((assignmentId, response));
    return response.future;
  }
}

class _Platform implements ReportPdfPlatform {
  @override
  List<ReportPdfAction> actions = [
    ReportPdfAction.open,
    ReportPdfAction.download,
  ];
  bool blocked = false;
  final targets = <_Target>[];
  final reserved = <ReportPdfAction>[];

  @override
  ReportPdfTarget? reserve(ReportPdfAction action) {
    reserved.add(action);
    if (blocked) return null;
    final target = _Target();
    targets.add(target);
    return target;
  }
}

class _Target implements ReportPdfTarget {
  int cancellations = 0;
  Uint8List? delivered;
  String? filename;

  @override
  void cancel() => cancellations++;

  @override
  Future<void> deliver(
    Uint8List bytes,
    String filename,
    bool Function() isCurrent,
  ) async {
    expect(isCurrent(), isTrue);
    delivered = bytes;
    this.filename = filename;
  }
}

void main() {
  late report.FakeSource source;
  late _Loader loader;
  late _Platform pdfPlatform;
  late List<WorkCompletionReportData> rendered;
  late List<Completer<Uint8List>> generations;
  setUp(() {
    source = report.FakeSource();
    loader = _Loader(source);
    pdfPlatform = _Platform();
    rendered = [];
    generations = [];
  });
  tearDown(() => unawaited(source.changes.close()));

  Future<WorkCompletionReportResult> ready(WidgetTester tester) async =>
      (await tester.runAsync(
        () => WorkCompletionReportRepository(source).load(report.id(2)),
      ))!;

  Future<void> show(
    WidgetTester tester, {
    String? assignmentId,
    double textScale = 1,
  }) => tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: WorkCompletionReportPage(
        assignmentId: assignmentId ?? report.id(2),
        repository: loader,
        fallback: AppRoutes.workAttendance,
        pdfPlatform: pdfPlatform,
        renderPdf: (data) {
          rendered.add(data);
          final pending = Completer<Uint8List>();
          generations.add(pending);
          return pending.future;
        },
      ),
    ),
  );

  for (final (width, scale) in [
    (320.0, 2.0),
    (390.0, 1.0),
    (768.0, 1.0),
    (1440.0, 1.0),
  ]) {
    testWidgets('document is complete and scrollable at $width / $scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final notes = 'Inventory updated · Pemeriksaan selesai · 库存更新 ' * 16;
      source.row['job_title'] =
          'Retail assistant — overnight stock replenishment and reconciliation';
      source.row['workplace_location'] = 'Jalan Tun Razak, Kuala Lumpur — receiving entrance near the main loading bay';
      source.row['company_name'] =
          'JobMate Company — Kuala Lumpur Distribution and Retail Operations';
      source.files.last['description'] = notes;
      source.row['attendance_resolution'] = {
        'assignment_id': report.id(2),
        'contract_version': 2,
        'version': 'a' * 32,
        'can_confirm_absence': false,
        'can_correct': false,
        'checkout_recovery_enforced': true,
        'recovery_cutoff': report.verifiedAt,
        'original_location': {'check_in_status': 'denied'},
        'resolution': {
          'request_id': report.id(30),
          'resolved_by': report.id(8),
          'decision': 'corrected',
          'reason': 'Private correction reason',
          'resolved_at': report.verifiedAt,
          'corrected_check_in_at': '2026-11-20T14:55:00Z',
          'corrected_check_out_at': '2026-11-20T17:10:00Z',
        },
      };
      await show(tester, textScale: scale);
      final spinner = find.byWidgetPredicate(
        (widget) =>
            widget is CircularProgressIndicator &&
            widget.semanticsLabel == 'Loading work report',
      );
      expect(spinner, findsOneWidget);
      expect(find.text('Loading report...'), findsOneWidget);
      final panel = tester.getRect(
        find.byKey(const ValueKey('work-report-loading-panel')),
      );
      expect(tester.getCenter(spinner).dx, closeTo(panel.center.dx, .1));
      expect(panel.height, greaterThanOrEqualTo(200));
      loader.requests.single.$2.complete(await ready(tester));
      await tester.pumpAndSettle();
      final doc = find.byType(WorkCompletionReportDocument);
      expect(doc, findsOneWidget);
      expect(tester.getSize(doc).width, lessThanOrEqualTo(960));
      for (final text in [
        'Job Information',
        'Work Schedule',
        'Attendance Information',
        'Work Verification',
        'Job Assignment Information',
        'Report Summary',
        source.row['job_title'] as String,
        source.row['workplace_location'] as String,
        source.row['company_name'] as String,
        'Assigned Worker',
        'Part-time',
        '20 Nov 2026 – 21 Nov 2026',
        '20 Nov 2026, 10:55:00 PM MYT',
        'Original attendance event: 20 Nov 2026, 11:00:00 PM MYT',
        'Employer-corrected attendance',
        'Recorded Attendance Duration',
        '2 h 15 min',
        '2 files submitted',
        'Submitted · round 2',
        'Marked Complete at Verification',
        'Employer',
        notes.trim(),
        'Generated by JobMate — AI-Assisted Recruitment Platform',
      ]) {
        expect(
          find.descendant(of: doc, matching: find.text(text)),
          findsWidgets,
          reason: text,
        );
      }
      expect(find.textContaining('supporting documentation'), findsOneWidget);
      expect(find.textContaining(report.id(2)), findsNothing);
      expect(find.textContaining('Private.pdf'), findsNothing);
      expect(find.textContaining('Private review reason'), findsNothing);
      expect(find.textContaining('private-'), findsNothing);
      expect(find.textContaining('Print / Export PDF'), findsNothing);
      expect(find.text('Open PDF'), findsOneWidget);
      expect(find.text('Download PDF'), findsOneWidget);
      expect(find.textContaining('Payable Working Hours'), findsNothing);
      final footer = find.text(
        'Generated by JobMate — AI-Assisted Recruitment Platform',
      );
      await tester.ensureVisible(footer);
      await tester.pumpAndSettle();
      expect(footer.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (failure, message) in [
    (WorkCompletionReportFailure.ineligible, 'Report not available yet'),
    (WorkCompletionReportFailure.unavailable, 'Report unavailable'),
    (
      WorkCompletionReportFailure.incomplete,
      'Report unavailable for this record',
    ),
    (WorkCompletionReportFailure.retry, 'Unable to load report'),
  ]) {
    testWidgets(
      '$failure is generic and Retry loads fresh optional fallbacks',
      (tester) async {
        await show(tester);
        loader.requests.single.$2.complete(
          WorkCompletionReportUnavailable(failure),
        );
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        expect(find.byType(WorkCompletionReportDocument), findsNothing);
        expect(find.text('Open PDF'), findsNothing);
        await tester.tap(find.text('Retry'));
        await tester.pump();
        source.failDisplay = true;
        loader.requests.last.$2.complete(await ready(tester));
        await tester.pumpAndSettle();
        expect(loader.requests, hasLength(2));
        expect(find.text('Not available'), findsNWidgets(2));
        expect(
          find.text('Location information not available.'),
          findsNWidgets(2),
        );
      },
    );
  }

  testWidgets(
    'assignment changes supersede requests and rebuilds do not reload',
    (tester) async {
      final payload = await ready(tester);
      await show(tester);
      await show(tester);
      expect(loader.requests, hasLength(1));
      await show(tester, assignmentId: report.id(12));
      loader.requests.first.$2.complete(payload);
      await tester.pump();
      expect(find.byType(WorkCompletionReportDocument), findsNothing);
      expect(loader.requests.last.$1, report.id(12));
      await tester.pumpWidget(const SizedBox());
      loader.requests.last.$2.complete(payload);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account and company changes clear prior and in-flight reports', (
    tester,
  ) async {
    final payload = await ready(tester);
    await show(tester);
    source.actor = report.id(8);
    source.changes.add(null);
    source.actor = report.id(1);
    source.changes.add(null);
    loader.requests.single.$2.complete(payload);
    await tester.pumpAndSettle();
    expect(find.byType(WorkCompletionReportDocument), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    loader.requests.last.$2.complete(payload);
    await tester.pumpAndSettle();
    expect(find.byType(WorkCompletionReportDocument), findsOneWidget);
    source.company = report.id(5);
    source.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(WorkCompletionReportDocument), findsNothing);
  });

  Future<void> showReady(WidgetTester tester) async {
    final initial = await ready(tester);
    await show(tester);
    loader.requests.single.$2.complete(initial);
    await tester.pumpAndSettle();
  }

  Future<void> click(WidgetTester tester, String label) async {
    final action = find.text(label);
    if (action.hitTestable().evaluate().isEmpty) {
      await tester.ensureVisible(action);
    }
    await tester.tap(action);
    await tester.pump();
  }

  for (final action in ReportPdfAction.values) {
    testWidgets(
      '${action.label} reauthorizes and exports the refreshed preview payload',
      (tester) async {
        if (action == ReportPdfAction.share ||
            action == ReportPdfAction.print) {
          pdfPlatform.actions = [ReportPdfAction.share, ReportPdfAction.print];
        }
        await showReady(tester);
        final document = find.byType(WorkCompletionReportDocument);
        final top = tester.getTopLeft(document).dy;
        await click(tester, action.label);
        expect(pdfPlatform.reserved, [action]);
        expect(loader.requests, hasLength(2));
        expect(find.text('Preparing PDF...'), findsOneWidget);
        expect(tester.getTopLeft(document).dy, top);
        ButtonStyleButton button(String label) =>
            tester.widget<ButtonStyleButton>(
              find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byWidgetPredicate(
                      (widget) => widget is ButtonStyleButton,
                    ),
                  )
                  .first,
            );
        expect(button('Preparing PDF...').onPressed, isNull);
        expect(button('Refresh').onPressed, isNull);
        for (final other in pdfPlatform.actions.where(
          (candidate) => candidate != action,
        )) {
          expect(button(other.label).onPressed, isNull);
        }
        await click(tester, 'Preparing PDF...');
        expect(loader.requests, hasLength(2));
        source.row['job_title'] = 'Refreshed role';
        final refreshed = await ready(tester) as WorkCompletionReportReady;
        loader.requests.last.$2.complete(refreshed);
        await tester.pump();
        expect(rendered.single, same(refreshed.data));
        expect(find.text('Refreshed role'), findsOneWidget);
        final bytes = Uint8List.fromList([1, 2]);
        generations.single.complete(bytes);
        await tester.pumpAndSettle();
        expect(pdfPlatform.targets.single.delivered, same(bytes));
        expect(
          pdfPlatform.targets.single.filename,
          'JobMate_Work_Report_2026-11-20.pdf',
        );
        expect(find.text('Preparing PDF...'), findsNothing);
        expect(tester.getTopLeft(document).dy, top);
        expect(button(action.label).onPressed, isNotNull);
      },
    );
  }

  for (final failure in WorkCompletionReportFailure.values) {
    testWidgets(
      'export denial $failure clears old report and closes reserved target',
      (tester) async {
        await showReady(tester);
        await click(tester, 'Open PDF');
        loader.requests.last.$2.complete(
          WorkCompletionReportUnavailable(failure),
        );
        await tester.pumpAndSettle();
        expect(rendered, isEmpty);
        expect(pdfPlatform.targets.single.cancellations, 1);
        expect(pdfPlatform.targets.single.delivered, isNull);
        expect(find.byType(WorkCompletionReportDocument), findsNothing);
        expect(find.text('Open PDF'), findsNothing);
      },
    );
  }

  for (final change in ['account', 'company', 'assignment', 'dispose']) {
    testWidgets('$change change invalidates export during PDF generation', (
      tester,
    ) async {
      await showReady(tester);
      await click(tester, 'Open PDF');
      loader.requests.last.$2.complete(await ready(tester));
      await tester.pump();
      expect(generations, hasLength(1));
      switch (change) {
        case 'account':
          source.actor = report.id(8);
          source.changes.add(null);
          source.actor = report.id(1);
          source.changes.add(null);
        case 'company':
          source.company = report.id(5);
          source.changes.add(null);
          source.company = null;
          source.changes.add(null);
        case 'assignment':
          await show(tester, assignmentId: report.id(12));
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
      }
      generations.single.complete(Uint8List.fromList([1]));
      await tester.pump();
      expect(pdfPlatform.targets.single.cancellations, 1);
      expect(pdfPlatform.targets.single.delivered, isNull);
      expect(find.byType(WorkCompletionReportDocument), findsNothing);
    });
  }

  testWidgets(
    'blocked popup offers download and generation errors allow a fresh retry',
    (tester) async {
      await showReady(tester);
      final document = find.byType(WorkCompletionReportDocument);
      final top = tester.getTopLeft(document).dy;
      pdfPlatform.blocked = true;
      await click(tester, 'Open PDF');
      expect(
        find.textContaining('Allow popups or use Download PDF'),
        findsOneWidget,
      );
      expect(loader.requests, hasLength(1));
      expect(tester.getTopLeft(document).dy, top);
      pdfPlatform.blocked = false;
      await click(tester, 'Download PDF');
      loader.requests.last.$2.complete(await ready(tester));
      await tester.pump();
      generations.single.completeError(StateError('Private export detail'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Unable to complete the PDF action'),
        findsOneWidget,
      );
      expect(find.textContaining('Private export detail'), findsNothing);
      expect(tester.getTopLeft(document).dy, top);
      await click(tester, 'Download PDF');
      expect(loader.requests, hasLength(3));
    },
  );

  for (final employer in [false, true]) {
    testWidgets(
      'evidence entry opens the shared report route employer=$employer',
      (tester) async {
        final work = attendance.FakeSource();
        final companyId = attendance.other;
        Future<JobAccess> select() async => JobAccess({
          'company_id': companyId,
          'company_name': 'Scoped company',
        }, null);
        final row = attendance.assignment(company: employer);
        row['assignment_status'] = 'completed';
        row['verification_status'] = 'verified';
        work.workerRead = () async => [row];
        work.companyRead = (_) async => [row];
        String? selected;
        final root = employer
            ? AppRoutes.workVerification
            : AppRoutes.workAttendance;
        final details = '$root/${attendance.id}/evidence';
        final router = GoRouter(
          initialLocation: details,
          routes: [
            GoRoute(
              path: root,
              builder: (_, _) => const Scaffold(body: Text('Shift list')),
            ),
            if (employer) ...[
              workVerificationRoute(
                evidence: true,
                source: work,
                checkAccess: () async => true,
                loadCompanyAccess: select,
              ),
              workVerificationRoute(
                report: true,
                source: work,
                checkAccess: () async => true,
                loadCompanyAccess: select,
                createReport: (company) {
                  selected = company;
                  return loader;
                },
              ),
            ] else ...[
              workAttendanceRoute(
                evidence: true,
                source: work,
                checkAccess: () async => true,
              ),
              workAttendanceRoute(
                report: true,
                source: work,
                checkAccess: () async => true,
                createReport: () => loader,
              ),
            ],
          ],
        );
        addTearDown(router.dispose);
        addTearDown(work.changes.close);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        final action = find.text('View Report');
        expect(action, findsOneWidget);
        expect(loader.requests, isEmpty);
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();
        await tester.pump();
        expect(loader.requests.single.$1, attendance.id);
        expect(selected, employer ? companyId : null);
        expect(find.byType(WorkCompletionReportPage), findsOneWidget);
        loader.requests.single.$2.complete(
          const WorkCompletionReportUnavailable(
            WorkCompletionReportFailure.unavailable,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Report unavailable'), findsOneWidget);
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(find.text('View Report'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'direct worker report uses fresh loader and falls back to history',
    (tester) async {
      final work = attendance.FakeSource();
      final router = GoRouter(
        initialLocation:
            '/work-attendance/${attendance.id}/report?from=history',
        routes: [
          workAttendanceRoute(
            report: true,
            source: work,
            checkAccess: () async => true,
            createReport: () => loader,
          ),
          GoRoute(
            path: AppRoutes.attendanceHistory,
            builder: (_, _) =>
                const Scaffold(body: Text('Attendance history list')),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(work.changes.close);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      expect(loader.requests.single.$1, attendance.id);
      loader.requests.single.$2.complete(
        const WorkCompletionReportUnavailable(
          WorkCompletionReportFailure.unavailable,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Attendance history list'), findsOneWidget);
    },
  );

  testWidgets('direct employer route enforces role gate before reporting', (
    tester,
  ) async {
    final work = attendance.FakeSource();
    var companyReads = 0;
    final router = GoRouter(
      initialLocation: '/work-verification/${attendance.id}/report',
      routes: [
        workVerificationRoute(
          report: true,
          source: work,
          checkAccess: () async => false,
          loadCompanyAccess: () async {
            companyReads++;
            return const JobAccess(null, 'Denied');
          },
          createReport: (_) => loader,
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(work.changes.close);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Page unavailable'), findsOneWidget);
    expect(companyReads, 0);
    expect(loader.requests, isEmpty);
  });

  for (final (assignmentStatus, verificationStatus) in [
    ('scheduled', 'not_submitted'),
    ('active', 'not_submitted'),
    ('awaiting_verification', 'pending_review'),
    ('awaiting_verification', 'more_evidence_required'),
    ('cancelled', 'verified'),
    ('disputed', 'disputed'),
  ]) {
    testWidgets(
      'evidence omits report for $assignmentStatus / $verificationStatus',
      (tester) async {
        final work = attendance.FakeSource();
        work.workerRead = () async => [
          attendance.assignment()
            ..['assignment_status'] = assignmentStatus
            ..['verification_status'] = verificationStatus,
        ];
        final router = GoRouter(
          initialLocation: '/work-attendance/${attendance.id}/evidence',
          routes: [
            workAttendanceRoute(
              evidence: true,
              source: work,
              checkAccess: () async => true,
            ),
          ],
        );
        addTearDown(router.dispose);
        addTearDown(work.changes.close);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        expect(find.text('View Report'), findsNothing);
        expect(loader.requests, isEmpty);
        expect(find.text('Server job'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'confirmed absence hides the action on an inconsistent verified row',
    (tester) async {
      final work = attendance.FakeSource();
      work.workerRead = () async => [
        attendance.assignment()
          ..['assignment_status'] = 'completed'
          ..['verification_status'] = 'verified'
          ..['attendance_resolution'] = resolutionContext(
            resolution: auditFor({
              'p_request_id': attendance.other,
              'p_decision': 'confirmed_absent',
              'p_reason': 'Recorded absence',
            }),
          ),
      ];
      final router = GoRouter(
        initialLocation: '/work-attendance/${attendance.id}/evidence',
        routes: [
          workAttendanceRoute(
            evidence: true,
            source: work,
            checkAccess: () async => true,
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(work.changes.close);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('View Report'), findsNothing);
      expect(find.text('Server job'), findsOneWidget);
    },
  );
}
