import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jobmate/features/admin/user_account_details_dialog.dart';
import 'package:jobmate/features/admin/user_management_gateway.dart';

class _Gateway implements UserManagementGateway {
  String status = 'active';
  final calls = <(String, String, String?)>[];
  bool deny = false;
  bool permissionDenied = false;

  @override
  Future<Map<String, dynamic>?> directoryDetails(String userId) async => {
    'user_id': userId,
    'name': 'Synthetic user',
    'role': 'job_seeker',
    'account_status': status,
    'verification_status': 'pending',
    'created_at': '2026-01-01T12:00:00Z',
  };

  @override
  Future<Map<String, dynamic>?> details(String userId) async {
    if (permissionDenied) {
      throw PostgrestException(
        message: 'User Management permission is required.',
        code: 'P0001',
      );
    }
    if (deny) throw StateError('Denied');
    return {
      'name': 'Synthetic user',
      'email': 'test@example.invalid',
      'role': 'job_seeker',
      'account_status': status,
      'verification_status': 'pending',
    };
  }

  @override
  Future<List<Map<String, dynamic>>> history(String userId, int offset) async =>
      [
        if (calls.isNotEmpty)
          {
            'action': calls.last.$2,
            'reason': calls.last.$3,
            'actor_name': 'Admin',
            'performed_at': '2026-01-01',
          },
      ];

  @override
  Future<void> changeStatus(
    String userId,
    String action,
    String? reason,
  ) async {
    calls.add((userId, action, reason));
    status = action == 'suspend' ? 'suspended' : 'active';
  }
}

void main() {
  testWidgets('suspension needs a reason and refreshes saved history', (
    tester,
  ) async {
    final gateway = _Gateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserAccountDetailsDialog(userId: 'user-1', gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Name: Synthetic user'), findsOneWidget);
    await tester.tap(find.text('Suspend account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a reason.'), findsOneWidget);
    expect(gateway.calls, isEmpty);
    await tester.enterText(find.byType(TextFormField), 'Repeated abuse');
    await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
    await tester.pumpAndSettle();
    expect(gateway.calls, [('user-1', 'suspend', 'Repeated abuse')]);
    expect(find.text('Account status: suspended'), findsOneWidget);
    expect(find.text('Reactivate account'), findsOneWidget);
    expect(find.text('suspend'), findsOneWidget);
    expect(find.textContaining('Reason: Repeated abuse'), findsOneWidget);
  });

  testWidgets('denied details do not offer account actions', (tester) async {
    final gateway = _Gateway()..deny = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserAccountDetailsDialog(userId: 'user-1', gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to load account details. Please retry.'),
      findsOneWidget,
    );
    expect(find.text('Suspend account'), findsNothing);
    expect(gateway.calls, isEmpty);
  });

  testWidgets('read-only account details hide contact, history and actions', (
    tester,
  ) async {
    final gateway = _Gateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserAccountDetailsDialog(
            userId: 'user-1',
            gateway: gateway,
            canManage: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Name: Synthetic user'), findsOneWidget);
    expect(find.text('Role: job_seeker'), findsOneWidget);
    expect(find.text('Email: test@example.invalid'), findsNothing);
    expect(find.text('Suspend account'), findsNothing);
    expect(find.text('Reactivate account'), findsNothing);
    expect(find.text('Account restriction history'), findsNothing);
  });

  testWidgets('missing User Management permission is explained clearly', (
    tester,
  ) async {
    final gateway = _Gateway()..permissionDenied = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserAccountDetailsDialog(userId: 'user-1', gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('You do not have access to these account details.'),
      findsOneWidget,
    );
    expect(find.text('Suspend account'), findsNothing);
    expect(find.text('Reactivate account'), findsNothing);
    expect(gateway.calls, isEmpty);
  });

  testWidgets('reactivation requires and submits a reason', (tester) async {
    final gateway = _Gateway()..status = 'suspended';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserAccountDetailsDialog(userId: 'user-2', gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reactivate account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reactivate'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a reason.'), findsOneWidget);
    expect(gateway.calls, isEmpty);
    await tester.enterText(find.byType(TextFormField), 'Review completed');
    await tester.tap(find.widgetWithText(FilledButton, 'Reactivate'));
    await tester.pumpAndSettle();
    expect(gateway.calls, [('user-2', 'reactivate', 'Review completed')]);
    expect(find.text('Account status: active'), findsOneWidget);
    expect(find.text('reactivate'), findsOneWidget);
    expect(find.textContaining('Reason: Review completed'), findsOneWidget);
  });

  testWidgets('cancelling a typed reason asks before discarding', (
    tester,
  ) async {
    final gateway = _Gateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserAccountDetailsDialog(userId: 'user-1', gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspend account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Reason in progress');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard the reason?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Reason in progress'), findsOneWidget);
    expect(gateway.calls, isEmpty);
  });
}
