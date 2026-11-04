import 'dart:async';

import 'package:jobmate/features/applications/employer_applicants_repository.dart';
import 'package:jobmate/features/jobs/job_postings_repository.dart';
import 'package:jobmate/features/applications/my_applications_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TestEmployerApplicantsSource implements EmployerApplicantsSource {
  String? actor = 'employer-a';
  final changes = StreamController<String?>.broadcast(sync: true);
  final requests = <String>[];
  int contextLoads = 0;
  EmployerPostingContext data = const EmployerPostingContext(
    JobAccess({
      'company_id': 'company-id',
      'company_name': 'ABC Company',
    }, null),
    [
      {
        'job_id': 'real-job-id',
        'company_id': 'company-id',
        'title': 'Part-Time Cafe Crew',
        'status': 'published',
      },
      {
        'job_id': 'closed-job-id',
        'company_id': 'company-id',
        'title': 'Closed posting',
        'status': 'closed',
      },
    ],
  );
  List<Map<String, dynamic>> rows = [];
  Future<EmployerPostingContext> Function()? fetchJobs;
  Future<List<Map<String, dynamic>>> Function(String)? fetchApplicants;
  final resumeRequests = <String>[];
  Future<FunctionResponse> Function()? fetchResume;
  @override
  Future<FunctionResponse> viewResume(String id) {
    resumeRequests.add(id);
    return fetchResume?.call() ??
        Future.value(
          FunctionResponse(
            status: 200,
            data: {
              'signed_url': 'https://example.invalid/mock-resume.pdf',
              'expires_in': 60,
            },
          ),
        );
  }

  final updates = <(String, MyApplicationStatus, String?)>[];
  Future<void> Function()? sendUpdate;
  @override
  Future<void> updateStatus(
    String id,
    MyApplicationStatus status,
    String? note,
  ) async {
    updates.add((id, status, note));
    if (sendUpdate != null) {
      await sendUpdate!();
      return;
    }
    rows = [
      for (final row in rows)
        if (row['application_id'] == id)
          {...row, 'status': status.name}
        else
          row,
    ];
  }

  @override
  String? get userId => actor;
  @override
  Stream<String?> get accountChanges => changes.stream;
  @override
  Future<EmployerPostingContext> loadJobs() {
    contextLoads++;
    return fetchJobs?.call() ?? Future.value(data);
  }

  @override
  Future<List<Map<String, dynamic>>> applicants(String jobId) {
    requests.add(jobId);
    return fetchApplicants?.call(jobId) ?? Future.value(rows);
  }

  void switchAccount(String? id) {
    actor = id;
    changes.add(id);
  }
}

Map<String, dynamic> applicantRow(String id, {String status = 'submitted'}) => {
  'application_id': id,
  'applicant_id': 'real-applicant-id',
  'applicant_name': 'Alex Thee',
  'resume_id': null,
  'cover_note': null,
  'status': status,
  'applied_at': '2026-11-04T10:11:37.58546Z',
  'updated_at': '2026-11-04T10:11:37.58546Z',
};
