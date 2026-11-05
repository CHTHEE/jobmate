import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jobmate/features/admin/company_review_details.dart';
import 'package:jobmate/features/admin/company_review_gateway.dart';
import 'package:jobmate/features/admin/company_review_page.dart';

Map<String, dynamic> request(int index) => {
  'request_id': 'request-$index',
  'company_id': 'company-$index',
  'company_name': 'Company $index',
  'submitted_by': 'owner-$index',
  'profile_snapshot': {
    'registration_number': 'SSM-$index',
    'location': 'Kuala Lumpur',
  },
  'storage_path': 'owner-$index/document.pdf',
  'original_name': 'support-$index.pdf',
  'mime_type': 'application/pdf',
  'size_bytes': 2048,
  'submitted_at': '2026-11-01T08:00:00Z',
};

// Fixtures are confined to tests; the application uses the authenticated gateway.
class ReviewFixture implements CompanyReviewGateway {
  ReviewFixture(int count) : rows = List.generate(count, request);
  final List<Map<String, dynamic>> rows;
  final offsets = <int>[];
  final limits = <int>[];
  final decisions = <(String, String, String?)>[];
  final downloads = <bool>[];
  Object? listError;
  Object? reviewError;
  bool documentDenied = false;
  bool sessionChanged = false;
  Completer<void>? pendingLoad;
  Completer<void>? pendingReview;

  @override
  void checkSession() {
    if (sessionChanged) throw StateError('Your signed-in account has changed.');
  }

  @override
  Future<List<Map<String, dynamic>>> pending({
    required int limit,
    required int offset,
  }) async {
    offsets.add(offset);
    limits.add(limit);
    await pendingLoad?.future;
    if (listError != null) throw listError!;
    return rows.skip(offset).take(limit).toList();
  }

  @override
  Future<String> review({
    required String requestId,
    required String decision,
    String? comment,
  }) async {
    decisions.add((requestId, decision, comment));
    await pendingReview?.future;
    rows.removeWhere((row) => row['request_id'] == requestId);
    if (reviewError != null) throw reviewError!;
    return decision;
  }

  @override
  Future<Uri> documentUrl(String path, {required bool download}) async {
    downloads.add(download);
    if (documentDenied) throw const StorageException('Permission denied');
    return Uri.parse('https://example.test/signed.pdf?download=$download');
  }
}

void main() {
  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'Logo preview and permission retry adapt at $width with large text',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final logos = ReviewFixture(1)..documentDenied = true;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: CompanyReviewPage(
              gateway: ReviewFixture(0),
              logoGateway: logos,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Logo changes'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('View Details'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('View Details'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Unable to load private images.'),
          findsOneWidget,
        );
        logos.documentDenied = false;
        await tester.tap(find.text('Refresh images'));
        await tester.pumpAndSettle();
        expect(find.text('Current photo at submission'), findsOneWidget);
        expect(find.text('Proposed photo'), findsOneWidget);
        expect(logos.downloads.every((download) => !download), isTrue);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Logo queue uses separate gateway and cannot switch during a review',
    (tester) async {
      final documents = ReviewFixture(1);
      final logos = ReviewFixture(1);
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyReviewPage(gateway: documents, logoGateway: logos),
        ),
      );
      await tester.pumpAndSettle();
      expect(logos.offsets, isEmpty);
      await tester.tap(find.text('Logo changes'));
      await tester.pumpAndSettle();
      expect(logos.offsets, [0]);
      expect(find.text('Pending logo changes'), findsOneWidget);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(find.text('Approve company logo?'), findsOneWidget);
      logos.pendingReview = Completer<void>();
      await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
      await tester.pump();
      expect(documents.decisions, isEmpty);
      expect(logos.decisions, [('request-0', 'verified', '')]);
      logos.pendingReview!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('No logo changes are waiting on this page.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Company documents'));
      await tester.pumpAndSettle();
      expect(find.text('Company 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> mount(WidgetTester tester, ReviewFixture data) async {
    await tester.pumpWidget(
      MaterialApp(home: CompanyReviewPage(gateway: data)),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 768.0, 1440.0]) {
    testWidgets('Queue displays pending submissions and details at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = ReviewFixture(1);
      await mount(tester, data);
      expect(find.text('Company Verification'), findsOneWidget);
      expect(find.text('Company 0'), findsOneWidget);
      expect(find.text('Pending review'), findsOneWidget);
      expect(data.limits, [21]);
      expect(tester.takeException(), isNull, reason: 'Pending list layout');
      await tester.tap(find.text('View Details'));
      await tester.pumpAndSettle();
      expect(find.text('company-0'), findsOneWidget);
      expect(find.text('SSM-0'), findsOneWidget);
      expect(find.text('2.0 KiB (2048 bytes)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Queue shows loading, permission error, retry and empty state', (
    tester,
  ) async {
    final data = ReviewFixture(0)..pendingLoad = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(home: CompanyReviewPage(gateway: data)),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    data.listError = const PostgrestException(
      message: 'Review permission required',
    );
    data.pendingLoad!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Review permission required'), findsOneWidget);
    data.listError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.text('No company applications are waiting on this page.'),
      findsOneWidget,
    );
  });
  testWidgets('Queue paginates using 21-row lookahead and refreshes', (
    tester,
  ) async {
    final data = ReviewFixture(21);
    await mount(tester, data);
    await tester.scrollUntilVisible(find.text('Next'), 600);
    await tester.ensureVisible(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(data.offsets, [0, 20]);
    expect(find.text('Company 20'), findsOneWidget);
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(data.offsets.last, 20);
    await tester.ensureVisible(find.text('Previous'));
    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    expect(data.offsets.last, 0);
  });
  testWidgets(
    'Approve supports an optional comment and prevents duplicate submission',
    (tester) async {
      final data = ReviewFixture(1)..pendingReview = Completer<void>();
      await mount(tester, data);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        '  Registration checked  ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
      await tester.pump();
      expect(data.decisions, [
        ('request-0', 'verified', 'Registration checked'),
      ]);
      expect(find.text('Saving company review...'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(data.decisions.length, 1);
      data.pendingReview!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('No company applications are waiting on this page.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('Reject requires a reason and submits rejected decision', (
    tester,
  ) async {
    final data = ReviewFixture(1);
    await mount(tester, data);
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reject').last);
    await tester.pump();
    expect(find.text('Enter a reason to continue.'), findsOneWidget);
    expect(data.decisions, isEmpty);
    await tester.enterText(
      find.byType(TextFormField),
      '  Certificate unreadable  ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Reject').last);
    await tester.pumpAndSettle();
    expect(data.decisions, [
      ('request-0', 'rejected', 'Certificate unreadable'),
    ]);
  });
  testWidgets('Stale request errors are shown and the queue is reloaded', (
    tester,
  ) async {
    final data = ReviewFixture(1)
      ..reviewError = const PostgrestException(
        message: 'This Company request is no longer pending.',
      );
    await mount(tester, data);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await tester.pumpAndSettle();
    expect(data.decisions.single.$3, '');
    expect(
      find.text('This Company request is no longer pending.'),
      findsOneWidget,
    );
    expect(data.offsets.length, 2);
    expect(find.text('Company 0'), findsNothing);
  });
  testWidgets(
    'Private PDF access prepares view/download URLs and expires them',
    (tester) async {
      final data = ReviewFixture(1);
      Uri? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyReviewDetails(
              request: request(0),
              gateway: data,
              openUrl: (uri) async {
                opened = uri;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Prepare secure PDF access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prepare secure PDF access'));
      await tester.pumpAndSettle();
      expect(data.downloads, [false, true]);
      await tester.ensureVisible(find.text('Download PDF'));
      await tester.tap(find.text('Download PDF'));
      await tester.pumpAndSettle();
      expect(opened?.queryParameters['download'], 'true');
      await tester.pump(const Duration(seconds: 51));
      expect(find.text('Prepare secure PDF access'), findsOneWidget);
      expect(find.text('View PDF'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Storage permission failures remain visible and retryable', (
    tester,
  ) async {
    final data = ReviewFixture(1)..documentDenied = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyReviewDetails(request: request(0), gateway: data),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Prepare secure PDF access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prepare secure PDF access'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Unable to access the private PDF'),
      findsOneWidget,
    );
    expect(find.text('View PDF'), findsNothing);
    expect(find.text('Prepare secure PDF access'), findsOneWidget);
  });

  testWidgets('Approval may be confirmed without a review comment', (
    tester,
  ) async {
    final data = ReviewFixture(1);
    await mount(tester, data);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await tester.pumpAndSettle();
    expect(data.decisions, [('request-0', 'verified', '')]);
  });

  testWidgets('Review cannot exceed the backend 2000-character limit', (
    tester,
  ) async {
    final data = ReviewFixture(1);
    await mount(tester, data);
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    // 1001 graphemes but 2002 Unicode code points, which exceeds SQL length().
    await tester.enterText(
      find.byType(TextFormField),
      List.filled(1001, 'a\u0301').join(),
    );
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Reject').last,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Reject').last);
    await tester.pump();
    expect(find.text('Use 2000 characters or fewer.'), findsOneWidget);
    expect(data.decisions, isEmpty);
  });

  testWidgets('Changed sessions cannot open a review decision dialog', (
    tester,
  ) async {
    final data = ReviewFixture(1);
    await mount(tester, data);
    data.sessionChanged = true;
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(find.text('Your signed-in account has changed.'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(data.decisions, isEmpty);
  });
}
