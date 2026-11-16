import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/applications/browse_job_card.dart';
import 'package:jobmate/features/applications/module2_repository.dart';

void main() {
  testWidgets(
    'compact cards wrap long data and preserve actions and disclosure',
    (tester) async {
      var saves = 0, details = 0;
      for (final width in [
        320.0,
        360.0,
        390.0,
        430.0,
        600.0,
        768.0,
        840.0,
        1024.0,
        1280.0,
        1440.0,
        1920.0,
      ]) {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        final job = BrowseJob({
          'title': 'A long job title for a customer service and event coordination role',
          'location': 'A long location with multiple districts and a detailed venue name',
          'employment_type': 'part_time',
          'work_arrangement': 'on_site',
          'status': 'published',
          'application_deadline': '2020-01-01',
          'salary_visible': false,
          'salary_min': 12345,
          'salary_max': 67890,
          'vacancies': 2,
          'published_at': '2026-11-01',
        }, company: 'Company with a longer name');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
                  child: BrowseJobCard(
                    job: job,
                    logo: const Icon(Icons.business),
                    saved: true,
                    onSave: () => saves++,
                    onDetails: () => details++,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'width $width');
        expect(find.text('Not disclosed'), findsOneWidget);
        expect(find.textContaining('12345'), findsNothing);
        expect(find.text('Application deadline has passed.'), findsOneWidget);
        await tester.tap(find.byTooltip('Unsave job (this session)'));
        await tester.ensureVisible(find.text('View Details'));
        await tester.tap(find.text('View Details'));
      }
      expect(saves, 11);
      expect(details, 11);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );
}
