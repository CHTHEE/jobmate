import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/hiring_membership_panel.dart';
import 'package:jobmate/features/applications/hiring_membership_status.dart';
import 'package:jobmate/features/applications/my_application_details_page.dart';

import 'fixtures/my_applications_source.dart';

Map<String, dynamic> membershipRow({
  String? status = 'active',
  bool recorded = true,
}) => {
  'contract_version': 1,
  'application_id': 'offer',
  'company_id': 'company-a',
  'user_id': 'seeker-a',
  'member_role': status == null ? null : 'member',
  'membership_status': status,
  'acceptance_recorded': recorded,
};

class MembershipSource extends TestMyApplicationsSource
    implements HiringMembershipStatusSource {
  int reads = 0;
  late Future<Map<String, dynamic>> Function() membership;
  @override
  Future<HiringMembershipSnapshot> loadMembership(String applicationId) async {
    reads++;
    return HiringMembershipSnapshot.fromJson(
      await membership(),
      applicationId: applicationId,
      userId: userId!,
    );
  }
}

void main() {
  test(
    'membership projection rejects foreign scope, malformed states and roles',
    () {
      for (final patch in <Map<String, dynamic>>[
        {'application_id': 'other'},
        {'user_id': 'other'},
        {'company_id': ''},
        {'membership_status': 'unknown'},
        {'member_role': 'administrator'},
        {'acceptance_recorded': 'true'},
        {'contract_version': 2},
      ]) {
        expect(
          () => HiringMembershipSnapshot.fromJson(
            {...membershipRow(), ...patch},
            applicationId: 'offer',
            userId: 'seeker-a',
          ),
          throwsFormatException,
        );
      }
    },
  );

  for (final status in ['active', 'inactive', 'revoked', null]) {
    testWidgets('authoritative membership $status is read-only', (
      tester,
    ) async {
      final source = MembershipSource()
        ..membership = () async => membershipRow(status: status);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HiringMembershipPanel(source: source, applicationId: 'offer'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Membership: ${status == null ? 'Not recorded' : status[0].toUpperCase() + status.substring(1)}',
        ),
        findsOneWidget,
      );
      if (status == 'active') {
        expect(
          find.textContaining('does not grant management'),
          findsOneWidget,
        );
      }
      if (status == 'revoked' || status == 'inactive') {
        expect(find.textContaining('will not reactivate'), findsOneWidget);
      }
      await tester.tap(find.text('Refresh membership'));
      await tester.pumpAndSettle();
      expect(source.reads, 2);
      expect(source.responses, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await source.changes.close();
    });
  }

  for (final width in [320.0, 1440.0]) {
    testWidgets('loading, error and retry fit $width and never accept again', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<Map<String, dynamic>>();
      final source = MembershipSource()..membership = () => pending.future;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 1100),
              textScaler: const TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: HiringMembershipPanel(
                  source: source,
                  applicationId: 'offer',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Checking company membership…'), findsOneWidget);
      pending.completeError(StateError('private backend failure'));
      await tester.pumpAndSettle();
      expect(
        find.text('Company membership could not be confirmed.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Do not accept the offer again'),
        findsOneWidget,
      );
      expect(find.textContaining('private backend'), findsNothing);
      source.membership = () async => membershipRow(recorded: false);
      await tester.tap(find.text('Retry membership check'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('hiring membership link needs company review'),
        findsOneWidget,
      );
      expect(source.responses, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await source.changes.close();
    });
  }

  testWidgets(
    'offer confirmation -> authoritative Hired -> membership, refresh revocation',
    (tester) async {
      final source = MembershipSource()
        ..rows = [applicationRow('offer', status: 'offered')]
        ..membership = () async => membershipRow();
      source.sendResponse = (_, action) async {
        source.rows = [applicationRow('offer', status: 'hired')];
        return 'hired';
      };
      await tester.pumpWidget(
        MaterialApp(
          home: MyApplicationDetailsPage(
            applicationId: 'offer',
            source: source,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(source.reads, 0);
      await tester.ensureVisible(find.text('Accept Offer'));
      await tester.tap(find.text('Accept Offer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm Accept Offer'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Membership: Active'));
      expect(find.text('Membership: Active'), findsOneWidget);
      expect(source.responses, [('offer', 'accept_offer')]);
      source.membership = () async => membershipRow(status: 'revoked');
      await tester.ensureVisible(find.text('Refresh membership'));
      await tester.tap(find.text('Refresh membership'));
      await tester.pumpAndSettle();
      expect(find.text('Membership: Revoked'), findsOneWidget);
      expect(source.responses, hasLength(1));
      // Parent refresh re-reads application AND membership without new acceptance.
      await tester.tap(find.byTooltip('Refresh application'));
      await tester.pumpAndSettle();
      expect(source.reads, 3);
      source.rows = [];
      source.switchAccount(null);
      await tester.pumpAndSettle();
      expect(find.text('Membership: Revoked'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await source.changes.close();
    },
  );
}
