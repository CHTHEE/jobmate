import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/work_attendance/work_attendance_routes.dart';
import 'package:jobmate/features/work_attendance/work_evidence_pages.dart';
import 'package:jobmate/features/work_attendance/work_verification_routes.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_attendance_repository_test.dart'
    show FakeSource, assignment, evidenceRow, id, other;

void main() {
  for (final employer in [false, true]) {
    final role = employer ? 'employer' : 'worker';
    final root = employer
        ? AppRoutes.workVerification
        : AppRoutes.workAttendance;
    group('$role evidence routes', () {
      late FakeSource source;
      late GoRouter router;
      late bool allowed;
      late Future<JobAccess> Function() companyAccess;
      late List<String> companyReads;
      late int metadataReads, roleChecks;

      GoRouter createRouter({String? initial}) => GoRouter(
        initialLocation: initial ?? '$root/$id/evidence',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: Text('Dashboard destination')),
          ),
          if (employer) ...[
            workVerificationRoute(
              source: source,
              checkAccess: () async => allowed,
              loadCompanyAccess: () => companyAccess(),
            ),
            workVerificationRoute(
              source: source,
              evidence: true,
              checkAccess: () async {
                roleChecks++;
                return allowed;
              },
              loadCompanyAccess: () => companyAccess(),
            ),
          ] else ...[
            workAttendanceRoute(
              source: source,
              checkAccess: () async => allowed,
            ),
            workAttendanceRoute(
              source: source,
              evidence: true,
              checkAccess: () async {
                roleChecks++;
                return allowed;
              },
            ),
          ],
        ],
      );

      setUp(() {
        source = FakeSource();
        allowed = true;
        companyReads = [];
        metadataReads = 0;
        roleChecks = 0;
        companyAccess = () async =>
            const JobAccess({'company_id': other}, null);
        final defaultCompany = source.companyRead;
        source.companyRead = (company) async {
          companyReads.add(company);
          final rows = await defaultCompany(company);
          return [
            for (final row in rows)
              {...row, 'verification_status': 'pending_review'},
          ];
        };
        source.evidenceRead = (assignmentId) async {
          expect(assignmentId, id);
          metadataReads++;
          return [evidenceRow()];
        };
      });
      tearDown(() async {
        router.dispose();
        await source.changes.close();
      });

      testWidgets(
        '$role direct URL and fresh refresh revalidate assignment; direct return is safe',
        (tester) async {
          router = createRouter(initial: '$root/$id/evidence?company_id=$id');
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          expect(find.text('file.pdf'), findsOneWidget);
          expect(roleChecks, 1);
          expect(metadataReads, 1);
          if (employer) expect(companyReads, [other]);
          expect(source.checkIns, 0);
          expect(source.checkOuts, 0);
          await tester.pumpWidget(const SizedBox());
          router.dispose();
          router = createRouter();
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          expect(metadataReads, 2);
          await tester.tap(
            find.text(
              employer ? 'Back to Work Verification' : 'Back to My Work Shifts',
            ),
          );
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, root);
          expect(find.text('View Evidence'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
          expect(source.changes.hasListener, isFalse);
        },
      );

      testWidgets(
        '$role card navigation and router Back preserve attendance controls',
        (tester) async {
          router = createRouter(initial: root);
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          if (!employer) expect(find.text('Check in'), findsOneWidget);
          await tester.ensureVisible(find.text('View Evidence'));
          await tester.tap(find.text('View Evidence'));
          await tester.pumpAndSettle();
          expect(
            GoRouterState.of(tester.element(find.byType(WorkEvidencePage)))
                .uri
                .path,
            '$root/$id/evidence',
          );
          expect(find.text('file.pdf'), findsOneWidget);
          router.pop();
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, root);
          expect(find.text('View Evidence'), findsOneWidget);
          if (!employer) expect(find.text('Check in'), findsOneWidget);
          expect(source.checkIns, 0);
          expect(source.checkOuts, 0);
          await tester.pumpWidget(const SizedBox());
        },
      );

      for (final assignment in ['invalid', other]) {
        testWidgets(
          '$role rejects assignment $assignment without reading metadata',
          (tester) async {
            router = createRouter(initial: '$root/$assignment/evidence');
            await tester.pumpWidget(MaterialApp.router(routerConfig: router));
            await tester.pumpAndSettle();
            expect(
              find.text(
                assignment == 'invalid'
                    ? 'Unable to load evidence'
                    : 'Evidence access denied',
              ),
              findsOneWidget,
            );
            expect(find.text('file.pdf'), findsNothing);
            expect(metadataReads, 0);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }

      testWidgets(
        '$role wrong/inactive role and signed-out access fail before list or evidence reads',
        (tester) async {
          allowed = false;
          router = createRouter();
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          expect(find.text('Page unavailable'), findsOneWidget);
          expect(source.calls, 0);
          source.switchAccount(null);
          await tester.pumpAndSettle();
          expect(find.text('Page unavailable'), findsOneWidget);
          expect(source.calls, 0);
          expect(roleChecks, 1);
          await tester.pumpWidget(const SizedBox());
        },
      );

      testWidgets(
        '$role account change clears metadata and rechecks role; logout stays isolated',
        (tester) async {
          router = createRouter();
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          expect(find.text('file.pdf'), findsOneWidget);
          allowed = false;
          source.switchAccount(other);
          await tester.pumpAndSettle();
          expect(find.text('file.pdf'), findsNothing);
          expect(find.text('Page unavailable'), findsOneWidget);
          expect(roleChecks, 2);
          expect(metadataReads, 1);
          source.switchAccount(null);
          await tester.pumpAndSettle();
          expect(find.text('file.pdf'), findsNothing);
          expect(metadataReads, 1);
          await tester.pumpWidget(const SizedBox());
          expect(source.changes.hasListener, isFalse);
        },
      );

      testWidgets(
        '$role account switch rejects pending metadata and revalidates ownership',
        (tester) async {
          final pending = Completer<List<Map<String, dynamic>>>();
          source.evidenceRead = (_) {
            metadataReads++;
            return pending.future;
          };
          router = createRouter();
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));
          for (var i = 0; i < 5; i++) {
            await tester.pump();
          }
          expect(metadataReads, 1);
          source.workerRead = () async => [];
          source.companyRead = (_) async => [];
          source.switchAccount(other);
          await tester.pumpAndSettle();
          pending.complete([evidenceRow()]);
          await tester.pumpAndSettle();
          expect(find.text('file.pdf'), findsNothing);
          expect(find.text('Evidence access denied'), findsOneWidget);
          expect(roleChecks, 2);
          expect(metadataReads, 1);
          await tester.pumpWidget(const SizedBox());
        },
      );

      testWidgets(
        '$role assignment parameter change disposes old viewer and denies unknown ID',
        (tester) async {
          router = createRouter();
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          expect(find.text('file.pdf'), findsOneWidget);
          router.go('$root/$other/evidence');
          await tester.pumpAndSettle();
          expect(find.text('file.pdf'), findsNothing);
          expect(find.text('Evidence access denied'), findsOneWidget);
          expect(metadataReads, 1);
          await tester.pumpWidget(const SizedBox());
          expect(source.changes.hasListener, isFalse);
        },
      );

      if (employer) {
        testWidgets(
          'employer direct pre-submission URL displays normal state without metadata RPC',
          (tester) async {
            source.companyRead = (company) async {
              companyReads.add(company);
              return [assignment(company: true)];
            };
            router = createRouter(initial: '$root/$id/evidence?company_id=$id');
            await tester.pumpWidget(MaterialApp.router(routerConfig: router));
            await tester.pumpAndSettle();
            expect(find.text('No evidence submitted yet'), findsOneWidget);
            expect(find.text('Evidence access denied'), findsNothing);
            expect(metadataReads, 0);
            expect(companyReads, [other]);
            router.go('$root/$other/evidence');
            await tester.pumpAndSettle();
            expect(find.text('Evidence access denied'), findsOneWidget);
            expect(find.text('No evidence submitted yet'), findsNothing);
            expect(metadataReads, 0);
            await tester.pumpWidget(const SizedBox());
          },
        );

        testWidgets(
          'employer account change resolves a new company without stale awaiting state',
          (tester) async {
            companyAccess = () async => JobAccess({
              'company_id': source.userId == id ? other : id,
            }, null);
            source.companyRead = (company) async {
              companyReads.add(company);
              return [
                assignment(company: true)
                  ..['verification_status'] = company == other
                      ? 'not_submitted'
                      : 'pending_review',
              ];
            };
            router = createRouter();
            await tester.pumpWidget(MaterialApp.router(routerConfig: router));
            await tester.pumpAndSettle();
            expect(find.text('No evidence submitted yet'), findsOneWidget);
            expect(metadataReads, 0);
            source.switchAccount(other);
            await tester.pumpAndSettle();
            expect(find.text('No evidence submitted yet'), findsNothing);
            expect(find.text('file.pdf'), findsOneWidget);
            expect(companyReads, [other, id]);
            expect(metadataReads, 1);
            source.switchAccount(null);
            await tester.pumpAndSettle();
            expect(find.text('file.pdf'), findsNothing);
            expect(find.text('No evidence submitted yet'), findsNothing);
            await tester.pumpWidget(const SizedBox());
          },
        );

        testWidgets(
          'employer ambiguous or denied company resolution never loads evidence',
          (tester) async {
            companyAccess = () async => throw const PostgrestException(
              message: 'Multiple memberships',
              code: 'PGRST116',
            );
            router = createRouter();
            await tester.pumpWidget(MaterialApp.router(routerConfig: router));
            await tester.pumpAndSettle();
            expect(find.text('Company access unavailable'), findsOneWidget);
            expect(companyReads, isEmpty);
            expect(metadataReads, 0);
            companyAccess = () async =>
                const JobAccess(null, 'Company access denied.');
            await tester.tap(find.text('Retry'));
            await tester.pumpAndSettle();
            expect(find.text('Company access denied.'), findsOneWidget);
            expect(metadataReads, 0);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    });
  }

  test('demo evidence URL remains separate', () {
    expect(AppRoutes.workEvidence, '/attendance/evidence');
    expect(
      AppRoutes.workAttendanceEvidence,
      '/work-attendance/:assignmentId/evidence',
    );
    expect(
      AppRoutes.workVerificationEvidence,
      '/work-verification/:assignmentId/evidence',
    );
  });
}
