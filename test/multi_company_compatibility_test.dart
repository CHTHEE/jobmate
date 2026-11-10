import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:jobmate/features/company/company_membership_selection.dart';
import 'package:jobmate/features/admin/user_membership_details.dart';
import 'package:jobmate/features/admin/user_management_gateway.dart';
import 'package:jobmate/features/admin/user_account_details_dialog.dart';

class _MembershipGateway implements UserManagementGateway {
  @override
  Future<Map<String, dynamic>?> details(String userId) async => {
    'user_id': userId,
    'name': 'Worker',
    'account_status': 'active',
    'memberships': [
      {'company_id': 'a', 'company_name': 'Alpha', 'member_role': 'owner'},
      {'company_id': 'b', 'company_name': 'Beta', 'member_role': 'member'},
    ],
  };
  @override
  Future<Map<String, dynamic>?> directoryDetails(String userId) async => {
    'user_id': userId,
    'name': 'Worker',
    'account_status': 'active',
  };
  @override
  Future<List<Map<String, dynamic>>> history(String userId, int offset) async =>
      [];
  @override
  Future<void> changeStatus(
    String userId,
    String action,
    String? reason,
  ) async {}
}

void main() {
  testWidgets(
    'Admin displays both affiliations without exposing them to directory-only viewers',
    (tester) async {
      for (final canManage in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: UserAccountDetailsDialog(
                key: ValueKey(canManage),
                userId: 'u',
                gateway: _MembershipGateway(),
                canManage: canManage,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Alpha'),
          canManage ? findsOneWidget : findsNothing,
        );
        expect(
          find.textContaining('Beta'),
          canManage ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
  Map<String, dynamic> membership(
    String company,
    String role, [
    String? status,
  ]) => {
    'company_id': company,
    'member_role': role,
    'membership_status': ?status,
  };
  test('legacy employer and owner contexts remain usable', () {
    for (final role in ['owner', 'employer']) {
      expect(
        selectCompanyProfileMembership([membership('a', role)])?['company_id'],
        'a',
      );
    }
  });
  test('ordinary affiliations do not block onboarding or select a company', () {
    expect(
      selectCompanyProfileMembership([
        membership('a', 'member'),
        membership('b', 'member'),
      ]),
      isNull,
    );
  });
  test(
    'owner context wins over other affiliations without granting access',
    () {
      expect(
        selectCompanyProfileMembership([
          membership('b', 'employer'),
          membership('a', 'owner'),
          membership('c', 'member'),
        ])?['company_id'],
        'a',
      );
    },
  );
  test('ambiguous employers and duplicate owners fail closed', () {
    for (final role in ['employer', 'owner']) {
      expect(
        () => selectCompanyProfileMembership([
          membership('a', role),
          membership('b', role),
        ]),
        throwsFormatException,
      );
    }
  });
  test('inactive revoked and unknown lifecycle never select company', () {
    for (final status in ['inactive', 'revoked', 'unknown']) {
      expect(
        selectCompanyProfileMembership([membership('a', 'employer', status)]),
        isNull,
      );
    }
  });
  Map<String, dynamic> account(String? company, [String? role]) => {
    'user_id': 'u',
    'name': 'Worker',
    'account_status': 'active',
    'company_id': company,
    'company_name': company,
    'member_role': role,
  };
  test('Admin preserves zero and single membership contracts', () {
    expect(normalizeUserMembershipDetails([], 'u'), isNull);
    expect(
      normalizeUserMembershipDetails([account(null)], 'u')?['memberships'],
      isEmpty,
    );
    expect(
      normalizeUserMembershipDetails([
        account('a', 'owner'),
      ], 'u')?['company_id'],
      'a',
    );
  });
  test(
    'Admin retains every authorized affiliation without arbitrary selection',
    () {
      final data = normalizeUserMembershipDetails([
        account('a', 'owner'),
        account('b', 'member'),
      ], 'u')!;
      expect(data['company_id'], isNull);
      expect(data['memberships'], hasLength(2));
    },
  );
  test('Admin rejects foreign inconsistent duplicate and malformed rows', () {
    for (final rows in [
      [
        account('a', 'member'),
        {...account('b', 'member'), 'user_id': 'other'},
      ],
      [
        account('a', 'member'),
        {...account('b', 'member'), 'name': 'Different'},
      ],
      [account('a', 'member'), account('a', 'member')],
      [account(null), account('a', 'member')],
      [account('a', 'administrator')],
    ]) {
      expect(
        () => normalizeUserMembershipDetails(rows, 'u'),
        throwsFormatException,
      );
    }
  });
}
