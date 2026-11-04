import 'dart:async';

import 'package:jobmate/features/applications/module2_repository.dart';

import 'my_applications_source.dart';
import 'employer_applicants_source.dart';

class TestPublishedJobsSource implements PublishedJobsSource {
  String? actor = 'seeker-a';
  final changes = StreamController<String?>.broadcast(sync: true);
  Future<List<Map<String, dynamic>>> Function()? fetch;
  List<Map<String, dynamic>> rows = [];
  int calls = 0;
  int signs = 0;
  Future<String> Function(String)? sign;
  @override
  Future<String> signLogo(String path) {
    signs++;
    return sign?.call(path) ?? Future.error(StateError('No test logo'));
  }

  @override
  String? get userId => actor;
  @override
  Stream<String?> get accountChanges => changes.stream;
  @override
  Future<List<Map<String, dynamic>>> list() {
    calls++;
    return fetch?.call() ?? Future.value(rows);
  }

  void switchAccount(String? id) {
    actor = id;
    changes.add(id);
  }
}

// Existing responsive fixtures remain deterministic; production never uses them.
Module2Repository fixtureModule2() {
  final demo = Module2Repository();
  final source = TestPublishedJobsSource()
    ..rows = [
      for (final job in demo.jobs.where((j) => j.text('status') == 'published'))
        {...job.fields, 'company_name': job.company},
    ];
  demo.dispose();
  return Module2Repository(
    publishedSource: source,
    myApplicationsSource: TestMyApplicationsSource()
      ..rows = [applicationRow('fixture-application')],
    employerApplicantsSource: TestEmployerApplicantsSource(),
  );
}
