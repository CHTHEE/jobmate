import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_repository.dart';
import 'package:jobmate/features/work_attendance/work_verification_pages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, id, other;

void main() {
  late FakeSource source;
  late WorkAttendanceRepository repository;
  late Future<JobAccess> Function() access;
  late List<String> companyCalls;
  setUp(() {
    source = FakeSource();
    repository = WorkAttendanceRepository(source);
    companyCalls = [];
    source.companyRead = (company) async {
      companyCalls.add(company);
      return [assignment(company: true)];
    };
    source.workerRead = () => throw StateError('Worker RPC must not run');
    source.evidenceRead = (_) => throw StateError('Evidence RPC must not run');
    access = () async => const JobAccess({'company_id': id}, null);
  });
  tearDown(() async {
    repository.dispose();
    await source.changes.close();
  });
  Future<void> showPage(WidgetTester tester, {String company = id}) =>
      tester.pumpWidget(
        MaterialApp(
          home: WorkVerificationPage(
            repository: repository,
            companyId: company,
            loadAccess: () => access(),
          ),
        ),
      );

  testWidgets('access check, list loading, connection error, retry and empty', (
    tester,
  ) async {
    final checking = Completer<JobAccess>();
    access = () => checking.future;
    await showPage(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(source.calls, 0);
    final pending = Completer<List<Map<String, dynamic>>>();
    source.companyRead = (_) => pending.future;
    checking.complete(const JobAccess({'company_id': id}, null));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(source.calls, 1);
    pending.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check your connection'), findsOneWidget);
    source.companyRead = (_) async => [];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No company work assignments'), findsOneWidget);
    expect(source.calls, 2);
  });

  testWidgets(
    'populated projection, MYT rollover and no review/write actions',
    (tester) async {
      source.companyRead = (company) async {
        companyCalls.add(company);
        return [
          assignment(company: true)
            ..['scheduled_start'] = '2026-11-05T20:30:00Z'
            ..['scheduled_end'] = '2026-11-06T05:00:00Z'
            ..['assignment_status'] = 'awaiting_verification'
            ..['verification_status'] = 'pending_review',
        ];
      };
      await showPage(tester);
      await tester.pumpAndSettle();
      for (final text in [
        'Server job',
        'Assigned worker',
        'Scheduled start: 06/11/2026 04:30 MYT',
        'Scheduled end: 06/11/2026 13:00 MYT',
        'Workplace: Server location',
        'Pending Review',
        'Action needed: review evidence',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(companyCalls, [id]);
      expect(find.text('Server company'), findsNothing);
      expect(find.textContaining('Checked in:'), findsNothing);
      for (final text in [
        'Verify Work',
        'Review evidence',
        'Create assignment',
        'View details',
      ]) {
        expect(find.text(text), findsNothing);
      }
      await tester.tap(find.byTooltip('Refresh company assignments'));
      await tester.pumpAndSettle();
      expect(companyCalls, [id, id]);
    },
  );

  testWidgets('denied or mismatched access never calls assignment RPC', (
    tester,
  ) async {
    for (final denied in [
      const JobAccess(null, 'An active employer account is required.'),
      const JobAccess({'company_id': id}, 'Company verification: pending'),
      const JobAccess({'company_id': other}, null),
    ]) {
      access = () async => denied;
      await showPage(tester);
      await tester.pumpAndSettle();
      expect(find.text('Company access denied'), findsOneWidget);
      expect(find.text('Server job'), findsNothing);
      expect(source.calls, 0);
    }
  });

  testWidgets('invalid company and signed-out session fail closed', (
    tester,
  ) async {
    var checks = 0;
    access = () async {
      checks++;
      return const JobAccess({'company_id': id}, null);
    };
    await showPage(tester, company: '');
    await tester.pumpAndSettle();
    expect(
      find.text('A valid authorized company ID is required.'),
      findsOneWidget,
    );
    expect(source.calls, 0);
    expect(checks, 0);
    source.switchAccount(null);
    await showPage(tester);
    await tester.pumpAndSettle();
    expect(find.text('Sign in required'), findsOneWidget);
    expect(source.calls, 0);
    expect(checks, 0);
  });

  for (final error in [
    const AuthException('expired'),
    const PostgrestException(
      message: 'Not authorized to view company assignments',
      code: 'P0001',
    ),
  ]) {
    testWidgets('RPC access error ${error.runtimeType}', (tester) async {
      source.companyRead = (_) async => throw error;
      await showPage(tester);
      await tester.pumpAndSettle();
      expect(
        find.text(
          error is AuthException ? 'Sign in required' : 'Company access denied',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Server job'), findsNothing);
    });
  }

  testWidgets('company change ignores stale list and stale access checks', (
    tester,
  ) async {
    final oldRows = Completer<List<Map<String, dynamic>>>();
    source.companyRead = (_) => oldRows.future;
    await showPage(tester);
    await tester.pump();
    final newAccess = Completer<JobAccess>();
    access = () => newAccess.future;
    await showPage(tester, company: other);
    expect(find.text('Server job'), findsNothing);
    source.companyRead = (company) async {
      companyCalls.add(company);
      return [
        assignment(company: true)..['job_title'] = 'Selected company job',
      ];
    };
    newAccess.complete(const JobAccess({'company_id': other}, null));
    await tester.pumpAndSettle();
    oldRows.complete([assignment(company: true)]);
    await tester.pumpAndSettle();
    expect(find.text('Selected company job'), findsOneWidget);
    expect(find.text('Server job'), findsNothing);
    expect(companyCalls, [other]);

    final staleAccess = Completer<JobAccess>();
    access = () => staleAccess.future;
    await showPage(tester);
    access = () async => const JobAccess({'company_id': other}, null);
    await showPage(tester, company: other);
    await tester.pumpAndSettle();
    staleAccess.complete(const JobAccess({'company_id': id}, null));
    await tester.pumpAndSettle();
    expect(repository.company.scopeId, other);
    expect(find.text('Selected company job'), findsOneWidget);
  });

  testWidgets(
    'account switch reauthorizes explicit company; logout clears rows',
    (tester) async {
      await showPage(tester);
      await tester.pumpAndSettle();
      expect(find.text('Server job'), findsOneWidget);
      final old = Completer<List<Map<String, dynamic>>>();
      source.companyRead = (_) => old.future;
      await tester.tap(find.byTooltip('Refresh company assignments'));
      await tester.pump();
      access = () async => const JobAccess({'company_id': other}, null);
      source.switchAccount(other);
      await tester.pumpAndSettle();
      expect(find.text('Company access denied'), findsOneWidget);
      old.complete([assignment(company: true)]);
      await tester.pumpAndSettle();
      expect(find.text('Server job'), findsNothing);
      source.switchAccount(null);
      await tester.pumpAndSettle();
      expect(find.text('Sign in required'), findsOneWidget);
      expect(find.text('Server job'), findsNothing);
    },
  );

  testWidgets('stale access errors ignored after account switch', (
    tester,
  ) async {
    final pending = Completer<JobAccess>();
    access = () => pending.future;
    await showPage(tester);
    access = () async => const JobAccess(null, 'Employer access denied.');
    source.switchAccount(other);
    await tester.pumpAndSettle();
    pending.completeError(Exception('old access failure'));
    await tester.pumpAndSettle();
    expect(find.text('Employer access denied.'), findsOneWidget);
    expect(find.textContaining('Unable to check company access'), findsNothing);
    expect(source.calls, 0);
  });

  testWidgets(
    'access connection failure can retry and disposal preserves repository ownership',
    (tester) async {
      access = () async => throw Exception('offline');
      await showPage(tester);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Unable to check company access'),
        findsOneWidget,
      );
      access = () async => const JobAccess({'company_id': id}, null);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Server job'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await repository.loadCompanyAssignments(id);
      expect(repository.company.rows, hasLength(1));
    },
  );

  for (final width in [320.0, 840.0, 1440.0]) {
    testWidgets('responsive company list at $width with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      source.companyRead = (_) async => [
        assignment(company: true)
          ..['job_title'] = List.filled(12, 'Long job title').join(' ')
          ..['verification_status'] = 'more_evidence_required',
      ];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: WorkVerificationPage(
            repository: repository,
            companyId: id,
            loadAccess: access,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('More Evidence Required'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
