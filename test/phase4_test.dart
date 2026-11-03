import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/phase4/phase4_store.dart';
import 'package:jobmate/features/phase4/evaluation_pages.dart';
import 'package:jobmate/features/phase4/reputation_page.dart';
import 'package:jobmate/features/phase4/payment_pages.dart';
import 'package:jobmate/features/phase4/admin_preview_pages.dart';
import 'package:jobmate/features/phase4/account_settings_page.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';

Future<Map<String, dynamic>> accountFixture() async => {
  'name': 'Account under test',
  'email': 'test@example.com',
  'role': 'job_seeker',
  'status': 'active',
  'phone_num': '',
  'profile_image_url': '',
};

void main() {
  test('Evaluation criteria match the specification exactly', () {
    expect(evaluationCriteria('job_seeker'), [
      'Communication',
      'Job Description Accuracy',
      'Professionalism',
      'Payment Reliability',
      'Work Environment',
      'Respect Towards Workers',
    ]);
    expect(evaluationCriteria('employer'), [
      'Communication',
      'Responsibility',
      'Teamwork',
      'Professionalism',
      'Adaptability',
      'Punctuality',
    ]);
  });
  test(
    'Completed assignments, all six ratings, feedback and duplicate guards',
    () {
      final store = Phase4Store();
      addTearDown(store.dispose);
      expect(
        () => store.submitEvaluation('sample-assignment-4', 'job_seeker'),
        throwsStateError,
      );
      expect(
        () => store.submitEvaluation('sample-assignment-1', 'job_seeker'),
        throwsStateError,
      );
      final draft = store.evaluationDraft('sample-assignment-1', 'job_seeker');
      for (final c in evaluationCriteria('job_seeker')) {
        draft.ratings[c] = 5;
      }
      draft.feedback = 'x' * 301;
      expect(
        () => store.submitEvaluation('sample-assignment-1', 'job_seeker'),
        throwsStateError,
      );
      draft.feedback = 'Sample work completed';
      draft.ratings['Communication'] = 0;
      expect(
        () => store.submitEvaluation('sample-assignment-1', 'job_seeker'),
        throwsStateError,
      );
      draft.ratings['Communication'] = 5;
      store.submitEvaluation('sample-assignment-1', 'job_seeker');
      expect(store.evaluation('sample-assignment-1', 'job_seeker')!.average, 5);
      expect(store.revealed('sample-assignment-1'), isFalse);
      expect(
        () => store.submitEvaluation('sample-assignment-1', 'job_seeker'),
        throwsStateError,
      );
      store.simulateCounterpart('sample-assignment-1', 'job_seeker');
      expect(store.revealed('sample-assignment-1'), isTrue);
      store.reportEvaluation(
        'sample-assignment-1',
        'job_seeker',
        'Inaccurate sample',
      );
      final id = store.evaluation('sample-assignment-1', 'employer')!.reportId!;
      expect(store.dispute(id)!.category, 'Evaluation');
      expect(
        () => store.reportEvaluation(
          'sample-assignment-1',
          'job_seeker',
          'Again',
        ),
        throwsStateError,
      );
    },
  );
  test('Payment records validate and store cents without moving money', () {
    final store = Phase4Store();
    addTearDown(store.dispose);
    expect(() => store.recordPayment(), throwsStateError);
    final d = store.paymentDraft
      ..assignmentId = 'sample-assignment-1'
      ..date = '2026-01-01'
      ..amount = '-1';
    expect(() => store.recordPayment(), throwsStateError);
    d.amount = '12.345';
    expect(() => store.recordPayment(), throwsStateError);
    d.amount = '180.25';
    d.date = '2026-02-31';
    expect(() => store.recordPayment(), throwsStateError);
    d.date = '2099-01-01';
    expect(() => store.recordPayment(), throwsStateError);
    d.date = '2026-01-01';
    d.reference = 'UNIQUE-SAMPLE';
    final p = store.recordPayment();
    expect(p.amount, 18025);
    expect(p.state, PaymentState.pending);
    expect(store.paymentDraft.amount, isEmpty);
    store.paymentDraft
      ..assignmentId = 'sample-assignment-1'
      ..date = '2026-01-01'
      ..amount = '180.25'
      ..reference = 'UNIQUE-SAMPLE';
    expect(() => store.recordPayment(), throwsStateError);
    store.confirmReceipt(p.id);
    expect(p.state, PaymentState.confirmed);
    expect(() => store.reportPayment(p.id, 'issue'), throwsStateError);
  });
  test(
    'Payment issues and evaluation reports create coherent demo disputes',
    () {
      final store = Phase4Store();
      addTearDown(store.dispose);
      store.reportPayment('demo-payment-1', 'Sample receipt not seen');
      final p = store.payment('demo-payment-1')!,
          d = store.dispute(store.payment('demo-payment-1')!.disputeId!)!;
      expect(p.state, PaymentState.disputed);
      expect(d.linkId, p.id);
      store.updateDispute(
        d.id,
        DisputeState.investigating,
        'Sample review started',
      );
      store.updateDispute(
        d.id,
        DisputeState.pendingInfo,
        'Provide a sample reference',
        party: 'Employer',
      );
      expect(d.requests.single, contains('Employer'));
      expect(d.state, DisputeState.pendingInfo);
      store.updateDispute(
        d.id,
        DisputeState.resolved,
        'Sample resolution, no financial correction',
      );
      expect(d.timeline.map((e) => e.$1), [
        DisputeState.open,
        DisputeState.investigating,
        DisputeState.pendingInfo,
        DisputeState.resolved,
      ]);
      expect(p.state, PaymentState.disputed);
      expect(
        () =>
            store.updateDispute(d.id, DisputeState.rejected, 'Another outcome'),
        throwsStateError,
      );
      expect(() => store.confirmReceipt(p.id), throwsStateError);
    },
  );
  test('Moderation is isolated to fictional accounts and jobs', () {
    final store = Phase4Store();
    addTearDown(store.dispose);
    expect(
      () => store.accountAction('sample-user-1', 'Suspended', ''),
      throwsStateError,
    );
    store.accountAction('sample-user-1', 'Suspended', 'Demo reason');
    expect(store.accounts.first.state, 'Suspended');
    store.accountAction('sample-user-1', 'Active', 'Demo reactivation');
    expect(store.accounts.first.state, 'Active');
    store.removeJob('sample-post-1', 'Sample policy issue');
    expect(store.jobs.first.state, 'Removed');
    expect(() => store.removeJob('sample-post-1', 'Again'), throwsStateError);
    expect(store.audit.length, 3);
    expect(adminReportHtml({'<script>': 1}), contains('&lt;script&gt;'));
    final generation = store.generation;
    store.profile('job_seeker').bio = 'draft';
    store.paymentDraft.amount = '200';
    store.notifications['sample'] = true;
    store.reset();
    expect(store.generation, generation + 1);
    expect(store.audit, isEmpty);
    expect(store.profile('job_seeker').bio, isEmpty);
    expect(store.paymentDraft.amount, isEmpty);
    expect(store.notifications, isEmpty);
  });
  testWidgets('Admin server gate shows loading, denied and retry states', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AdminPreviewGate(
          checkAccess: () {
            calls++;
            return calls == 1 ? pending.future : Future.value(false);
          },
          child: const Text('Protected content'),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to verify administrator access'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Access denied'), findsOneWidget);
    expect(find.text('Protected content'), findsNothing);
  });
  for (final width in [320.0, 768.0, 1440.0]) {
    for (final screen in [
      'Seeker Evaluations',
      'Employer Evaluations',
      'Rate Employer',
      'Rate Worker',
      'Evaluation Details',
      'Worker Reputation',
      'Company Reputation',
      'Record Payment',
      'Worker Payments',
      'Employer Payments',
      'Payment Details',
      'Employer Payment Details',
      'Admin Overview',
      'Admin Accounts',
      'Admin Jobs',
      'Admin Disputes',
      'Admin Reports',
      'Dispute Details',
      'Seeker Settings',
      'Employer Settings',
      'Admin Settings',
      'Edit Sample Profile',
      'Edit Sample Company',
    ]) {
      testWidgets('$screen responsive at $width', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = Phase4Store();
        addTearDown(store.dispose);
        final child = switch (screen) {
          'Seeker Evaluations' => EvaluationsPage(store: store),
          'Employer Evaluations' => EvaluationsPage(
            employer: true,
            store: store,
          ),
          'Rate Employer' => EvaluationFormPage(
            assignmentId: 'sample-assignment-1',
            store: store,
          ),
          'Rate Worker' => EvaluationFormPage(
            assignmentId: 'sample-assignment-1',
            employer: true,
            store: store,
          ),
          'Evaluation Details' => EvaluationDetailPage(
            assignmentId: 'sample-assignment-2',
            store: store,
          ),
          'Worker Reputation' => ReputationPage(store: store),
          'Company Reputation' => ReputationPage(employer: true, store: store),
          'Record Payment' => PaymentRecordPage(store: store),
          'Worker Payments' => PaymentHistoryPage(store: store),
          'Employer Payments' => PaymentHistoryPage(
            employer: true,
            store: store,
          ),
          'Payment Details' => PaymentDetailPage(
            paymentId: 'demo-payment-1',
            store: store,
          ),
          'Employer Payment Details' => PaymentDetailPage(
            paymentId: 'demo-payment-3',
            employer: true,
            store: store,
          ),
          'Admin Overview' => AdminPreviewPage(store: store),
          'Admin Accounts' => AdminPreviewPage(
            section: 'Accounts',
            store: store,
          ),
          'Admin Jobs' => AdminPreviewPage(section: 'Jobs', store: store),
          'Admin Disputes' => AdminPreviewPage(
            section: 'Disputes',
            store: store,
          ),
          'Admin Reports' => AdminPreviewPage(section: 'Reports', store: store),
          'Dispute Details' => DisputeDetailPage(
            disputeId: 'demo-case-1',
            store: store,
          ),
          'Seeker Settings' => AccountSettingsPage(
            store: store,
            loadAccount: accountFixture,
          ),
          'Employer Settings' => AccountSettingsPage(
            role: 'employer',
            store: store,
            loadAccount: accountFixture,
          ),
          'Admin Settings' => AccountSettingsPage(
            role: 'administrator',
            store: store,
            loadAccount: accountFixture,
          ),
          'Edit Sample Profile' => ExtendedProfilePage(store: store),
          _ => ExtendedProfilePage(employer: true, store: store),
        };
        final router = GoRouter(
          routes: [GoRoute(path: '/', builder: (_, _) => child)],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(theme: JobMateTheme.light(), routerConfig: router),
        );
        await tester.pumpAndSettle();
        if (screen.endsWith('Settings')) {
          expect(find.text('Your real account'), findsOneWidget);
          expect(find.text('Profile completion: 50%'), findsOneWidget);
        } else {
          expect(find.text('DEMO / PREVIEW'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        if (screen == 'Worker Reputation') {
          await tester.tap(find.byType(SwitchListTile));
          await tester.pumpAndSettle();
          expect(find.text('Not enough verified data'), findsOneWidget);
        }
        if (screen == 'Worker Payments') {
          await tester.enterText(find.byType(TextField).first, 'no match');
          await tester.pumpAndSettle();
          expect(find.text('No payment records found'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets(
    'Rating confirmation produces a demo success and visibility state',
    (tester) async {
      final store = Phase4Store();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: JobMateTheme.light(),
          home: EvaluationFormPage(
            assignmentId: 'sample-assignment-1',
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Submit Evaluation (demo)'));
      await tester.tap(find.text('Submit Evaluation (demo)'));
      await tester.pumpAndSettle();
      expect(find.text('Rate all six criteria from 1 to 5.'), findsOneWidget);
      for (final c in evaluationCriteria('job_seeker')) {
        final choice = find.byTooltip('$c: 5 out of 5');
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Submit Evaluation (demo)'));
      await tester.tap(find.text('Submit Evaluation (demo)'));
      await tester.pumpAndSettle();
      expect(store.evaluation('sample-assignment-1', 'job_seeker'), isNull);
      await tester.tap(find.text('Confirm demo action'));
      await tester.pumpAndSettle();
      expect(find.text('Demo evaluation recorded'), findsOneWidget);
      expect(store.revealed('sample-assignment-1'), isFalse);
    },
  );
}
