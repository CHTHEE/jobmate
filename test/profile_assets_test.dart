import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jobmate/features/company/company_logo_editor.dart';
import 'package:jobmate/features/home/dashboard_content.dart';
import 'package:jobmate/features/profile/resume_page.dart';
import 'package:jobmate/features/profile/resume_repository.dart';
import 'package:jobmate/shared/widgets/app_workspace.dart';
import 'package:jobmate/shared/widgets/loading_overlay.dart';

Uint8List pdf() => Uint8List.fromList('%PDF-1.4 fixture'.codeUnits);
XFile pdfFile(String name) => XFile.fromData(pdf(), name: name, path: name);
Uint8List png() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jBz0AAAAASUVORK5CYII=',
);

class TestResumes implements ResumeGateway {
  String role = 'job_seeker', status = 'active', verification = 'pending';
  bool validSession = true, loseFirstResponse = false;
  int uploads = 0;
  final saves = <String>[];
  final versions = <ResumeFile>[];
  Completer<void>? pending;
  Object? listError;
  @override
  void checkSession() {
    if (!validSession) throw StateError('Account changed.');
  }

  @override
  Future<Map<String, dynamic>> loadAccount() async => {
    'role': role,
    'status': status,
    'verification_status': verification,
  };
  @override
  Future<List<ResumeFile>> list() async {
    if (listError != null) throw listError!;
    return List.of(versions);
  }

  @override
  Future<void> upload(ResumeUpload file) async {
    checkSession();
    uploads++;
  }

  @override
  Future<void> save(ResumeUpload file) async {
    saves.add(file.id);
    if (pending != null) await pending!.future;
    checkSession();
    if (!versions.any((r) => r.id == file.id)) {
      versions.insert(
        0,
        ResumeFile(
          id: file.id,
          path: 'own/${file.id}/document.pdf',
          name: file.name,
          size: file.bytes.length,
          bucket: 'jobmate-resumes',
          uploadedAt: DateTime.now(),
        ),
      );
    }
    if (loseFirstResponse && saves.length == 1) {
      throw Exception('Lost response');
    }
  }

  @override
  Future<Uri> documentUrl(ResumeFile file) async =>
      Uri.parse('https://example.com/own-resume');
}

class TestLogos implements CompanyLogoGateway {
  int uploads = 0;
  final uploadAttempts = <CompanyLogoUpload>[];
  final saves = <CompanyLogoUpload>[];
  bool loseFirstResponse = false, validSession = true;
  bool commitBeforeLostResponse = false;
  Object? uploadError;
  Completer<void>? pending;
  Map<String, dynamic>? request;
  bool statusUnavailable = false;
  @override
  Future<Map<String, dynamic>?> latestRequest() async {
    checkSession();
    if (statusUnavailable) throw Exception('Unavailable');
    return request;
  }

  @override
  void checkSession() {
    if (!validSession) throw StateError('Account changed.');
  }

  @override
  Future<void> upload(CompanyLogoUpload image) async {
    checkSession();
    uploads++;
    uploadAttempts.add(image);
    if (uploadError != null) throw uploadError!;
  }

  @override
  Future<String> save(CompanyLogoUpload image) async {
    saves.add(image);
    if (pending != null) await pending!.future;
    checkSession();
    if (commitBeforeLostResponse) {
      request = {'request_id': image.id, 'status': 'pending'};
    }
    if (loseFirstResponse && saves.length == 1) {
      throw Exception('Lost response');
    }
    request = {'request_id': image.id, 'status': 'pending'};
    return 'pending';
  }
}

Future<void> chooseAndSave(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Choose PDF'));
  await tester.tap(find.text('Choose PDF'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Save resume'));
  await tester.tap(find.text('Save resume'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Native Back confirms before losing a selected resume', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Profile root')),
        ),
        GoRoute(
          path: '/resume',
          builder: (_, _) => ResumePage(
            gateway: TestResumes(),
            pickFile: () async => pdfFile('draft.pdf'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/resume');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose PDF'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Leave this page?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text('Selected: draft.pdf'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave page'));
    await tester.pumpAndSettle();
    expect(find.text('Profile root'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'Resume validation rejects empty, oversized, renamed and malformed files',
    () {
      expect(() => validateResume('resume.pdf', pdf()), returnsNormally);
      for (final data in [
        ('resume.pdf', Uint8List(0)),
        ('resume.pdf', Uint8List(5 * 1024 * 1024 + 1)),
        ('resume.txt', pdf()),
        ('resume.pdf', Uint8List.fromList('not a pdf'.codeUnits)),
        ('${'a' * 252}.pdf', pdf()),
      ]) {
        expect(() => validateResume(data.$1, data.$2), throwsFormatException);
      }
    },
  );

  for (final status in ['not_submitted', 'pending', 'verified', 'rejected']) {
    testWidgets(
      'Active seeker can replace resume regardless of legacy $status',
      (tester) async {
        final gateway = TestResumes()..verification = status;
        gateway.versions.add(
          const ResumeFile(
            id: 'old',
            path: 'own/old/document.pdf',
            name: 'previous.pdf',
            size: 80,
            bucket: 'jobmate-verification',
            uploadedAt: null,
            legacy: true,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ResumePage(
              gateway: gateway,
              pickFile: () async => pdfFile('new.pdf'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('previous.pdf'), findsOneWidget);
        await chooseAndSave(tester);
        expect(gateway.versions.first.name, 'new.pdf');
        expect(gateway.versions.length, 2);
        expect(gateway.verification, status);
        expect(find.text('Previous resumes'), findsOneWidget);
        expect(find.text('Submit for review'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Uncertain resume save retries the same upload without duplicating a version',
    (tester) async {
      final gateway = TestResumes()..loseFirstResponse = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ResumePage(
            gateway: gateway,
            pickFile: () async => pdfFile('new.pdf'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await chooseAndSave(tester);
      expect(find.text('Retry same resume'), findsOneWidget);
      expect(gateway.versions.length, 1);
      final picker = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Replace selected PDF'),
      );
      expect(picker.onPressed, isNull);
      await tester.ensureVisible(find.text('Retry same resume'));
      await tester.tap(find.text('Retry same resume'));
      await tester.pumpAndSettle();
      expect(gateway.uploads, 1);
      expect(gateway.saves.length, 2);
      expect(gateway.saves[0], gateway.saves[1]);
      expect(gateway.versions.length, 1);
    },
  );

  for (final account in [('employer', 'active'), ('job_seeker', 'suspended')]) {
    testWidgets('Resume UI denies ${account.$1} / ${account.$2}', (
      tester,
    ) async {
      final gateway = TestResumes()
        ..role = account.$1
        ..status = account.$2;
      await tester.pumpWidget(MaterialApp(home: ResumePage(gateway: gateway)));
      await tester.pumpAndSettle();
      expect(find.text('Choose PDF'), findsNothing);
      expect(gateway.uploads, 0);
    });
  }

  testWidgets('Resume failure has no fake success and preserves selection', (
    tester,
  ) async {
    final gateway = TestResumes()..pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: ResumePage(
          gateway: gateway,
          pickFile: () async => pdfFile('pending.pdf'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save resume'));
    await tester.pump();
    expect(
      tester.widget<LoadingOverlay>(find.byType(LoadingOverlay)).isLoading,
      isTrue,
    );
    gateway.validSession = false;
    gateway.pending!.complete();
    await tester.pumpAndSettle();
    expect(gateway.versions, isEmpty);
    expect(find.text('Selected: pending.pdf'), findsOneWidget);
    expect(
      find.text('Resume saved. No administrator approval is required.'),
      findsNothing,
    );
  });

  testWidgets(
    'Unavailable resume backend exposes Retry and no upload controls',
    (tester) async {
      final gateway = TestResumes()..listError = Exception('Not configured');
      await tester.pumpWidget(MaterialApp(home: ResumePage(gateway: gateway)));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Choose PDF'), findsNothing);
      gateway.listError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Choose PDF'), findsOneWidget);
    },
  );

  for (final size in [
    const Size(320, 720),
    const Size(568, 320),
    const Size(1440, 900),
  ]) {
    testWidgets('Resume and company photo adapt to $size / large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: ResumePage(
            gateway: TestResumes(),
            pickFile: () async => pdfFile('resume.pdf'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: WorkspaceContent(
              child: CompanyLogoEditor(gateway: TestLogos(), canEdit: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Non-owner cannot open the company photo picker', (tester) async {
    var picks = 0;
    final gateway = TestLogos();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyLogoEditor(
            gateway: gateway,
            canEdit: false,
            pickImage: () async {
              picks++;
              return XFile.fromData(png(), name: 'logo.png');
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Company photo'));
    await tester.pumpAndSettle();
    expect(picks, 0);
    expect(gateway.uploads, 0);
  });

  testWidgets(
    'Unconfirmed logo submission permits the same photo to be selected again without automatic retry',
    (tester) async {
      final gateway = TestLogos()..loseFirstResponse = true;
      var picks = 0;
      String? submittedStatus;
      final original = png();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyLogoEditor(
              gateway: gateway,
              canEdit: true,
              currentPath: 'own/old/logo.png',
              initialBytes: original,
              pickImage: () async {
                picks++;
                return XFile.fromData(png(), name: 'logo.png');
              },
              onSubmitted: (status) => submittedStatus = status,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Change company photo'));
      await tester.pumpAndSettle();
      expect(submittedStatus, isNull);
      expect(find.text('Retry same photo'), findsNothing);
      expect(gateway.saves.length, 1);
      await tester.tap(find.text('Choose photo again'));
      await tester.pumpAndSettle();
      expect(gateway.uploads, 2);
      expect(picks, 2);
      expect(gateway.saves.length, 2);
      expect(gateway.saves[0].id, isNot(gateway.saves[1].id));
      expect(gateway.saves.last.expectedPath, 'own/old/logo.png');
      expect(submittedStatus, 'pending');
      expect(
        find.text('Pending approval. Your current photo remains unchanged.'),
        findsOneWidget,
      );
      expect(
        identical(
          (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes,
          original,
        ),
        isTrue,
      );
      await tester.tap(find.byTooltip('Change company photo'));
      await tester.pumpAndSettle();
      expect(picks, 2, reason: 'Only one pending request is allowed');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Storage 403 releases the picker and never submits the denied upload',
    (tester) async {
      final gateway = TestLogos()
        ..uploadError = const StorageException(
          'new row violates row-level security policy',
          statusCode: '403',
          error: 'Unauthorized',
        );
      var picks = 0;
      final samePhoto = XFile.fromData(png(), name: 'logo.png');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyLogoEditor(
              gateway: gateway,
              canEdit: true,
              pickImage: () async {
                picks++;
                return samePhoto;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Photo upload was denied.'), findsOneWidget);
      expect(find.text('Retry same photo'), findsNothing);
      expect(gateway.uploads, 1);
      expect(gateway.saves, isEmpty);
      expect(picks, 1);
      gateway.uploadError = null;
      await tester.tap(find.text('Choose photo again'));
      await tester.pumpAndSettle();
      expect(picks, 2);
      expect(gateway.uploads, 2);
      expect(
        gateway.uploadAttempts.first.id,
        isNot(gateway.uploadAttempts.last.id),
      );
      expect(gateway.saves.length, 1);
      expect(
        find.text('Pending approval. Your current photo remains unchanged.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Lost response checks existing Pending without uploading or submitting again',
    (tester) async {
      final gateway = TestLogos()
        ..loseFirstResponse = true
        ..commitBeforeLostResponse = true;
      var picks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyLogoEditor(
              gateway: gateway,
              canEdit: true,
              pickImage: () async {
                picks++;
                return XFile.fromData(png(), name: 'logo.png');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      expect(
        find.text('Pending approval. Your current photo remains unchanged.'),
        findsOneWidget,
      );
      expect(find.text('Retry same photo'), findsNothing);
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      expect(picks, 1);
      expect(gateway.uploads, 1);
      expect(gateway.saves.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Rejected logo can be resubmitted; unavailable status blocks new uploads',
    (tester) async {
      final gateway = TestLogos()
        ..request = {
          'status': 'rejected',
          'review_comment': 'Use a clearer company logo.',
        };
      var picks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyLogoEditor(
              gateway: gateway,
              canEdit: true,
              pickImage: () async {
                picks++;
                return null;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Use a clearer company logo.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Change company photo'));
      await tester.pumpAndSettle();
      expect(picks, 1);
      gateway.statusUnavailable = true;
      await tester.tap(find.text('Refresh logo review status'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Change company photo'));
      await tester.pumpAndSettle();
      expect(picks, 1);
      expect(
        find.textContaining('Unable to load logo review status.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An unavailable status check after a lost response blocks fresh submissions until refreshed',
    (tester) async {
      final gateway = TestLogos()
        ..loseFirstResponse = true
        ..pending = Completer<void>();
      var picks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyLogoEditor(
              gateway: gateway,
              canEdit: true,
              pickImage: () async {
                picks++;
                return XFile.fromData(png(), name: 'logo.png');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose photo'));
      await tester.pump();
      gateway.statusUnavailable = true;
      gateway.pending!.complete();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Unable to load logo review status.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Choose photo again'));
      await tester.pumpAndSettle();
      expect(picks, 1);
      expect(gateway.saves.length, 1);
      expect(find.text('Retry same photo'), findsNothing);
      gateway.statusUnavailable = false;
      await tester.tap(find.text('Refresh logo review status'));
      await tester.pumpAndSettle();
      expect(
        gateway.uploads,
        1,
        reason: 'Refreshing status must never resubmit',
      );
      await tester.tap(find.text('Choose photo again'));
      await tester.pumpAndSettle();
      expect(picks, 2);
      expect(gateway.saves.length, 2);
      expect(
        find.text('Pending approval. Your current photo remains unchanged.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Seeker dashboard uses Resume without a verification badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceContent(
            child: DashboardContent(
              profile: const {
                'role': 'job_seeker',
                'name': 'Applicant',
                'status': 'active',
                'verification_status': 'pending',
              },
              email: 'fixture@example.com',
              onProfile: () {},
              onCompany: () {},
              onVerification: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My Resume'), findsOneWidget);
    expect(find.text('Manage resume'), findsOneWidget);
    expect(find.text('Personal verification'), findsNothing);
  });
}
