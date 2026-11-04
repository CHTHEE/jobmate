import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/module2_repository.dart';
import 'package:jobmate/features/applications/published_company_logo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/published_jobs_source.dart';

void main() {
  const path = 'owner/profile-upload/logo.png';
  late TestPublishedJobsSource source;
  late PublishedJobsRepository repository;
  late DateTime now;
  setUp(() async {
    now = DateTime(2026, 11, 4);
    source = TestPublishedJobsSource()
      ..rows = [
        {
          'job_id': 'real-job',
          'company_name': 'Company',
          'logo_storage_path': path,
        },
      ]
      ..sign = (_) async => 'https://example.invalid/signed-logo';
    repository = PublishedJobsRepository(source, now: () => now);
    await repository.load();
  });
  tearDown(() async {
    repository.dispose();
    await source.changes.close();
  });

  test(
    'Maps nullable logo path and caches concurrent signing until expiry',
    () async {
      expect(repository.jobs.single.logoStoragePath, path);
      final first = repository.logoUrl(path);
      expect(identical(first, repository.logoUrl(path)), isTrue);
      expect(await first, 'https://example.invalid/signed-logo');
      expect(
        await repository.logoUrl(path),
        'https://example.invalid/signed-logo',
      );
      expect(source.signs, 1);
      now = now.add(const Duration(minutes: 5));
      await repository.logoUrl(path);
      expect(source.signs, 2);
    },
  );

  test('Missing paths and signing failures safely return null', () async {
    expect(BrowseJob.published({'job_id': 'missing'}).logoStoragePath, isNull);
    expect(await repository.logoUrl(null), isNull);
    expect(await repository.logoUrl(''), isNull);
    expect(await repository.logoUrl('  '), isNull);
    expect(source.signs, 0);
    source.sign = (_) => Future.error(StateError('Storage denied'));
    expect(await repository.logoUrl(path), isNull);
    expect(await repository.logoUrl(path), isNull);
    expect(source.signs, 1);
  });

  test(
    'Explicit job refresh retries a previously failed signing request',
    () async {
      source.sign = (_) =>
          Future.error(StateError('Temporary signing failure'));
      expect(await repository.logoUrl(path), isNull);
      source.sign = (_) async => 'https://example.invalid/recovered';
      await repository.load();
      expect(
        await repository.logoUrl(path),
        'https://example.invalid/recovered',
      );
      expect(source.signs, 2);
    },
  );

  test(
    'Refresh replaces old null paths and retains successful signed URLs',
    () async {
      source.rows = [
        {
          'job_id': 'real-job',
          'company_name': 'Company',
          'logo_storage_path': null,
        },
      ];
      await repository.load();
      expect(repository.jobs.single.logoStoragePath, isNull);
      source.rows = [
        {
          'job_id': 'real-job',
          'company_name': 'Company',
          'logo_storage_path': path,
        },
      ];
      await repository.load();
      expect(repository.jobs.single.logoStoragePath, path);
      await repository.logoUrl(path);
      await repository.load();
      await repository.logoUrl(path);
      expect(source.signs, 1);
    },
  );

  test(
    'Storage diagnostics retain status and redact credentials and URLs',
    () async {
      final messages = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) =>
          messages.add(message ?? '');
      addTearDown(() => debugPrint = previous);
      source.sign = (_) => Future.error(
        const StorageException(
          'Denied https://private.invalid/logo?token=secret-value token=short-secret',
          statusCode: '403',
        ),
      );
      expect(await repository.logoUrl(path), isNull);
      final output = messages.join('\n');
      expect(output, contains('Storage status=403'));
      expect(output, contains('Denied'));
      expect(output, isNot(contains('https://')));
      expect(output, isNot(contains('secret-value')));
      expect(output, isNot(contains('short-secret')));
    },
  );

  test(
    'Account changes clear signed URLs and discard pending results',
    () async {
      final pending = Completer<String>();
      source.sign = (_) => pending.future;
      final previous = repository.logoUrl(path);
      source.switchAccount('seeker-b');
      pending.complete('https://example.invalid/previous-account');
      expect(await previous, isNull);
      await Future<void>.delayed(Duration.zero);
      source.sign = (_) async => 'https://example.invalid/new-account';
      expect(
        await repository.logoUrl(path),
        'https://example.invalid/new-account',
      );
      expect(source.signs, 2);
      source.switchAccount(null);
      expect(await repository.logoUrl(path), isNull);
    },
  );

  Widget logo({double size = 40, Widget? fallback, String? overridePath}) =>
      MaterialApp(
        home: Scaffold(
          body: PublishedCompanyLogo(
            key: const ValueKey('logo'),
            job: overridePath == null
                ? repository.jobs.single
                : BrowseJob.published({
                    'job_id': 'missing',
                    'company_name': 'Company',
                    'logo_storage_path': overridePath,
                  }),
            repository: repository,
            size: size,
            fallback: fallback,
          ),
        ),
      );

  testWidgets(
    'Signed image uses existing avatar footprint and no repeat signing',
    (tester) async {
      await tester.pumpWidget(logo());
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as NetworkImage).url,
        'https://example.invalid/signed-logo',
      );
      expect(image.semanticLabel, 'Company logo');
      expect(image.fit, BoxFit.contain);
      expect(
        tester.getSize(find.byType(PublishedCompanyLogo)),
        const Size(40, 40),
      );
      expect(find.byType(ClipOval), findsWidgets);
      await tester.pumpWidget(logo());
      await tester.pumpAndSettle();
      repository.toggleSave('real-job');
      await tester.pumpAndSettle();
      expect(source.signs, 1);
      // Decoding/network errors reuse the avatar, never a broken-image icon.
      final fallback = image.errorBuilder!(
        tester.element(find.byType(Image)),
        StateError('Invalid image'),
        StackTrace.current,
      );
      expect(fallback, isA<CircleAvatar>());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Missing logo and failed signing show avatar, details retain 24px',
    (tester) async {
      await tester.pumpWidget(logo(overridePath: ''));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.text('C'), findsOneWidget);
      expect(source.signs, 0);
      source.sign = (_) => Future.error(StateError('No access'));
      await tester.pumpWidget(
        logo(size: 24, fallback: const Icon(Icons.business_outlined)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.business_outlined), findsOneWidget);
      expect(
        tester.getSize(find.byType(PublishedCompanyLogo)),
        const Size(24, 24),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Logout removes a resolved image from a mounted avatar', (
    tester,
  ) async {
    await tester.pumpWidget(logo());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    source.switchAccount(null);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('C'), findsOneWidget);
  });
}
